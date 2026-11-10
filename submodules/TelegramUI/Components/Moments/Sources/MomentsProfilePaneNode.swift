import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import PeerInfoPaneNode

public final class MomentsProfilePaneNode: ASDisplayNode, PeerInfoPaneNode {
    private let context: AccountContext
    private let peerId: EnginePeer.Id
    private let list = ListViewImpl()
    private let ready = Promise<Bool>(false)
    private var items: [MomentsCard] = []
    private var rendered = 0
    private var rendering = false
    private var renderAgain = false
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
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init()
        self.addSubnode(self.list)
        let _ = (context.engine.moments.profilePosts(id: "\(peerId.toInt64())", filter: "posts", cursor: nil) |> deliverOnMainQueue).start(next: { [weak self] page in
            self?.items = page.items
            self?.ready.set(.single(true))
            self?.render()
        }, error: { [weak self] _ in
            self?.ready.set(.single(true))
        })
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

    private func render() {
        guard self.list.bounds.width > 0 else { return }
        if self.rendering {
            self.renderAgain = true
            return
        }
        let strings = self.presentationData.strings
        let theme = self.presentationData.theme
        let handlers = MomentsPostHandlers(open: { [weak self] card in
            guard let self, let parent = self.parentController else { return }
            (parent.navigationController as? NavigationController)?.pushViewController(MomentsDetailScreen(context: self.context, card: card))
        }, author: { _ in }, like: { _ in }, comment: { _ in }, repost: { _ in }, share: { _ in }, save: { _ in }, more: { _, _ in }, follow: { _ in }, undo: { _ in }, fullText: { _ in }, topic: { _ in }, link: { _ in })
        let rows: [ListViewItem] = self.items.map { card in
            MomentsPostItem(card: card, strings: strings, theme: theme, fontSize: self.presentationData.listsFontSize.baseDisplaySize, showFollow: false, expanded: false, hidden: false, albumIndex: 0, playing: false, context: self.context, handlers: handlers)
        }
        let previous = self.rendered
        let count = rows.count
        self.rendering = true
        self.list.transaction(deleteIndices: (0..<previous).map { ListViewDeleteItem(index: $0, directionHint: nil) }, insertIndicesAndItems: rows.enumerated().map { ListViewInsertItem(index: $0.offset, previousIndex: nil, item: $0.element, directionHint: nil) }, updateIndicesAndItems: [], options: [.Synchronous], updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: self.list.bounds.size, insets: UIEdgeInsets(top: 0, left: 0, bottom: 24, right: 0), duration: 0, curve: .Default(duration: nil)), updateOpaqueState: nil, completion: { [weak self] _ in
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

public final class MomentsSearchContentNode: ASDisplayNode {
    private let context: AccountContext
    private let list = ListViewImpl()
    private var query = ""
    private var result = MomentsSearchResult()
    private var rendered = 0
    private var rendering = false
    private var renderAgain = false
    private var presentationData: PresentationData
    public var openPeer: ((EnginePeer.Id) -> Void)?
    public var openPost: ((MomentsCard) -> Void)?

    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init()
        self.addSubnode(self.list)
    }

    public func update(size: CGSize, presentationData: PresentationData, query: String) {
        self.presentationData = presentationData
        self.list.frame = CGRect(origin: .zero, size: size)
        if query != self.query {
            self.query = query
            guard !query.isEmpty else {
                self.result = MomentsSearchResult()
                self.render()
                return
            }
            let _ = (self.context.engine.moments.search(query: query, scope: "all", sort: "relevance", cursor: nil) |> deliverOnMainQueue).start(next: { [weak self] result in
                self?.result = result
                self?.render()
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
            rows.append(MomentsStatusItem(text: "#\(topic.name)  \(topic.visibleCount)", theme: theme, action: {}))
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
