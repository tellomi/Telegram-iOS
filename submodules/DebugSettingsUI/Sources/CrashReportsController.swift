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
import AppBundle

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
    try report.diagnosticJSON.write(to: json)
    let archive = directory.appendingPathComponent("report.zip")
    guard SSZipArchive.createZipFile(atPath: archive.path, withFilesAtPaths: [json.path]) else {
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

    init(sharedContext: SharedAccountContext, context: AccountContext?) {
        self.sharedContext = sharedContext
        self.context = context
    }

    deinit {
        self.disposable.dispose()
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
            .action(ContextMenuActionItem(text: "Send to Telegram Team", icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Forward"), color: theme.contextMenu.primaryColor)
            }, action: { controller, _ in
                controller?.dismiss(completion: {
                    self.confirmSend(report)
                })
            })),
            .action(ContextMenuActionItem(text: "Share Log", icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Share"), color: theme.contextMenu.primaryColor)
            }, action: { controller, _ in
                controller?.dismiss(completion: {
                    self.share(report)
                })
            })),
            .action(ContextMenuActionItem(text: "View Log", icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/File"), color: theme.contextMenu.primaryColor)
            }, action: { controller, _ in
                controller?.dismiss(completion: {
                    self.view(report)
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

    private func share(_ report: CrashReport) {
        guard self.canPresent, !self.busy else { return }
        guard let context = self.context else {
            self.alert("Sign In Required", "Sign in to a Telegram account to share this log.")
            return
        }
        let controller = self.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.onlyWriteable, .excludeDisabled, .excludeSecretChats]))
        controller.peerSelected = { [weak controller] peer, threadId in
            guard self.canPresent, !self.busy else { return }
            controller?.dismiss()
            self.busy = true
            let progress = OverlayStatusController(theme: self.sharedContext.currentPresentationData.with { $0 }.theme, type: .loading(cancelled: nil))
            self.progress = progress
            self.present(progress)
            self.enqueue(report, context: context, peerId: peer.id, threadId: threadId, toTelegramTeam: false)
        }
        self.push(controller)
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
            self.show(textAlertController(sharedContext: self.sharedContext, title: "Send Crash Log?", text: "From: \(sender)\n\nThe archive includes the crash diagnostic and stack addresses. App and device details are included in the message text. You can review these in View Log.", actions: [
                TextAlertAction(type: .genericAction, title: self.sharedContext.currentPresentationData.with { $0 }.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .defaultAction, title: "Send", action: { self.send(report, context: context) })
            ]))
        }))
    }

    func send(_ report: CrashReport, context: AccountContext, completion: @escaping (Bool) -> Void = { _ in }) {
        guard self.canPresent, !self.busy else {
            completion(false)
            return
        }
        self.busy = true
        let progress = OverlayStatusController(theme: self.sharedContext.currentPresentationData.with { $0 }.theme, type: .loading(cancelled: nil))
        self.progress = progress
        self.present(progress)
        let botName = resolvedCrashReportBot(context)
        let resolution = context.engine.peers.resolvePeerByName(name: botName, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            if case let .result(peer) = result { return .single(peer) }
            return .complete()
        }
        |> take(1)
        |> timeout(15.0, queue: Queue.mainQueue(), alternate: .single(nil))
        |> deliverOnMainQueue
        self.disposable.set(resolution.start(next: { [weak self] peer in
            guard let self else {
                completion(false)
                return
            }
            guard let peer, case let .user(user) = peer, user.botInfo != nil else {
                self.finishSending()
                completion(false)
                self.alert("Could Not Find Crash Log Bot", "Check your connection and try again. The log remains saved on this device.")
                return
            }
            // Cached resolution can complete synchronously. Install the next phase after
            // the current MetaDisposable.set has returned.
            DispatchQueue.main.async {
                self.checkBlockedAndEnqueue(report, context: context, peer: peer, botName: botName, completion: completion)
            }
        }))
    }

    private func checkBlockedAndEnqueue(_ report: CrashReport, context: AccountContext, peer: EnginePeer, botName: String, completion: @escaping (Bool) -> Void) {
        let peerId = peer.id
        self.disposable.set((context.engine.data.get(TelegramEngine.EngineData.Item.Peer.IsBlocked(id: peerId))
        |> deliverOnMainQueue).start(next: { [weak self] blocked in
            guard let self else {
                completion(false)
                return
            }
            if case .known(true) = blocked {
                self.finishSending()
                completion(false)
                self.alert("Crash Log Bot Is Blocked", "Open @\(botName) and unblock it before sending the log.")
                return
            }
            self.enqueue(report, context: context, peerId: peerId, threadId: nil, toTelegramTeam: true, completion: completion)
        }))
    }

    private func enqueue(_ report: CrashReport, context: AccountContext, peerId: EnginePeer.Id, threadId: Int64?, toTelegramTeam: Bool, completion: @escaping (Bool) -> Void = { _ in }) {
        crashReportWorkQueue.async { [self] in
            let archive = Result { try crashReportArchive(report) }
            DispatchQueue.main.async { [self] in
                switch archive {
                case let .success(data):
                    let document = crashReportDocument(applicationVersion: report.metadata.applicationVersion, deviceType: report.metadata.deviceType)
                    let id = Int64.random(in: Int64.min ... Int64.max)
                    let resource = LocalFileMediaResource(fileId: id, size: Int64(data.count), isSecretRelated: false)
                    context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data)
                    let file = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: document.mimeType, size: Int64(data.count), attributes: [.FileName(fileName: document.fileName)], alternativeRepresentations: [])
                    let message: EnqueueMessage = .message(text: document.caption, attributes: [], inlineStickers: [:], mediaReference: .standalone(media: file), threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                    self.disposable.set((enqueueMessages(account: context.account, peerId: peerId, messages: [message])
                    |> mapToSignal { ids -> Signal<Bool, NoError> in
                        guard let messageId = ids.compactMap({ $0 }).first else {
                            return .single(false)
                        }
                        return crashReportServerAcceptance(account: context.account, messageId: messageId)
                    }
                    |> deliverOnMainQueue).start(next: { [weak self] confirmed in
                        guard let self else {
                            completion(confirmed)
                            return
                        }
                        self.finishSending()
                        if confirmed {
                            completion(true)
                            self.show(UndoOverlayController(presentationData: self.sharedContext.currentPresentationData.with { $0 }, content: .succeed(text: toTelegramTeam ? "Thank you for helping make Telegram better!" : "Log shared", timeout: nil, customUndoText: nil), action: { _ in
                                return false
                            }))
                        } else {
                            completion(false)
                            self.alert("Could Not Send Log", "Please try again. The log remains saved on this device.")
                        }
                    }))
                case .failure:
                    self.finishSending()
                    completion(false)
                    self.alert("Could Not Prepare Log", "Please try again. The log remains saved on this device.")
                }
            }
        }
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

