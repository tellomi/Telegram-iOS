import AccountContext
import AppBundle
import AsyncDisplayKit
import ContextUI
import Display
import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import TellomiDiscover
import UIKit
import UIKitRuntimeUtils

/// Discover tab. The live feed stays off until `tellomi_discover_feed_enabled` is true.
/// Logged-out sessions keep the empty state and do not ask for a credential.
public final class TellomiFeedScreen: ViewController {
    private let context: AccountContext
    private var presentationData: PresentationData
    private var appConfiguration: AppConfiguration
    private var presentationDataDisposable: Disposable?
    private var configurationDisposable: Disposable?
    private var loggedOutDisposable: Disposable?
    private let loader: TellomiDiscoverLoader
    private var loggedOut = false
    private var kind: TellomiDiscoverFeedKind = .recommend
    private var tabs: [TellomiDiscoverFeedKind] = [.recommend, .following]
    private var posts: [TellomiDiscoverFeedKind: [TellomiDiscoverPost]] = [:]
    private var cursors: [TellomiDiscoverFeedKind: String] = [:]
    private var sawCapabilities = false
    private var engineHasFeed = false
    private var engineVisible: Bool?
    private var engineConfigLoaded = false
    private var textLimit = tellomiDiscoverPostTextLimit
    private var loading = false
    private var loadingMore = false
    private var feedGeneration = 0
    private var failed = false
    private var pendingPostId: String?
    private var audienceDisposable: Disposable?
    private var appliedLayout: ContainerViewLayout?

