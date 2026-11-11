import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import PeerInfoPaneNode

public final class MomentsProfilePaneNode: ASDisplayNode, PeerInfoPaneNode {
    private let context: AccountContext
    private let peerId: EnginePeer.Id
    private let profileId: String
    private let list = ListViewImpl()
    private let ready = Promise<Bool>(false)
    private let actions: MomentsFeedActions
    private var items: [MomentsCard] = []
    private var cursor: String?
    private var loaded = false
    private var loading = false
    private var failed = false
    private var query = MomentsQueryGeneration()
    private var postsDisposable: Disposable?
    private var followingDisposable: Disposable?
    private var followersDisposable: Disposable?
    private var followingCount: Int?
    private var followersCount: Int?
    private var followingHidden = false
    private var followersHidden = false
    private var expanded = Set<String>()
    private var appliedIds: [String] = []
    private var appliedPrints: [String] = []
    private var listBusy = false
    private var renderQueued = false
    private var presentationData: PresentationData
    public var parentController: ViewController?
    public var tabBarOffsetUpdated: ((ContainedViewLayoutTransition) -> Void)?
    public var tabBarOffset: CGFloat = 0
    public var isReady: Signal<Bool, NoError> { self.ready.get() }
    public var status: Signal<PeerInfoStatusData?, NoError> { .single(nil) }
    public var externalDataUpdated: ((ContainedViewLayoutTransition) -> Void)?
    public var openPeer: ((EnginePeer.Id) -> Void)?

    public init(context: AccountContext, peerId: EnginePeer.Id) {
        self.context = context
        self.peerId = peerId
        self.profileId = "\(peerId.toInt64())"
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.actions = MomentsFeedActions(context: context, presentationData: self.presentationData)
        super.init()
        self.addSubnode(self.list)
        self.actions.controller = { [weak self] in self?.parentController }
        self.actions.onReplace = { [weak self] id, transform in
            guard let self else {
                return
            }
            self.items = self.items.map { $0.id == id ? transform($0) : $0 }
            self.render()
        }
        self.actions.onExpand = { [weak self] id in
            self?.expanded.insert(id)
            self?.render()
        }
        self.actions.onMutation = { [weak self] mutation in
            guard let self, case let .reported(id) = mutation else {
                return
            }
            self.items.removeAll { $0.id == id }
            self.render()
        }
        self.list.displayedItemRangeChanged = { [weak self] range, _ in
            guard let self else {
                return
            }
            let last = range.visibleRange?.lastIndex ?? range.loadedRange?.lastIndex ?? 0
            if last >= self.rowCount - 3 {
                self.loadPosts(refresh: false)
            }
        }
        self.loadPosts(refresh: true)
        self.loadCounts()
    }

    deinit {
        self.postsDisposable?.dispose()
        self.followingDisposable?.dispose()
        self.followersDisposable?.dispose()
    }

    private var isSelf: Bool {
        return self.peerId == self.context.account.peerId
    }

    private var rowCount: Int {
        return self.headerCount + self.items.count
    }

    private var headerCount: Int {
        return (self.isSelf ? 2 : 0) + 2
    }

    public func update(size: CGSize, topInset: CGFloat, sideInset: CGFloat, bottomInset: CGFloat, deviceMetrics: DeviceMetrics, visibleHeight: CGFloat, isScrollingLockedAtTop: Bool, expandProgress: CGFloat, navigationHeight: CGFloat, presentationData: PresentationData, synchronous: Bool, transition: ContainedViewLayoutTransition) {
        self.presentationData = presentationData
        let frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        transition.updateFrame(node: self.list, frame: frame)
        self.render()
    }

    public func scrollToTop() -> Bool { return false }
    public func transferVelocity(_ velocity: CGFloat) {}
    public func cancelPreviewGestures() {}
    public func findLoadedMessage(id: EngineMessage.Id) -> EngineMessage? { return nil }
    public func transitionNodeForGallery(messageId: EngineMessage.Id, media: EngineMedia) -> (ASDisplayNode, CGRect, () -> (UIView?, UIView?))? { return nil }
    public func addToTransitionSurface(view: UIView) {}
    public func updateHiddenMedia() {}
    public func updateSelectedMessages(animated: Bool) {}
    public func ensureMessageIsVisible(id: EngineMessage.Id) {}

    private func loadPosts(refresh: Bool) {
        guard momentsShouldLoadFeedPage(loaded: self.loaded, cursor: self.cursor, refresh: refresh, loading: self.loading) else {
            return
        }
        let generation = self.query.begin()
        self.loading = true
        let requestCursor = refresh ? nil : self.cursor
        self.postsDisposable?.dispose()
        self.postsDisposable = (self.context.engine.moments.profilePosts(id: self.profileId, filter: "posts", cursor: requestCursor) |> deliverOnMainQueue).start(next: { [weak self] page in
            guard let self, self.query.accepts(generation) else {
                return
            }
            let refreshing = refresh || requestCursor == nil
            let merged = momentsMergeFeed(existing: refreshing ? [] : self.items, pageItems: page.items, cursor: page.nextCursor, refreshing: refreshing)
            self.items = merged.items
            self.cursor = merged.cursor
            self.loading = false
            self.loaded = true
            self.failed = false
            self.ready.set(.single(true))
            self.render()
        }, error: { [weak self] error in
            guard let self, self.query.accepts(generation), momentsListLoadResult(error) != .ignore else {
                return
            }
            self.loading = false
            self.loaded = true
            self.failed = true
            self.ready.set(.single(true))
            self.render()
        })
    }

