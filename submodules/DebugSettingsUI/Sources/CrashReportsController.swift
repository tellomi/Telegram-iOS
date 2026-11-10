import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import CrashReporting
import ZipArchive
import OverlayStatusController
import UndoUI
import ContextUI
import BuildConfig
#if DEBUG
import AppBundle
#endif

private let crashReportPendingKey = "tellomi.crashReport.pendingSend"

private func crashReportPendingIds() -> Set<String> {
    return Set(UserDefaults.standard.stringArray(forKey: crashReportPendingKey) ?? [])
}

private func crashReportSetPending(_ ids: Set<String>) {
    UserDefaults.standard.set(Array(ids), forKey: crashReportPendingKey)
}

private func crashReportMarkPending(_ id: String) {
    var ids = crashReportPendingIds()
    ids.insert(id)
    crashReportSetPending(ids)
}

private func crashReportClearPending(_ id: String) {
    var ids = crashReportPendingIds()
    ids.remove(id)
    crashReportSetPending(ids)
}

private func crashReportMarkPresented(_ id: String) {
    crashReportWorkQueue.async {
        try? CrashReportStore.shared.markPresented(ids: [id])
    }
}

private func crashReportCaption(_ report: CrashReport) -> String {
    return [
        "Tellomi crash log",
        "Report: \(report.id)",
        "App: \(report.metadata.applicationVersion) (\(report.metadata.buildVersion))",
        "OS: \(report.metadata.osVersion)",
        "Device: \(report.metadata.deviceType)",
        "Architecture: \(report.metadata.architecture)"
    ].joined(separator: "\n")
}

private func crashReportBotName(context: AccountContext) -> String {
    let configuration = context.currentAppConfiguration.with { $0 }
    if let data = configuration.data, let name = data["tellomi_crash_report_bot"] as? String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        if !trimmed.isEmpty {
            return trimmed
        }
    }
    return "TellomiBot"
}

private func crashReportText(_ context: AccountContext, _ key: String, english: String, chinese: String) -> String {
    let strings = context.sharedContext.currentPresentationData.with { $0 }.strings
    let resolved: String
    switch key {
    case "title":
        resolved = strings.CrashReport_AvailableTitle
    case "text":
        resolved = strings.CrashReport_AvailableText
    case "send":
        resolved = strings.CrashReport_SendLog
    case "botTitle":
        resolved = strings.CrashReport_BotMissingTitle
    case "botText":
        resolved = strings.CrashReport_BotMissingText
    case "saved":
        resolved = strings.CrashReport_SavedInstead
    case "thanks":
        resolved = strings.CrashReport_Thanks
    case "offline":
        resolved = strings.CrashReport_Offline
    case "failed":
        resolved = strings.CrashReport_Failed
    default:
        resolved = english
    }
    let codes = [strings.primaryComponent.languageCode, strings.baseLanguageCode].map { $0.lowercased() }
    if codes.contains(where: { $0.hasPrefix("zh") }), resolved == english || resolved.isEmpty {
        return chinese
    }
    return resolved
}
private let crashReportWorkQueue = DispatchQueue(label: "org.telegram.crash-report-ui", qos: .utility)

private struct CrashReportItemTag: ItemListItemTag {
    let id: String

    func isEqual(to other: ItemListItemTag) -> Bool {
        return (other as? CrashReportItemTag)?.id == self.id
    }
}

private final class CrashReportContextReferenceContentSource: ContextReferenceContentSource {
    private let sourceView: UIView

    init(sourceView: UIView) {
        self.sourceView = sourceView
    }

    func transitionInfo() -> ContextControllerReferenceViewInfo? {
        return ContextControllerReferenceViewInfo(referenceView: self.sourceView, contentAreaInScreenSpace: mainWindowScreenBounds, insets: UIEdgeInsets(top: -4.0, left: 0.0, bottom: -4.0, right: 0.0))
    }
}

