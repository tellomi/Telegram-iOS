import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import StickerPickerScreen
import EntityKeyboard
import MediaEditor
import PresentationDataUtils
import UndoUI
import ItemListUI

public final class MomentsDetailScreen: ViewController {
    private let context: AccountContext
    private var card: MomentsCard
    private var comments: [MomentsComment] = []
    private var sort = "hot"
    public var openPeer: ((EnginePeer.Id) -> Void)?
    private var presentationData: PresentationData
    private let list = ListViewImpl()
    private let field = UITextField()
    private var rendered = 0
    private var rendering = false
    private var renderAgain = false
    private var commentComposer = MomentsCommentComposerState()
    private let focusCommentId: String?
    private var didApplyCommentFocus = false
    private var pendingScrollCommentId: String?

    public init(context: AccountContext, card: MomentsCard, focusCommentId: String? = nil) {
        self.context = context
        self.card = card
        self.focusCommentId = focusCommentId
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = momentsText(self.presentationData.strings, .comment)
    }

    required init(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.addSubnode(self.list)
        self.displayNode.view.addSubview(self.field)
        self.field.borderStyle = .roundedRect
        self.field.placeholder = momentsText(self.presentationData.strings, .commentPlaceholder)
        self.field.returnKeyType = .send
        self.field.delegate = self
        let sortButton = UIButton(type: .system)
        sortButton.tag = 7
        sortButton.setTitle(momentsText(self.presentationData.strings, .sortHot), for: .normal)
        sortButton.addTarget(self, action: #selector(self.toggleSort), for: .touchUpInside)
        self.displayNode.view.addSubview(sortButton)
        self.reload()
        self.displayNodeDidLoad()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        let bottom = layout.intrinsicInsets.bottom + 44
        if let sortButton = self.displayNode.view.viewWithTag(7) {
            sortButton.frame = CGRect(x: layout.size.width - 100, y: top, width: 88, height: 32)
        }
        self.list.frame = CGRect(x: 0, y: top + 32, width: layout.size.width, height: layout.size.height - top - 32 - bottom)
        self.field.frame = CGRect(x: 56, y: layout.size.height - bottom + 6, width: layout.size.width - 68, height: 34)
        if self.displayNode.view.viewWithTag(11) == nil {
            let stickers = UIButton(type: .system)
            stickers.tag = 11
            stickers.setTitle(self.presentationData.strings.Message_Animation, for: .normal)
            stickers.addTarget(self, action: #selector(self.stickerPressed), for: .touchUpInside)
            self.displayNode.view.addSubview(stickers)
        }
        self.displayNode.view.viewWithTag(11)?.frame = CGRect(x: 8, y: layout.size.height - bottom + 6, width: 44, height: 34)
        self.render()
    }

    private func reload() {
        let _ = (self.context.engine.moments.comments(postId: self.card.id, sort: self.sort, cursor: nil) |> deliverOnMainQueue).start(next: { [weak self] page in
            guard let self else {
                return
            }
            self.comments = page.comments
            if !self.didApplyCommentFocus {
                switch momentsCommentFocus(commentId: self.focusCommentId, comments: page.comments) {
                case let .located(id):
                    self.pendingScrollCommentId = id
                    self.didApplyCommentFocus = true
                case .missing:
                    self.didApplyCommentFocus = true
                    momentsPresentErrorToast(controller: self, presentationData: self.presentationData, text: self.presentationData.strings.Moments_CommentMissing)
                case nil:
                    break
                }
            }
            self.render()
        })
    }

    private func render() {
        guard self.list.bounds.width > 0 else { return }
        if self.rendering {
            self.renderAgain = true
            return
        }
        let strings = self.presentationData.strings
        let theme = self.presentationData.theme
        var items: [ListViewItem] = [MomentsPostItem(card: self.card, strings: strings, theme: theme, fontSize: self.presentationData.listsFontSize.baseDisplaySize, showFollow: false, expanded: true, hidden: false, albumIndex: 0, playing: false, context: self.context, handlers: self.handlers())]
        if !self.card.viewer.canComment {
            items.append(MomentsStatusItem(text: self.card.viewer.commentDeniedReason ?? momentsText(strings, .commentClosed), theme: theme, action: {}))
        }
        var scrollIndex: Int?
        for comment in self.comments where !comment.disliked {
            if self.pendingScrollCommentId == comment.id || comment.replies.contains(where: { $0.id == self.pendingScrollCommentId }) {
                scrollIndex = items.count
            }
            items.append(MomentsStatusItem(text: self.commentLine(comment), theme: theme, action: { [weak self] in self?.replyTo(comment) }))
            for reply in comment.replies.prefix(2) where !reply.disliked {
                let name = reply.author?.displayName ?? ""
                let target = reply.replyToName.map { "@\($0) " } ?? ""
                items.append(MomentsStatusItem(text: "\(name) \(target)\(reply.text)", theme: theme, action: {}))
            }
            if comment.replyCount > 2 {
                items.append(MomentsStatusItem(text: "\(momentsText(strings, .viewReplies)) \(comment.replyCount)", theme: theme, action: { [weak self] in self?.expand(comment) }))
            }
        }
        let previous = self.rendered
        let count = items.count
        self.rendering = true
        let scroll = scrollIndex.map { ListViewScrollToItem(index: $0, position: .center(.bottom), animated: false, curve: .Default(duration: nil), directionHint: .Down) }
        self.pendingScrollCommentId = nil
        self.list.transaction(deleteIndices: (0..<previous).map { ListViewDeleteItem(index: $0, directionHint: nil) }, insertIndicesAndItems: items.enumerated().map { ListViewInsertItem(index: $0.offset, previousIndex: nil, item: $0.element, directionHint: nil) }, updateIndicesAndItems: [], options: [.Synchronous], scrollToItem: scroll, updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: self.list.bounds.size, insets: .zero, duration: 0, curve: .Default(duration: nil)), updateOpaqueState: nil, completion: { [weak self] _ in
            guard let self else { return }
            self.rendered = count
            self.rendering = false
            if self.renderAgain {
                self.renderAgain = false
                self.render()
            }
        })
        self.field.isEnabled = self.card.viewer.canComment && self.card.commentPolicy != .closed
        if self.card.commentPolicy == .closed {
            self.field.placeholder = momentsText(strings, .commentClosed)
        }
    }

    private func commentLine(_ comment: MomentsComment) -> String {
        let strings = self.presentationData.strings
        let name = comment.author?.displayName ?? ""
        if comment.text.isEmpty, let attachment = comment.attachment {
            return "\(name)  \(momentsAttachmentTitle(strings, attachment.type))"
        }
        return "\(name)  \(comment.text)"
    }

    private func handlers() -> MomentsPostHandlers {
        return MomentsPostHandlers(open: { _ in }, author: { [weak self] card in
            guard let id = card.author?.telegramUserId, id != 0 else { return }
            self?.openPeer?(EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(id)))
        }, like: { [weak self] card in
            guard let self else { return }
            self.card.viewer.liked.toggle()
            self.card.counts.likes += self.card.viewer.liked ? 1 : -1
            let _ = self.context.engine.moments.setLiked(card.id, liked: self.card.viewer.liked).start()
            self.render()
        }, comment: { _ in }, repost: { _ in }, share: { card in
            UIPasteboard.general.string = momentsPostLink(id: card.id)
        }, save: { [weak self] card in
            guard let self else { return }
            self.card.viewer.saved.toggle()
            let _ = self.context.engine.moments.setSaved(card.id, saved: self.card.viewer.saved).start()
            self.render()
        }, more: { _, _ in }, follow: { _ in }, undo: { _ in }, fullText: { _ in }, topic: { [weak self] name in
            guard let self, let topic = momentsTopicName(name) else {
                return
            }
            let screen = MomentsTopicScreen(context: self.context, name: topic)
            screen.openPeer = self.openPeer
            (self.navigationController as? NavigationController)?.pushViewController(screen)
        }, link: { [weak self] url in
            guard let self else { return }
            self.context.sharedContext.openExternalUrl(context: self.context, urlContext: .generic, url: url, forceExternal: false, presentationData: self.presentationData, navigationController: self.navigationController as? NavigationController, dismissInput: {})
        }, likers: { [weak self] card in
            guard let self else { return }
            self.openPeople(title: momentsText(self.presentationData.strings, .like), load: self.context.engine.moments.likers(postId: card.id) |> map { authors in
                [MomentsPeopleSection(title: nil, people: authors)]
            })
        }, voters: { [weak self] card in
            guard let self else { return }
            self.openPeople(title: momentsText(self.presentationData.strings, .endPoll), load: self.context.engine.moments.pollVoters(postId: card.id) |> map { options in
                options.map { MomentsPeopleSection(title: $0.text, people: $0.voters) }
            })
        })
    }

