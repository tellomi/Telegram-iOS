import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import PeerReportScreen

private struct MomentsCommentTarget {
    var id: String
    var text: String
    var author: MomentsAuthor?
    var name: String
    var viewerAuthored: Bool
}

/// Douyin-style comment sheet over the feed list. Hot and latest keep separate cursors.
public final class MomentsCommentSheet: ViewController, UIScrollViewDelegate {
    private let context: AccountContext
    private let card: MomentsCard
    public var openPeer: ((EnginePeer.Id) -> Void)?
    public var onDismiss: (() -> Void)?
    private var presentationData: PresentationData
    private var commentsBySort: [String: [MomentsComment]] = [:]
    private var cursors = MomentsCommentCursors()
    private var loadedSorts: Set<String> = []
    private var sort = "hot"
    private var total = 0
    private var loadedReplies: [String: [MomentsReply]] = [:]
    private var replyCursor: [String: String] = [:]
    private var imageSlots: [MomentsRemoteImageSlot] = []
    private var expanded: Set<String> = []
    private var expandedSheet = false
    private var targets: [String: MomentsCommentTarget] = [:]
    private var tombstones: Set<String> = []
    private var composer = MomentsCommentComposerState()
    private var replyParent: String?
    private var replyName: String?
    private var pendingMediaKey: String?
    private var pendingSticker = false
    private var sending = false
    private var loadingComments = false
    private var commentEpoch = 0
    private let dim = UIButton(type: .custom)
    private let panel = UIView()
    private let titleLabel = UILabel()
    private let hotButton = UIButton(type: .system)
    private let latestButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let expandButton = UIButton(type: .system)
    private let list = UIScrollView()
    private let replyChip = UIButton(type: .system)
    private let errorLabel = UILabel()
    private let input = UITextField()
    private let disposable = MetaDisposable()