/// `PresentationStrings` uses the server langpack, then the English bundle. A language
/// Tellomi ships uses its own lproj until that pack has a translation that is not the English sentence.
private var crashReportPromptTables: [String: [String: String]] = [:]
private let crashReportPromptTablesLock = NSLock()

private func crashReportPromptLproj(_ code: String) -> String? {
    let normalized = code.lowercased().replacingOccurrences(of: "_", with: "-")
    if normalized.isEmpty {
        return nil
    }
    if normalized == "en" || normalized.hasPrefix("en-") {
        return "en"
    }
    if normalized == "zh-hant" || normalized.hasPrefix("zh-hant-") || normalized == "zh-tw" || normalized.hasPrefix("zh-tw-") || normalized == "zh-hk" || normalized.hasPrefix("zh-hk-") || normalized == "zh-mo" || normalized.hasPrefix("zh-mo-") {
        return "zh-Hant"
    }
    if normalized == "zh" || normalized.hasPrefix("zh-") {
        return "zh-Hans"
    }
    if normalized.hasPrefix("pt") {
        return "pt"
    }
    let base = normalized.split(separator: "-").first.map(String.init) ?? normalized
    switch base {
    case "ar", "be", "ca", "de", "es", "fa", "fr", "id", "it", "ko", "ms", "nl", "pl", "ru", "tr", "uk", "uz":
        return base
    default:
        return nil
    }
}

private func crashReportPromptBundledString(_ key: String, _ folder: String) -> String? {
    crashReportPromptTablesLock.lock()
    let cached = crashReportPromptTables[folder]
    crashReportPromptTablesLock.unlock()
    let table: [String: String]
    if let cached {
        table = cached
    } else {
        guard let path = getAppBundle().path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: folder),
              let loaded = NSDictionary(contentsOfFile: path) as? [String: String] else {
            return nil
        }
        crashReportPromptTablesLock.lock()
        crashReportPromptTables[folder] = loaded
        crashReportPromptTablesLock.unlock()
        table = loaded
    }
    if let value = table[key], !value.isEmpty {
        return value
    }
    return nil
}

private func crashReportPromptString(_ strings: PresentationStrings, _ key: String, _ resolved: String) -> String {
    let english = crashReportPromptBundledString(key, "en")
    for code in [strings.primaryComponent.languageCode, strings.baseLanguageCode] {
        guard let folder = crashReportPromptLproj(code), folder != "en" else {
            continue
        }
        guard let bundled = crashReportPromptBundledString(key, folder) else {
            continue
        }
        if let english, resolved != english, resolved != key {
            return resolved
        }
        return bundled
    }
    return resolved
}

private func resolvedCrashReportBot(_ context: AccountContext) -> String {
    let configured = context.currentAppConfiguration.with { configuration -> String? in
        guard let data = configuration.data else {
            return nil
        }
        return data[crashReportBotConfigKey] as? String
    }
    return crashReportBotUsername(configured: configured)
}