    private var feedNode: TellomiFeedScreenNode {
        return self.displayNode as! TellomiFeedScreenNode
    }

    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.appConfiguration = context.currentAppConfiguration.with { $0 }
        self.loader = tellomiDiscoverMakeLoader(account: context.account)

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))

        self.tabBarItemContextActionType = .always

        self.loggedOutDisposable = (context.account.loggedOut
        |> deliverOnMainQueue).start(next: { [weak self] loggedOut in
            guard let self else {
                return
            }
            self.loggedOut = loggedOut
            if loggedOut {
                self.loader.cancel()
                self.loading = false
                self.loadingMore = false
            }
            self.sync(reload: false)
        })
        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else {
                return
            }
            self.presentationData = presentationData
            self.sync(reload: false)
        })
        self.configurationDisposable = (context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.App())
        |> deliverOnMainQueue).start(next: { [weak self] configuration in
            guard let self else {
                return
            }
            self.appConfiguration = configuration
            self.sync(reload: false)
        })
        self.sync(reload: false)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
        self.configurationDisposable?.dispose()
        self.loggedOutDisposable?.dispose()
        self.audienceDisposable?.dispose()
        self.loader.cancel()
    }

    public func openPost(id: String) {
        self.pendingPostId = id
        if self.isNodeLoaded {
            self.sync(reload: false)
        }
    }

    override public func loadDisplayNode() {
        let node = TellomiFeedScreenNode()
        node.onSelectTab = { [weak self] index in
            self?.selectTab(index)
        }
        node.onSelectPost = { [weak self] id in
            self?.openPost(id: id)
        }
        node.onRefresh = { [weak self] in
            self?.loadFeed(reset: true)
        }
        node.onNearEnd = { [weak self] in
            self?.loadFeed(reset: false)
        }
        self.displayNode = node
        self.displayNodeDidLoad()
        self.sync(reload: true)
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.appliedLayout = layout
        let navigationHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.feedNode.updateLayout(size: layout.size, topInset: navigationHeight, bottomInset: layout.intrinsicInsets.bottom, transition: transition)
    }

    override public func tabBarItemContextAction(sourceView: ContextExtractedContentContainingView, gesture: ContextGesture) {
        guard tellomiBottomNavigationEnabled(appConfiguration: self.context.currentAppConfiguration.with { $0 }) else {
            return
        }
        let copy = TellomiTabCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode)
        let items: [ContextMenuItem] = [
            .action(ContextMenuActionItem(text: copy.hideFeed, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Peer Info/HideIcon"), color: theme.contextMenu.primaryColor)
            }, action: { [weak self] controller, _ in
                controller?.dismiss(completion: {
                    guard let self else {
                        return
                    }
                    let _ = updateTellomiTabSettingsInteractively(accountManager: self.context.sharedContext.accountManager, { settings in
                        return settings.withUpdatedShowFeedTab(false)
                    }).start()
                })
            }))
        ]
        let contextController = makeContextController(presentationData: self.presentationData, source: .reference(TellomiFeedTabBarContextReferenceContentSource(controller: self, sourceView: sourceView)), items: .single(ContextController.Items(content: .list(items))), recognizer: nil, gesture: gesture)
        self.context.sharedContext.mainWindow?.presentInGlobalOverlay(contextController)
    }

    private func configuration() -> TellomiDiscoverConfiguration {
        return TellomiDiscoverConfiguration.resolve(
            enabledField: tellomiDiscoverConfigField(self.appConfiguration.data?[tellomiDiscoverFeedEnabledKey]),
            baseURLField: tellomiDiscoverConfigField(self.appConfiguration.data?[tellomiDiscoverFeedBaseURLKey])
        )
    }

    private func sync(reload: Bool) {
        let configuration = self.configuration()
        let loggedIn = !self.loggedOut
        let legacy = TellomiTabCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode)
        let copy = TellomiDiscoverCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode)
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.title = legacy.feed
        self.navigationItem.title = legacy.feed
        self.tabBarItem.title = legacy.feed
        self.tabBarItem.image = tellomiFeedTabIcon(filled: false)
        self.tabBarItem.selectedImage = tellomiFeedTabIcon(filled: true)
        self.tabBarItem.animationName = nil
        self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: self.presentationData), transition: .immediate)

        if let pendingPostId = self.pendingPostId {
            let postChrome = tellomiDiscoverChrome(loggedIn: loggedIn, enabled: configuration.enabled, kind: self.kind, openedPostId: pendingPostId, failed: false)
            if case let .detail(id) = postChrome.surface {
                self.pendingPostId = nil
                let controller = TellomiDiscoverPostController(context: self.context, postId: id, loader: self.loader, configuration: configuration, loggedIn: loggedIn)
                self.push(controller)
            }
        }

        let chrome = tellomiDiscoverChrome(loggedIn: loggedIn, enabled: configuration.enabled, kind: self.kind, openedPostId: nil, failed: self.failed)
        if !chrome.issuesNetwork {
            self.loader.cancel()
            self.loading = false
            self.loadingMore = false
        }
        if chrome.showsCompose, self.engineVisible != false {
            self.navigationItem.setRightBarButton(UIBarButtonItem(title: copy.compose, style: .plain, target: self, action: #selector(self.composePressed)), animated: false)
        } else {
            self.navigationItem.setRightBarButton(nil, animated: false)
        }

        let mode: TellomiFeedNodeMode
        let legacyTitle: String
        let legacyBody: String
        switch chrome.surface {
        case .legacyEmpty(let postUnavailable):
            mode = .legacy
            legacyTitle = legacy.feedEmptyTitle
            legacyBody = postUnavailable || self.pendingPostId != nil ? legacy.feedPostUnavailable : legacy.feedEmptyText
        case .feed, .detail where self.engineVisible == false:
            mode = .legacy
            legacyTitle = legacy.feedEmptyTitle
            legacyBody = legacy.feedEmptyText
        case .feed, .detail:
            mode = .feed
            legacyTitle = copy.emptyTitle
            legacyBody = copy.emptyText
        case .nearby:
            mode = .feed
            legacyTitle = copy.emptyTitle
            legacyBody = copy.nearbyEmpty
        }
        let selected = self.tabs.firstIndex(of: self.kind) ?? 0
        if self.isNodeLoaded {
            self.feedNode.update(presentationData: self.presentationData, model: TellomiFeedNodeModel(
                mode: mode,
                tabTitles: self.tabs.map { self.tabTitle($0, copy: copy) },
                selectedTab: selected,
                posts: self.posts[self.kind] ?? [],
                loading: self.loading || self.loadingMore,
                failure: chrome.failure ? copy.failed : nil,
                legacyTitle: legacyTitle,
                legacyBody: legacyBody,
                copy: copy
            ))
            if let layout = self.appliedLayout {
                let navigationHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
                self.feedNode.updateLayout(size: layout.size, topInset: navigationHeight, bottomInset: layout.intrinsicInsets.bottom, transition: .immediate)
            }
        }
        if chrome.loadsFeed, self.engineVisible != false, !self.loading, reload || (self.posts[self.kind] == nil && !self.failed) {
            self.loadFeed(reset: true)
        }
    }

    private func tabTitle(_ kind: TellomiDiscoverFeedKind, copy: TellomiDiscoverCopy) -> String {
        switch kind {
        case .recommend:
            return copy.recommend
        case .following:
            return copy.following
        case .nearby:
            return copy.nearby
        }
    }

    private func selectTab(_ index: Int) {
        guard self.tabs.indices.contains(index) else {
            return
        }
        let kind = self.tabs[index]
        guard kind != self.kind else {
            return
        }
        self.kind = kind
        self.failed = false
        self.loading = false
        self.loadingMore = false
        self.sync(reload: true)
    }

    private func loadFeed(reset: Bool) {
        let configuration = self.configuration()
        let chrome = tellomiDiscoverChrome(loggedIn: !self.loggedOut, enabled: configuration.enabled, kind: self.kind, openedPostId: nil, failed: false)
        guard chrome.loadsFeed else {
            return
        }
        let cursor = reset ? nil : self.cursors[self.kind]
        if !reset {
            guard !self.loading, !self.loadingMore, cursor != nil else {
                return
            }
        }
        self.feedGeneration += 1
        let generation = self.feedGeneration
        if reset {
            self.loading = true
            self.loadingMore = false
            self.sawCapabilities = false
            self.engineVisible = nil
            self.engineConfigLoaded = false
        } else {
            self.loadingMore = true
        }
        self.advance(reset: reset, generation: generation, kind: self.kind, cursor: cursor, configuration: configuration)
    }

    private func advance(reset: Bool, generation: Int, kind: TellomiDiscoverFeedKind, cursor: String?, configuration: TellomiDiscoverConfiguration) {
        guard generation == self.feedGeneration else {
            return
        }
        let operation: TellomiDiscoverOperation
        if !self.sawCapabilities {
            operation = .capabilities
        } else if !self.engineHasFeed {
            self.finishHidden(generation: generation)
            return
        } else if self.engineVisible == nil {
            operation = .status
        } else if self.engineVisible == false {
            self.finishHidden(generation: generation)
            return
        } else if self.engineConfigLoaded == false, reset {
            operation = .engineConfig
        } else if kind == .nearby {
            self.loading = false
            self.loadingMore = false
            self.sync(reload: false)
            return
        } else {
            operation = .feed(kind, cursor: cursor, personalized: true)
        }
        self.loader.run(loggedIn: true, configuration: configuration, operation: operation) { [weak self] result in
            guard let self, self.feedGeneration == generation else {
                return
            }
            switch result {
            case let .success(.capabilities(value)):
                self.sawCapabilities = true
                self.engineHasFeed = value.features.contains("feed")
                self.advance(reset: reset, generation: generation, kind: kind, cursor: cursor, configuration: configuration)
            case let .success(.status(visible)):
                self.engineVisible = visible
                self.advance(reset: reset, generation: generation, kind: kind, cursor: cursor, configuration: configuration)
            case let .success(.engineConfig(value)):
                self.engineConfigLoaded = true
                self.textLimit = value.postTextChars
                if !value.tabs.isEmpty {
                    self.tabs = value.tabs
                    if !self.tabs.contains(self.kind) {
                        self.kind = self.tabs[0]
                    }
                }
                self.advance(reset: reset, generation: generation, kind: self.kind, cursor: cursor, configuration: configuration)
            case let .success(.feed(page)):
                if page.items.isEmpty {
                    if reset {
                        self.posts[kind] = []
                    }
                    self.cursors[kind] = nil
                    self.failed = false
                    self.loading = false
                    self.loadingMore = false
                    self.sync(reload: false)
                } else {
                    self.loadCards(page, reset: reset, generation: generation, kind: kind, configuration: configuration)
                }
            case .failure(.hidden):
                self.finishHidden(generation: generation)
            case .failure(.disabled), .failure(.signedOut):
                self.failed = false
                self.loading = false
                self.loadingMore = false
                self.sync(reload: false)
            case .failure:
                if reset {
                    self.failed = true
                }
                self.loading = false
                self.loadingMore = false
                self.sync(reload: false)
            default:
                self.failed = true
                self.loading = false
                self.loadingMore = false
                self.sync(reload: false)
            }
        }
    }

    private func loadCards(_ page: TellomiDiscoverFeedPage, reset: Bool, generation: Int, kind: TellomiDiscoverFeedKind, configuration: TellomiDiscoverConfiguration) {
        self.loader.run(loggedIn: true, configuration: configuration, operation: .cards(page.items.map(\.id))) { [weak self] result in
            guard let self, self.feedGeneration == generation else {
                return
            }
            self.loading = false
            self.loadingMore = false
            switch result {
            case let .success(.cards(cards)):
                let displayed = cards.map(tellomiDiscoverDisplayPost)
                if reset || self.posts[kind] == nil {
                    self.posts[kind] = displayed
                } else {
                    self.posts[kind, default: []].append(contentsOf: displayed)
                }
                if let cursor = page.cursor {
                    self.cursors[kind] = cursor
                } else {
                    self.cursors.removeValue(forKey: kind)
                }
                self.failed = false
            case .failure(.hidden):
                self.engineVisible = false
                self.failed = false
            case .failure:
                if reset {
                    self.failed = true
                }
            }
            self.sync(reload: false)
        }
    }

    private func finishHidden(generation: Int) {
        guard generation == self.feedGeneration else {
            return
        }
        self.engineVisible = false
        self.failed = false
        self.loading = false
        self.loadingMore = false
        self.posts[self.kind] = []
        self.sync(reload: false)
    }

    @objc private func composePressed() {
        let configuration = self.configuration()
        guard tellomiDiscoverChrome(loggedIn: !self.loggedOut, enabled: configuration.enabled, kind: self.kind, openedPostId: nil, failed: false).showsCompose else {
            return
        }
        let textLimit = self.textLimit
        let selfUserId = self.context.account.peerId.id._internalGetInt64Value()
        let controller = TellomiDiscoverComposeController(context: self.context, textLimit: textLimit, publish: { [weak self] text, visibility, userIds, nonce, completion in
            guard let self else {
                completion(.failure(.signedOut))
                return
            }
            let configuration = self.configuration()
            guard !self.loggedOut, configuration.enabled else {
                completion(.failure(self.loggedOut ? .signedOut : .disabled))
                return
            }
            let step = tellomiDiscoverPublishStep(text: text, visibility: visibility, userIds: userIds, selfUserId: selfUserId, clientNonce: nonce, textLimit: textLimit, token: nil, now: Int64(Date().timeIntervalSince1970))
            switch step {
            case .ready:
                self.loader.run(loggedIn: true, configuration: configuration, operation: .publish(text: text, visibility: visibility, audienceToken: nil, clientNonce: nonce, textLimit: textLimit), completion: completion)
            case let .needsAudienceToken(kind, ids):
                self.audienceDisposable?.dispose()
                self.audienceDisposable = (tellomiDiscoverAudienceToken(account: self.context.account, kind: kind, userIds: ids)
                |> deliverOnMainQueue).start(next: { [weak self] token in
                    guard let self else {
                        completion(.failure(.signedOut))
                        return
                    }
                    self.loader.run(loggedIn: true, configuration: configuration, operation: .publish(text: text, visibility: visibility, audienceToken: token.token, clientNonce: nonce, textLimit: textLimit), completion: completion)
                }, error: { error in
                    completion(.failure(tellomiDiscoverClientError(for: error)))
                })
            case let .rejected(error):
                completion(.failure(error))
            }
        }, published: { [weak self] in
            guard let self else {
                return
            }
            self.posts[self.kind] = nil
            self.sync(reload: true)
        })
        self.push(controller)
    }
}