    private func replyTo(_ comment: MomentsComment) {
        self.field.text = ""
        self.field.accessibilityHint = comment.id
        self.field.becomeFirstResponder()
    }

    private func expand(_ comment: MomentsComment) {
        let _ = (self.context.engine.moments.replies(rootId: comment.id, cursor: nil) |> deliverOnMainQueue).start(next: { [weak self] page in
            guard let self else { return }
            self.comments = self.comments.map { item in
                guard item.id == comment.id else { return item }
                var copy = item
                copy.replies = page.replies.filter { !$0.disliked }
                copy.replyCount = page.total > 0 ? page.total : copy.replies.count
                return copy
            }
            self.render()
        })
    }

    private func openPeople(title: String, load: Signal<[MomentsPeopleSection], MomentsAPIError>) {
        (self.navigationController as? NavigationController)?.pushViewController(momentsPeopleController(context: self.context, title: title, load: load))
    }

    @objc private func stickerPressed() {
        guard self.card.viewer.canComment, self.card.commentPolicy != .closed else { return }
        let input = EmojiPagerContentComponent.momentsStickerInput(
            context: self.context,
            animationCache: self.context.animationCache,
            animationRenderer: self.context.animationRenderer,
            stickerNamespaces: [Namespaces.ItemCollection.CloudStickerPacks],
            stickerOrderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudSavedStickers, Namespaces.OrderedItemList.CloudRecentStickers, Namespaces.OrderedItemList.CloudAllPremiumStickers],
            chatPeerId: self.context.account.peerId
        )
        |> map { stickers -> StickerPickerInput in
            return StickerPickerInputData(emoji: nil, stickers: stickers, gifs: nil)
        }
        let screen = StickerPickerScreen(context: self.context, inputData: input, expanded: true, hasEmoji: false, hasGifs: true, hasInteractiveStickers: false)
        screen.completion = { [weak self] content in
            guard let self, let content else {
                return true
            }
            let file: TelegramMediaFile
            let type: MomentsMediaType
            switch content {
            case let .file(reference, _):
                file = reference.media
                type = reference.media.mimeType == "video/mp4" ? .gif : .sticker
            case let .video(media):
                file = media
                type = .gif
            default:
                return true
            }
            self.uploadCommentMedia(file: file, type: type, parentId: self.field.accessibilityHint)
            return true
        }
        (self.navigationController as? NavigationController)?.pushViewController(screen)
    }

    /// Comments store the same media object as a post: a tus key, not a Telegram document id.
    private func uploadCommentMedia(file: TelegramMediaFile, type: MomentsMediaType, parentId: String?) {
        if type == .audio {
            let duration = file.duration ?? 0
            if duration > momentsVoiceMaxDuration(self.context.engine.moments.currentLimits(), comment: true) {
                return
            }
        }
        let resource = file.resource
        let resolved = self.commentMediaPath(resource)
        let dimensions = file.dimensions
        let upload = resolved
        |> mapToSignal { [weak self] path -> Signal<MomentsMedia, MomentsAPIError> in
            guard let self else {
                return .complete()
            }
            return self.context.engine.moments.uploadFile(MomentsUploadFile(
                path: path,
                filename: file.fileName ?? momentsPlaybackFileName(type),
                mimeType: file.mimeType.isEmpty ? momentsPlaybackMimeType(type) : file.mimeType,
                type: type,
                width: Int(dimensions?.width ?? 0),
                height: Int(dimensions?.height ?? 0),
                durationMs: Int((file.duration ?? 0) * 1000),
                order: 0
            ))
        }
        let _ = (upload |> deliverOnMainQueue).start(next: { [weak self] media in
            guard let self else { return }
            let attachment: [String: Any] = [
                "type": media.type.rawValue,
                "key": media.key,
                "w": media.width,
                "h": media.height,
                "duration_ms": media.durationMs
            ]
            let _ = self.context.engine.moments.addComment(postId: self.card.id, text: "", parentId: parentId, attachment: attachment).start()
            self.reload()
        }, error: { [weak self] _ in
            guard let self else { return }
            momentsPresentErrorToast(controller: self, presentationData: self.presentationData, text: momentsText(self.presentationData.strings, .loadFailed))
        })
    }

    /// Download the sticker or GIF, give up after 12 seconds, and try once more.
    private func commentMediaPath(_ resource: TelegramMediaResource) -> Signal<String, MomentsAPIError> {
        if let local = resource as? LocalFileReferenceMediaResource, FileManager.default.fileExists(atPath: local.localFilePath) {
            return .single(local.localFilePath)
        }
        let engineResource = EngineMediaResource(resource)
        func once() -> Signal<String, MomentsAPIError> {
            return Signal<String, MomentsAPIError> { [weak self] subscriber in
                guard let self else {
                    subscriber.putError(.cancelled)
                    return EmptyDisposable
                }
                let fetch = self.context.engine.resources.fetchedResource(resource: engineResource).start(error: { _ in
                    subscriber.putError(.transport("fetch"))
                })
                let watched = self.context.engine.resources.data(resource: engineResource, waitUntilFetchStatus: true)
                |> filter { $0.isComplete && !$0.path.isEmpty }
                |> take(1)
                let data = watched.start(next: { item in
                    subscriber.putNext(item.path)
                    subscriber.putCompletion()
                })
                return ActionDisposable {
                    fetch.dispose()
                    data.dispose()
                }
            }
            |> timeout(12.0, queue: Queue.concurrentDefaultQueue(), alternate: .fail(.transport("timeout")))
        }
        return once()
        |> `catch` { _ -> Signal<String, MomentsAPIError> in
            return once()
        }
    }

    @objc private func toggleSort() {
        self.sort = self.sort == "hot" ? "latest" : "hot"
        (self.displayNode.view.viewWithTag(7) as? UIButton)?.setTitle(momentsText(self.presentationData.strings, self.sort == "hot" ? .sortHot : .sortLatest), for: .normal)
        self.reload()
    }
}

