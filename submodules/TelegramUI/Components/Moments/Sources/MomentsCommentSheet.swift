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
        self.disposable.set((self.context.engine.moments.comments(postId: self.card.id, sort: "hot", cursor: nil) |> deliverOnMainQueue).start(next: { [weak self] comments in
            self?.comments = comments
            self?.relayoutComments()
        }))
    }

    private func relayoutComments() {
        let strings = self.presentationData.strings
        let theme = self.presentationData.theme
        let total = self.card.counts.comments
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
                for reply in comment.replies {
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
        if author?.id == self.card.author?.id && !(author?.id ?? "").isEmpty {
            nameLabel.text = name + "  " + momentsText(strings, .authorTag)
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
        let meta = UILabel(frame: CGRect(x: x + 40, y: body.frame.maxY + 4, width: width - 80, height: 16))
        meta.font = Font.regular(12)
        meta.textColor = theme.list.itemSecondaryTextColor
        meta.text = momentsRelativeTime(created) + "  " + momentsText(strings, .reply)
        self.list.addSubview(meta)
        let like = UILabel(frame: CGRect(x: x + width - 36, y: y, width: 36, height: 32))
        like.font = Font.regular(12)
        like.textColor = theme.list.itemSecondaryTextColor
        like.textAlignment = .right
        like.text = likes > 0 ? "♡ \(likes)" : "♡"
        self.list.addSubview(like)
        return meta.frame.maxY + 12
    }

    @objc private func expandReplies(_ button: UIButton) {
        guard self.comments.indices.contains(button.tag) else { return }
        self.expanded.insert(self.comments[button.tag].id)
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
