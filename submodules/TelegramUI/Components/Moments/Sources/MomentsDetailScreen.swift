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

    public init(context: AccountContext, card: MomentsCard) {
        self.context = context
        self.card = card
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
            stickers.setTitle("GIF", for: .normal)
            stickers.addTarget(self, action: #selector(self.stickerPressed), for: .touchUpInside)
            self.displayNode.view.addSubview(stickers)
        }
        self.displayNode.view.viewWithTag(11)?.frame = CGRect(x: 8, y: layout.size.height - bottom + 6, width: 44, height: 34)
        self.render()
    }

    private func reload() {
        let _ = (self.context.engine.moments.comments(postId: self.card.id, sort: self.sort, cursor: nil) |> deliverOnMainQueue).start(next: { [weak self] comments in
            self?.comments = comments
            self?.render()
        })
    }

    private func render() {
        guard self.list.bounds.width > 0 else { return }
        let strings = self.presentationData.strings
        let theme = self.presentationData.theme
        var items: [ListViewItem] = [MomentsPostItem(card: self.card, strings: strings, theme: theme, fontSize: self.presentationData.listsFontSize.baseDisplaySize, showFollow: false, expanded: true, hidden: false, albumIndex: 0, playing: false, handlers: self.handlers())]
        if !self.card.viewer.canComment {
            items.append(MomentsStatusItem(text: self.card.viewer.commentDeniedReason ?? momentsText(strings, .commentClosed), theme: theme, action: {}))
        }
        for comment in self.comments {
            items.append(MomentsStatusItem(text: self.commentLine(comment), theme: theme, action: { [weak self] in self?.replyTo(comment) }))
            for reply in comment.replies.prefix(2) {
                let name = reply.author?.displayName ?? ""
                let target = reply.replyToName.map { "@\($0) " } ?? ""
                items.append(MomentsStatusItem(text: "\(name) \(target)\(reply.text)", theme: theme, action: {}))
            }
            if comment.replyCount > 2 {
                items.append(MomentsStatusItem(text: "\(momentsText(strings, .viewReplies)) \(comment.replyCount)", theme: theme, action: { [weak self] in self?.expand(comment) }))
            }
        }
        let previous = self.rendered
        self.rendered = items.count
        self.list.transaction(deleteIndices: (0..<previous).map { ListViewDeleteItem(index: $0, directionHint: nil) }, insertIndicesAndItems: items.enumerated().map { ListViewInsertItem(index: $0.offset, previousIndex: nil, item: $0.element, directionHint: nil) }, updateIndicesAndItems: [], options: [.Synchronous], updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: self.list.bounds.size, insets: .zero, duration: 0, curve: .Default(duration: nil)), updateOpaqueState: nil, completion: { _ in })
        self.field.isEnabled = self.card.viewer.canComment && self.card.commentPolicy != .closed
        if self.card.commentPolicy == .closed {
            self.field.placeholder = momentsText(strings, .commentClosed)
        }
    }

    private func commentLine(_ comment: MomentsComment) -> String {
        let name = comment.author?.displayName ?? ""
        if comment.text.isEmpty, let attachment = comment.attachment {
            return "\(name)  \(attachment.type.rawValue)"
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
        }, more: { _, _ in }, follow: { _ in }, undo: { _ in }, fullText: { _ in }, topic: { _ in }, link: { [weak self] url in
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
        let _ = (self.context.engine.moments.replies(rootId: comment.id, cursor: nil) |> deliverOnMainQueue).start(next: { [weak self] replies in
            guard let self else { return }
            self.comments = self.comments.map { item in
                guard item.id == comment.id else { return item }
                var copy = item
                copy.replies = replies
                copy.replyCount = replies.count
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
                let data = self.context.engine.resources.data(resource: engineResource, waitUntilFetchStatus: true)
                |> filter { $0.isComplete && !$0.path.isEmpty }
                |> take(1)
                |> start(next: { item in
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
        guard !text.isEmpty, text.count <= MomentsLimits.standard.commentTextLimit else { return false }
        let parent = textField.accessibilityHint
        let _ = self.context.engine.moments.addComment(postId: self.card.id, text: text, parentId: parent).start()
        textField.text = ""
        textField.accessibilityHint = nil
        textField.resignFirstResponder()
        self.reload()
        return false
    }
}

public final class MomentsNotificationsScreen: ViewController {
    private let context: AccountContext
    public var openPeer: ((EnginePeer.Id) -> Void)?
    private var presentationData: PresentationData
    private let list = ListViewImpl()
    private var items: [MomentsNotification] = []
    private var kind = "interactions"
    private var rendered = 0

    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = momentsText(self.presentationData.strings, .notifications)
    }

    required init(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.addSubnode(self.list)
        self.reload()
        self.displayNodeDidLoad()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.list.frame = CGRect(x: 0, y: top, width: layout.size.width, height: layout.size.height - top)
        self.render()
    }

    private func reload() {
        let _ = (self.context.engine.moments.notifications(tab: self.kind) |> deliverOnMainQueue).start(next: { [weak self] items in
            self?.items = items
            self?.render()
        }, error: { [weak self] error in
            guard let self else { return }
            let text = error == .notFound ? momentsText(self.presentationData.strings, .unavailable) : momentsText(self.presentationData.strings, .loadFailed)
            self.items = []
            self.render(empty: text)
        })
    }

    private func render(empty: String? = nil) {
        guard self.list.bounds.width > 0 else { return }
        let theme = self.presentationData.theme
        let strings = self.presentationData.strings
        var rows: [ListViewItem] = []
        if let empty {
            rows = [MomentsStatusItem(text: empty, theme: theme, action: { [weak self] in self?.reload() })]
        } else if self.items.isEmpty {
            rows = [MomentsStatusItem(text: momentsText(strings, .notifications), theme: theme, action: {})]
        } else {
            for item in self.items {
                let names = item.actors.map(\.displayName).joined(separator: ", ")
                let extra = item.extraActorCount > 0 ? " +\(item.extraActorCount)" : ""
                let line = item.unavailable ? momentsText(strings, .unavailable) : "\(names)\(extra) \(item.kind.rawValue) \(item.text ?? "")"
                rows.append(MomentsStatusItem(text: line, theme: theme, action: { [weak self] in
                    guard let self else { return }
                    if item.unavailable {
                        self.present(textAlertController(context: self.context, title: nil, text: momentsText(strings, .unavailable), actions: [TextAlertAction(type: .defaultAction, title: momentsText(strings, .cancel), action: {})]), in: .window(.root))
                    } else if item.kind == .follow || item.kind == .mutual, let id = item.actors.first?.telegramUserId, id != 0 {
                        self.openPeer?(EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(id)))
                    }
                }))
            }
        }
        let previous = self.rendered
        self.rendered = rows.count
        self.list.transaction(deleteIndices: (0..<previous).map { ListViewDeleteItem(index: $0, directionHint: nil) }, insertIndicesAndItems: rows.enumerated().map { ListViewInsertItem(index: $0.offset, previousIndex: nil, item: $0.element, directionHint: nil) }, updateIndicesAndItems: [], options: [.Synchronous], updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: self.list.bounds.size, insets: .zero, duration: 0, curve: .Default(duration: nil)), updateOpaqueState: nil, completion: { _ in })
    }
}
