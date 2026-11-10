import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext

/// Douyin-style comment sheet. Fields the engine does not send (province, dislike) are omitted.
public final class MomentsCommentSheet: ViewController {
    private let context: AccountContext
    private let card: MomentsCard
    public var openPeer: ((EnginePeer.Id) -> Void)?
    private var presentationData: PresentationData
    private var comments: [MomentsComment] = []
    private var total = 0
    private var loadedReplies: [String: [MomentsReply]] = [:]
    private var expanded: Set<String> = []
    private var expandedSheet = false
    private let dim = UIButton(type: .custom)
    private let panel = UIView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let expandButton = UIButton(type: .system)
    private let list = UIScrollView()
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
    }

    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        let view = self.displayNode.view
        view.backgroundColor = .clear
        self.dim.backgroundColor = UIColor.black.withAlphaComponent(0.45)
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
        self.closeButton.setTitle("✕", for: .normal)
        self.closeButton.setTitleColor(theme.list.itemPrimaryTextColor, for: .normal)
        self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.panel.addSubview(self.closeButton)
        self.expandButton.setTitle("⤢", for: .normal)
        self.expandButton.setTitleColor(theme.list.itemSecondaryTextColor, for: .normal)
        self.expandButton.addTarget(self, action: #selector(self.expandPressed), for: .touchUpInside)
        self.panel.addSubview(self.expandButton)
        self.panel.addSubview(self.list)
        self.input.borderStyle = .none
        self.input.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.input.layer.cornerRadius = 18
        self.input.placeholder = momentsText(self.presentationData.strings, .commentPrompt)
        self.input.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        self.input.leftViewMode = .always
        self.input.returnKeyType = .send
        self.input.delegate = self
        self.panel.addSubview(self.input)
        self.displayNodeDidLoad()
        self.reload()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.dim.frame = CGRect(origin: .zero, size: layout.size)
        let top = self.expandedSheet ? layout.statusBarHeight ?? 20 : layout.size.height * 0.32
        self.panel.frame = CGRect(x: 0, y: top, width: layout.size.width, height: layout.size.height - top)
        self.titleLabel.frame = CGRect(x: 56, y: 8, width: layout.size.width - 112, height: 36)
        self.expandButton.frame = CGRect(x: 8, y: 8, width: 40, height: 36)
        self.closeButton.frame = CGRect(x: layout.size.width - 48, y: 8, width: 40, height: 36)
        let inputBottom = layout.intrinsicInsets.bottom + 8
        self.input.frame = CGRect(x: 12, y: self.panel.bounds.height - inputBottom - 36, width: layout.size.width - 24, height: 36)
        self.list.frame = CGRect(x: 0, y: 48, width: layout.size.width, height: self.input.frame.minY - 56)
        self.relayoutComments()
    }

    private func reload() {
        self.disposable.set((self.context.engine.moments.comments(postId: self.card.id, sort: "hot", cursor: nil, thread: true) |> deliverOnMainQueue).start(next: { [weak self] page in
            guard let self else { return }
            self.comments = page.comments.filter { !$0.disliked }
            self.total = page.total
            self.relayoutComments()
        }))
    }

    private func relayoutComments() {
        let strings = self.presentationData.strings
        let theme = self.presentationData.theme
        let total = self.total > 0 ? self.total : self.card.counts.comments
        let countWord = momentsText(strings, .commentCount)
        self.titleLabel.text = countWord == "条评论" ? "\(total)\(countWord)" : "\(total) \(countWord)"
        self.list.subviews.forEach { $0.removeFromSuperview() }
        var y: CGFloat = 8
        let width = self.list.bounds.width
        guard width > 0 else { return }
        for comment in self.comments {
            y = self.addRow(comment: comment, reply: nil, x: 12, y: y, width: width - 24, theme: theme, strings: strings)
            let shown = self.expanded.contains(comment.id)
            if comment.replyCount > 0 && !shown {
                let button = UIButton(type: .system)
                button.frame = CGRect(x: 56, y: y, width: width - 80, height: 28)
                button.contentHorizontalAlignment = .left
                let replyWord = momentsText(strings, .expandReplies)
                let replyTitle = replyWord == "条回复" ? "—— 展开\(comment.replyCount)\(replyWord)" : "—— \(comment.replyCount) \(replyWord)"
                button.setTitle(replyTitle, for: .normal)
                button.setTitleColor(theme.list.itemSecondaryTextColor, for: .normal)
                button.tag = self.comments.firstIndex(where: { $0.id == comment.id }) ?? 0
                button.addTarget(self, action: #selector(self.expandReplies(_:)), for: .touchUpInside)
                self.list.addSubview(button)
                y += 32
            } else if shown {
                for reply in self.loadedReplies[comment.id] ?? comment.replies where !reply.disliked {
                    y = self.addRow(comment: comment, reply: reply, x: 44, y: y, width: width - 56, theme: theme, strings: strings)
                }
            }
        }
        self.list.contentSize = CGSize(width: width, height: y + 12)
    }

    private func addRow(comment: MomentsComment, reply: MomentsReply?, x: CGFloat, y: CGFloat, width: CGFloat, theme: PresentationTheme, strings: PresentationStrings) -> CGFloat {
        let author = reply?.author ?? comment.author
        let text = reply?.text ?? comment.text
        let created = reply?.createdAt ?? comment.createdAt
        let likes = reply?.likeCount ?? comment.likeCount
        let isAuthor = reply?.isAuthor ?? comment.isAuthor
        let region = reply?.ipRegionLabel ?? comment.ipRegionLabel
        let attachment = reply?.attachment ?? comment.attachment
        let rowId = reply?.id ?? comment.id
        let liked = reply?.liked ?? comment.liked
        let avatar = UILabel(frame: CGRect(x: x, y: y, width: 32, height: 32))
        avatar.backgroundColor = theme.list.itemHighlightedBackgroundColor
        avatar.layer.cornerRadius = 16
        avatar.clipsToBounds = true
        avatar.textAlignment = .center
        avatar.font = Font.semibold(13)
        avatar.textColor = theme.list.itemPrimaryTextColor
        let name = author?.displayName ?? ""
        avatar.text = name.isEmpty ? "" : String(name.prefix(1))
        self.list.addSubview(avatar)
        let nameLabel = UILabel(frame: CGRect(x: x + 40, y: y, width: width - 80, height: 16))
        nameLabel.font = Font.regular(12)
        nameLabel.textColor = theme.list.itemSecondaryTextColor
        if isAuthor {
            let tag = momentsText(strings, .authorTag)
            let prefix = (name + "  ") as NSString
            let marked = NSMutableAttributedString(string: prefix as String + tag, attributes: [.font: Font.regular(12), .foregroundColor: theme.list.itemSecondaryTextColor])
            marked.addAttributes([.foregroundColor: UIColor(rgb: 0xFF3B30)], range: NSRange(location: prefix.length, length: (tag as NSString).length))
            nameLabel.attributedText = marked
        } else {
            nameLabel.text = name
        }
        self.list.addSubview(nameLabel)
        let body = UILabel(frame: CGRect(x: x + 40, y: y + 16, width: width - 80, height: 0))
        body.font = Font.regular(15)
        body.textColor = theme.list.itemPrimaryTextColor
        body.numberOfLines = 0
        var bodyText = text
        if let reply, let target = reply.replyToName, !target.isEmpty {
            bodyText = momentsText(strings, .reply) + " @" + target + " " + text
        }
        body.text = bodyText
        let bodyHeight = body.sizeThatFits(CGSize(width: width - 80, height: 200)).height
        body.frame.size.height = bodyHeight
        self.list.addSubview(body)
        var cursor = body.frame.maxY
        if let attachment, let remoteURL = attachment.remoteURL, remoteURL.hasPrefix("https://"), momentsPresentsAsImage(attachment.type) {
            let image = UIImageView(frame: CGRect(x: x + 40, y: cursor + 6, width: 72, height: 72))
            image.layer.cornerRadius = 8
            image.clipsToBounds = true
            image.contentMode = .scaleAspectFill
            momentsLoadImage(remoteURL, into: image)
            self.list.addSubview(image)
            cursor += 80
        }
        let meta = UILabel(frame: CGRect(x: x + 40, y: cursor + 4, width: width - 110, height: 16))
        meta.font = Font.regular(12)
        meta.textColor = theme.list.itemSecondaryTextColor
        var metaText = momentsRelativeTime(created)
        if let region, !region.isEmpty {
            metaText += " · " + region
        }
        metaText += "  " + momentsText(strings, .reply)
        meta.text = metaText
        self.list.addSubview(meta)
        let like = UIButton(type: .system)
        like.frame = CGRect(x: x + width - 72, y: y, width: 36, height: 32)
        like.setTitle(likes > 0 ? "\(likes)" : "♡", for: .normal)
        like.setTitleColor(liked ? UIColor(rgb: 0xFF3B30) : theme.list.itemSecondaryTextColor, for: .normal)
        like.accessibilityIdentifier = rowId
        like.addTarget(self, action: #selector(self.likePressed(_:)), for: .touchUpInside)
        self.list.addSubview(like)
        let dislike = UIButton(type: .system)
        dislike.frame = CGRect(x: x + width - 32, y: y, width: 28, height: 32)
        dislike.setTitle("⇩", for: .normal)
        dislike.setTitleColor(theme.list.itemSecondaryTextColor, for: .normal)
        dislike.accessibilityIdentifier = rowId
        dislike.addTarget(self, action: #selector(self.dislikePressed(_:)), for: .touchUpInside)
        self.list.addSubview(dislike)
        return meta.frame.maxY + 12
    }

    @objc private func expandReplies(_ button: UIButton) {
        guard self.comments.indices.contains(button.tag) else { return }
        let comment = self.comments[button.tag]
        self.expanded.insert(comment.id)
        let _ = (self.context.engine.moments.replies(rootId: comment.id, cursor: nil) |> deliverOnMainQueue).start(next: { [weak self] page in
            self?.loadedReplies[comment.id] = page.replies
            self?.relayoutComments()
        })
        self.relayoutComments()
    }

    @objc private func likePressed(_ button: UIButton) {
        guard let id = button.accessibilityIdentifier else { return }
        let liked = self.reaction(id: id)?.liked == true
        let _ = self.context.engine.moments.setCommentLiked(id: id, liked: !liked).start()
        self.toggleLike(id: id)
    }

    @objc private func dislikePressed(_ button: UIButton) {
        guard let id = button.accessibilityIdentifier else { return }
        let _ = self.context.engine.moments.setCommentDisliked(id: id, disliked: true).start()
        self.comments.removeAll { $0.id == id }
        for key in self.loadedReplies.keys {
            self.loadedReplies[key]?.removeAll { $0.id == id }
        }
        self.relayoutComments()
    }

    private func reaction(id: String) -> (liked: Bool, count: Int)? {
        if let comment = self.comments.first(where: { $0.id == id }) {
            return (comment.liked, comment.likeCount)
        }
        for replies in self.loadedReplies.values {
            if let reply = replies.first(where: { $0.id == id }) {
                return (reply.liked, reply.likeCount)
            }
        }
        return nil
    }

    private func toggleLike(id: String) {
        self.comments = self.comments.map { item in
            guard item.id == id else { return item }
            var copy = item
            copy.liked.toggle()
            copy.likeCount += copy.liked ? 1 : -1
            if copy.likeCount < 0 { copy.likeCount = 0 }
            return copy
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
        self.dismiss()
    }

    @objc private func expandPressed() {
        self.expandedSheet.toggle()
        if let layout = self.currentlyAppliedLayout {
            self.containerLayoutUpdated(layout, transition: .animated(duration: 0.25, curve: .spring))
        }
    }
}

extension MomentsCommentSheet: UITextFieldDelegate {
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = textField.text ?? ""
        guard !text.isEmpty else { return false }
        let _ = self.context.engine.moments.addComment(postId: self.card.id, text: text, parentId: nil).start()
        textField.text = ""
        textField.resignFirstResponder()
        self.reload()
        return false
    }
}
