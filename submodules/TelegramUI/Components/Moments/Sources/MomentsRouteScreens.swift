import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext

public final class MomentsPostListScreen: ViewController {
    private let context: AccountContext
    private let actions: MomentsFeedActions
    private let loadPage: (String?, String) -> Signal<MomentsPage, MomentsAPIError>
    private let emptyText: (PresentationStrings) -> String
    private let showsSort: Bool
    private var presentationData: PresentationData
    private let list = ListViewImpl()
    private let anchor = MomentsReturnAnchor()
    private var items: [MomentsCard] = []
    private var cursor: String?
    private var loaded = false
    private var loading = false
    private var failed = false
    private var query = MomentsQueryGeneration()
    private var disposable: Disposable?
    private var sort: String
    private var expanded = Set<String>()
    private var appliedIds: [String] = []
    private var appliedPrints: [String] = []
    private var listBusy = false
    private var renderQueued = false
    private var queuedReset = false
    private let topicName: String?
    public var openPeer: ((EnginePeer.Id) -> Void)? {
        didSet {
            self.actions.openPeer = self.openPeer
        }
    }

    init(context: AccountContext, title: String, emptyText: @escaping (PresentationStrings) -> String, showsSort: Bool, topicName: String? = nil, load: @escaping (String?, String) -> Signal<MomentsPage, MomentsAPIError>) {
        self.context = context
        self.loadPage = load
        self.emptyText = emptyText
        self.showsSort = showsSort
        self.topicName = topicName
        self.sort = "hot"
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.actions = MomentsFeedActions(context: context, presentationData: self.presentationData)
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = title
        self.actions.controller = { [weak self] in self }
        self.actions.onReplace = { [weak self] id, transform in
            guard let self else {
                return
            }
            self.items = self.items.map { $0.id == id ? transform($0) : $0 }
            self.render(resetScroll: false)
        }
        self.actions.onExpand = { [weak self] id in
            self?.expanded.insert(id)
            self?.render(resetScroll: false)
        }
        self.actions.beforeOpen = { [weak self] place in
            self?.anchor.willOpen(place)
        }
        self.actions.onMutation = { [weak self] mutation in
            guard let self, case let .reported(id) = mutation else {
                return
            }
            self.items.removeAll { $0.id == id }
            self.render(resetScroll: false)
        }
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.disposable?.dispose()
    }

    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.addSubnode(self.list)
        self.list.displayedItemRangeChanged = { [weak self] range, _ in
            guard let self else {
                return
            }
            let last = range.visibleRange?.lastIndex ?? range.loadedRange?.lastIndex ?? 0
            if last >= self.items.count - 3 {
                self.load(refresh: false)
            }
        }
        self.list.visibleContentOffsetChanged = { [weak self] offset, _ in
            guard let self, case let .known(value) = offset else {
                return
            }
            self.anchor.noteOffset(value)
        }
        if self.showsSort {
            let sortButton = UIButton(type: .system)
            sortButton.tag = 7
            sortButton.addTarget(self, action: #selector(self.toggleSort), for: .touchUpInside)
            self.displayNode.view.addSubview(sortButton)
        }
        self.load(refresh: true)
        self.displayNodeDidLoad()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let name = self.topicName ?? ""
        self.anchor.returned(root: { offset in
            .topic(name: name, offset: offset)
        }, restore: { [weak self] place in
            guard let self, case let .topic(restoredName, offset) = place, restoredName == name else {
                return
            }
            let _ = self.list.scrollToOffsetFromTop(offset, animated: false)
        })
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        let sortHeight: CGFloat = self.showsSort ? 32 : 0
        if let sortButton = self.displayNode.view.viewWithTag(7) as? UIButton {
            sortButton.frame = CGRect(x: layout.size.width - 120, y: top, width: 108, height: 32)
            let title = momentsText(self.presentationData.strings, self.sort == "hot" ? .sortHot : .sortLatest)
            sortButton.setTitle(title, for: .normal)
        }
        self.list.frame = CGRect(x: 0, y: top + sortHeight, width: layout.size.width, height: max(0, layout.size.height - top - sortHeight))
        self.render(resetScroll: false)
    }

    private func load(refresh: Bool) {
        guard momentsShouldLoadFeedPage(loaded: self.loaded, cursor: self.cursor, refresh: refresh, loading: self.loading) else {
            return
        }
        let generation = self.query.begin()
        self.loading = true
        self.failed = false
        let requestCursor = refresh ? nil : self.cursor
        let sort = self.sort
        self.disposable?.dispose()
        self.disposable = (self.loadPage(requestCursor, sort) |> deliverOnMainQueue).start(next: { [weak self] page in
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
            self.render(resetScroll: refresh)
        }, error: { [weak self] error in
            guard let self, self.query.accepts(generation), momentsListLoadResult(error) != .ignore else {
                return
            }
            self.loading = false
            self.loaded = true
            self.failed = true
            self.render(resetScroll: false)
        })
    }