func momentsPresentErrorToast(controller: ViewController, presentationData: PresentationData, text: String) {
    controller.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: 3.0, customUndoText: nil), elevatedLayout: false, action: { _ in true }), in: .current)
}

extension MomentsDetailScreen: UITextFieldDelegate {
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = textField.text ?? ""
        guard !text.isEmpty, text.count <= self.context.engine.moments.currentLimits().commentTextLimit else { return false }
        guard self.card.viewer.canComment, self.card.commentPolicy != .closed else { return false }
        let parent = textField.accessibilityHint
        let draft = momentsCommentComposerForSend(previous: self.commentComposer, text: text, parentId: parent, mediaKey: nil, sticker: false)
        guard case .success = momentsEncodeComment(draft) else {
            momentsPresentErrorToast(controller: self, presentationData: self.presentationData, text: momentsText(self.presentationData.strings, .commentSendFailed))
            return false
        }
        self.commentComposer = draft
        let _ = self.context.engine.moments.addComment(postId: self.card.id, text: text, parentId: parent, clientNonce: draft.clientNonce).start(error: { [weak self] _ in
            guard let self else { return }
            self.commentComposer = momentsCommentComposerAfterFailure(draft)
            momentsPresentErrorToast(controller: self, presentationData: self.presentationData, text: momentsText(self.presentationData.strings, .commentSendFailed))
        }, completed: { [weak self] in
            guard let self else { return }
            if textField.text == text {
                textField.text = ""
            }
            if textField.accessibilityHint == parent {
                textField.accessibilityHint = nil
            }
            self.commentComposer = momentsCommentComposerAfterSuccess()
            textField.resignFirstResponder()
            self.reload()
        })
        return false
    }
}