private func crashReportsSignal() -> Signal<Result<[CrashReport], Error>, NoError> {
    return Signal { subscriber in
        let reload: () -> Void = {
            crashReportWorkQueue.async {
                subscriber.putNext(Result { try CrashReportStore.shared.reports() })
            }
        }
        let observer = NotificationCenter.default.addObserver(forName: CrashReportStore.didChange, object: nil, queue: nil) { _ in
            reload()
        }
        reload()
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

private func crashReportArchive(_ report: CrashReport) throws -> Data {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let json = directory.appendingPathComponent("crash.json")
    let metadata = directory.appendingPathComponent("metadata.json")
    let text = directory.appendingPathComponent("report.txt")
    try report.diagnosticJSON.write(to: json)
    try report.exportMetadata().write(to: metadata)
    try Data(report.text.utf8).write(to: text)
    let archive = directory.appendingPathComponent("report.zip")
    guard SSZipArchive.createZipFile(atPath: archive.path, withFilesAtPaths: [json.path, metadata.path, text.path]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return try Data(contentsOf: archive)
}

/// The sender is tied to the account displayed in the confirmation, even if the user switches accounts later.
private final class CrashReportActions {
    let sharedContext: SharedAccountContext
    let context: AccountContext?
    var present: (ViewController) -> Void = { _ in }
    var push: (ViewController) -> Void = { _ in }
    var presentMenu: (ViewController) -> Void = { _ in }
    var reportNode: (String) -> ItemListDisclosureItemNode? = { _ in nil }
    private let disposable = MetaDisposable()
    private var busy = false
    private var progress: ViewController?
    private weak var presentedController: ViewController?
    var canPresent = true {
        didSet {
            if !self.canPresent {
                self.presentedController?.dismiss()
                self.progress?.dismiss()
            }
        }
    }

    func show(_ controller: ViewController) {
        guard self.canPresent else { return }
        self.presentedController = controller
        self.present(controller)
    }

    private func finishSending() {
        self.busy = false
        self.progress?.dismiss()
        self.progress = nil
    }

    /// `iOSCrashReportsBot` does not exist on Tellomi. Resolve `tellomi_crash_report_bot` when app config sets it, otherwise `TellomiBot`. If that peer is missing or is not a bot, the zip still goes to Saved Messages so Send Log is not a dead end.
    private func sendToSavedMessages(_ report: CrashReport, context: AccountContext) {
        let peerId = context.account.peerId
        crashReportWorkQueue.async { [self] in
            let archive = Result { try crashReportArchive(report) }
            DispatchQueue.main.async { [self] in
                switch archive {
                case let .success(data):
                    let id = Int64.random(in: Int64.min ... Int64.max)
                    let resource = LocalFileMediaResource(fileId: id, size: Int64(data.count), isSecretRelated: false)
                    context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data)
                    let file = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/zip", size: Int64(data.count), attributes: [.FileName(fileName: "CrashReport-\(report.id.prefix(12)).zip")], alternativeRepresentations: [])
                    let message: EnqueueMessage = .message(text: crashReportCaption(report), attributes: [], inlineStickers: [:], mediaReference: .standalone(media: file), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                    self.disposable.set((enqueueMessages(account: context.account, peerId: peerId, messages: [message])
                    |> deliverOnMainQueue).start(next: { [weak self] ids in
                        guard let self else { return }
                        self.finishSending()
                        guard ids.contains(where: { $0 != nil }) else {
                            self.toast(crashReportText(context, "failed", english: "Could not send the crash log. It remains saved on this device.", chinese: "崩溃日志没有发出去。它仍保存在这台设备上。"))
                            return
                        }
                        crashReportClearPending(report.id)
                        crashReportMarkPresented(report.id)
                        self.toast(crashReportText(context, "saved", english: "The crash bot is not available, so the log was saved to Saved Messages.", chinese: "崩溃日志机器人不可用，日志已保存到收藏夹。"))
                    }))
                case .failure:
                    self.finishSending()
                    self.alert(crashReportText(context, "botTitle", english: "Could Not Find Crash Log Bot", chinese: "找不到崩溃日志机器人"), crashReportText(context, "botText", english: "Check your connection and try again. The log remains saved on this device.", chinese: "请检查网络后再试。日志仍保存在这台设备上。"))
                }
            }
        }
    }

    init(sharedContext: SharedAccountContext, context: AccountContext?) {
        self.sharedContext = sharedContext
        self.context = context
    }

    deinit {
        self.disposable.dispose()
    }

    func toast(_ text: String) {
        self.show(UndoOverlayController(presentationData: self.sharedContext.currentPresentationData.with { $0 }, content: .succeed(text: text, timeout: nil, customUndoText: nil), action: { _ in
            return false
        }))
    }

    func alert(_ title: String, _ text: String) {
        self.show(textAlertController(sharedContext: self.sharedContext, title: title, text: text, actions: [
            TextAlertAction(type: .defaultAction, title: self.sharedContext.currentPresentationData.with { $0 }.strings.Common_OK, action: {})
        ]))
    }

    #if DEBUG
    func testCrash() {
        let bundle = getAppBundle()
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif
        #if targetEnvironment(simulator)
        let deviceType = (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? UIDevice.current.model) + " (Simulator)"
        #else
        let deviceType = UIDevice.current.model
        #endif
        let metadata = CrashReportMetadata(
            applicationVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            buildVersion: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceType: deviceType,
            architecture: architecture
        )
        do {
            try CrashReportStore.shared.simulateCrash(metadata: metadata, crash: {
                abort()
            })
        } catch {
            self.alert("Could Not Save Test Log", "The app was not crashed because the test log could not be saved.\n\n\(error.localizedDescription)")
        }
    }
    #endif

    func open(_ report: CrashReport) {
        guard self.canPresent, let sourceNode = self.reportNode(report.id) else { return }
        let data = self.sharedContext.currentPresentationData.with { $0 }
        let items: [ContextMenuItem] = [
            .action(ContextMenuActionItem(text: "View Log", icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/File"), color: theme.contextMenu.primaryColor)
            }, action: { controller, _ in
                controller?.dismiss(completion: {
                    self.view(report)
                })
            })),
            .action(ContextMenuActionItem(text: "Send to Telegram Team", icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Forward"), color: theme.contextMenu.primaryColor)
            }, action: { controller, _ in
                controller?.dismiss(completion: {
                    self.confirmSend(report)
                })
            })),
            .action(ContextMenuActionItem(text: "Delete Log", textColor: .destructive, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.contextMenu.destructiveColor)
            }, action: { controller, _ in
                controller?.dismiss(completion: {
                    self.show(textAlertController(sharedContext: self.sharedContext, title: "Delete Crash Log?", text: "This removes the saved log from this device.", actions: [
                        TextAlertAction(type: .genericAction, title: data.strings.Common_Cancel, action: {}),
                        TextAlertAction(type: .destructiveAction, title: "Delete", action: {
                            crashReportWorkQueue.async {
                                do {
                                    try CrashReportStore.shared.remove(id: report.id)
                                } catch {
                                    DispatchQueue.main.async { self.alert("Could Not Delete Log", "Please try again.") }
                                }
                            }
                        })
                    ]))
                })
            }))
        ]
        let controller = makeContextController(
            presentationData: data,
            source: .reference(CrashReportContextReferenceContentSource(sourceView: sourceNode.view)),
            items: .single(ContextController.Items(content: .list(items))),
            gesture: nil
        )
        sourceNode.updateHasContextMenu(hasContextMenu: true)
        controller.dismissed = { [weak sourceNode] in
            sourceNode?.updateHasContextMenu(hasContextMenu: false)
        }
        self.presentedController = controller
        self.presentMenu(controller)
    }

    private func view(_ report: CrashReport) {
        crashReportWorkQueue.async {
            let text = report.text
            DispatchQueue.main.async {
                self.push(CrashReportTextController(presentationData: self.sharedContext.currentPresentationData.with { $0 }, text: text))
            }
        }
    }

    func confirmSend(_ report: CrashReport) {
        guard self.canPresent, !self.busy else { return }
        guard let context = self.context else {
            self.alert("Sign In Required", "Sign in to a Telegram account to send this log.")
            return
        }
        self.busy = true
        self.disposable.set((context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
        |> deliverOnMainQueue).start(next: { [weak self] peer in
            guard let self else { return }
            self.busy = false
            guard let peer else {
                self.alert("Could Not Load Account", "Please try again.")
                return
            }
            var sender = peer.debugDisplayTitle
            if let username = peer.addressName, !username.isEmpty {
                sender += " (@\(username))"
            }
            // Reset before showing the confirmation so dismissing it by tapping outside is harmless.
            self.show(textAlertController(sharedContext: self.sharedContext, title: "Send Crash Log?", text: "From: \(sender)\n\nThe archive includes the crash diagnostic, app and device details, and stack addresses. You can review these in View Log.", actions: [
                TextAlertAction(type: .genericAction, title: self.sharedContext.currentPresentationData.with { $0 }.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .defaultAction, title: "Send", action: { self.send(report, context: context) })
            ]))
        }))
    }

    func send(_ report: CrashReport, context: AccountContext) {
        guard self.canPresent, !self.busy else { return }
        crashReportMarkPending(report.id)
        self.disposable.set((context.account.networkState |> take(1) |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self, self.canPresent, !self.busy else { return }
            if case .online = state {
                self.beginSend(report, context: context)
            } else {
                self.toast(crashReportText(context, "offline", english: "You're offline. The log stays on this device and will be sent when you reconnect.", chinese: "当前没有网络。日志仍在这台设备上，连上网络后会发送。"))
            }
        }))
    }

    private func beginSend(_ report: CrashReport, context: AccountContext) {
        self.busy = true
        let progress = OverlayStatusController(theme: self.sharedContext.currentPresentationData.with { $0 }.theme, type: .loading(cancelled: nil))
        self.progress = progress
        self.present(progress)
        let resolution = context.engine.peers.resolvePeerByName(name: crashReportBotName(context: context), referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            if case let .result(peer) = result { return .single(peer) }
            return .complete()
        }
        |> take(1)
        |> timeout(15.0, queue: Queue.mainQueue(), alternate: .single(nil))
        |> deliverOnMainQueue
        self.disposable.set(resolution.start(next: { [weak self] peer in
            guard let self else { return }
            guard let peer, case let .user(user) = peer, user.botInfo != nil else {
                self.sendToSavedMessages(report, context: context)
                return
            }
            // Cached resolution can complete synchronously. Install the next phase after
            // the current MetaDisposable.set has returned.
            DispatchQueue.main.async {
                self.checkBlockedAndEnqueue(report, context: context, peer: peer)
            }
        }))
    }

    private func checkBlockedAndEnqueue(_ report: CrashReport, context: AccountContext, peer: EnginePeer) {
        let peerId = peer.id
        self.disposable.set((context.engine.data.get(TelegramEngine.EngineData.Item.Peer.IsBlocked(id: peerId))
        |> deliverOnMainQueue).start(next: { [weak self] blocked in
            guard let self else { return }
            if case .known(true) = blocked {
                self.finishSending()
                self.alert(crashReportText(context, "botTitle", english: "Could Not Find Crash Log Bot", chinese: "找不到崩溃日志机器人"), crashReportText(context, "botText", english: "Check your connection and try again. The log remains saved on this device.", chinese: "请检查网络后再试。日志仍保存在这台设备上。"))
                return
            }
            crashReportWorkQueue.async { [self] in
                let archive = Result { try crashReportArchive(report) }
                DispatchQueue.main.async { [self] in
                    switch archive {
                    case let .success(data):
                        let id = Int64.random(in: Int64.min ... Int64.max)
                        let resource = LocalFileMediaResource(fileId: id, size: Int64(data.count), isSecretRelated: false)
                        context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data)
                        let file = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/zip", size: Int64(data.count), attributes: [.FileName(fileName: "CrashReport-\(report.id.prefix(12)).zip")], alternativeRepresentations: [])
                        let message: EnqueueMessage = .message(text: crashReportCaption(report), attributes: [], inlineStickers: [:], mediaReference: .standalone(media: file), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                        self.disposable.set((enqueueMessages(account: context.account, peerId: peerId, messages: [message])
                        |> deliverOnMainQueue).start(next: { [weak self] ids in
                            guard let self else { return }
                            self.finishSending()
                            guard ids.contains(where: { $0 != nil }) else {
                                self.toast(crashReportText(context, "failed", english: "Could not send the crash log. It remains saved on this device.", chinese: "崩溃日志没有发出去。它仍保存在这台设备上。"))
                                return
                            }
                            crashReportClearPending(report.id)
                            crashReportMarkPresented(report.id)
                            self.show(UndoOverlayController(presentationData: self.sharedContext.currentPresentationData.with { $0 }, content: .succeed(text: crashReportText(context, "thanks", english: "Thank you for helping make Tellomi better!", chinese: "感谢你帮助改进 Tellomi！"), timeout: nil, customUndoText: nil), action: { _ in
                                return false
                            }))
                        }))
                    case .failure:
                        self.finishSending()
                        self.alert("Could Not Prepare Log", "Please try again. The log remains saved on this device.")
                    }
                }
            }
        }))
    }
}