    public init(context: AccountContext, card: MomentsCard) {
        self.context = context
        self.card = card
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: nil)
        self.statusBar.statusBarStyle = .Ignore
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.disposable.dispose()
        self.onDismiss?()
    }

    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        let view = self.displayNode.view
        view.backgroundColor = .clear
        self.dim.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        self.dim.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        view.addSubview(self.dim)
        let theme = self.presentationData.theme
        self.panel.backgroundColor = theme.list.plainBackgroundColor
        self.panel.layer.cornerRadius = 16
        self.panel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        self.panel.clipsToBounds = true
        view.addSubview(self.panel)
        self.titleLabel.font = Font.semibold(15)
        self.titleLabel.textAlignment = .center
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.panel.addSubview(self.titleLabel)
        self.hotButton.addTarget(self, action: #selector(self.hotPressed), for: .touchUpInside)
        self.latestButton.addTarget(self, action: #selector(self.latestPressed), for: .touchUpInside)
        self.panel.addSubview(self.hotButton)
        self.panel.addSubview(self.latestButton)
        self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.panel.addSubview(self.closeButton)
        self.expandButton.addTarget(self, action: #selector(self.expandPressed), for: .touchUpInside)
        self.panel.addSubview(self.expandButton)
        self.list.alwaysBounceVertical = true
        self.list.delegate = self
        self.panel.addSubview(self.list)
        self.replyChip.contentHorizontalAlignment = .left
        self.replyChip.addTarget(self, action: #selector(self.clearReplyPressed), for: .touchUpInside)
        self.panel.addSubview(self.replyChip)
        self.errorLabel.font = Font.regular(13)
        self.errorLabel.textColor = UIColor(rgb: 0xFF2E38)
        self.errorLabel.numberOfLines = 2
        self.errorLabel.isHidden = true
        self.panel.addSubview(self.errorLabel)
        self.input.borderStyle = .none
        self.input.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.input.layer.cornerRadius = 18
        self.input.placeholder = self.presentationData.strings.Moments_CommentHint
        self.input.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        self.input.leftViewMode = .always
        self.input.returnKeyType = .send
        self.input.delegate = self
        self.panel.addSubview(self.input)
        self.applyChrome()
        self.displayNodeDidLoad()
        self.fetchComments(appending: false)
    }

    private var commentsOpen: Bool {
        return self.card.viewer.canComment && self.card.commentPolicy != .closed
    }

    private var displayedComments: [MomentsComment] {
        return self.commentsBySort[self.sort] ?? []
    }

    private func applyChrome() {
        let theme = self.presentationData.theme
        let strings = self.presentationData.strings
        self.closeButton.setTitle(nil, for: .normal)
        self.closeButton.setImage(momentsTintedIcon("Navigation/Close", theme.list.itemPrimaryTextColor), for: .normal)
        self.closeButton.accessibilityLabel = strings.Common_Cancel
        let expandName = self.expandedSheet ? "Media Editor/ZoomOut" : "Chat/Context Menu/Expand"
        self.expandButton.setTitle(nil, for: .normal)
        self.expandButton.setImage(momentsTintedIcon(expandName, theme.list.itemSecondaryTextColor), for: .normal)
        self.expandButton.accessibilityLabel = strings.Moments_FullText
        self.hotButton.setTitle(strings.Moments_Sort_Hot, for: .normal)
        self.latestButton.setTitle(strings.Moments_Sort_Latest, for: .normal)
        let selectedColor = theme.list.itemAccentColor
        let idleColor = theme.list.itemSecondaryTextColor
        self.hotButton.setTitleColor(self.sort == "hot" ? selectedColor : idleColor, for: .normal)
        self.latestButton.setTitleColor(self.sort == "latest" ? selectedColor : idleColor, for: .normal)
        if self.commentsOpen {
            if let name = self.replyName, !name.isEmpty {
                self.input.placeholder = strings.Moments_ReplyTo(name).string
            } else {
                self.input.placeholder = strings.Moments_CommentHint
            }
            self.input.isEnabled = !self.sending
        } else {
            self.input.placeholder = strings.Moments_Comment_Closed
            self.input.isEnabled = false
        }
        self.replyChip.isHidden = self.replyParent == nil
        if let name = self.replyName, !name.isEmpty {
            let title = strings.Moments_ReplyTo(name).string + " · " + strings.Common_Cancel
            self.replyChip.setTitle(title, for: .normal)
        } else if self.replyParent != nil {
            self.replyChip.setTitle(strings.Common_Cancel, for: .normal)
        }
        self.replyChip.setTitleColor(theme.list.itemSecondaryTextColor, for: .normal)
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.dim.frame = CGRect(origin: .zero, size: layout.size)
        self.applyChrome()
        let top = self.expandedSheet ? layout.statusBarHeight ?? 20 : layout.size.height * 0.28
        self.panel.frame = CGRect(x: 0, y: top, width: layout.size.width, height: layout.size.height - top)
        self.titleLabel.frame = CGRect(x: 56, y: 8, width: layout.size.width - 112, height: 28)
        self.expandButton.frame = CGRect(x: 8, y: 8, width: 40, height: 28)
        self.closeButton.frame = CGRect(x: layout.size.width - 48, y: 8, width: 40, height: 28)
        self.hotButton.frame = CGRect(x: 16, y: 40, width: 88, height: 28)
        self.latestButton.frame = CGRect(x: 108, y: 40, width: 88, height: 28)
        let bottom = layout.insets(options: [.input]).bottom
        var cursor = self.panel.bounds.height - bottom - 8
        self.input.frame = CGRect(x: 12, y: cursor - 36, width: layout.size.width - 24, height: 36)
        cursor = self.input.frame.minY - 4
        if !self.errorLabel.isHidden {
            self.errorLabel.frame = CGRect(x: 16, y: cursor - 32, width: layout.size.width - 32, height: 32)
            cursor = self.errorLabel.frame.minY
        }
        if !self.replyChip.isHidden {
            self.replyChip.frame = CGRect(x: 16, y: cursor - 28, width: layout.size.width - 32, height: 28)
            cursor = self.replyChip.frame.minY
        }
        self.list.frame = CGRect(x: 0, y: 72, width: layout.size.width, height: max(0, cursor - 76))
        self.relayoutComments()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === self.list else { return }
        let distance = scrollView.contentSize.height - scrollView.bounds.height - scrollView.contentOffset.y
        if distance < 160 {
            self.fetchComments(appending: true)
        }
    }

    private func fetchComments(appending: Bool) {
        let sort = self.sort
        let cursor = appending ? self.cursors.cursor(sort: sort) : nil
        if appending {
            guard cursor != nil, !self.loadingComments else { return }
        }
        self.loadingComments = true
        self.commentEpoch += 1
        let epoch = self.commentEpoch
        self.disposable.set((self.context.engine.moments.comments(postId: self.card.id, sort: sort, cursor: cursor, thread: true) |> deliverOnMainQueue).start(next: { [weak self] page in
            guard let self, self.commentEpoch == epoch, self.sort == sort else { return }
            self.loadingComments = false
            self.applyCommentPage(page, sort: sort, appending: appending)
        }, error: { [weak self] _ in
            guard let self, self.commentEpoch == epoch else { return }
            self.loadingComments = false
            if self.displayedComments.isEmpty {
                self.errorLabel.text = self.presentationData.strings.Moments_LoadFailed
                self.errorLabel.isHidden = false
                self.relayoutFrame()
            }
        }))
    }

    private func applyCommentPage(_ page: MomentsCommentPage, sort: String, appending: Bool) {
        let incoming = page.comments.filter { !$0.disliked }
        var list = appending ? (self.commentsBySort[sort] ?? []) : []
        let existing = Set(list.map { $0.id })
        list.append(contentsOf: incoming.filter { !existing.contains($0.id) })
        self.commentsBySort[sort] = list
        self.cursors = self.cursors.storing(sort: sort, cursor: page.cursor)
        self.loadedSorts.insert(sort)
        self.total = page.total
        self.relayoutComments()
    }

    @objc private func hotPressed() {
        self.selectSort("hot")
    }

    @objc private func latestPressed() {
        self.selectSort("latest")
    }

    private func selectSort(_ sort: String) {
        guard sort != self.sort else { return }
        self.sort = sort
        self.loadingComments = false
        self.commentEpoch += 1
        self.disposable.set(nil)
        self.list.contentOffset = .zero
        self.applyChrome()
        self.relayoutComments()
        if !self.loadedSorts.contains(sort) {
            self.fetchComments(appending: false)
        }
    }

    private func relayoutFrame() {
        if let layout = self.currentlyAppliedLayout {
            self.containerLayoutUpdated(layout, transition: .immediate)
        }
    }

    private func relayoutComments() {
        let strings = self.presentationData.strings
        let theme = self.presentationData.theme
        let total = self.total > 0 ? self.total : self.card.counts.comments
        self.titleLabel.text = "\(total) \(strings.Moments_CommentCount)"
        for slot in self.imageSlots {
            slot.cancel()
        }
        self.imageSlots.removeAll()
        self.targets.removeAll()
        self.list.subviews.forEach { $0.removeFromSuperview() }
        var y: CGFloat = 8
        let width = self.list.bounds.width
        guard width > 0 else { return }
        for comment in self.displayedComments {
            y = self.addRow(id: comment.id, author: comment.author, text: comment.text, created: comment.createdAt, likes: comment.likeCount, liked: comment.liked, isAuthor: comment.isAuthor, region: comment.ipRegionLabel, attachment: comment.attachment, replyToName: nil, viewerAuthored: comment.viewerAuthored, x: 12, y: y, width: width - 24, theme: theme, strings: strings)
            let shown = self.expanded.contains(comment.id)
            if comment.replyCount > 0 && !shown {
                y = self.addMoreButton(title: "—— " + strings.Moments_ShowReplies(comment.replyCount).string, identifier: "expand:" + comment.id, x: 48, y: y, width: width - 72, theme: theme, action: #selector(self.expandReplies(_:)))
            } else if shown {
                for reply in self.loadedReplies[comment.id] ?? comment.replies where !reply.disliked {
                    y = self.addRow(id: reply.id, author: reply.author, text: reply.text, created: reply.createdAt, likes: reply.likeCount, liked: reply.liked, isAuthor: reply.isAuthor, region: reply.ipRegionLabel, attachment: reply.attachment, replyToName: reply.replyToName, viewerAuthored: reply.viewerAuthored, x: 48, y: y, width: width - 60, theme: theme, strings: strings)
                }
                if self.replyCursor[comment.id]?.isEmpty == false {
                    y = self.addMoreButton(title: "—— " + strings.Moments_ShowReplies(max(comment.replyCount - (self.loadedReplies[comment.id]?.count ?? 0), 1)).string, identifier: "more:" + comment.id, x: 48, y: y, width: width - 72, theme: theme, action: #selector(self.expandReplies(_:)))
                }
            }
        }
        if self.cursors.cursor(sort: self.sort) != nil {
            y = self.addMoreButton(title: strings.Moments_More, identifier: "comments", x: 12, y: y, width: width - 24, theme: theme, action: #selector(self.moreCommentsPressed))
        }
        self.list.contentSize = CGSize(width: width, height: y + 12)
    }

    private func addMoreButton(title: String, identifier: String, x: CGFloat, y: CGFloat, width: CGFloat, theme: PresentationTheme, action: Selector) -> CGFloat {
        let button = UIButton(type: .system)
        button.frame = CGRect(x: x, y: y, width: width, height: 28)
        button.contentHorizontalAlignment = .left
        button.setTitle(title, for: .normal)
        button.setTitleColor(theme.list.itemSecondaryTextColor, for: .normal)
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
        self.list.addSubview(button)
        return y + 32
    }

    private func addRow(id: String, author: MomentsAuthor?, text: String, created: Int64, likes: Int, liked: Bool, isAuthor: Bool, region: String?, attachment: MomentsMedia?, replyToName: String?, viewerAuthored: Bool, x: CGFloat, y: CGFloat, width: CGFloat, theme: PresentationTheme, strings: PresentationStrings) -> CGFloat {
        let name = author?.displayName ?? ""
        self.targets[id] = MomentsCommentTarget(id: id, text: text, author: author, name: name, viewerAuthored: viewerAuthored)
        let row = UIView(frame: CGRect(x: x, y: y, width: width, height: 44))
        row.accessibilityIdentifier = id
        let press = UILongPressGestureRecognizer(target: self, action: #selector(self.rowLongPressed(_:)))
        row.addGestureRecognizer(press)
        let avatar = UIButton(type: .custom)
        avatar.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
        avatar.backgroundColor = theme.list.itemHighlightedBackgroundColor
        avatar.layer.cornerRadius = 16
        avatar.clipsToBounds = true
        avatar.titleLabel?.font = Font.semibold(13)
        avatar.setTitle(name.isEmpty ? "" : String(name.prefix(1)), for: .normal)
        avatar.setTitleColor(theme.list.itemPrimaryTextColor, for: .normal)
        avatar.accessibilityIdentifier = id
        avatar.accessibilityLabel = name
        avatar.addTarget(self, action: #selector(self.authorPressed(_:)), for: .touchUpInside)
        row.addSubview(avatar)
        let nameButton = UIButton(type: .custom)
        nameButton.frame = CGRect(x: 40, y: 0, width: width - 120, height: 18)
        nameButton.contentHorizontalAlignment = .left
        nameButton.titleLabel?.font = Font.regular(13)
        nameButton.accessibilityIdentifier = id
        nameButton.accessibilityLabel = name
        nameButton.addTarget(self, action: #selector(self.authorPressed(_:)), for: .touchUpInside)
        if isAuthor {
            let tag = strings.Moments_Author
            let prefix = (name + "  ") as NSString
            let marked = NSMutableAttributedString(string: prefix as String + tag, attributes: [.font: Font.regular(13), .foregroundColor: theme.list.itemSecondaryTextColor])
            marked.addAttributes([.foregroundColor: UIColor(rgb: 0xFF2E38)], range: NSRange(location: prefix.length, length: (tag as NSString).length))
            nameButton.setAttributedTitle(marked, for: .normal)
        } else {
            nameButton.setTitle(name, for: .normal)
            nameButton.setTitleColor(theme.list.itemSecondaryTextColor, for: .normal)
        }
        row.addSubview(nameButton)
        let removed = self.tombstones.contains(id)
        let body = UILabel(frame: CGRect(x: 40, y: 18, width: width - 80, height: 0))
        body.font = Font.regular(15)
        body.textColor = theme.list.itemPrimaryTextColor
        body.numberOfLines = 0
        if removed {
            body.text = strings.Moments_Unavailable
        } else {
            var bodyText = text
            if let replyToName, !replyToName.isEmpty {
                bodyText = strings.Moments_ReplyTo(replyToName).string + " " + text
            }
            body.text = bodyText
        }
        let bodyHeight = body.sizeThatFits(CGSize(width: width - 80, height: 400)).height
        body.frame.size.height = bodyHeight
        row.addSubview(body)
        var cursor = body.frame.maxY
        if !removed, let attachment, let remoteURL = momentsFeedImageURL(attachment, targetPixels: momentsCarouselImagePixels), remoteURL.hasPrefix("https://") {
            let image = UIImageView(frame: CGRect(x: 40, y: cursor + 8, width: 120, height: 120))
            image.layer.cornerRadius = 8
            image.clipsToBounds = true
            image.contentMode = .scaleAspectFill
            let slot = MomentsRemoteImageSlot()
            slot.bind(url: remoteURL, imageView: image, context: self.context, maxSide: 120)
            self.imageSlots.append(slot)
            row.addSubview(image)
            cursor += 136
        }
        let meta = UILabel(frame: CGRect(x: 40, y: cursor + 4, width: width - 160, height: 16))
        meta.font = Font.regular(12)
        meta.textColor = theme.list.itemSecondaryTextColor
        var parts = [momentsRelativeTime(strings, created)]
        if let region, !region.isEmpty {
            parts.append(region)
        }
        meta.text = parts.joined(separator: " · ")
        row.addSubview(meta)
        if !removed && self.commentsOpen {
            let reply = UIButton(type: .system)
            reply.frame = CGRect(x: 40 + meta.sizeThatFits(CGSize(width: width, height: 16)).width + 8, y: meta.frame.minY, width: 72, height: 16)
            reply.contentHorizontalAlignment = .left
            reply.setTitle(strings.Moments_Reply, for: .normal)
            reply.titleLabel?.font = Font.regular(12)
            reply.setTitleColor(theme.list.itemSecondaryTextColor, for: .normal)
            reply.accessibilityIdentifier = id
            reply.addTarget(self, action: #selector(self.replyPressed(_:)), for: .touchUpInside)
            row.addSubview(reply)
        }
        if !removed {
            let likeColor = liked ? UIColor(rgb: 0xFF2E38) : theme.list.itemSecondaryTextColor
            let like = UIButton(type: .system)
            like.frame = CGRect(x: width - 72, y: 0, width: 36, height: 32)
            like.setImage(momentsTintedIcon(liked ? "Stories/InputLikeOn" : "Stories/InputLikeOff", likeColor), for: .normal)
            like.setTitle(likes > 0 ? " \(likes)" : nil, for: .normal)
            like.setTitleColor(likeColor, for: .normal)
            like.accessibilityIdentifier = id
            like.accessibilityLabel = strings.Moments_Like
            like.addTarget(self, action: #selector(self.likePressed(_:)), for: .touchUpInside)
            row.addSubview(like)
            let dislike = UIButton(type: .system)
            dislike.frame = CGRect(x: width - 32, y: 0, width: 32, height: 32)
            dislike.setImage(momentsTintedIcon("Navigation/Close", theme.list.itemSecondaryTextColor), for: .normal)
            dislike.accessibilityIdentifier = id
            dislike.accessibilityLabel = strings.Moments_HidePost
            dislike.addTarget(self, action: #selector(self.dislikePressed(_:)), for: .touchUpInside)
            row.addSubview(dislike)
        }
        let height = meta.frame.maxY + 12
        row.frame.size.height = height
        self.list.addSubview(row)
        return y + height
    }

    @objc private func moreCommentsPressed() {
        self.fetchComments(appending: true)
    }

    @objc private func expandReplies(_ button: UIButton) {
        guard let identifier = button.accessibilityIdentifier else { return }
        let commentId = identifier.replacingOccurrences(of: "expand:", with: "").replacingOccurrences(of: "more:", with: "")
        guard let comment = self.displayedComments.first(where: { $0.id == commentId }) else { return }
        let cursor = identifier.hasPrefix("more:") ? self.replyCursor[comment.id] : nil
        self.expanded.insert(comment.id)
        let _ = (self.context.engine.moments.replies(rootId: comment.id, cursor: cursor) |> deliverOnMainQueue).start(next: { [weak self] page in
            guard let self else { return }
            let incoming = page.replies.filter { !$0.disliked }
            if cursor == nil {
                self.loadedReplies[comment.id] = incoming
            } else {
                var current = self.loadedReplies[comment.id] ?? []
                let existing = Set(current.map { $0.id })
                current.append(contentsOf: incoming.filter { !existing.contains($0.id) })
                self.loadedReplies[comment.id] = current
            }
            if let next = page.cursor, !next.isEmpty, next != cursor {
                self.replyCursor[comment.id] = next
            } else {
                self.replyCursor.removeValue(forKey: comment.id)
            }
            self.relayoutComments()
        })
        self.relayoutComments()
    }

    @objc private func likePressed(_ button: UIButton) {
        guard let id = button.accessibilityIdentifier, !self.tombstones.contains(id) else { return }
        let liked = self.reaction(id: id)?.liked == true
        let _ = self.context.engine.moments.setCommentLiked(id: id, liked: !liked).start()
        self.toggleLike(id: id)
    }

    @objc private func dislikePressed(_ button: UIButton) {
        guard let id = button.accessibilityIdentifier else { return }
        let _ = self.context.engine.moments.setCommentDisliked(id: id, disliked: true).start()
        self.commentsBySort = self.commentsBySort.mapValues { list in
            list.filter { $0.id != id }
        }
        for key in self.loadedReplies.keys {
            self.loadedReplies[key]?.removeAll { $0.id == id }
        }
        self.relayoutComments()
    }

    @objc private func authorPressed(_ button: UIButton) {
        guard let id = button.accessibilityIdentifier, let author = self.targets[id]?.author else { return }
        self.openAuthor(author)
    }

    @objc private func replyPressed(_ button: UIButton) {
        guard let id = button.accessibilityIdentifier, let target = self.targets[id] else { return }
        self.beginReply(target)
    }

    @objc private func rowLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let id = gesture.view?.accessibilityIdentifier, let target = self.targets[id], !self.tombstones.contains(id) else { return }
        self.presentMenu(target)
    }

    private func openAuthor(_ author: MomentsAuthor) {
        guard author.telegramUserId != 0 else { return }
        let peerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(author.telegramUserId))
        self.openPeer?(peerId)
    }

    private func beginReply(_ target: MomentsCommentTarget) {
        guard self.commentsOpen else {
            self.showCommentError(.invalid("comments_closed"))
            return
        }
        self.replyParent = target.id
        self.replyName = target.name
        self.applyChrome()
        self.relayoutFrame()
        self.input.becomeFirstResponder()
    }

    private func viewerId() -> Int64 {
        return self.context.account.peerId.toInt64()
    }

    private func canDelete(_ target: MomentsCommentTarget) -> Bool {
        if target.viewerAuthored {
            return true
        }
        let me = self.viewerId()
        guard me != 0 else { return false }
        if target.author?.telegramUserId == me { return true }
        return self.card.author?.telegramUserId == me
    }

    private func canReport(_ author: MomentsAuthor?) -> Bool {
        let me = self.viewerId()
        if let id = author?.telegramUserId, id != 0, id == me {
            return false
        }
        return true
    }

    private func presentMenu(_ target: MomentsCommentTarget) {
        let strings = self.presentationData.strings
        let sheet = ActionSheetController(theme: ActionSheetControllerTheme(presentationData: self.presentationData))
        let dismiss: () -> Void = { [weak sheet] in
            sheet?.dismissAnimated()
        }
        var items: [ActionSheetItem] = []
        if self.commentsOpen {
            items.append(ActionSheetButtonItem(title: strings.Moments_Reply, color: .accent, action: { [weak self] in
                dismiss()
                self?.beginReply(target)
            }))
        }
        if !target.text.isEmpty {
            items.append(ActionSheetButtonItem(title: strings.Moments_CopyText, color: .accent, action: {
                dismiss()
                UIPasteboard.general.string = target.text
            }))
        }
        if self.canReport(target.author) {
            items.append(ActionSheetButtonItem(title: strings.Moments_Report, color: .destructive, action: { [weak self] in
                dismiss()
                self?.report(target)
            }))
        }
        if self.canDelete(target) {
            items.append(ActionSheetButtonItem(title: strings.Common_Delete, color: .destructive, action: { [weak self] in
                dismiss()
                self?.deleteComment(target)
            }))
        }
        guard !items.isEmpty else { return }
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: strings.Common_Cancel, color: .accent, action: dismiss)])
        ])
        self.present(sheet, in: .window(.root))
    }

    private func report(_ target: MomentsCommentTarget) {
        guard let authorId = target.author?.telegramUserId, authorId != 0 else {
            let _ = self.context.engine.moments.report(targetType: "content", targetId: target.id, reason: "other", detail: nil).start(error: { [weak self] error in
                self?.showCommentError(error)
            })
            return
        }
        let peerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(authorId))
        presentPeerReportOptions(context: self.context, parent: self, contextController: nil, subject: .peer(peerId), passthrough: true, completion: { [weak self] reason, _ in
            guard let self, let reason else { return }
            let _ = self.context.engine.moments.report(targetType: "content", targetId: target.id, reason: momentsReportReasonCode(reason), detail: nil).start(error: { [weak self] error in
                self?.showCommentError(error)
            })
        })
    }

    private func deleteComment(_ target: MomentsCommentTarget) {
        let _ = self.context.engine.moments.deleteComment(id: target.id).start(error: { [weak self] error in
            self?.showCommentError(error)
        }, completed: { [weak self] in
            guard let self else { return }
            self.tombstones.insert(target.id)
            self.relayoutComments()
        })
    }

    private func reaction(id: String) -> (liked: Bool, count: Int)? {
        if let comment = self.displayedComments.first(where: { $0.id == id }) {
            return (comment.liked, comment.likeCount)
        }
        for replies in self.loadedReplies.values {
            if let reply = replies.first(where: { $0.id == id }) {
                return (reply.liked, reply.likeCount)
            }
        }
        for comments in self.commentsBySort.values {
            if let comment = comments.first(where: { $0.id == id }) {
                return (comment.liked, comment.likeCount)
            }
        }
        return nil
    }

    private func toggleLike(id: String) {
        self.commentsBySort = self.commentsBySort.mapValues { list in
            list.map { item in
                guard item.id == id else { return item }
                var copy = item
                copy.liked.toggle()
                copy.likeCount += copy.liked ? 1 : -1
                if copy.likeCount < 0 { copy.likeCount = 0 }
                return copy
            }
        }
        for key in self.loadedReplies.keys {
            self.loadedReplies[key] = self.loadedReplies[key]?.map { item in
                guard item.id == id else { return item }
                var copy = item
                copy.liked.toggle()
                copy.likeCount += copy.liked ? 1 : -1
                if copy.likeCount < 0 { copy.likeCount = 0 }
                return copy
            }
        }
        self.relayoutComments()
    }

    @objc private func closePressed() {
        let action = self.onDismiss
        self.onDismiss = nil
        action?()
        self.dismiss()
    }

    @objc private func expandPressed() {
        self.expandedSheet.toggle()
        self.relayoutFrame()
    }

    @objc private func clearReplyPressed() {
        self.replyParent = nil
        self.replyName = nil
        self.applyChrome()
        self.relayoutFrame()
    }

    private func showCommentError(_ error: MomentsAPIError) {
        let text: String
        switch error {
        case .cancelled:
            return
        case let .invalid(code) where code == "comments_closed" || code == "reply_not_allowed" || code == "not_commentable" || code == "harassment_guard":
            text = self.presentationData.strings.Moments_Comment_Closed
        default:
            text = self.presentationData.strings.Moments_Comment_SendFailed
        }
        self.errorLabel.text = text
        self.errorLabel.isHidden = false
        self.relayoutFrame()
    }

    private func pendingAttachment() -> [String: Any]? {
        guard let key = self.pendingMediaKey, !key.isEmpty else { return nil }
        var body: [String: Any] = ["key": key]
        if self.pendingSticker {
            body["type"] = "sticker"
            body["sticker"] = true
        }
        return body
    }

    private func sendComment() {
        guard self.commentsOpen, !self.sending else {
            if !self.commentsOpen {
                self.showCommentError(.invalid("comments_closed"))
            }
            return
        }
        let text = self.input.text ?? ""
        guard text.count <= MomentsLimits.standard.commentTextLimit else {
            self.showCommentError(.invalid("comment"))
            return
        }
        let next = momentsCommentComposerForSend(previous: self.composer, text: text, parentId: self.replyParent, mediaKey: self.pendingMediaKey, sticker: self.pendingSticker)
        guard case .success = momentsEncodeComment(next) else {
            self.showCommentError(.invalid("comment"))
            return
        }
        self.composer = next
        self.sending = true
        self.applyChrome()
        let sentText = text
        let sentParent = self.replyParent
        let sentMedia = self.pendingMediaKey
        let _ = self.context.engine.moments.addComment(postId: self.card.id, text: text, parentId: self.replyParent, attachment: self.pendingAttachment(), clientNonce: next.clientNonce).start(error: { [weak self] error in
            guard let self else { return }
            self.sending = false
            self.composer = momentsCommentComposerAfterFailure(next)
            self.applyChrome()
            self.showCommentError(error)
        }, completed: { [weak self] in
            guard let self else { return }
            self.sending = false
            if self.input.text == sentText {
                self.input.text = ""
            }
            if self.replyParent == sentParent {
                self.replyParent = nil
                self.replyName = nil
            }
            if self.pendingMediaKey == sentMedia {
                self.pendingMediaKey = nil
                self.pendingSticker = false
            }
            self.composer = momentsCommentComposerAfterSuccess()
            self.errorLabel.isHidden = true
            self.commentsBySort = [:]
            self.cursors = MomentsCommentCursors()
            self.loadedSorts = []
            self.applyChrome()
            self.fetchComments(appending: false)
        })
    }
}

extension MomentsCommentSheet: UITextFieldDelegate {
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.sendComment()
        return false
    }

    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let current = textField.text ?? ""
        guard let textRange = Range(range, in: current) else { return true }
        let updated = current.replacingCharacters(in: textRange, with: string)
        return updated.count <= MomentsLimits.standard.commentTextLimit
    }
}