private struct MomentsNoticeState {
    var tab = "interactions"
    var items: [MomentsNotification] = []
    var cursor: String?
    var loaded = false
    var loading = false
    var failed = false
}

private final class MomentsNoticeArguments {
    let select: (String) -> Void
    let open: (MomentsNotification) -> Void
    let retry: () -> Void
    init(select: @escaping (String) -> Void, open: @escaping (MomentsNotification) -> Void, retry: @escaping () -> Void) {
        self.select = select
        self.open = open
        self.retry = retry
    }
}

private enum MomentsNoticeEntry: ItemListNodeEntry {
    case filter(Int32, String, String, Bool)
    case row(Int32, MomentsNotification, String)
    case status(String, Bool)

    var section: ItemListSectionId {
        switch self {
        case .filter:
            return 0
        default:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case let .filter(index, _, _, _):
            return index
        case let .row(index, _, _):
            return 100 + index
        case .status:
            return 10_000
        }
    }

    static func <(lhs: MomentsNoticeEntry, rhs: MomentsNoticeEntry) -> Bool {
        if lhs.section != rhs.section {
            return lhs.section < rhs.section
        }
        return lhs.stableId < rhs.stableId
    }

    static func ==(lhs: MomentsNoticeEntry, rhs: MomentsNoticeEntry) -> Bool {
        switch lhs {
        case let .filter(index, tab, title, selected):
            if case .filter(index, tab, title, selected) = rhs { return true }
            return false
        case let .row(index, item, line):
            if case .row(index, item, line) = rhs { return true }
            return false
        case let .status(text, retry):
            if case .status(text, retry) = rhs { return true }
            return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MomentsNoticeArguments
        switch self {
        case let .filter(_, tab, title, selected):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: selected ? .generic : .neutral, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.select(tab)
            })
        case let .row(_, item, line):
            return ItemListActionItem(presentationData: presentationData, title: line, kind: .neutral, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.open(item)
            })
        case let .status(text, retry):
            if retry {
                return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .center, sectionId: self.section, style: .blocks, action: arguments.retry)
            }
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class MomentsNoticeModel {
    let context: AccountContext
    var openPeer: ((EnginePeer.Id) -> Void)?
    weak var controller: ViewController?
    var state = MomentsNoticeState()
    let promise = Promise<MomentsNoticeState>()
    private var listQuery = MomentsQueryGeneration()
    private var openQuery = MomentsQueryGeneration()
    private var listDisposable: Disposable?
    private var openDisposable: Disposable?
    private var marked = Set<String>()

    init(context: AccountContext, openPeer: ((EnginePeer.Id) -> Void)?) {
        self.context = context
        self.openPeer = openPeer
        self.promise.set(.single(self.state))
    }

    deinit {
        self.listDisposable?.dispose()
        self.openDisposable?.dispose()
    }

    func select(_ tab: String) {
        guard tab != self.state.tab else {
            return
        }
        self.state.tab = tab
        self.state.items = []
        self.state.cursor = nil
        self.state.loaded = false
        self.state.loading = false
        self.state.failed = false
        self.promise.set(.single(self.state))
        self.load(refresh: true)
    }

    func load(refresh: Bool) {
        guard momentsShouldLoadFeedPage(loaded: self.state.loaded, cursor: self.state.cursor, refresh: refresh, loading: self.state.loading) else {
            return
        }
        let generation = self.listQuery.begin()
        let tab = self.state.tab
        self.state.loading = true
        let requestCursor = refresh ? nil : self.state.cursor
        self.listDisposable?.dispose()
        self.listDisposable = (self.context.engine.moments.notifications(tab: tab, cursor: requestCursor) |> deliverOnMainQueue).start(next: { [weak self] page in
            guard let self, self.listQuery.accepts(generation), self.state.tab == tab else {
                return
            }
            let refreshing = refresh || requestCursor == nil
            if refreshing {
                var seen = Set<String>()
                self.state.items = page.items.filter { seen.insert($0.id).inserted }
                self.state.cursor = page.items.isEmpty ? nil : page.nextCursor
            } else if page.items.isEmpty {
                self.state.cursor = nil
            } else {
                var seen = Set(self.state.items.map(\.id))
                for item in page.items where seen.insert(item.id).inserted {
                    self.state.items.append(item)
                }
                self.state.cursor = page.nextCursor
            }
            self.state.loading = false
            self.state.loaded = true
            self.state.failed = false
            self.promise.set(.single(self.state))
            self.markRead(tab)
        }, error: { [weak self] error in
            guard let self, self.listQuery.accepts(generation), momentsListLoadResult(error) != .ignore else {
                return
            }
            self.state.loading = false
            self.state.loaded = true
            self.state.failed = true
            self.promise.set(.single(self.state))
        })
    }

    private func markRead(_ tab: String) {
        guard self.marked.insert(tab).inserted else {
            return
        }
        let _ = self.context.engine.moments.markNotificationsRead(tab: tab).start()
    }

    func open(_ item: MomentsNotification) {
        guard self.controller != nil else {
            return
        }
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        switch momentsNotificationDestination(item) {
        case .unavailable:
            self.present(presentationData.strings.Moments_Unavailable)
        case let .peer(userId):
            guard let peerId = momentsPeerId(userId), let openPeer = self.openPeer else {
                self.present(presentationData.strings.Moments_Unavailable)
                return
            }
            openPeer(peerId)
        case let .post(id, commentId):
            let generation = self.openQuery.begin()
            self.openDisposable?.dispose()
            self.openDisposable = (self.context.engine.moments.post(id: id) |> deliverOnMainQueue).start(next: { [weak self] card in
                guard let self, self.openQuery.accepts(generation), let controller = self.controller else {
                    return
                }
                if card.isUnavailable {
                    self.present(self.context.sharedContext.currentPresentationData.with { $0 }.strings.Moments_Unavailable)
                    return
                }
                let detail = MomentsDetailScreen(context: self.context, card: card, focusCommentId: commentId)
                detail.openPeer = self.openPeer
                (controller.navigationController as? NavigationController)?.pushViewController(detail)
            }, error: { [weak self] error in
                guard let self, self.openQuery.accepts(generation) else {
                    return
                }
                let strings = self.context.sharedContext.currentPresentationData.with { $0 }.strings
                self.present(error == .notFound ? strings.Moments_Unavailable : strings.Moments_LoadFailed)
            })
        }
    }

    private func present(_ text: String) {
        guard let controller = self.controller else {
            return
        }
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        controller.present(textAlertController(context: self.context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {})]), in: .window(.root))
    }
}