/// Completes with the server's answer. A message that is still uploading or sending stays open.
private func crashReportServerAcceptance(account: Account, messageId: MessageId) -> Signal<Bool, NoError> {
    return account.postbox.messageView(messageId)
    |> map { view -> CrashReportDelivery in
        guard let message = view.message else {
            return .waiting
        }
        return crashReportDelivery(failed: message.flags.contains(.Failed), stillSending: message.flags.isSending)
    }
    |> mapToSignal { delivery -> Signal<Bool, NoError> in
        switch delivery {
        case .waiting:
            return .complete()
        case .sent:
            return .single(true)
        case .failed:
            return .single(false)
        }
    }
    |> take(1)
}

private func crashReportPromptApply(_ effects: [CrashReportPromptEffect], ids: Set<String>) {
    for effect in effects {
        if case .markResolved = effect {
            guard !ids.isEmpty else {
                return
            }
            crashReportWorkQueue.async {
                do {
                    try CrashReportStore.shared.markPresented(ids: ids)
                } catch {
                    // The choice stands for this launch. A failed write leaves the reports pending, so the next launch asks again.
                }
            }
        }
    }
}

/// Install only after the authorized root controller becomes ready. Storage and capture do not depend on this subscription.
public func setupCrashReportPrompt(context: AccountContext, isInternalBuild: Bool, navigationController: NavigationController, present: @escaping (ViewController) -> Void) -> Disposable {
    let actions = CrashReportActions(sharedContext: context.sharedContext, context: context)
    actions.present = present
    actions.push = { [weak navigationController] in navigationController?.pushViewController($0) }
    var machine = CrashReportPromptMachine()
    var latestEnvironment = CrashReportPromptEnvironment(canPresent: false, alertsEnabled: false, hasPending: false)
    var latestPending: [CrashReport] = []
    weak var alert: ViewController?
    var deliver: ([CrashReportPromptEffect], [CrashReport]) -> Void = { _, _ in }
    deliver = { effects, pending in
        for effect in effects {
            switch effect {
            case .dismiss:
                alert?.dismiss()
                alert = nil
            case .present:
                let offered = pending
                let ids = Set(offered.map(\.id))
                let strings = context.sharedContext.currentPresentationData.with { $0 }.strings
                let controller = textAlertController(sharedContext: context.sharedContext, title: crashReportPromptString(strings, "CrashReport.Prompt.Title", strings.CrashReport_Prompt_Title), text: crashReportPromptString(strings, "CrashReport.Prompt.Text", strings.CrashReport_Prompt_Text), actions: [
                    TextAlertAction(type: .genericAction, title: crashReportPromptString(strings, "CrashReport.Prompt.NotNow", strings.CrashReport_Prompt_NotNow), action: {
                        crashReportPromptApply(machine.decline(), ids: ids)
                    }),
                    TextAlertAction(type: .defaultAction, title: crashReportPromptString(strings, "CrashReport.Prompt.Send", strings.CrashReport_Prompt_Send), action: {
                        let _ = machine.beginSend()
                        guard let report = offered.first else {
                            let _ = machine.sendFailed()
                            deliver(machine.environment(latestEnvironment), latestPending)
                            return
                        }
                        actions.send(report, context: context, completion: { confirmed in
                            if confirmed {
                                crashReportPromptApply(machine.sendConfirmed(), ids: ids)
                            } else {
                                let _ = machine.sendFailed()
                                deliver(machine.environment(latestEnvironment), latestPending)
                            }
                        })
                    })
                ])
                alert = controller
                present(controller)
            case .markResolved:
                break
            }
        }
    }
    let disposable = (combineLatest(crashReportsSignal(), context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.experimentalUISettings]), context.sharedContext.applicationBindings.applicationIsActive, context.sharedContext.appLockContext.isPasscodeLocked)
    |> deliverOnMainQueue).start(next: { result, sharedData, active, locked in
        let canPresent = active && !locked
        actions.canPresent = canPresent
        let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings]?.get(ExperimentalUISettings.self) ?? .defaultSettings
        let alertsEnabled = crashReportAlertsEnabled(override: settings.showCrashReportAlerts, isInternalBuild: isInternalBuild)
        let pending: [CrashReport]
        if case let .success(reports) = result {
            pending = reports.filter { !$0.wasPresented }
        } else {
            pending = []
        }
        latestEnvironment = CrashReportPromptEnvironment(canPresent: canPresent, alertsEnabled: alertsEnabled, hasPending: !pending.isEmpty)
        latestPending = pending
        deliver(machine.environment(latestEnvironment), pending)
    })
    return ActionDisposable {
        disposable.dispose()
        Queue.mainQueue().async {
            actions.canPresent = false
            alert?.dismiss()
        }
    }
}