    private func loadCounts() {
        self.followingDisposable?.dispose()
        self.followersDisposable?.dispose()
        self.followingDisposable = (self.context.engine.moments.following(id: self.profileId, cursor: nil) |> deliverOnMainQueue).start(next: { [weak self] page in
            self?.followingHidden = false
            self?.followingCount = page.total
            self?.render()
        }, error: { [weak self] error in
            guard momentsListLoadResult(error) == .hidden else {
                return
            }
            self?.followingHidden = true
            self?.followingCount = nil
            self?.render()
        })
        self.followersDisposable = (self.context.engine.moments.followers(id: self.profileId, cursor: nil) |> deliverOnMainQueue).start(next: { [weak self] page in
            self?.followersHidden = false
            self?.followersCount = page.total
            self?.render()
        }, error: { [weak self] error in
            guard momentsListLoadResult(error) == .hidden else {
                return
            }
            self?.followersHidden = true
            self?.followersCount = nil
            self?.render()
        })
    }

    private func render() {
        guard self.list.bounds.width > 0 else {
            return
        }
        if self.listBusy {
            self.renderQueued = true
            return
        }
        let strings = self.presentationData.strings
        let theme = self.presentationData.theme
        self.actions.presentationData = self.presentationData
        self.actions.openPeer = self.openPeer
        let handlers = self.actions.handlers()
        var entries: [ListViewItem] = []
        var ids: [String] = []
        var prints: [String] = []
        let context = self.context
        if self.isSelf {
            self.appendLink(&entries, ids: &ids, prints: &prints, stable: "saved", title: strings.Moments_Profile_Saved, count: nil, hidden: false) { [weak self] in
                self?.openCollection(title: strings.Moments_Profile_Saved, emptyText: { $0.Moments_EmptyList }, load: { cursor, _ in
                    context.engine.moments.saved(cursor: cursor)
                })
            }
            self.appendLink(&entries, ids: &ids, prints: &prints, stable: "liked", title: strings.Moments_Profile_Liked, count: nil, hidden: false) { [weak self] in
                self?.openCollection(title: strings.Moments_Profile_Liked, emptyText: { $0.Moments_EmptyList }, load: { cursor, _ in
                    context.engine.moments.liked(cursor: cursor)
                })
            }
        }
        self.appendLink(&entries, ids: &ids, prints: &prints, stable: "following", title: strings.Moments_Segment_Following, count: self.followingCount, hidden: self.followingHidden) { [weak self] in
            self?.openPeople(followers: false)
        }
        self.appendLink(&entries, ids: &ids, prints: &prints, stable: "followers", title: strings.Moments_Followers, count: self.followersCount, hidden: self.followersHidden) { [weak self] in
            self?.openPeople(followers: true)
        }
        if self.items.isEmpty && (self.failed || self.loaded) {
            let text = self.failed ? momentsText(strings, .loadFailed) : momentsText(strings, .profilePosts)
            entries.append(MomentsStatusItem(text: text, theme: theme, action: { [weak self] in
                guard let self else {
                    return
                }
                self.loaded = false
                self.loading = false
                self.loadPosts(refresh: true)
            }))
            ids.append("status")
            prints.append(text)
        }
        for card in self.items {
            entries.append(MomentsPostItem(card: card, strings: strings, theme: theme, fontSize: self.presentationData.listsFontSize.baseDisplaySize, showFollow: false, expanded: self.expanded.contains(card.id), hidden: false, albumIndex: 0, playing: false, context: self.context, handlers: handlers))
            ids.append(card.id)
            prints.append([String(card.version), card.viewer.liked ? "1" : "0", String(card.counts.likes), String(card.counts.comments), self.expanded.contains(card.id) ? "e" : "c"].joined(separator: ":"))
        }
        if self.appliedIds == ids && self.appliedPrints == prints {
            return
        }
        let edit: (deletes: [Int], inserts: [Int], updates: [Int])
        if self.appliedIds == ids {
            edit = ([], [], momentsChangedRowIndexes(previous: self.appliedPrints, next: prints))
        } else {
            edit = momentsListEdit(previousIds: self.appliedIds, nextIds: ids)
        }
        self.listBusy = true
        self.list.transaction(deleteIndices: edit.deletes.map { ListViewDeleteItem(index: $0, directionHint: nil) }, insertIndicesAndItems: edit.inserts.map { ListViewInsertItem(index: $0, previousIndex: nil, item: entries[$0], directionHint: nil) }, updateIndicesAndItems: edit.updates.map { ListViewUpdateItem(index: $0, previousIndex: $0, item: entries[$0], directionHint: nil) }, options: [.Synchronous], updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: self.list.bounds.size, insets: UIEdgeInsets(top: 0, left: 0, bottom: 24, right: 0), duration: 0, curve: .Default(duration: nil)), updateOpaqueState: nil, completion: { [weak self] _ in
            Queue.mainQueue().async {
                guard let self else {
                    return
                }
                self.appliedIds = ids
                self.appliedPrints = prints
                self.listBusy = false
                if self.renderQueued {
                    self.renderQueued = false
                    self.render()
                }
            }
        })
    }

    private func appendLink(_ entries: inout [ListViewItem], ids: inout [String], prints: inout [String], stable: String, title: String, count: Int?, hidden: Bool, action: @escaping () -> Void) {
        let label = (!hidden && count != nil) ? "\(count ?? 0)" : ""
        entries.append(ItemListDisclosureItem(presentationData: ItemListPresentationData(self.presentationData), title: title, label: label, sectionId: 0, style: .plain, disclosureStyle: .arrow, action: action))
        ids.append(stable)
        prints.append(title + label)
    }

    private func openPeople(followers: Bool) {
        guard let parent = self.parentController else {
            return
        }
        let screen = momentsRelationController(context: self.context, profileId: self.profileId, followers: followers, openPeer: self.openPeer)
        (parent.navigationController as? NavigationController)?.pushViewController(screen)
    }

    private func openCollection(title: String, emptyText: @escaping (PresentationStrings) -> String, load: @escaping (String?, String) -> Signal<MomentsPage, MomentsAPIError>) {
        guard let parent = self.parentController else {
            return
        }
        let screen = MomentsPostListScreen(context: self.context, title: title, emptyText: emptyText, showsSort: false, load: load)
        screen.openPeer = self.openPeer
        (parent.navigationController as? NavigationController)?.pushViewController(screen)
    }
}