private func momentsNoticeLine(_ strings: PresentationStrings, _ item: MomentsNotification) -> String {
    if item.unavailable {
        return strings.Moments_Unavailable
    }
    let names = item.actors.map(\.displayName).joined(separator: ", ")
    let extra = item.extraActorCount > 0 ? " +\(item.extraActorCount)" : ""
    return "\(names)\(extra) \(momentsNotificationTitle(strings, item.kind)) \(item.text ?? "")"
}

func momentsNotificationsController(context: AccountContext, openPeer: ((EnginePeer.Id) -> Void)?) -> ViewController {
    let model = MomentsNoticeModel(context: context, openPeer: openPeer)
    let signal = combineLatest(context.sharedContext.presentationData, model.promise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, MomentsNoticeArguments)) in
        let strings = presentationData.strings
        let arguments = MomentsNoticeArguments(select: { tab in
            model.select(tab)
        }, open: { item in
            model.open(item)
        }, retry: {
            model.state.loaded = false
            model.state.loading = false
            model.load(refresh: true)
        })
        let filters = [("interactions", strings.Moments_Notif_Interactions), ("follows", strings.Moments_Notif_Follows), ("system", strings.Moments_Notif_System)]
        var entries: [MomentsNoticeEntry] = []
        for (index, filter) in filters.enumerated() {
            entries.append(.filter(Int32(index), filter.0, filter.1, filter.0 == state.tab))
        }
        if state.failed && state.items.isEmpty {
            entries.append(.status(strings.Moments_LoadFailed, true))
        } else if state.loaded && state.items.isEmpty {
            entries.append(.status(strings.Moments_Notifications, false))
        } else {
            for (index, item) in state.items.enumerated() {
                entries.append(.row(Int32(index), item, momentsNoticeLine(strings, item)))
            }
            if state.failed {
                entries.append(.status(strings.Moments_LoadFailed, true))
            }
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(strings.Moments_Notifications), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    model.controller = controller
    controller.visibleBottomContentOffsetChanged = { [weak model] offset in
        if case let .known(value) = offset, value < 200.0 {
            model?.load(refresh: false)
        }
    }
    model.load(refresh: true)
    return controller
}

private func momentsAttachmentTitle(_ strings: PresentationStrings, _ type: MomentsMediaType) -> String {
    switch type {
    case .image:
        return strings.Message_Photo
    case .video:
        return strings.Message_Video
    case .audio:
        return strings.Message_Audio
    case .sticker:
        return strings.Message_Sticker
    case .gif:
        return strings.Message_Animation
    }
}

private func momentsNotificationTitle(_ strings: PresentationStrings, _ kind: MomentsNotificationKind) -> String {
    switch kind {
    case .like:
        return momentsText(strings, .like)
    case .comment:
        return momentsText(strings, .comment)
    case .reply:
        return momentsText(strings, .reply)
    case .mention:
        return momentsText(strings, .pushMentions)
    case .follow:
        return momentsText(strings, .pushFollows)
    case .mutual:
        return momentsText(strings, .audienceMutual)
    case .repost:
        return momentsText(strings, .repost)
    case .quote:
        return momentsText(strings, .quote)
    case .newPost:
        return momentsText(strings, .pushNewPosts)
    case .system, .all:
        return momentsText(strings, .notifications)
    }
}