private enum CrashReportEntry: ItemListNodeEntry {
    case showAlerts(PresentationTheme, Bool)
    case alertsInfo(PresentationTheme)
    case reportsHeader(PresentationTheme)
    case report(Int, PresentationTheme, CrashReport)
    case information(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
        case .showAlerts, .alertsInfo: return 0
        case .reportsHeader, .report, .information: return 1
        }
    }
    var stableId: String {
        switch self {
        case .showAlerts: return "showAlerts"
        case .alertsInfo: return "alertsInfo"
        case .reportsHeader: return "reportsHeader"
        case let .report(_, _, report): return report.id
        case .information: return "information"
        }
    }
    private var index: Int {
        switch self {
        case .showAlerts: return -3
        case .alertsInfo: return -2
        case .reportsHeader: return -1
        case let .report(index, _, _): return index
        case .information: return Int.max
        }
    }
    static func < (lhs: CrashReportEntry, rhs: CrashReportEntry) -> Bool { return lhs.index < rhs.index }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .showAlerts(_, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Ask to Send Crash Logs", value: value, sectionId: self.section, style: .blocks, updated: { value in
                guard let actions = arguments as? CrashReportActions else { return }
                let _ = updateExperimentalUISettingsInteractively(accountManager: actions.sharedContext.accountManager, { settings in
                    var settings = settings
                    settings.showCrashReportAlerts = value
                    return settings
                }).start()
            })
        case .alertsInfo:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Show a prompt after the app crashes so you can send a log to help us fix the issue."), sectionId: self.section)
        case .reportsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "RECENT CRASHES", sectionId: self.section)
        case let .report(_, _, report):
            let date = DateFormatter.localizedString(from: report.receivedAt, dateStyle: .short, timeStyle: .short)
            let version = "\(report.metadata.applicationVersion) (\(report.metadata.buildVersion))"
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: date, label: version, sectionId: self.section, style: .blocks, action: {
                (arguments as? CrashReportActions)?.open(report)
            }, tag: CrashReportItemTag(id: report.id))
        case let .information(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func crashReportsController(sharedContext: SharedAccountContext, context: AccountContext?) -> ViewController {
    let actions = CrashReportActions(sharedContext: sharedContext, context: context)
    let isInternalBuild = BuildConfig(baseAppBundleId: sharedContext.applicationBindings.appBundleId).isInternalBuild
    let signal = combineLatest(sharedContext.presentationData, crashReportsSignal(), sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.experimentalUISettings]))
    |> map { presentationData, result, sharedData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings]?.get(ExperimentalUISettings.self) ?? .defaultSettings
        var entries: [CrashReportEntry] = [
            .showAlerts(presentationData.theme, crashReportAlertsEnabled(override: settings.showCrashReportAlerts, isInternalBuild: isInternalBuild)),
            .alertsInfo(presentationData.theme)
        ]
        switch result {
        case let .success(reports):
            if !reports.isEmpty {
                entries.append(.reportsHeader(presentationData.theme))
            }
            entries.append(contentsOf: reports.enumerated().map { .report($0.offset, presentationData.theme, $0.element) })
            entries.append(.information(presentationData.theme, reports.isEmpty ? "No recent crash logs yet." : "The 10 most recent crash logs are displayed here."))
        case .failure:
            entries.append(.information(presentationData.theme, "Unknown Error Occured."))
        }
        let rightNavigationButton: ItemListNavigationButton?
        #if DEBUG
        rightNavigationButton = ItemListNavigationButton(content: .text("Test"), style: .regular, enabled: true, action: {
            actions.testCrash()
        })
        #else
        rightNavigationButton = nil
        #endif
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Crash Logs"), leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks), actions))
    }
    let controller = ItemListController(sharedContext: sharedContext, state: signal)
    actions.present = { [weak controller] in controller?.present($0, in: .window(.root)) }
    actions.presentMenu = { [weak controller] in controller?.presentInGlobalOverlay($0, with: nil) }
    actions.reportNode = { [weak controller] id in
        return controller?.itemNode(forTag: CrashReportItemTag(id: id)) as? ItemListDisclosureItemNode
    }
    actions.push = { [weak controller] in (controller?.navigationController as? NavigationController)?.pushViewController($0) }
    return controller
}