public final class MomentsSearchContentNode: ASDisplayNode {
    private let context: AccountContext
    private let list = ListViewImpl()
    private var query = ""
    private var result = MomentsSearchResult()
    private var searchGeneration = MomentsQueryGeneration()
    private var searchDisposable: Disposable?
    private var rendered = 0
    private var rendering = false
    private var renderAgain = false
    private var presentationData: PresentationData
    public var openPeer: ((EnginePeer.Id) -> Void)?
    public var openPost: ((MomentsCard) -> Void)?
    public var openTopic: ((String) -> Void)?

    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init()
        self.addSubnode(self.list)
    }

    deinit {
        self.searchDisposable?.dispose()
    }

    public func update(size: CGSize, presentationData: PresentationData, query: String) {
        self.presentationData = presentationData
        self.list.frame = CGRect(origin: .zero, size: size)
        if query != self.query {
            self.query = query
            let generation = self.searchGeneration.begin()
            self.searchDisposable?.dispose()
            guard !query.isEmpty else {
                self.result = MomentsSearchResult()
                self.render()
                return
            }
            self.searchDisposable = (self.context.engine.moments.search(query: query, scope: "all", sort: "relevance", cursor: nil) |> deliverOnMainQueue).start(next: { [weak self] result in
                guard let self, self.searchGeneration.accepts(generation) else {
                    return
                }
                self.result = result
                self.render()
            })
        } else {
            self.render()
        }
    }

    private func render() {
        guard self.list.bounds.width > 0 else { return }
        if self.rendering {
            self.renderAgain = true
            return
        }
        let theme = self.presentationData.theme
        let strings = self.presentationData.strings
        var rows: [ListViewItem] = []
        for user in self.result.users {
            rows.append(MomentsStatusItem(text: user.displayName, theme: theme, action: { [weak self] in
                guard user.telegramUserId != 0 else { return }
                self?.openPeer?(EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(user.telegramUserId)))
            }))
        }
        for topic in self.result.topics {
            let name = topic.name
            rows.append(MomentsStatusItem(text: "#\(name)  \(topic.visibleCount)", theme: theme, action: { [weak self] in
                guard let self, momentsTopicName(name) != nil else {
                    return
                }
                self.openTopic?(name)
            }))
        }
        for post in self.result.posts {
            let title = post.isUnavailable ? momentsText(strings, .unavailable) : post.text
            rows.append(MomentsStatusItem(text: title, theme: theme, action: { [weak self] in self?.openPost?(post) }))
        }
        if rows.isEmpty {
            rows = [MomentsStatusItem(text: momentsText(strings, .search), theme: theme, action: {})]
        }
        let previous = self.rendered
        let count = rows.count
        self.rendering = true
        self.list.transaction(deleteIndices: (0..<previous).map { ListViewDeleteItem(index: $0, directionHint: nil) }, insertIndicesAndItems: rows.enumerated().map { ListViewInsertItem(index: $0.offset, previousIndex: nil, item: $0.element, directionHint: nil) }, updateIndicesAndItems: [], options: [.Synchronous], updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: self.list.bounds.size, insets: .zero, duration: 0, curve: .Default(duration: nil)), updateOpaqueState: nil, completion: { [weak self] _ in
            guard let self else { return }
            self.rendered = count
            self.rendering = false
            if self.renderAgain {
                self.renderAgain = false
                self.render()
            }
        })
    }
}
