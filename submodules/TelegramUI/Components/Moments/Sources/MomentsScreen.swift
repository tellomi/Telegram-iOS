import Foundation
import UIKit
import Display
import AppBundle
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import ComponentFlow
import HorizontalTabsComponent
import PeerReportScreen
import PresentationDataUtils

public final class MomentsScreen: ViewController {
    private let context: AccountContext
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    private var networkDisposable: Disposable?
    private let launchDisposable = DisposableSet()
    private var resetWhenShown = false
    /// A comment sheet covers the list. Dismissing it must not reset the tab or the scroll position.
    var suppressFeedReset = false
    public var openPeer: ((EnginePeer.Id) -> Void)?

    private var nodeIfLoaded: MomentsScreenNode {
        return self.displayNode as! MomentsScreenNode
    }

    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: nil)
        self.title = momentsText(self.presentationData.strings, .title)
        self.tabBarItem.title = self.title
        self.tabBarItem.image = momentsTabIcon()
        self.tabBarItem.selectedImage = self.tabBarItem.image
        self.scrollToTop = { [weak self] in
            self?.nodeIfLoaded.scrollToTop()
        }
        self.presentationDataDisposable = (context.sharedContext.presentationData |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else { return }
            self.presentationData = presentationData
            self.title = momentsText(presentationData.strings, .title)
            self.tabBarItem.title = self.title
            if self.isNodeLoaded {
                self.nodeIfLoaded.updatePresentationData(presentationData)
            }
        })
        self.networkDisposable = (context.account.networkState |> deliverOnMainQueue).start(next: { [weak self] state in
            self?.nodeIfLoadedIfReady?.setNetworkState(state)
        })
        self.launchDisposable.add((context.engine.moments.reloadPersonalizedRecommendations() |> deliverOnMainQueue).start(next: { _ in }))
        self.launchDisposable.add((context.engine.moments.remoteConfig() |> deliverOnMainQueue).start(next: { [weak self] _ in
            self?.nodeIfLoadedIfReady?.remoteConfigUpdated()
        }, error: { _ in }))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
        self.networkDisposable?.dispose()
        self.launchDisposable.dispose()
    }

    private var nodeIfLoadedIfReady: MomentsScreenNode? {
        return self.isNodeLoaded ? self.nodeIfLoaded : nil
    }

    override public func loadDisplayNode() {
        self.displayNode = MomentsScreenNode(context: self.context, controller: self)
        self.displayNodeDidLoad()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.nodeIfLoaded.containerLayoutUpdated(layout, transition: transition)
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if self.suppressFeedReset {
            return
        }
        let top = self.navigationController?.topViewController
        if top === self.parent || top === self {
            self.resetWhenShown = true
        }
        self.nodeIfLoadedIfReady?.setScreenVisible(false)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !self.suppressFeedReset {
            self.nodeIfLoadedIfReady?.setScreenVisible(true)
            if self.resetWhenShown {
                self.resetWhenShown = false
                self.nodeIfLoaded.resetToRecommend()
            }
        }
        self.refreshBadge()
    }

    public func refreshBadge() {
        let _ = (self.context.engine.moments.notifications(tab: "interactions") |> deliverOnMainQueue).start(next: { [weak self] items in
            let unread = items.contains(where: { !$0.read })
            self?.tabBarItem.badgeValue = unread ? "•" : nil
        }, error: { _ in })
    }
}

private final class MomentsFeedModel {
    var items: [MomentsCard] = []
    var cursor: String?
    var loading = false
    var failed = false
    var failedRefresh = false
    var loaded = false
    var newCount = 0
    var renderedIds: [String] = []
}

