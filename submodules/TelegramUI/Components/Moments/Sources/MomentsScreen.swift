import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import ComponentFlow
import HorizontalTabsComponent
import Postbox
import CoreLocation
import DeviceLocationManager

public final class MomentsScreen: ViewController {
    private let context: AccountContext
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    private var networkDisposable: Disposable?
    private var resetWhenShown = false
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
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
        self.networkDisposable?.dispose()
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
        let top = self.navigationController?.topViewController
        if top === self.parent || top === self {
            self.resetWhenShown = true
        }
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if self.resetWhenShown {
            self.resetWhenShown = false
            self.nodeIfLoaded.resetToRecommend()
        }
        self.nodeIfLoaded.installCredential()
        self.refreshBadge()
    }

    public func refreshBadge() {
        let _ = (self.context.engine.moments.notifications(kind: "all") |> deliverOnMainQueue).start(next: { [weak self] items in
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
    private var expanded: Set<String> = []
    private var albumIndex: [String: Int] = [:]
    private var sessionHidden: Set<String> = []
    private var hides = MomentsLocalHides()
    private var city: String?
    private var cityName: String?
    private var nearbySort = "latest"
    private var playing: MomentsPlaybackRequest = .none
    private let disposable = DisposableSet()
    private var probe: SwiftSignalKit.Timer?
    private let sortControl = UIButton(type: .system)
    private var validLayout: ContainerViewLayout?

    init(context: AccountContext, controller: MomentsScreen) {
        self.context = context
        self.controller = controller
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init()
        self.setViewBlock { UITracingLayerView() }
        for kind in MomentsFeedKind.allCases {
            self.models[kind] = MomentsFeedModel()
            let list = ListView()
            self.lists[kind] = list
            self.pager.addSubview(list.view)
        }
        self.view.addSubview(self.titleLabel)
        self.view.addSubview(self.compose)
        self.view.addSubview(self.heart)
        self.view.addSubview(self.pill)
        self.view.addSubview(self.sortControl)
        self.view.addSubview(self.pager)
        self.pager.delegate = self
        self.pager.albumHit = { [weak self] point in
            self?.pointHitsAlbum(point) ?? false
        }
        self.compose.addTarget(self, action: #selector(self.composePressed), for: .touchUpInside)
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
    }

    deinit {
        self.disposable.dispose()
        self.probe?.invalidate()
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
    }

    func installCredential() {
        let data = self.context.currentAppConfiguration.with { $0 }.data
        let base = (data?["moments_engine_base_url"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? MomentsEndpoint.defaultBaseURL
        if let token = data?["moments_engine_token"] as? String, !token.isEmpty {
            MomentsCredentialStore.shared.set(MomentsCredential(token: token, baseURL: base), accountPeerId: self.context.account.peerId.toInt64())
        }
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
        self.heart.frame = CGRect(x: width - 96, y: top + 6, width: 36, height: 32)
        self.compose.frame = CGRect(x: width - 52, y: top + 6, width: 40, height: 32)
        self.heart.setTitle("♡", for: .normal)
        self.compose.setTitle("+", for: .normal)
        self.heart.accessibilityLabel = momentsText(self.presentationData.strings, .notifications)
        self.compose.accessibilityLabel = momentsText(self.presentationData.strings, .compose)
        let tabSize = self.tabs.update(transition: .immediate, component: AnyComponent(self.tabsComponent(width: width)), environment: {}, containerSize: CGSize(width: width - 16, height: 36))
        if let view = self.tabs.view {
            if view.superview == nil { self.view.addSubview(view) }
            view.frame = CGRect(x: 8, y: top + 44, width: tabSize.width, height: 36)
        }
        let pillY = top + 84
        self.pill.frame = CGRect(x: (width - 140) / 2, y: pillY, width: 140, height: 28)
        self.sortControl.isHidden = self.selected != .nearby
        self.sortControl.setTitle(momentsText(self.presentationData.strings, self.nearbySort == "latest" ? .nearbyLatest : .nearbyMixed), for: .normal)
        self.sortControl.frame = CGRect(x: width - 92, y: pillY, width: 80, height: 28)
        let listTop = pillY + 8
        let listHeight = layout.size.height - listTop - layout.intrinsicInsets.bottom
        self.pager.frame = CGRect(x: 0, y: listTop, width: width, height: listHeight)
        self.pager.contentSize = CGSize(width: width * CGFloat(MomentsFeedKind.allCases.count), height: listHeight)
        for (index, kind) in MomentsFeedKind.allCases.enumerated() {
            self.lists[kind]?.frame = CGRect(x: width * CGFloat(index), y: 0, width: width, height: listHeight)
            self.render(kind, resetScroll: false)
        }
        if self.models[.recommend]?.loaded == false {
            self.load(.recommend, refresh: false)
        }
    }

    private func tabsComponent(width: CGFloat) -> HorizontalTabsComponent {
        let strings = self.presentationData.strings
        let titles = [
            momentsText(strings, .recommend),
            momentsText(strings, .following),
            momentsText(strings, .friends),
            self.cityName.map { "\(momentsText(strings, .nearby)) \($0)" } ?? momentsText(strings, .nearby)
        ]
        let selectedIndex = MomentsFeedKind.allCases.firstIndex(of: self.selected) ?? 0
        return HorizontalTabsComponent(
            context: self.context,
            theme: self.presentationData.theme,
            tabs: titles.enumerated().map { index, title in
                HorizontalTabsComponent.Tab(id: AnyHashable(index), content: .title(HorizontalTabsComponent.Tab.Title(text: title, entities: [], enableAnimations: false)), badge: nil, action: { [weak self] in
                    self?.select(MomentsFeedKind.allCases[index], animated: true)
                })
            },
            selectedTab: AnyHashable(selectedIndex),
            isEditing: false,
            layout: .fill,
            liftWhileSwitching: false
        )
    }

    private func select(_ kind: MomentsFeedKind, animated: Bool) {
        guard kind != self.selected else {
            self.scrollToTop()
            return
        }
        self.sessionHidden.removeAll()
        self.selected = kind
        let index = MomentsFeedKind.allCases.firstIndex(of: kind) ?? 0
        self.pager.setContentOffset(CGPoint(x: self.pager.bounds.width * CGFloat(index), y: 0), animated: animated)
        if self.models[kind]?.loaded != true {
            if kind == .nearby && self.city == nil {
                self.prepareNearby()
            } else {
                self.load(kind, refresh: false)
            }
        }
        self.scheduleProbe()
        if let layout = self.validLayout {
            self.containerLayoutUpdated(layout, transition: .immediate)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let width = max(scrollView.bounds.width, 1)
        let index = Int(round(scrollView.contentOffset.x / width))
        let kind = MomentsFeedKind.allCases[max(0, min(index, MomentsFeedKind.allCases.count - 1))]
        if kind != self.selected {
            self.sessionHidden.removeAll()
            self.selected = kind
            if self.models[kind]?.loaded != true {
                self.load(kind, refresh: false)
            }
        }
    }

    private func load(_ kind: MomentsFeedKind, refresh: Bool) {
        guard var model = self.models[kind], !model.loading else { return }
        if !refresh && model.loaded && model.cursor == nil && !model.items.isEmpty { return }
        model.loading = true
        model.failed = false
        self.models[kind] = model
        let cursor = refresh ? nil : model.cursor
        if !model.loaded {
            self.disposable.add(self.context.engine.moments.cachedPage(kind).start(next: { [weak self] page in
                guard let self, let page, self.models[kind]?.items.isEmpty == true else { return }
                self.models[kind]?.items = page.items
                self.render(kind, resetScroll: false)
            }))
        }
        self.disposable.add((self.context.engine.moments.loadFeed(kind, cursor: cursor, city: self.city, sort: self.nearbySort) |> deliverOnMainQueue).start(next: { [weak self] page in
            guard let self else { return }
            var model = self.models[kind] ?? MomentsFeedModel()
            model.loading = false
            model.loaded = true
            model.failed = false
            model.cursor = page.nextCursor
            model.newCount = 0
            if refresh || cursor == nil {
                model.items = page.items
            } else {
                model.items.append(contentsOf: page.items)
            }
            self.models[kind] = model
            self.render(kind, resetScroll: refresh)
            self.pill.isHidden = self.models[self.selected]?.newCount ?? 0 == 0
        }, error: { [weak self] _ in
            guard let self else { return }
            var model = self.models[kind] ?? MomentsFeedModel()
            model.loading = false
            model.failed = true
            model.loaded = true
            self.models[kind] = model
            self.render(kind, resetScroll: false)
        }))
    }

    private func render(_ kind: MomentsFeedKind, resetScroll: Bool) {
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
            if model.failed && model.items.isEmpty {
                text = model.loaded ? momentsText(strings, .loadFailed) : momentsText(strings, .credentialMissing)
            } else {
                switch kind {
                case .recommend: text = momentsText(strings, .emptyRecommend)
                case .following: text = momentsText(strings, .emptyFollowing)
                case .friends: text = momentsText(strings, .emptyFriends) + "\n" + momentsText(strings, .findPeople)
                case .nearby: text = momentsText(strings, .emptyNearby) + "\n" + momentsText(strings, .switchCity)
                }
            }
            entries = [MomentsStatusItem(text: text, theme: theme, action: { [weak self] in
                if kind == .nearby { self?.prepareNearby() } else { self?.load(kind, refresh: true) }
            })]
        } else {
            for card in visible {
                let playingVideo: Bool
                if case let .video(postId, _) = self.playing { playingVideo = postId == card.id } else { playingVideo = false }
                entries.append(MomentsPostItem(card: card, strings: strings, theme: theme, fontSize: font, showFollow: kind == .recommend, expanded: self.expanded.contains(card.id), hidden: self.sessionHidden.contains(card.id), albumIndex: self.albumIndex[card.id] ?? 0, playing: playingVideo, handlers: handlers))
            }
            if model.failed {
                entries.append(MomentsStatusItem(text: momentsText(strings, .loadFailed), theme: theme, action: { [weak self] in self?.load(kind, refresh: false) }))
            }
        }
        let ids = entries.map { item -> String in
            if let post = item as? MomentsPostItem { return post.hidden ? "h:\(post.card.id)" : post.card.id + ":\(post.card.version)" }
            return "status"
        }
        let previous = model.renderedIds
        self.models[kind]?.renderedIds = ids
        let insets = UIEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        if previous == ids && !resetScroll {
            list.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: entries.enumerated().map { ListViewUpdateItem(index: $0.offset, previousIndex: $0.offset, item: $0.element, directionHint: nil) }, options: [.Synchronous, .LowLatency], scrollToItem: nil, updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: list.bounds.size, insets: insets, duration: 0, curve: .Default(duration: nil)), stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        } else {
            list.transaction(deleteIndices: previous.enumerated().map { ListViewDeleteItem(index: $0.offset, directionHint: nil) }, insertIndicesAndItems: entries.enumerated().map { ListViewInsertItem(index: $0.offset, previousIndex: nil, item: $0.element, directionHint: nil) }, updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: resetScroll ? ListViewScrollToItem(index: 0, position: .top(0), animated: false, curve: .Default(duration: nil), directionHint: .Up) : nil, updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: list.bounds.size, insets: insets, duration: 0, curve: .Default(duration: nil)), stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        }
        self.pill.setTitle(momentsText(strings, .newPosts), for: .normal)
        self.pill.backgroundColor = theme.list.itemAccentColor
        self.pill.setTitleColor(theme.list.plainBackgroundColor, for: .normal)
        self.pill.isHidden = kind != self.selected || (self.models[self.selected]?.newCount ?? 0) == 0
        self.updatePlayback()
    }

    private func handlers() -> MomentsPostHandlers {
        return MomentsPostHandlers(open: { [weak self] card in self?.open(card) }, author: { [weak self] card in self?.openAuthor(card) }, like: { [weak self] card in self?.toggleLike(card) }, comment: { [weak self] card in self?.open(card) }, repost: { [weak self] card in self?.repost(card) }, share: { [weak self] card in self?.share(card) }, save: { [weak self] card in self?.toggleSave(card) }, more: { [weak self] card, view in self?.more(card, view) }, follow: { [weak self] card in self?.follow(card) }, undo: { [weak self] id in self?.undo(id) }, fullText: { [weak self] card in self?.expanded.insert(card.id); self?.render(self?.selected ?? .recommend, resetScroll: false) }, topic: { _ in }, link: { [weak self] url in self?.openURL(url) })
    }

    private func open(_ card: MomentsCard) {
        guard let controller = self.controller else { return }
        let detail = MomentsDetailScreen(context: self.context, card: card)
        detail.openPeer = self.controller?.openPeer
        (controller.navigationController as? NavigationController)?.pushViewController(detail)
    }

    private func openAuthor(_ card: MomentsCard) {
        guard let id = card.author?.telegramUserId, id != 0 else { return }
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(id))
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
        guard momentsCanRepostOrQuote(audience: card.audience?.kind), let controller = self.controller else { return }
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
        }))
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
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(authorId))
        presentPeerReportOptions(context: self.context, parent: controller, contextController: nil, subject: .peer(peerId), passthrough: true, completion: { [weak self] reason, _ in
            guard let self, let reason else { return }
            self.hides.reportedPosts.insert(card.id)
            self.context.engine.moments.storeHides(self.hides)
            let _ = self.context.engine.moments.report(targetType: "post", targetId: card.id, reason: momentsReportReasonCode(reason), detail: nil).start()
            self.render(self.selected, resetScroll: false)
        })
    }

    private func mapCard(_ id: String, _ transform: (MomentsCard) -> MomentsCard) {
        for kind in MomentsFeedKind.allCases {
            guard var model = self.models[kind] else { continue }
            model.items = model.items.map { $0.id == id ? transform($0) : $0 }
            self.models[kind] = model
        }
        self.render(self.selected, resetScroll: false)
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
        self.nearbySort = self.nearbySort == "latest" ? "mixed" : "latest"
        self.load(.nearby, refresh: true)
    }

    private func presentComposer(quoteId: String?) {
        guard let controller = self.controller else { return }
        let composer = MomentsComposerScreen(context: self.context, quoteId: quoteId)
        (controller.navigationController as? NavigationController)?.pushViewController(composer)
    }

    private func openURL(_ url: String) {
        guard let controller = self.controller else { return }
        self.context.sharedContext.openExternalUrl(context: self.context, urlContext: .generic, url: url, forceExternal: false, presentationData: self.presentationData, navigationController: controller.navigationController as? NavigationController, dismissInput: {})
    }

    private func prepareNearby() {
        guard let controller = self.controller else { return }
        let alert = textAlertController(context: self.context, title: momentsText(self.presentationData.strings, .nearby), text: momentsText(self.presentationData.strings, .nearbyPermission), actions: [
            TextAlertAction(type: .genericAction, title: momentsText(self.presentationData.strings, .cancel), action: { [weak self] in self?.pickCity() }),
            TextAlertAction(type: .defaultAction, title: momentsText(self.presentationData.strings, .nearby), action: { [weak self] in self?.requestCity() })
        ], actionLayout: .vertical)
        controller.present(alert, in: .window(.root))
    }

    private func requestCity() {
        guard let manager = self.context.sharedContext.locationManager else {
            self.pickCity()
            return
        }
        self.disposable.add((currentLocationManagerCoordinate(manager: manager, timeout: 8) |> deliverOnMainQueue).start(next: { [weak self] coordinate in
            guard let self else { return }
            guard let coordinate else {
                self.pickCity()
                return
            }
            CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { marks, _ in
                let city = marks?.first?.locality
                Queue.mainQueue().async {
                    if let city {
                        self.cityName = city
                        self.city = city
                        self.load(.nearby, refresh: true)
                    } else {
                        self.pickCity()
                    }
                }
            }
        }))
    }

    private func pickCity() {
        guard let controller = self.controller else { return }
        let screen = MomentsCityScreen(context: self.context, picked: { [weak self] city in
            self?.city = city.code
            self?.cityName = city.name
            self?.load(.nearby, refresh: true)
        })
        (controller.navigationController as? NavigationController)?.pushViewController(screen)
    }

    private func scheduleProbe() {
        self.probe?.invalidate()
        guard self.selected.probesForNewPosts else { return }
        let timer = SwiftSignalKit.Timer(timeout: MomentsLimits.standard.newPostsProbeInterval, repeat: true, completion: { [weak self] in
            guard let self, let since = self.models[self.selected]?.items.first?.id else { return }
            let _ = (self.context.engine.moments.newCount(self.selected, since: since) |> deliverOnMainQueue).start(next: { [weak self] count in
                guard let self else { return }
                self.models[self.selected]?.newCount = count
                self.pill.isHidden = count == 0
            })
        }, queue: Queue.mainQueue())
        timer.start()
        self.probe = timer
    }

    private func updatePlayback() {
        let reduce = self.presentationData.reduceMotion || UIAccessibility.isReduceMotionEnabled
        let autoplay = self.context.sharedContext.energyUsageSettings.autoplayVideo && !reduce
        if !autoplay {
            self.playing = momentsNextPlayback(current: self.playing, event: .autoplayDisabled)
        }
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
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 26, height: 26))
    return renderer.image { ctx in
        let context = ctx.cgContext
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(1.6)
        context.setLineCap(.round)
        context.stroke(CGRect(x: 4, y: 5, width: 18, height: 14).insetBy(dx: 0.8, dy: 0.8))
        context.move(to: CGPoint(x: 8, y: 23))
        context.addLine(to: CGPoint(x: 13, y: 18))
        context.strokePath()
    }.withRenderingMode(.alwaysTemplate)
}