    @objc private func toggleSort() {
        self.sort = self.sort == "hot" ? "latest" : "hot"
        self.loaded = false
        self.cursor = nil
        self.loading = false
        self.load(refresh: true)
    }

    private func render(resetScroll: Bool) {
        guard self.list.bounds.width > 0 else {
            return
        }
        if self.listBusy {
            self.renderQueued = true
            self.queuedReset = self.queuedReset || resetScroll
            return
        }
        let strings = self.presentationData.strings
        let theme = self.presentationData.theme
        self.actions.presentationData = self.presentationData
        self.actions.openPeer = self.openPeer
        let handlers = self.actions.handlers()
        var entries: [ListViewItem] = []
        if self.items.isEmpty {
            let text = self.failed ? momentsText(strings, .loadFailed) : self.emptyText(strings)
            entries = [MomentsStatusItem(text: text, theme: theme, action: { [weak self] in
                guard let self else {
                    return
                }
                self.loaded = false
                self.loading = false
                self.load(refresh: true)
            })]
        } else {
            for card in self.items {
                entries.append(MomentsPostItem(card: card, strings: strings, theme: theme, fontSize: self.presentationData.listsFontSize.baseDisplaySize, showFollow: false, expanded: self.expanded.contains(card.id), hidden: false, albumIndex: 0, playing: false, context: self.context, handlers: handlers))
            }
            if self.failed {
                entries.append(MomentsStatusItem(text: momentsText(strings, .loadFailed), theme: theme, action: { [weak self] in
                    self?.load(refresh: false)
                }))
            }
        }
        let rows: [(stable: String, print: String)] = entries.map { item in
            if let post = item as? MomentsPostItem {
                let card = post.card
                let print = [String(card.version), card.viewer.liked ? "1" : "0", String(card.counts.likes), String(card.counts.comments), post.expanded ? "e" : "c"].joined(separator: ":")
                return (card.id, print)
            }
            if let status = item as? MomentsStatusItem {
                return ("status", status.text)
            }
            return ("status", "")
        }
        let ids = rows.map(\.stable)
        let prints = rows.map(\.print)
        if self.appliedIds == ids && self.appliedPrints == prints && !resetScroll {
            return
        }
        let edit: (deletes: [Int], inserts: [Int], updates: [Int])
        if self.appliedIds == ids {
            edit = ([], [], momentsChangedRowIndexes(previous: self.appliedPrints, next: prints))
        } else {
            edit = momentsListEdit(previousIds: self.appliedIds, nextIds: ids)
        }
        self.listBusy = true
        let scroll = resetScroll && !entries.isEmpty ? ListViewScrollToItem(index: 0, position: .top(0), animated: false, curve: .Default(duration: nil), directionHint: .Up) : nil
        self.list.transaction(deleteIndices: edit.deletes.map { ListViewDeleteItem(index: $0, directionHint: nil) }, insertIndicesAndItems: edit.inserts.map { ListViewInsertItem(index: $0, previousIndex: nil, item: entries[$0], directionHint: nil) }, updateIndicesAndItems: edit.updates.map { ListViewUpdateItem(index: $0, previousIndex: $0, item: entries[$0], directionHint: nil) }, options: [.Synchronous], scrollToItem: scroll, updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: self.list.bounds.size, insets: UIEdgeInsets(top: 0, left: 0, bottom: 24, right: 0), duration: 0, curve: .Default(duration: nil)), updateOpaqueState: nil, completion: { [weak self] _ in
            Queue.mainQueue().async {
                guard let self else {
                    return
                }
                self.appliedIds = ids
                self.appliedPrints = prints
                self.listBusy = false
                if self.renderQueued {
                    let reset = self.queuedReset
                    self.renderQueued = false
                    self.queuedReset = false
                    self.render(resetScroll: reset)
                }
            }
        })
    }
}

public func MomentsTopicScreen(context: AccountContext, name: String) -> MomentsPostListScreen {
    let topic = momentsTopicName(name) ?? name
    return MomentsPostListScreen(context: context, title: "#\(topic)", emptyText: { $0.Moments_TopicEmpty }, showsSort: true, topicName: topic, load: { cursor, sort in
        context.engine.moments.topic(name: topic, sort: sort, cursor: cursor)
        |> map { page in
            MomentsPage(items: page.items, nextCursor: page.nextCursor)
        }
    })
}