private func tellomiDiscoverConfigField(_ value: JSONElement?) -> TellomiDiscoverConfigField {
    guard let value else {
        return .missing
    }
    if let value = value as? Bool {
        return .bool(value)
    }
    if let value = value as? String {
        return .string(value)
    }
    if let value = value as? Double {
        return .number(value)
    }
    if let value = value as? NSNumber {
        return .number(value.doubleValue)
    }
    return .missing
}

private func tellomiFeedTabIcon(filled: Bool) -> UIImage? {
    let side: CGFloat = 28.0
    UIGraphicsBeginImageContextWithOptions(CGSize(width: side, height: side), false, 0.0)
    defer {
        UIGraphicsEndImageContext()
    }
    let circle = UIBezierPath(ovalIn: CGRect(x: 2.5, y: 2.5, width: 23.0, height: 23.0))
    circle.lineWidth = 1.6
    UIColor.black.setStroke()
    circle.stroke()

    let needle = UIBezierPath()
    needle.move(to: CGPoint(x: 14.0, y: 7.0))
    needle.addLine(to: CGPoint(x: 18.5, y: 16.5))
    needle.addLine(to: CGPoint(x: 14.0, y: 21.0))
    needle.addLine(to: CGPoint(x: 9.5, y: 16.5))
    needle.close()
    UIColor.black.setFill()
    UIColor.black.setStroke()
    if filled {
        needle.fill()
    } else {
        needle.lineWidth = 1.4
        needle.stroke()
    }
    UIBezierPath(ovalIn: CGRect(x: 12.4, y: 12.4, width: 3.2, height: 3.2)).fill()
    return UIGraphicsGetImageFromCurrentImageContext()?.withRenderingMode(.alwaysTemplate)
}

private final class TellomiFeedTabBarContextReferenceContentSource: ContextReferenceContentSource {
    let keepInPlace: Bool = true

    private let controller: ViewController
    private let sourceView: ContextExtractedContentContainingView

    init(controller: ViewController, sourceView: ContextExtractedContentContainingView) {
        self.controller = controller
        self.sourceView = sourceView
    }

    func transitionInfo() -> ContextControllerReferenceViewInfo? {
        let _ = self.controller
        return ContextControllerReferenceViewInfo(
            referenceView: self.sourceView.contentView,
            contentAreaInScreenSpace: mainWindowScreenBounds,
            actionsPosition: .top
        )
    }
}