final class MomentsPagerView: UIScrollView, UIGestureRecognizerDelegate {
    var albumHit: ((CGPoint) -> Bool)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isPagingEnabled = true
        self.showsHorizontalScrollIndicator = false
        self.panGestureRecognizer.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === self.panGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        let point = gestureRecognizer.location(in: self)
        if point.x - self.contentOffset.x < 24 {
            return false
        }
        if self.albumHit?(point) == true {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

final class MomentsScreenNode: ASDisplayNode, UIScrollViewDelegate {
    private let context: AccountContext
    private weak var controller: MomentsScreen?
    private var presentationData: PresentationData
    private let titleLabel = UILabel()
    private let compose = UIButton(type: .system)
    private let heart = UIButton(type: .system)
    private let pill = UIButton(type: .system)
    private let tabs = ComponentView<Empty>()
    private let pager = MomentsPagerView()
    private var lists: [MomentsFeedKind: ListView] = [:]
    private var models: [MomentsFeedKind: MomentsFeedModel] = [:]
    private var selected: MomentsFeedKind = .recommend
    /// FR-010. Always these four, including when capabilities omits `friends`.
    private var visibleTabs: [MomentsFeedKind] = [.recommend, .following, .friends, .nearby]
    private var expanded: Set<String> = []
    private var albumIndex: [String: Int] = [:]
    private var sessionHidden: Set<String> = []
    private var hides = MomentsLocalHides()
    private var nearbySort = "latest"
    private var playing: MomentsPlaybackRequest = .none
    private var resolvingPlayback = false
    private let disposable = DisposableSet()
    private var probe: SwiftSignalKit.Timer?
    private let sortControl = UIButton(type: .system)
    private let composeFab = UIButton(type: .system)
    private var validLayout: ContainerViewLayout?
    /// Ids the list has already applied. A second layout pass must not update rows the list does not have yet.
    private var appliedIds: [MomentsFeedKind: [String]] = [:]
    private var appliedPrints: [MomentsFeedKind: [String]] = [:]
    private var listBusy: [MomentsFeedKind: Bool] = [:]
    private var renderQueued: Set<MomentsFeedKind> = []
    private var renderEpoch: [MomentsFeedKind: Int] = [:]
    private var renderedListSize: [MomentsFeedKind: CGSize] = [:]
    private var loadEpoch: [MomentsFeedKind: Int] = [:]
    private var loadDisposables: [MomentsFeedKind: Disposable] = [:]
    private var pullOffset: [MomentsFeedKind: CGFloat] = [:]
    private var screenVisible = false
    private var offeredPendingSend = false
    private var postedCard: MomentsCard?
    private var displayedPersonalized: Bool?
    private var probeEpoch = 0
    private var probeDisposable: Disposable?
    private let prefetch: MomentsPrefetchManager

    init(context: AccountContext, controller: MomentsScreen) {
        self.context = context
        self.controller = controller
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.prefetch = MomentsPrefetchManager(context: context)
        super.init()
        self.setViewBlock { UITracingLayerView() }
        for kind in self.visibleTabs {
            self.models[kind] = MomentsFeedModel()
            let list = ListViewImpl()
            list.didScrollWithOffset = { [weak self] _, _, _, _ in
                self?.updateVisiblePlayback()
            }
            list.displayedItemRangeChanged = { [weak self] range, _ in
                guard let self, kind == self.selected else {
                    return
                }
                let cards = self.models[kind]?.items ?? []
                let first = range.visibleRange?.firstIndex ?? range.loadedRange?.firstIndex ?? 0
                let last = range.visibleRange?.lastIndex ?? range.loadedRange?.lastIndex ?? first
                self.prefetch.update(cards: cards, firstIndex: first, lastIndex: last)
            }
            list.visibleContentOffsetChanged = { [weak self] offset, _ in
                guard let self else { return }
                if case let .known(value) = offset {
                    self.pullOffset[kind] = value
                }
            }
            list.visibleBottomContentOffsetChanged = { [weak self] offset in
                guard let self, kind == self.selected else { return }
                if case let .known(value) = offset, value < 240 {
                    self.load(kind, refresh: false)
                }
            }
            list.didEndScrolling = { [weak self] _ in
                guard let self, kind == self.selected else { return }
                if (self.pullOffset[kind] ?? 0) < -64 {
                    self.load(kind, refresh: true)
                }
            }
            self.lists[kind] = list
            self.pager.addSubview(list.view)
        }
        self.view.addSubview(self.titleLabel)
        self.view.addSubview(self.heart)
        self.view.addSubview(self.pill)
        self.view.addSubview(self.sortControl)
        self.view.addSubview(self.pager)
        self.view.addSubview(self.composeFab)
        self.composeFab.layer.cornerRadius = 24
        self.composeFab.clipsToBounds = true
        self.compose.isHidden = true
        self.pager.delegate = self
        self.pager.albumHit = { [weak self] point in
            self?.pointHitsAlbum(point) ?? false
        }
        self.composeFab.addTarget(self, action: #selector(self.composePressed), for: .touchUpInside)
        self.heart.addTarget(self, action: #selector(self.heartPressed), for: .touchUpInside)
        self.pill.addTarget(self, action: #selector(self.pillPressed), for: .touchUpInside)
        self.sortControl.addTarget(self, action: #selector(self.sortPressed), for: .touchUpInside)
        self.titleLabel.font = Font.semibold(17)
        self.pill.isHidden = true
        self.pill.layer.cornerRadius = 14
        self.disposable.add(context.engine.moments.cachedHides().start(next: { [weak self] hides in
            self?.hides = hides
            self?.render(self?.selected ?? .recommend, resetScroll: false)
        }))
        self.disposable.add((context.engine.moments.personalizedRecommendationsSignal() |> deliverOnMainQueue).start(next: { [weak self] value in
            self?.personalizedChanged(value)
        }))
    }

    deinit {
        self.disposable.dispose()
        self.probe?.invalidate()
        self.probeDisposable?.dispose()
        for disposable in self.loadDisposables.values {
            disposable.dispose()
        }
    }

    func updatePresentationData(_ presentationData: PresentationData) {
        self.presentationData = presentationData
        self.render(self.selected, resetScroll: false)
    }

    func setNetworkState(_ state: AccountNetworkState) {
        let strings = self.presentationData.strings
        switch state {
        case .waitingForNetwork:
            self.titleLabel.text = strings.State_WaitingForNetwork
        case .connecting:
            self.titleLabel.text = strings.State_Connecting
        case .updating:
            self.titleLabel.text = strings.State_Updating
        case .online:
            self.titleLabel.text = momentsText(strings, .title)
        }
    }

    func scrollToTop() {
        guard self.listBusy[self.selected] != true, (self.appliedIds[self.selected]?.isEmpty == false) else {
            return
        }
        self.lists[self.selected]?.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous], scrollToItem: ListViewScrollToItem(index: 0, position: .top(0), animated: true, curve: .Default(duration: 0.25), directionHint: .Up), updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
    }

    func resetToRecommend() {
        self.sessionHidden.removeAll()
        self.selected = .recommend
        let width = self.pager.bounds.width
        if width > 0 {
            self.pager.setContentOffset(.zero, animated: false)
        }
        self.load(.recommend, refresh: true)
        self.updateSelectionChrome()
        self.scheduleProbe()
    }

    func remoteConfigUpdated() {
        self.scheduleProbe()
    }

    private func personalizedChanged(_ value: Bool) {
        let previous = self.displayedPersonalized
        self.displayedPersonalized = value
        guard let previous, previous != value else {
            return
        }
        let model = self.models[.recommend]
        if model?.loaded == true || model?.loading == true {
            self.load(.recommend, refresh: true)
        }
    }

    func setScreenVisible(_ visible: Bool) {
        guard visible != self.screenVisible else { return }
        self.screenVisible = visible
        self.scheduleProbe()
        if visible {
            self.offerPendingSend()
        }
    }

    /// A killed app left a post in the outbox. Offer that one task; do not send it until asked.
    private func offerPendingSend() {
        guard !self.offeredPendingSend, let controller = self.controller else {
            return
        }
        if controller.navigationController?.viewControllers.contains(where: { $0 is MomentsComposerScreen }) == true {
            return
        }
        let _ = (self.context.engine.moments.storedPendingPosts()
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] posts in
            guard let self, let controller = self.controller, let post = momentsSelectPendingPost(posts) else {
                return
            }
            if controller.navigationController?.viewControllers.contains(where: { $0 is MomentsComposerScreen }) == true {
                return
            }
            guard momentsPendingDisposition(post, fileExists: { FileManager.default.fileExists(atPath: $0) }) == .offerRetry else {
                return
            }
            guard !self.offeredPendingSend else {
                return
            }
            self.offeredPendingSend = true
            let strings = self.presentationData.strings
            controller.present(textAlertController(context: self.context, title: strings.Moments_Outbox_Title, text: strings.Moments_Outbox_Text, actions: [
                TextAlertAction(type: .defaultAction, title: strings.Moments_Outbox_Retry, action: { [weak self] in
                    self?.presentComposer(quoteId: nil, sendPending: true)
                }),
                TextAlertAction(type: .destructiveAction, title: strings.Moments_Draft_Discard, action: { [weak self] in
                    self?.context.engine.moments.storePendingPosts([])
                }),
                TextAlertAction(type: .genericAction, title: strings.Moments_Outbox_Later, action: {})
            ], actionLayout: .vertical), in: .window(.root))
        })
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.validLayout = layout
        let top = (layout.statusBarHeight ?? 20) 
        let width = layout.size.width
        self.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
        self.titleLabel.textColor = self.presentationData.theme.list.itemPrimaryTextColor
        if self.titleLabel.text == nil {
            self.titleLabel.text = momentsText(self.presentationData.strings, .title)
        }
        self.titleLabel.frame = CGRect(x: 16, y: top, width: width - 140, height: 44)
        self.heart.frame = CGRect(x: width - 52, y: top + 6, width: 40, height: 32)
        let iconColor = self.presentationData.theme.list.itemPrimaryTextColor
        self.heart.setTitle(nil, for: .normal)
        self.heart.setImage(generateTintedImage(image: UIImage(bundleImageName: "Stories/InputLikeOff"), color: iconColor), for: .normal)
        self.heart.accessibilityLabel = momentsText(self.presentationData.strings, .notifications)
        let accent = self.presentationData.theme.list.itemAccentColor
        self.composeFab.backgroundColor = accent
        self.composeFab.setImage(momentsTintedIcon("Chat List/ComposeIcon", .white), for: .normal)
        self.composeFab.accessibilityLabel = momentsText(self.presentationData.strings, .compose)
        let fabFrame: CGFloat = 56
        let fabCircle: CGFloat = 48
        let fabInset = (fabFrame - fabCircle) / 2
        let fabX = width - 20 - fabFrame + fabInset
        let fabY = layout.size.height - (layout.intrinsicInsets.bottom + 16 + fabFrame) + fabInset
        self.composeFab.frame = CGRect(x: fabX, y: fabY, width: fabCircle, height: fabCircle)
        self.composeFab.layer.cornerRadius = fabCircle / 2
        self.view.bringSubviewToFront(self.composeFab)
        let tabSize = self.tabs.update(transition: .immediate, component: AnyComponent(self.tabsComponent(width: width)), environment: {}, containerSize: CGSize(width: width - 16, height: 40))
        if let view = self.tabs.view {
            if view.superview == nil { self.view.addSubview(view) }
            view.frame = CGRect(x: 8, y: top + 44, width: tabSize.width, height: 40)
        }
        let pillY = top + 88
        self.pill.frame = CGRect(x: (width - 140) / 2, y: pillY, width: 140, height: 28)
        self.sortControl.isHidden = self.selected != .nearby
        self.sortControl.setTitle(momentsText(self.presentationData.strings, self.nearbySort == "latest" ? .nearbyLatest : .nearbyMixed), for: .normal)
        self.sortControl.frame = CGRect(x: width - 92, y: pillY, width: 80, height: 28)
        let listTop = pillY + 8
        let listHeight = layout.size.height - listTop - layout.intrinsicInsets.bottom
        self.pager.frame = CGRect(x: 0, y: listTop, width: width, height: listHeight)
        self.pager.contentSize = CGSize(width: width * CGFloat(self.visibleTabs.count), height: listHeight)
        let listSize = CGSize(width: width, height: listHeight)
        for (index, kind) in self.visibleTabs.enumerated() {
            self.lists[kind]?.frame = CGRect(x: width * CGFloat(index), y: 0, width: width, height: listHeight)
            if self.renderedListSize[kind] != listSize {
                self.renderedListSize[kind] = listSize
                self.render(kind, resetScroll: false)
            }
        }
        if self.models[.recommend]?.loaded == false {
            self.load(.recommend, refresh: false)
        }
    }

    private func tabsComponent(width: CGFloat) -> HorizontalTabsComponent {
        let strings = self.presentationData.strings
        let titles = self.visibleTabs.map { kind -> String in
            switch kind {
            case .recommend:
                return momentsText(strings, .recommend)
            case .following:
                return momentsText(strings, .following)
            case .friends:
                return momentsText(strings, .friends)
            case .nearby:
                return momentsText(strings, .nearby)
            }
        }
        let selectedIndex = self.visibleTabs.firstIndex(of: self.selected) ?? 0
        return HorizontalTabsComponent(
            context: self.context,
            theme: self.presentationData.theme,
            tabs: titles.enumerated().map { index, title in
                HorizontalTabsComponent.Tab(id: AnyHashable(index), content: .title(HorizontalTabsComponent.Tab.Title(text: title, entities: [], enableAnimations: false)), badge: nil, action: { [weak self] in
                    guard let self else { return }
                    self.select(self.visibleTabs[index], animated: true)
                })
            },
            selectedTab: AnyHashable(selectedIndex),
            isEditing: false,
            layout: .fill,
            liftWhileSwitching: false
        )
    }

    private enum MomentsSelectionSource {
        case tab
        case swipe
    }

    private func select(_ kind: MomentsFeedKind, animated: Bool) {
        self.commitSelection(kind, source: .tab, animated: animated)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === self.pager, !decelerate else { return }
        self.commitPagerSelection()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === self.pager else { return }
        self.commitPagerSelection()
    }

    /// Tab taps and horizontal swipes update the same selection: selected tab, top bar, nearby sort bar, in-flight requests, pill and probe.
    private func commitSelection(_ kind: MomentsFeedKind, source: MomentsSelectionSource, animated: Bool) {
        if kind == self.selected {
            if source == .tab {
                self.scrollToTop()
            }
            return
        }
        self.cancelLoads(except: kind)
        self.invalidateProbe()
        self.sessionHidden.removeAll()
        self.selected = kind
        if source == .tab {
            let index = self.visibleTabs.firstIndex(of: kind) ?? 0
            let width = self.pager.bounds.width
            if width > 0 {
                self.pager.setContentOffset(CGPoint(x: width * CGFloat(index), y: 0), animated: animated)
            }
        }
        if self.models[kind]?.loaded != true {
            self.load(kind, refresh: false)
        }
        self.updateSelectionChrome()
        self.scheduleProbe()
    }

    private func commitPagerSelection() {
        let width = max(self.pager.bounds.width, 1)
        let index = Int(round(self.pager.contentOffset.x / width))
        let kind = self.visibleTabs[max(0, min(index, self.visibleTabs.count - 1))]
        self.commitSelection(kind, source: .swipe, animated: false)
    }

    private func updateSelectionChrome() {
        self.updatePill()
        if let layout = self.validLayout {
            self.containerLayoutUpdated(layout, transition: .immediate)
        }
    }

    private func cancelLoad(_ kind: MomentsFeedKind) {
        // Bump the epoch before dispose. A cancelled request can call its error handler
        // synchronously, and that handler must not render while a tab swipe is still in the scroll view.
        self.loadEpoch[kind] = (self.loadEpoch[kind] ?? 0) + 1
        self.loadDisposables[kind]?.dispose()
        self.loadDisposables[kind] = nil
        self.models[kind]?.loading = false
    }

    private func cancelLoads(except kept: MomentsFeedKind?) {
        for kind in Array(self.loadDisposables.keys) where kind != kept {
            self.cancelLoad(kind)
        }
    }

    private func load(_ kind: MomentsFeedKind, refresh: Bool) {
        guard let model = self.models[kind] else { return }
        guard momentsShouldLoadFeedPage(loaded: model.loaded, cursor: model.cursor, refresh: refresh, loading: model.loading) else { return }
        let epoch = (self.loadEpoch[kind] ?? 0) + 1
        self.loadEpoch[kind] = epoch
        self.loadDisposables[kind]?.dispose()
        if refresh {
            self.probeEpoch += 1
            self.probeDisposable?.dispose()
            self.probeDisposable = nil
        }
        model.loading = true
        model.failed = false
        self.models[kind] = model
        let cursor = refresh ? nil : model.cursor
        let bag = DisposableSet()
        if !model.loaded {
            bag.add(self.context.engine.moments.cachedPage(kind).start(next: { [weak self] page in
                guard let self, self.loadEpoch[kind] == epoch, let page, self.models[kind]?.items.isEmpty == true else { return }
                self.models[kind]?.items = page.items
                self.render(kind, resetScroll: false)
            }))
        }
        bag.add((self.context.engine.moments.loadFeed(kind, cursor: cursor, city: nil, sort: self.nearbySort) |> deliverOnMainQueue).start(next: { [weak self] page in
            guard let self, self.loadEpoch[kind] == epoch else { return }
            let model = self.models[kind] ?? MomentsFeedModel()
            model.loading = false
            model.loaded = true
            model.failed = false
            model.failedRefresh = false
            let refreshing = refresh || cursor == nil
            let merged = momentsMergeFeed(existing: refreshing ? [] : model.items, pageItems: page.items, cursor: page.nextCursor, refreshing: refreshing)
            model.cursor = merged.cursor
            if refresh {
                model.newCount = 0
            }
            model.items = merged.items
            if kind == .following, let posted = self.postedCard {
                if merged.items.contains(where: { $0.id == posted.id }) {
                    self.postedCard = nil
                } else {
                    model.items = momentsFeedWithPosted(items: merged.items, posted: posted)
                }
            }
            self.models[kind] = model
            self.render(kind, resetScroll: refresh)
            self.updatePill()
        }, error: { [weak self] _ in
            guard let self, self.loadEpoch[kind] == epoch else { return }
            let model = self.models[kind] ?? MomentsFeedModel()
            model.loading = false
            model.failed = true
            model.failedRefresh = refresh
            model.loaded = true
            self.models[kind] = model
            self.render(kind, resetScroll: false)
        }))
        self.loadDisposables[kind] = bag
    }

    private func render(_ kind: MomentsFeedKind, resetScroll: Bool, updateInsets: Bool = true) {
        guard let list = self.lists[kind], let model = self.models[kind], list.bounds.width > 0 else { return }
        let strings = self.presentationData.strings
        let theme = self.presentationData.theme
        let font = self.presentationData.listsFontSize.baseDisplaySize
        let handlers = self.handlers()
        var entries: [ListViewItem] = []
        let visible = model.items.filter { card in
            if self.sessionHidden.contains(card.id) { return true }
            return self.hides.allows(card, surface: kind.surface)
        }
            if visible.isEmpty {
            let text: String
            let failed = model.failed && model.items.isEmpty
            if failed {
                text = model.loaded ? momentsText(strings, .loadFailed) : momentsText(strings, .credentialMissing)
            } else {
                switch kind {
                case .recommend: text = momentsText(strings, .emptyRecommend)
                case .following: text = momentsText(strings, .emptyFollowing)
                case .friends: text = momentsText(strings, .emptyFriends) + "\n" + momentsText(strings, .findPeople)
                case .nearby: text = momentsText(strings, .emptyNearby)
                }
            }
            entries = [MomentsStatusItem(text: text, theme: theme, action: { [weak self] in
                guard let self else { return }
                if kind == .friends && !failed {
                    self.select(.recommend, animated: true)
                } else {
                    self.load(kind, refresh: true)
                }
            })]
        } else {
            for card in visible {
                let playingVideo: Bool
                if case let .video(postId, _) = self.playing { playingVideo = postId == card.id } else { playingVideo = false }
                entries.append(MomentsPostItem(card: card, strings: strings, theme: theme, fontSize: font, showFollow: kind == .recommend, expanded: self.expanded.contains(card.id), hidden: self.sessionHidden.contains(card.id), albumIndex: self.albumIndex[card.id] ?? 0, playing: playingVideo, context: self.context, handlers: handlers))
            }
            if model.failed {
                let retryRefresh = model.failedRefresh
                entries.append(MomentsStatusItem(text: momentsText(strings, .loadFailed), theme: theme, action: { [weak self] in self?.load(kind, refresh: retryRefresh) }))
            }
        }
        let rows = entries.map { item -> (stable: String, print: String) in
            if let post = item as? MomentsPostItem {
                let card = post.card
                let stable = (post.hidden ? "h:" : "") + card.id
                let print = [
                    String(card.version),
                    card.viewer.liked ? "1" : "0",
                    String(card.counts.likes),
                    String(card.counts.comments),
                    String(post.albumIndex),
                    post.playing ? "p" : "s",
                    post.expanded ? "e" : "c"
                ].joined(separator: ":")
                return (stable, print)
            }
            if let status = item as? MomentsStatusItem {
                return ("status", status.text)
            }
            return ("status", "")
        }
        let ids = rows.map(\.stable)
        let prints = rows.map(\.print)
        if self.listBusy[kind] == true {
            self.renderQueued.insert(kind)
            return
        }
        let previous = self.appliedIds[kind] ?? []
        let previousPrints = self.appliedPrints[kind] ?? []
        let edit: (deletes: [Int], inserts: [Int], updates: [Int])
        if previous == ids {
            edit = ([], [], momentsChangedRowIndexes(previous: previousPrints, next: prints))
            if edit.updates.isEmpty && !resetScroll {
                self.appliedPrints[kind] = prints
                return
            }
        } else {
            edit = momentsListEdit(previousIds: previous, nextIds: ids)
        }
        let insets = UIEdgeInsets(top: 0, left: 0, bottom: 72, right: 0)
        let epoch = (self.renderEpoch[kind] ?? 0) + 1
        self.renderEpoch[kind] = epoch
        self.listBusy[kind] = true
        let scroll = resetScroll && !entries.isEmpty ? ListViewScrollToItem(index: 0, position: .top(0), animated: false, curve: .Default(duration: nil), directionHint: .Up) : nil
        let sizeUpdate = updateInsets || resetScroll ? ListViewUpdateSizeAndInsets(size: list.bounds.size, insets: insets, duration: 0, curve: .Default(duration: nil)) : nil
        list.transaction(deleteIndices: edit.deletes.map { ListViewDeleteItem(index: $0, directionHint: nil) }, insertIndicesAndItems: edit.inserts.map { ListViewInsertItem(index: $0, previousIndex: nil, item: entries[$0], directionHint: nil) }, updateIndicesAndItems: edit.updates.map { ListViewUpdateItem(index: $0, previousIndex: $0, item: entries[$0], directionHint: nil) }, options: [.Synchronous, .LowLatency], scrollToItem: scroll, updateSizeAndInsets: sizeUpdate, stationaryItemRange: nil, updateOpaqueState: nil, completion: { [weak self] _ in
            Queue.mainQueue().async {
                guard let self, self.renderEpoch[kind] == epoch else { return }
                self.appliedIds[kind] = ids
                self.appliedPrints[kind] = prints
                self.listBusy[kind] = false
                if self.renderQueued.contains(kind) {
                    self.renderQueued.remove(kind)
                    self.render(kind, resetScroll: false)
                }
            }
        })
        self.pill.backgroundColor = theme.list.itemAccentColor
        self.pill.setTitleColor(theme.list.plainBackgroundColor, for: .normal)
        self.updatePill()
    }

    private func handlers() -> MomentsPostHandlers {
        return MomentsPostHandlers(open: { [weak self] card in self?.open(card) }, author: { [weak self] card in self?.openAuthor(card) }, like: { [weak self] card in self?.toggleLike(card) }, comment: { [weak self] card in self?.openComments(card) }, repost: { [weak self] card in self?.repost(card) }, share: { [weak self] card in self?.share(card) }, save: { [weak self] card in self?.toggleSave(card) }, more: { [weak self] card, view in self?.more(card, view) }, follow: { [weak self] card in self?.follow(card) }, undo: { [weak self] id in self?.undo(id) }, fullText: { [weak self] card in self?.expanded.insert(card.id); self?.render(self?.selected ?? .recommend, resetScroll: false, updateInsets: false) }, topic: { _ in }, link: { [weak self] url in self?.openURL(url) }, likers: { [weak self] card in self?.openLikers(card) }, voters: { [weak self] card in self?.openVoters(card) }, openMedia: { [weak self] card, index in self?.openMedia(card, index: index) })
    }

    /// The post body opens the standalone detail screen. The comment button keeps the sheet over this list.
    private func open(_ card: MomentsCard) {
        guard let controller = self.controller, !card.isUnavailable else { return }
        let detail = MomentsDetailScreen(context: self.context, card: card)
        detail.openPeer = controller.openPeer
        (controller.navigationController as? NavigationController)?.pushViewController(detail)
    }

    private func openComments(_ card: MomentsCard) {
        guard let controller = self.controller, !card.isUnavailable else { return }
        let sheet = MomentsCommentSheet(context: self.context, card: card)
        sheet.openPeer = controller.openPeer
        controller.suppressFeedReset = true
        self.setScreenVisible(false)
        sheet.onDismiss = { [weak self, weak controller] in
            controller?.suppressFeedReset = false
            self?.setScreenVisible(true)
        }
        controller.present(sheet, in: .window(.root))
    }

    private func openMedia(_ card: MomentsCard, index: Int) {
        guard let controller = self.controller else { return }
        momentsPresentGallery(context: self.context, card: card, index: index, controller: controller)
    }

    private func openAuthor(_ card: MomentsCard) {
        guard let id = card.author?.telegramUserId, id != 0 else { return }
        let peerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(id))
        self.controller?.openPeer?(peerId)
    }

    private func toggleLike(_ card: MomentsCard) {
        self.mapCard(card.id) { item in
            var copy = item
            copy.viewer.liked.toggle()
            copy.counts.likes += copy.viewer.liked ? 1 : -1
            if copy.counts.likes < 0 { copy.counts.likes = 0 }
            return copy
        }
        let _ = self.context.engine.moments.setLiked(card.id, liked: !card.viewer.liked).start(error: { [weak self] _ in
            self?.mapCard(card.id) { _ in card }
        })
    }

    private func toggleSave(_ card: MomentsCard) {
        self.mapCard(card.id) { item in
            var copy = item
            copy.viewer.saved.toggle()
            return copy
        }
        let _ = self.context.engine.moments.setSaved(card.id, saved: !card.viewer.saved).start()
    }

    private func follow(_ card: MomentsCard) {
        guard let author = card.author else { return }
        let next = !author.followed
        self.mapCard(card.id) { item in
            var copy = item
            if var author = copy.author { author.followed = next; copy.author = author }
            return copy
        }
        let _ = self.context.engine.moments.setFollow(authorId: author.id, follow: next).start()
    }

    private func repost(_ card: MomentsCard) {
        guard let controller = self.controller else { return }
        guard momentsCanRepostOrQuote(audience: card.audience?.kind) else {
            controller.present(textAlertController(context: self.context, title: nil, text: momentsText(self.presentationData.strings, .repostPublicOnly), actions: [TextAlertAction(type: .defaultAction, title: momentsText(self.presentationData.strings, .cancel), action: {})]), in: .window(.root))
            return
        }
        let sheet = ActionSheetController(theme: ActionSheetControllerTheme(presentationData: self.presentationData))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: momentsText(self.presentationData.strings, .repost), color: .accent, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    let _ = self?.context.engine.moments.setRepost(card.id, repost: true).start()
                }),
                ActionSheetButtonItem(title: momentsText(self.presentationData.strings, .quote), color: .accent, action: { [weak self, weak sheet] in
                    sheet?.dismissAnimated()
                    self?.presentComposer(quoteId: card.id)
                })
            ]),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: momentsText(self.presentationData.strings, .cancel), color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        controller.present(sheet, in: .window(.root))
    }

    private func share(_ card: MomentsCard) {
        guard let controller = self.controller else { return }
        let link = momentsPostLink(id: card.id)
        let share = self.context.sharedContext.makeShareController(context: self.context, params: ShareControllerParams(subject: .url(link)))
        controller.present(share, in: .window(.root))
    }

    private func more(_ card: MomentsCard, _ source: UIView) {
        guard let controller = self.controller else { return }
        let strings = self.presentationData.strings
        let mine = card.author?.telegramUserId == self.context.account.peerId.toInt64()
        var items: [ContextMenuItem] = []
        if mine {
            items.append(.action(ContextMenuActionItem(text: momentsText(strings, .delete), textColor: .destructive, icon: { _ in nil }, action: { [weak self] _, f in
                f(.default)
                let _ = self?.context.engine.moments.deletePost(id: card.id).start()
            })))
        } else {
            items.append(.action(ContextMenuActionItem(text: momentsText(strings, .notInterested), icon: { _ in nil }, action: { [weak self] _, f in
                f(.default)
                self?.hide(card, notInterested: true)
            })))
            items.append(.action(ContextMenuActionItem(text: momentsText(strings, .hidePost), icon: { _ in nil }, action: { [weak self] _, f in
                f(.default)
                self?.hide(card, notInterested: false)
            })))
            if let author = card.author {
                items.append(.action(ContextMenuActionItem(text: momentsText(strings, .mute), icon: { _ in nil }, action: { [weak self] _, f in
                    f(.default)
                    self?.hides.mutedAuthors.insert(author.id)
                    self?.context.engine.moments.storeHides(self?.hides ?? MomentsLocalHides())
                    let _ = self?.context.engine.moments.setMuted(profileId: author.id, muted: true).start()
                    self?.render(self?.selected ?? .recommend, resetScroll: false)
                })))
            }
            items.append(.action(ContextMenuActionItem(text: momentsText(strings, .report), textColor: .destructive, icon: { _ in nil }, action: { [weak self] _, f in
                f(.default)
                self?.report(card)
            })))
        }
        items.append(.action(ContextMenuActionItem(text: momentsText(strings, .copyLink), icon: { _ in nil }, action: { _, f in
            f(.default)
            UIPasteboard.general.string = momentsPostLink(id: card.id)
        })))
        let sourceView = source
        let contextController = makeContextController(presentationData: self.presentationData, source: .reference(MomentsContextSource(controller: controller, sourceView: sourceView)), items: .single(ContextController.Items(content: .list(items))), gesture: nil)
        controller.presentInGlobalOverlay(contextController)
    }

    private func hide(_ card: MomentsCard, notInterested: Bool) {
        self.sessionHidden.insert(card.id)
        if notInterested {
            self.hides.notInterested.insert(card.id)
            let _ = self.context.engine.moments.notInterested(postId: card.id).start()
        } else {
            self.hides.hiddenPosts.insert(card.id)
            let _ = self.context.engine.moments.hide(postId: card.id, undo: false).start()
        }
        self.context.engine.moments.storeHides(self.hides)
        self.render(self.selected, resetScroll: false)
    }

    private func undo(_ id: String) {
        self.sessionHidden.remove(id)
        self.hides.hiddenPosts.remove(id)
        self.hides.notInterested.remove(id)
        self.context.engine.moments.storeHides(self.hides)
        let _ = self.context.engine.moments.hide(postId: id, undo: true).start()
        self.render(self.selected, resetScroll: false)
    }

    private func report(_ card: MomentsCard) {
        guard let controller = self.controller, let authorId = card.author?.telegramUserId else { return }
        let peerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(authorId))
        presentPeerReportOptions(context: self.context, parent: controller, contextController: nil, subject: .peer(peerId), passthrough: true, completion: { [weak self] reason, _ in
            guard let self, let reason else { return }
            self.hides.reportedPosts.insert(card.id)
            self.context.engine.moments.storeHides(self.hides)
            let _ = self.context.engine.moments.report(targetType: "post", targetId: card.id, reason: momentsReportReasonCode(reason), detail: nil).start()
            self.render(self.selected, resetScroll: false)
        })
    }

    private func mapCard(_ id: String, _ transform: (MomentsCard) -> MomentsCard) {
        for kind in self.visibleTabs {
            guard let model = self.models[kind] else { continue }
            model.items = model.items.map { $0.id == id ? transform($0) : $0 }
            self.models[kind] = model
            // One row, no inset pass. A full layout pass redraws every visible cell and the neighbours flash.
            self.render(kind, resetScroll: false, updateInsets: false)
        }
    }

    @objc private func composePressed() { self.presentComposer(quoteId: nil) }
    @objc private func heartPressed() {
        guard let controller = self.controller else { return }
        let screen = MomentsNotificationsScreen(context: self.context)
        screen.openPeer = controller.openPeer
        (controller.navigationController as? NavigationController)?.pushViewController(screen)
        let _ = self.context.engine.moments.markNotificationsRead().start()
        controller.tabBarItem.badgeValue = nil
    }
    @objc private func pillPressed() { self.load(self.selected, refresh: true) }

    @objc private func sortPressed() {
        self.cancelLoad(.nearby)
        self.nearbySort = self.nearbySort == "latest" ? "mixed" : "latest"
        self.load(.nearby, refresh: true)
        self.updateSelectionChrome()
        self.scheduleProbe()
    }

    private func presentComposer(quoteId: String?, sendPending: Bool = false) {
        guard let controller = self.controller else { return }
        let composer = MomentsComposerScreen(context: self.context, quoteId: quoteId, sendPending: sendPending)
        composer.onPosted = { [weak self] card in
            self?.showPosted(card)
        }
        (controller.navigationController as? NavigationController)?.pushViewController(composer)
    }

    /// A 200 from create-post, including a replayed nonce, is this post. It is already off the outbox.
    private func showPosted(_ card: MomentsCard) {
        self.postedCard = card
        if self.models[.following] == nil {
            self.models[.following] = MomentsFeedModel()
        }
        self.models[.following]?.items = momentsFeedWithPosted(items: self.models[.following]?.items ?? [], posted: card)
        self.render(.following, resetScroll: true)
        self.select(.following, animated: false)
        self.load(.following, refresh: true)
    }

    private func openURL(_ url: String) {
        guard let controller = self.controller else { return }
        self.context.sharedContext.openExternalUrl(context: self.context, urlContext: .generic, url: url, forceExternal: false, presentationData: self.presentationData, navigationController: controller.navigationController as? NavigationController, dismissInput: {})
    }

    private func scheduleProbe() {
        self.invalidateProbe()
        self.updatePill()
        guard momentsFeedShouldProbe(kind: self.selected, screenVisible: self.screenVisible) else {
            return
        }
        let interval = self.context.engine.moments.currentLimits().newPostsProbeInterval
        let timer = SwiftSignalKit.Timer(timeout: interval, repeat: true, completion: { [weak self] in
            self?.probeHead()
        }, queue: .mainQueue())
        self.probe = timer
        timer.start()
        self.probeHead()
    }

    private func invalidateProbe() {
        self.probe?.invalidate()
        self.probe = nil
        self.probeEpoch += 1
        self.probeDisposable?.dispose()
        self.probeDisposable = nil
    }

    /// Asks for the first page and only raises the pill. The rows stay put until the pill or a refresh loads them.
    private func probeHead() {
        let kind = self.selected
        guard momentsFeedShouldProbe(kind: kind, screenVisible: self.screenVisible) else { return }
        guard self.models[kind]?.loaded == true else { return }
        let epoch = self.probeEpoch
        self.probeDisposable?.dispose()
        self.probeDisposable = (self.context.engine.moments.loadFeed(kind, cursor: nil, city: nil, sort: self.nearbySort) |> deliverOnMainQueue).start(next: { [weak self] page in
            guard let self, self.probeEpoch == epoch, self.selected == kind, self.screenVisible else { return }
            let visible = self.models[kind]?.items.map(\.id) ?? []
            self.models[kind]?.newCount = momentsUnseenHeadCount(visibleIds: visible, probedIds: page.items.map(\.id))
            self.updatePill()
        }, error: { _ in })
    }

    private func updatePill() {
        let count = self.models[self.selected]?.newCount ?? 0
        self.pill.setTitle(momentsText(self.presentationData.strings, .newPosts), for: .normal)
        self.pill.isHidden = !self.selected.probesForNewPosts || count == 0
    }

    private func autoplayAllowed() -> Bool {
        let reduce = self.presentationData.reduceMotion || UIAccessibility.isReduceMotionEnabled
        return self.context.sharedContext.energyUsageSettings.autoplayVideo && !reduce
    }

    private func updateVisiblePlayback() {
        guard !self.resolvingPlayback, let list = self.lists[self.selected] else { return }
        let next: MomentsPlaybackRequest
        if !self.autoplayAllowed() {
            next = momentsNextPlayback(current: self.playing, event: .autoplayDisabled)
        } else {
            var candidate: (String, Int)?
            list.forEachItemNode { node in
                if candidate == nil, let post = node as? MomentsPostItemNode, let found = post.autoplayTarget(listView: list.view) {
                    candidate = found
                }
            }
            if let candidate {
                next = momentsNextPlayback(current: self.playing, event: .videoBecameVisible(postId: candidate.0, index: candidate.1))
            } else if case .video = self.playing {
                next = .none
            } else {
                next = self.playing
            }
        }
        guard next != self.playing else { return }
        self.playing = next
        self.resolvingPlayback = true
        list.forEachItemNode { node in
            guard let post = node as? MomentsPostItemNode else { return }
            let active: Bool
            if case let .video(postId, _) = next {
                active = post.showsCard(postId)
            } else {
                active = false
            }
            post.setPlaybackActive(active)
        }
        self.resolvingPlayback = false
    }

    private func openLikers(_ card: MomentsCard) {
        guard let controller = self.controller else { return }
        (controller.navigationController as? NavigationController)?.pushViewController(momentsPeopleController(context: self.context, title: momentsText(self.presentationData.strings, .like), load: self.context.engine.moments.likers(postId: card.id) |> map { authors in
            [MomentsPeopleSection(title: nil, people: authors)]
        }))
    }

    private func openVoters(_ card: MomentsCard) {
        guard let controller = self.controller, card.poll != nil else { return }
        (controller.navigationController as? NavigationController)?.pushViewController(momentsPeopleController(context: self.context, title: momentsText(self.presentationData.strings, .endPoll), load: self.context.engine.moments.pollVoters(postId: card.id) |> map { options in
            options.map { MomentsPeopleSection(title: $0.text, people: $0.voters) }
        }))
    }

    private func pointHitsAlbum(_ point: CGPoint) -> Bool {
        guard let list = self.lists[self.selected] else { return false }
        var hit = false
        list.forEachItemNode { node in
            if let post = node as? MomentsPostItemNode, post.albumContains(self.pager.convert(point, to: nil)) {
                hit = true
            }
        }
        return hit
    }
}

private final class MomentsContextSource: ContextReferenceContentSource {
    private let controller: ViewController
    private let sourceView: UIView
    init(controller: ViewController, sourceView: UIView) {
        self.controller = controller
        self.sourceView = sourceView
    }
    func transitionInfo() -> ContextControllerReferenceViewInfo? {
        return ContextControllerReferenceViewInfo(referenceView: self.sourceView, contentAreaInScreenSpace: mainWindowScreenBounds)
    }
}

private func momentsTabIcon() -> UIImage? {
    return UIImage(bundleImageName: "Chat List/Tabs/IconNews")?.withRenderingMode(.alwaysTemplate)
}