private final class CrashReportTextController: ViewController {
    private let textView = UITextView()
    private let presentationData: PresentationData

    init(presentationData: PresentationData, text: String) {
        self.presentationData = presentationData
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: presentationData))
                
        self.title = "Crash Log"
        self.textView.text = text
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
        self.textView.backgroundColor = .clear
        self.textView.textColor = self.presentationData.theme.list.itemPrimaryTextColor
        self.textView.font = .monospacedSystemFont(ofSize: 12.0, weight: .regular)
        self.textView.isEditable = false
        self.textView.alwaysBounceVertical = true
        self.textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        self.textView.contentInsetAdjustmentBehavior = .never
        self.displayNode.view.addSubview(self.textView)
        self.displayNodeDidLoad()
    }
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.textView.frame = CGRect(x: layout.safeInsets.left, y: top, width: layout.size.width - layout.safeInsets.left - layout.safeInsets.right, height: max(0, layout.size.height - top - layout.intrinsicInsets.bottom))
    }
}

/// Install only after the authorized root controller becomes ready. Storage and capture do not depend on this subscription.
public func setupCrashReportPrompt(context: AccountContext, isInternalBuild: Bool, navigationController: NavigationController, present: @escaping (ViewController) -> Void) -> Disposable {
    let actions = CrashReportActions(sharedContext: context.sharedContext, context: context)
    actions.present = present
    actions.push = { [weak navigationController] in navigationController?.pushViewController($0) }
    var didPresent = false
    var didFlush = false
    weak var alert: ViewController?
    let disposable = (combineLatest(crashReportsSignal(), context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.experimentalUISettings]), context.sharedContext.applicationBindings.applicationIsActive, context.sharedContext.appLockContext.isPasscodeLocked)
    |> deliverOnMainQueue).start(next: { result, sharedData, active, locked in
        actions.canPresent = active && !locked
        guard active && !locked else {
            didFlush = false
            if alert != nil {
                alert?.dismiss()
                alert = nil
                didPresent = false
            }
            return
        }
        if !didFlush, case let .success(reports) = result {
            didFlush = true
            if let queued = reports.first(where: { crashReportPendingIds().contains($0.id) }) {
                actions.send(queued, context: context)
                return
            }
        }
        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings]?.get(ExperimentalUISettings.self) ?? .defaultSettings
        guard !didPresent, crashReportAlertsEnabled(override: settings.showCrashReportAlerts, isInternalBuild: isInternalBuild), case let .success(reports) = result else { return }
        let pending = reports.filter { !$0.wasPresented }
        guard !pending.isEmpty else { return }
        didPresent = true
        let strings = context.sharedContext.currentPresentationData.with { $0 }.strings
        let pendingIds = Set(pending.map(\.id))
        let markPresented = {
            crashReportWorkQueue.async {
                try? CrashReportStore.shared.markPresented(ids: pendingIds)
            }
        }
        let controller = textAlertController(sharedContext: context.sharedContext, title: crashReportText(context, "title", english: "New Crash Log Available", chinese: "有新的崩溃日志"), text: crashReportText(context, "text", english: "The app closed unexpectedly.\n\nWould you like to send a crash log to help us fix the issue?", chinese: "应用意外关闭了。\n\n要把崩溃日志发出去，帮我们修好这个问题吗？"), actions: [
            TextAlertAction(type: .genericAction, title: strings.Common_NotNow, action: {
                markPresented()
            }),
            TextAlertAction(type: .defaultAction, title: crashReportText(context, "send", english: "Send Log", chinese: "发送日志"), action: {
                actions.send(pending[0], context: context)
            })
        ])
        alert = controller
        present(controller)
    })
    return ActionDisposable {
        disposable.dispose()
        Queue.mainQueue().async {
            actions.canPresent = false
            alert?.dismiss()
        }
    }
}
