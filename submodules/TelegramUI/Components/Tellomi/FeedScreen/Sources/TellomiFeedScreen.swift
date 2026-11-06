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
    private var cityCode: String? = tellomiDiscoverStoredCity()
    private var locationAsked = false
    private var locator: TellomiDiscoverCityLocator?
    private var banner: String?
    private var tabs: [TellomiDiscoverFeedKind] = tellomiDiscoverHomeTabs()
    private var pickingCity = false
    private var nearbyUnavailable = false
    private var posts: [TellomiDiscoverFeedKind: [TellomiDiscoverPost]] = [:]
    private var cursors: [TellomiDiscoverFeedKind: String] = [:]
    private var sawCapabilities = false
    private var engineHasFeed = false
    private var engineVisible: Bool?
    private var engineConfigLoaded = false
    private var textLimit = tellomiDiscoverPostTextLimit
    private var mediaUpload = false
    private var mediaBaseURL: URL?
    private let localPreviews = TellomiDiscoverLocalPreviewBook()
    private var previewAccount: String {
        if let id = self.context.account.peerId.tellomiCloudUserId {
            return String(id)
        }
        return ""
    }
    private var notedAccount: String?
    private var loading = false
    private var loadingMore = false
    private var feedGeneration = 0
    private var failed = false
    private var pendingPostId: String?
    /// A chat close can still be tearing the feed screen out of the navigation
    /// stack. Presenting the post then is a no-op, so it is retried for about a
    /// second (D-57), the same window the Android bar uses.
    private var postPresentAttempts = 0
    private var postPresentRetryQueued = false
    private let postPresentAttemptLimit = 12
    private var audienceDisposable: Disposable?
    private var recommendationDisposable: Disposable?
    private var recommendationKnown = false
    private var personalizedRecommend = true
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
                self.notedAccount = nil
                self.loader.signOut()
                self.localPreviews.dropAll()
                self.loading = false
                self.loadingMore = false
            } else {
                let account = self.previewAccount
                if !account.isEmpty, account != self.notedAccount {
                    self.notedAccount = account
                    self.loader.noteSignedIn(account: account)
                }
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
        self.recommendationDisposable = (context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.ApplicationSpecificPreference(key: ApplicationSpecificPreferencesKeys.tellomiRecommendationSettings))
        |> deliverOnMainQueue).start(next: { [weak self] entry in
            guard let self else {
                return
            }
            let personalized = tellomiRecommendFeedIsPersonalized(tellomiRecommendationChoice(storedPersonalized: tellomiRecommendationSettings(entry: entry).personalized))
            let update = tellomiRecommendCacheUpdate(preferenceKnown: self.recommendationKnown, wasPersonalized: self.personalizedRecommend, isPersonalized: personalized, viewingRecommend: self.kind == .recommend)
            self.recommendationKnown = true
            self.personalizedRecommend = personalized
            switch update {
            case .none:
                // The view's own sync skipped Recommend until this value arrived.
                // Do not start that request before the tab has loaded its view.
                if self.isNodeLoaded, self.kind == .recommend, self.posts[.recommend] == nil, !self.loading {
                    self.sync(reload: true)
                }
            case let .drop(reload):
                self.posts[.recommend] = nil
                self.cursors[.recommend] = nil
                if reload {
                    self.failed = false
                    self.banner = nil
                    self.loading = false
                    self.loadingMore = false
                    self.feedGeneration += 1
                    let configuration = self.configuration()
                    let chrome = tellomiDiscoverChrome(loggedIn: !self.loggedOut, enabled: configuration.enabled, kind: .recommend, openedPostId: nil, failed: false, city: self.cityCode)
                    if chrome.loadsFeed, self.engineVisible != false {
                        self.loadFeed(reset: true)
                    }
                    self.sync(reload: false)
                }
            }
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
        self.recommendationDisposable?.dispose()
        self.locator?.stop()
        self.loader.cancel()
    }

    private func presentPostMenu(_ id: String) {
        guard let id = tellomiDiscoverPostId(id) else {
            return
        }
        let post = (self.posts[self.kind] ?? []).first(where: { $0.id == id })
        tellomiPresentDiscoverPostMenu(host: self, context: self.context, loggedIn: !self.loggedOut, configuration: self.configuration(), loader: self.loader, postId: id, post: post, onReposted: { [weak self] reposted in
            self?.noteRepost(id: id, reposted: reposted)
        }, onQuote: { [weak self] in
            self?.presentCompose(quoteOf: id, quotePreview: post?.text ?? "")
        })
    }

    private func noteRepost(id: String, reposted: Bool) {
        guard var posts = self.posts[self.kind], let index = posts.firstIndex(where: { $0.id == id }) else {
            return
        }
        var current = posts[index]
        current.reposted = reposted
        current.repostCount = max(0, current.repostCount + (reposted ? 1 : -1))
        posts[index] = current
        self.posts[self.kind] = posts
        self.sync(reload: false)
    }

    public func openPost(id: String) {
        if self.pendingPostId != id {
            self.postPresentAttempts = 0
            self.postPresentRetryQueued = false
        }
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
        node.onReportPost = { [weak self] id in
            self?.presentPostMenu(id)
        }
        node.onRefresh = { [weak self] in
            self?.loadFeed(reset: true)
        }
        node.onNearEnd = { [weak self] in
            self?.loadFeed(reset: false)
        }
        node.onUseLocation = { [weak self] in
            self?.startLocator()
        }
        node.onSelectCity = { [weak self] code in
            self?.applyCity(code)
        }
        node.onChangeCity = { [weak self] in
            self?.pickingCity = true
            self?.sync(reload: false)
        }
        node.onClearCity = { [weak self] in
            self?.clearCity()
        }
        node.onLegacyTitle = { [weak self] in
            guard let self, self.kind == .nearby, self.nearbyUnavailable else {
                return
            }
            self.nearbyUnavailable = false
            self.failed = false
            self.loadFeed(reset: true)
            self.sync(reload: false)
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
        let copy = TellomiTabCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode, pack: self.stringPack())
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

    private func stringPack() -> [String: String] {
        return tellomiStringPack(primary: self.presentationData.strings.primaryComponent.dict, secondary: self.presentationData.strings.secondaryComponent?.dict)
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
        let legacy = TellomiTabCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode, pack: self.stringPack())
        let copy = TellomiDiscoverCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode, pack: self.stringPack())
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.title = legacy.feed
        self.navigationItem.title = legacy.feed
        self.tabBarItem.title = legacy.feed
        self.tabBarItem.image = UIImage(bundleImageName: "Chat List/Tabs/IconDiscover")
        self.tabBarItem.selectedImage = UIImage(bundleImageName: "Chat List/Tabs/IconDiscoverFilled")
        self.tabBarItem.animationName = nil
        self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: self.presentationData), transition: .immediate)

        if let pendingPostId = self.pendingPostId {
            let postChrome = tellomiDiscoverChrome(loggedIn: loggedIn, enabled: configuration.enabled, kind: self.kind, openedPostId: pendingPostId, failed: false, city: self.cityCode)
            if case let .detail(id) = postChrome.surface {
                if self.navigationController != nil {
                    self.pendingPostId = nil
                    self.postPresentAttempts = 0
                    self.postPresentRetryQueued = false
                    let controller = TellomiDiscoverPostController(context: self.context, postId: id, loader: self.loader, configuration: configuration, loggedIn: loggedIn, mediaUpload: self.mediaUpload, mediaBaseURL: self.mediaBaseURL, previews: self.localPreviews, previewAccount: self.previewAccount)
                    self.push(controller)
                } else if !self.postPresentRetryQueued, self.postPresentAttempts < self.postPresentAttemptLimit {
                    self.postPresentAttempts += 1
                    self.postPresentRetryQueued = true
                    Queue.mainQueue().after(0.08) { [weak self] in
                        guard let self else {
                            return
                        }
                        self.postPresentRetryQueued = false
                        if self.pendingPostId != nil {
                            self.sync(reload: false)
                        }
                    }
                }
            }
        }

        let chrome = tellomiDiscoverChrome(loggedIn: loggedIn, enabled: configuration.enabled, kind: self.kind, openedPostId: nil, failed: self.failed, city: self.cityCode)
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
        case .feed where self.engineVisible == false, .detail where self.engineVisible == false:
            mode = .legacy
            legacyTitle = legacy.feedEmptyTitle
            legacyBody = legacy.feedEmptyText
        case .feed where self.pickingCity, .chooseCity:
            mode = .city
            legacyTitle = copy.cityPrompt
            legacyBody = copy.cityDenied
        case .feed, .detail:
            mode = .feed
            if self.kind == .nearby, self.nearbyUnavailable {
                legacyTitle = copy.nearbyUnavailable
                legacyBody = copy.nearbyUnavailableHint
            } else if self.kind == .nearby {
                legacyTitle = copy.nearbyEmpty
                legacyBody = copy.cityDenied
            } else {
                legacyTitle = copy.emptyTitle
                legacyBody = copy.emptyText
            }
        }
        let selected = self.tabs.firstIndex(of: self.kind) ?? 0
        let languageCode = self.presentationData.strings.primaryComponent.languageCode
        let pack = self.stringPack()
        let publishCity = tellomiDiscoverPublishCity(self.cityCode)
        let showCityLine = mode == .feed
        if self.isNodeLoaded {
            self.feedNode.update(presentationData: self.presentationData, model: TellomiFeedNodeModel(
                mode: mode,
                tabTitles: self.tabs.map { self.tabTitle($0, copy: copy) },
                selectedTab: selected,
                posts: self.posts[self.kind] ?? [],
                loading: self.loading || self.loadingMore,
                failure: self.banner ?? (chrome.failure ? copy.failed : nil),
                legacyTitle: legacyTitle,
                legacyBody: legacyBody,
                copy: copy,
                cities: tellomiDiscoverCities(languageCode: languageCode, pack: pack),
                cityLine: showCityLine ? tellomiDiscoverComposeCityLine(self.cityCode, languageCode: languageCode, pack: pack) : nil,
                cityAction: showCityLine ? (publishCity == nil ? copy.cityPrompt : copy.changeCity) : nil,
                clearCityTitle: mode == .city && publishCity != nil ? copy.composeCityNone : nil,
                legacyTitleTappable: mode == .feed && self.kind == .nearby && self.nearbyUnavailable && !self.loading
            ))
            if let layout = self.appliedLayout {
                let navigationHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
                self.feedNode.updateLayout(size: layout.size, topInset: navigationHeight, bottomInset: layout.intrinsicInsets.bottom, transition: .immediate)
            }
        }
        let waitingForRecommendation = self.kind == .recommend && !self.recommendationKnown
        if chrome.loadsFeed, !self.pickingCity, self.engineVisible != false, !self.loading, !waitingForRecommendation, reload || (self.posts[self.kind] == nil && !self.failed && !self.nearbyUnavailable) {
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
        self.pickingCity = false
        guard kind != self.kind else {
            self.sync(reload: false)
            return
        }
        self.kind = kind
        self.failed = false
        self.banner = nil
        self.loading = false
        self.loadingMore = false
        if kind == .nearby {
            self.considerNearbyLocation()
        }
        self.sync(reload: true)
    }

    private func considerNearbyLocation() {
        let gate = tellomiDiscoverNearbyGate(city: self.cityCode, location: tellomiDiscoverLocationGate(), asked: self.locationAsked)
        if case .choose(true) = gate {
            self.locationAsked = true
            self.startLocator()
        }
    }

    private func startLocator() {
        self.locator?.stop()
        let locator = TellomiDiscoverCityLocator()
        locator.onCity = { [weak self] code in
            guard let self else {
                return
            }
            if self.cityCode == nil, let code {
                self.applyCity(code)
            } else {
                self.sync(reload: false)
            }
        }
        locator.onDenied = { [weak self] in
            self?.sync(reload: false)
        }
        self.locator = locator
        locator.start()
    }

    private func applyCity(_ code: String) {
        guard let code = tellomiDiscoverKnownCityCode(code) else {
            self.banner = TellomiDiscoverCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode, pack: self.stringPack()).invalidCity
            self.sync(reload: false)
            return
        }
        self.locator?.stop()
        self.cityCode = code
        tellomiDiscoverStoreCity(code)
        self.pickingCity = false
        self.nearbyUnavailable = false
        self.banner = nil
        self.failed = false
        self.posts[.nearby] = nil
        self.cursors[.nearby] = nil
        self.sync(reload: true)
    }

    private func clearCity() {
        self.locator?.stop()
        self.cityCode = nil
        tellomiDiscoverStoreCity(nil)
        self.pickingCity = false
        self.nearbyUnavailable = false
        self.banner = nil
        self.failed = false
        self.posts[.nearby] = nil
        self.cursors[.nearby] = nil
        self.sync(reload: false)
    }

    private func loadFeed(reset: Bool) {
        let configuration = self.configuration()
        let chrome = tellomiDiscoverChrome(loggedIn: !self.loggedOut, enabled: configuration.enabled, kind: self.kind, openedPostId: nil, failed: false, city: self.cityCode)
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
            guard let city = tellomiDiscoverKnownCityCode(self.cityCode) else {
                self.loading = false
                self.loadingMore = false
                self.sync(reload: false)
                return
            }
            operation = .nearby(city: city, cursor: cursor)
        } else {
            operation = .feed(kind, cursor: cursor, personalized: tellomiDiscoverFeedRequestPersonalized(kind: kind, switchOn: self.personalizedRecommend))
        }
        self.loader.run(loggedIn: true, configuration: configuration, operation: operation) { [weak self] result in
            guard let self, self.feedGeneration == generation else {
                return
            }
            switch result {
            case let .success(.capabilities(value)):
                self.sawCapabilities = true
                self.engineHasFeed = value.features.contains("feed")
                self.mediaUpload = tellomiDiscoverFeatureEnabled(value, TellomiDiscoverImageContract.mediaUpload)
                self.advance(reset: reset, generation: generation, kind: kind, cursor: cursor, configuration: configuration)
            case let .success(.status(visible)):
                self.engineVisible = visible
                self.advance(reset: reset, generation: generation, kind: kind, cursor: cursor, configuration: configuration)
            case let .success(.engineConfig(value)):
                self.engineConfigLoaded = true
                self.textLimit = value.postTextChars
                self.mediaBaseURL = value.mediaBaseURL
                self.tabs = tellomiDiscoverHomeTabs()
                if !self.tabs.contains(self.kind) {
                    self.kind = self.tabs[0]
                    if self.kind == .nearby {
                        self.considerNearbyLocation()
                    }
                }
                self.advance(reset: reset, generation: generation, kind: self.kind, cursor: cursor, configuration: configuration)
            case let .success(.feed(page)):
                if kind == .nearby {
                    self.nearbyUnavailable = false
                }
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
            case .failure(.nearbyUnavailable):
                self.nearbyUnavailable = true
                self.failed = false
                self.banner = nil
                self.posts[kind] = []
                self.cursors.removeValue(forKey: kind)
                self.loading = false
                self.loadingMore = false
                self.sync(reload: false)
            case .failure(.invalidCity):
                self.nearbyUnavailable = false
                self.cityCode = nil
                tellomiDiscoverStoreCity(nil)
                self.banner = TellomiDiscoverCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode, pack: self.stringPack()).invalidCity
                self.loading = false
                self.loadingMore = false
                self.sync(reload: false)
            case .failure(.disabled), .failure(.signedOut):
                self.nearbyUnavailable = false
                self.failed = false
                self.loading = false
                self.loadingMore = false
                self.sync(reload: false)
            case .failure:
                self.nearbyUnavailable = false
                if reset {
                    self.failed = true
                }
                self.loading = false
                self.loadingMore = false
                self.sync(reload: false)
            default:
                self.nearbyUnavailable = false
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
            case .success:
                if reset {
                    self.failed = true
                }
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
        self.presentCompose(quoteOf: nil, quotePreview: "")
    }

    private func presentCompose(quoteOf: String?, quotePreview: String) {
        let configuration = self.configuration()
        guard tellomiDiscoverChrome(loggedIn: !self.loggedOut, enabled: configuration.enabled, kind: self.kind, openedPostId: nil, failed: false, city: self.cityCode).showsCompose else {
            return
        }
        let textLimit = self.textLimit
        let controller = TellomiDiscoverComposeController(context: self.context, textLimit: textLimit, quoteOf: quoteOf, quotePreview: quotePreview, publish: { [weak self] request, completion in
            guard let self else {
                completion(.failure(.signedOut))
                return
            }
            let city = tellomiDiscoverPublishCity(self.cityCode)
            tellomiRunDiscoverPublish(context: self.context, loader: self.loader, configuration: self.configuration(), loggedIn: !self.loggedOut, city: city, textLimit: textLimit, request: request, retainAudience: { [weak self] disposable in
                self?.audienceDisposable?.dispose()
                self?.audienceDisposable = disposable
            }, completion: completion)
        }, published: { [weak self] in
            guard let self else {
                return
            }
            self.posts[self.kind] = nil
            self.sync(reload: true)
        }, mediaUpload: self.mediaUpload, configuration: configuration, loader: self.loader, previews: self.localPreviews, previewAccount: self.previewAccount)
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
