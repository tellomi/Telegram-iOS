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
    private var city: String?
    private var pages: [TellomiDiscoverFeedKind: TellomiDiscoverPage] = [:]
    private var loading = false
    private var loadingMore = false
    private var feedGeneration = 0
    private var failed = false
    private var pendingPostId: String?
    private var cityLocator: TellomiDiscoverCityLocator?
    private var appliedLayout: ContainerViewLayout?

    private var feedNode: TellomiFeedScreenNode {
        return self.displayNode as! TellomiFeedScreenNode
    }

    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.appConfiguration = context.currentAppConfiguration.with { $0 }
        self.loader = tellomiDiscoverMakeLoader(account: context.account)
        self.city = tellomiDiscoverStoredCity()

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
                self.cityLocator?.stop()
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
        self.loader.cancel()
        self.cityLocator?.stop()
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
        node.onUseLocation = { [weak self] in
            self?.requestCity()
        }
        node.onSubmitCity = { [weak self] raw in
            self?.submitCity(raw)
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
            let postChrome = tellomiDiscoverChrome(loggedIn: loggedIn, enabled: configuration.enabled, kind: self.kind, city: self.city, openedPostId: pendingPostId, failed: false)
            if case let .detail(id) = postChrome.surface {
                self.pendingPostId = nil
                let controller = TellomiDiscoverPostController(context: self.context, postId: id, loader: self.loader, configuration: configuration, loggedIn: loggedIn)
                self.push(controller)
            }
        }

        let chrome = tellomiDiscoverChrome(loggedIn: loggedIn, enabled: configuration.enabled, kind: self.kind, city: self.city, openedPostId: nil, failed: self.failed)
        if !chrome.issuesNetwork {
            self.loader.cancel()
            self.loading = false
            self.loadingMore = false
            self.cityLocator?.stop()
        }
        if chrome.showsCompose {
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
        case .cityPrompt:
            mode = .city
            legacyTitle = ""
            legacyBody = ""
        case .feed, .detail:
            mode = .feed
            legacyTitle = copy.emptyTitle
            legacyBody = copy.emptyText
        }
        let selected: Int
        switch self.kind {
        case .recommend:
            selected = 0
        case .following:
            selected = 1
        case .nearby:
            selected = 2
        }
        if self.isNodeLoaded {
            self.feedNode.update(presentationData: self.presentationData, model: TellomiFeedNodeModel(
                mode: mode,
                selectedTab: selected,
                posts: self.pages[self.kind]?.posts ?? [],
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
        if chrome.loadsFeed && !self.loading && (reload || (self.pages[self.kind] == nil && !self.failed)) {
            self.loadFeed(reset: true)
        }
    }

    private func selectTab(_ index: Int) {
        let kind: TellomiDiscoverFeedKind
        switch index {
        case 1:
            kind = .following
        case 2:
            kind = .nearby
        default:
            kind = .recommend
        }
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
        let chrome = tellomiDiscoverChrome(loggedIn: !self.loggedOut, enabled: configuration.enabled, kind: self.kind, city: self.city, openedPostId: nil, failed: false)
        guard chrome.loadsFeed else {
            return
        }
        let cursor = reset ? nil : self.pages[self.kind]?.nextCursor
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
        } else {
            self.loadingMore = true
        }
        let kind = self.kind
        self.loader.run(loggedIn: true, configuration: configuration, operation: .feed(kind, cursor: cursor, city: self.city)) { [weak self] result in
            guard let self, self.feedGeneration == generation else {
                return
            }
            self.loading = false
            self.loadingMore = false
            guard self.kind == kind else {
                self.sync(reload: false)
                return
            }
            switch result {
            case let .success(.page(page)):
                if reset || self.pages[kind] == nil {
                    self.pages[kind] = page
                } else if var existing = self.pages[kind] {
                    existing.posts.append(contentsOf: page.posts)
                    existing.nextCursor = page.nextCursor
                    self.pages[kind] = existing
                }
                self.failed = false
            case .failure(.disabled), .failure(.signedOut), .failure(.needsCity):
                self.failed = false
            case .failure:
                if reset {
                    self.failed = true
                }
            }
            self.sync(reload: false)
        }
    }

    private func requestCity() {
        let configuration = self.configuration()
        let chrome = tellomiDiscoverChrome(loggedIn: !self.loggedOut, enabled: configuration.enabled, kind: .nearby, city: nil, openedPostId: nil, failed: false)
        guard chrome.surface == .cityPrompt else {
            return
        }
        self.cityLocator?.stop()
        let locator = TellomiDiscoverCityLocator()
        self.cityLocator = locator
        locator.onCity = { [weak self] city in
            guard let self else {
                return
            }
            self.cityLocator = nil
            if let city {
                self.submitCity(city)
            } else {
                self.sync(reload: false)
            }
        }
        locator.onDenied = { [weak self] in
            self?.cityLocator = nil
            self?.sync(reload: false)
        }
        locator.start()
    }

    private func submitCity(_ raw: String) {
        guard let city = tellomiDiscoverNormalizedCity(raw) else {
            return
        }
        tellomiDiscoverStoreCity(city)
        self.city = city
        self.pages[.nearby] = nil
        self.kind = .nearby
        self.failed = false
        self.sync(reload: true)
    }

    @objc private func composePressed() {
        let configuration = self.configuration()
        guard tellomiDiscoverChrome(loggedIn: !self.loggedOut, enabled: configuration.enabled, kind: self.kind, city: self.city, openedPostId: nil, failed: false).showsCompose else {
            return
        }
        let controller = TellomiDiscoverComposeController(context: self.context, publish: { [weak self] text, visibility, completion in
            guard let self else {
                completion(.failure(.signedOut))
                return
            }
            let configuration = self.configuration()
            guard !self.loggedOut, configuration.enabled else {
                completion(.failure(self.loggedOut ? .signedOut : .disabled))
                return
            }
            self.loader.run(loggedIn: true, configuration: configuration, operation: .publish(text: text, visibility: visibility), completion: completion)
        }, published: { [weak self] in
            guard let self else {
                return
            }
            self.pages[self.kind] = nil
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
