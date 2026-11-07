import AccountContext
import AsyncDisplayKit
import Display
import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import TellomiDiscover
import UIKit

final class TellomiDiscoverPostController: ViewController {
    private let context: AccountContext
    private let postId: String
    private let loader: TellomiDiscoverLoader
    private let configuration: TellomiDiscoverConfiguration
    private let loggedIn: Bool
    private let mediaUpload: Bool
    private let mediaBaseURL: URL?
    private let previews: TellomiDiscoverLocalPreviewBook?
    private let previewAccount: String
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    private var audienceDisposable: Disposable?
    private let textNode = ImmediateTextNode()
    private let scrollView = UIScrollView()
    private let linkCard = TellomiDiscoverLinkCardView()
    private var commentRows: [TellomiDiscoverCommentRow] = []
    private var pollButtons: [UIButton] = []
    private let likeButton = UIButton(type: .system)
    private let commentField = UITextField()
    private let surface: String
    private var like: TellomiDiscoverLike?
    private let comments = TellomiDiscoverComments()
    private var commentsBound = false
    private let moreCommentsButton = UIButton(type: .system)
    private var imageViews: [UIImageView] = []
    private var imageTasks: [URLSessionDataTask] = []
    private let imageSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()
    private var post: TellomiDiscoverPost?
    private var failed = false
    private var started = false

    init(context: AccountContext, postId: String, loader: TellomiDiscoverLoader, configuration: TellomiDiscoverConfiguration, loggedIn: Bool, surface: String = "recommend", mediaUpload: Bool = false, mediaBaseURL: URL? = nil, previews: TellomiDiscoverLocalPreviewBook? = nil, previewAccount: String = "") {
        self.context = context
        self.postId = postId
        self.surface = tellomiDiscoverLikeSurface(surface)
        self.loader = loader
        self.configuration = configuration
        self.loggedIn = loggedIn
        self.mediaUpload = mediaUpload
        self.mediaBaseURL = mediaBaseURL
        self.previews = previews
        self.previewAccount = previewAccount
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        let copy = TellomiTabCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: self.presentationData.strings.primaryComponent.dict, secondary: self.presentationData.strings.secondaryComponent?.dict))
        self.title = copy.feed
        if loggedIn {
            let item = UIBarButtonItem(title: "…", style: .plain, target: self, action: #selector(self.menuPressed))
            item.accessibilityIdentifier = "tellomi.discover.share"
            self.navigationItem.setRightBarButton(item, animated: false)
        }
        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else {
                return
            }
            self.presentationData = presentationData
            self.apply()
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.like?.close()
        self.comments.close()
        self.presentationDataDisposable?.dispose()
        self.audienceDisposable?.dispose()
        for task in self.imageTasks {
            task.cancel()
        }
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.textNode.maximumNumberOfLines = 0
        self.displayNodeDidLoad()
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.delaysContentTouches = false
        self.scrollView.backgroundColor = .clear
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.scrollView.keyboardDismissMode = .interactive
        self.displayNode.view.addSubview(self.scrollView)
        self.scrollView.addSubview(self.textNode.view)
        self.scrollView.addSubview(self.linkCard)
        self.likeButton.contentHorizontalAlignment = .left
        self.likeButton.addTarget(self, action: #selector(self.likePressed), for: .touchUpInside)
        self.likeButton.accessibilityIdentifier = "tellomi.discover.like"
        self.commentField.accessibilityIdentifier = "tellomi.discover.comment"
        self.commentField.returnKeyType = .send
        self.commentField.autocorrectionType = .no
        self.commentField.addTarget(self, action: #selector(self.commentReturned), for: .editingDidEndOnExit)
        self.scrollView.addSubview(self.likeButton)
        self.scrollView.addSubview(self.commentField)
        self.moreCommentsButton.accessibilityIdentifier = "tellomi.discover.comments.more"
        self.moreCommentsButton.addTarget(self, action: #selector(self.moreCommentsPressed), for: .touchUpInside)
        self.scrollView.addSubview(self.moreCommentsButton)
        self.apply()
        self.loadIfAllowed()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let navigationHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.scrollView.frame = CGRect(x: 0, y: navigationHeight, width: layout.size.width, height: max(1, layout.size.height - navigationHeight))
        let width = max(1, layout.size.width - 32.0)
        let textSize = self.textNode.updateLayout(CGSize(width: width, height: 4000))
        var pieces: [TellomiDiscoverDetailPiece] = [.text(Double(textSize.height))]
        var imageHeights: [CGFloat] = []
        for imageView in self.imageViews {
            let imageWidth = min(width, 280.0)
            let imageHeight: CGFloat
            if let image = imageView.image, image.size.width > 1, image.size.height > 1 {
                imageHeight = min(320.0, imageWidth * image.size.height / image.size.width)
            } else {
                imageHeight = 160.0
            }
            imageHeights.append(imageHeight)
            pieces.append(.image(Double(imageHeight)))
        }
        var linkHeight: CGFloat = 0
        if !self.linkCard.isHidden {
            linkHeight = self.linkCard.sizeThatFits(CGSize(width: width, height: 200)).height
            pieces.append(.link(Double(linkHeight)))
        }
        for _ in self.pollButtons {
            pieces.append(.poll(40))
        }
        let showsReact = self.loggedIn && self.post != nil
        if showsReact {
            pieces.append(.comment(44))
            pieces.append(.comment(36))
            if self.comments.hasMore() {
                pieces.append(.comment(36))
            }
        }
        var commentHeights: [CGFloat] = []
        for row in self.commentRows {
            let height = row.layout(width: width)
            commentHeights.append(height)
            pieces.append(.comment(Double(height)))
        }
        let bottom = max(layout.intrinsicInsets.bottom, layout.safeInsets.bottom) + 16.0
        let placed = tellomiDiscoverDetailLayout(contentWidth: Double(layout.size.width), viewportHeight: Double(self.scrollView.bounds.height), pieces: pieces, bottom: Double(bottom))
        var index = 0
        if index < placed.frames.count {
            let frame = placed.frames[index]
            self.textNode.frame = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            index += 1
        }
        for (imageView, imageHeight) in zip(self.imageViews, imageHeights) {
            guard index < placed.frames.count else {
                break
            }
            let frame = placed.frames[index]
            imageView.frame = CGRect(x: frame.x, y: frame.y, width: frame.width, height: max(frame.height, Double(imageHeight)))
            index += 1
        }
        if !self.linkCard.isHidden, index < placed.frames.count {
            let frame = placed.frames[index]
            self.linkCard.frame = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            index += 1
        } else {
            self.linkCard.frame = .zero
        }
        for button in self.pollButtons {
            guard index < placed.frames.count else {
                break
            }
            let frame = placed.frames[index]
            button.frame = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            index += 1
        }
        if showsReact, index + 1 < placed.frames.count {
            let likeFrame = placed.frames[index]
            self.likeButton.isHidden = false
            self.likeButton.frame = CGRect(x: likeFrame.x, y: likeFrame.y, width: likeFrame.width, height: likeFrame.height)
            index += 1
            let fieldFrame = placed.frames[index]
            self.commentField.isHidden = false
            self.commentField.frame = CGRect(x: fieldFrame.x, y: fieldFrame.y, width: fieldFrame.width, height: fieldFrame.height)
            index += 1
            if self.comments.hasMore(), index < placed.frames.count {
                let moreFrame = placed.frames[index]
                self.moreCommentsButton.isHidden = false
                self.moreCommentsButton.frame = CGRect(x: moreFrame.x, y: moreFrame.y, width: moreFrame.width, height: moreFrame.height)
                index += 1
            } else {
                self.moreCommentsButton.isHidden = true
                self.moreCommentsButton.frame = .zero
            }
        } else {
            self.likeButton.isHidden = true
            self.likeButton.frame = .zero
            self.commentField.isHidden = true
            self.commentField.frame = .zero
            self.moreCommentsButton.isHidden = true
            self.moreCommentsButton.frame = .zero
        }
        for (row, commentHeight) in zip(self.commentRows, commentHeights) {
            guard index < placed.frames.count else {
                break
            }
            let frame = placed.frames[index]
            row.frame = CGRect(x: frame.x, y: frame.y, width: frame.width, height: max(frame.height, Double(commentHeight)))
            index += 1
        }
        self.scrollView.contentSize = CGSize(width: layout.size.width, height: CGFloat(placed.contentHeight))
    }

    @objc private func menuPressed() {
        tellomiPresentDiscoverPostMenu(host: self, context: self.context, loggedIn: self.loggedIn, configuration: self.configuration, loader: self.loader, postId: self.postId, post: self.post, onReposted: { [weak self] reposted in
            guard let self, var post = self.post else {
                return
            }
            post.reposted = reposted
            post.repostCount = max(0, post.repostCount + (reposted ? 1 : -1))
            self.post = post
            self.apply()
        }, onQuote: { [weak self] in
            self?.openQuote()
        })
    }

    private func openQuote() {
        let preview = self.post?.text ?? ""
        let textLimit = tellomiDiscoverPostTextLimit
        let controller = TellomiDiscoverComposeController(context: self.context, textLimit: textLimit, quoteOf: self.postId, quotePreview: preview, publish: { [weak self] request, completion in
            guard let self else {
                completion(.failure(.signedOut))
                return
            }
            tellomiRunDiscoverPublish(context: self.context, loader: self.loader, configuration: self.configuration, loggedIn: self.loggedIn, city: tellomiDiscoverStoredCity(), textLimit: textLimit, request: request, retainAudience: { [weak self] disposable in
                self?.audienceDisposable?.dispose()
                self?.audienceDisposable = disposable
            }, completion: completion)
        }, published: {}, mediaUpload: self.mediaUpload, configuration: self.configuration, loader: self.loader, previews: self.previews, previewAccount: self.previewAccount)
        self.push(controller)
    }

    @objc private func votePressed(_ button: UIButton) {
        let option = button.tag
        guard let poll = self.post?.poll, poll.voted.isEmpty, poll.options.indices.contains(option) else {
            return
        }
        self.loader.run(loggedIn: true, configuration: self.configuration, operation: .vote(postId: self.postId, option: option)) { [weak self] result in
            guard let self, case let .success(.voted(tally)) = result, var post = self.post, let poll = post.poll else {
                return
            }
            post.poll = tellomiDiscoverPoll(poll, applying: tally)
            self.post = post
            self.apply()
            if let layout = self.currentlyAppliedLayout {
                self.containerLayoutUpdated(layout, transition: .immediate)
            }
        }
    }

    private func loadIfAllowed() {
        guard !self.started else {
            return
        }
        let chrome = tellomiDiscoverChrome(loggedIn: self.loggedIn, enabled: self.configuration.enabled, kind: .recommend, openedPostId: self.postId, failed: false)
        guard chrome.loadsPost, case let .detail(id) = chrome.surface else {
            self.failed = true
            self.apply()
            return
        }
        self.started = true
        self.loader.run(loggedIn: true, configuration: self.configuration, operation: .cards([id])) { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case let .success(.cards(cards)):
                self.post = cards.first.map(tellomiDiscoverDisplayPost)
                self.failed = self.post == nil || self.post?.unavailable == true
                self.installImages()
                if self.loggedIn, self.post != nil {
                    self.openComments()
                }
            default:
                self.failed = true
            }
            self.apply()
            if let layout = self.currentlyAppliedLayout {
                self.containerLayoutUpdated(layout, transition: .immediate)
            }
        }
    }

    private func apply() {
        let pack = tellomiStringPack(primary: self.presentationData.strings.primaryComponent.dict, secondary: self.presentationData.strings.secondaryComponent?.dict)
        let copy = TellomiDiscoverCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode, pack: pack)
        let legacy = TellomiTabCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode, pack: pack)
        self.displayNode.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
        let body: String
        if let post = self.post {
            let summary = tellomiDiscoverPostSummary(post: post, copy: copy, list: false, includePoll: false)
            body = [summary.title, summary.body, summary.meta].filter { !$0.isEmpty }.joined(separator: "\n\n")
        } else if self.failed || !self.loggedIn || !self.configuration.enabled {
            body = legacy.feedPostUnavailable
        } else {
            body = ""
        }
        self.textNode.attributedText = NSAttributedString(string: body, font: Font.regular(16.0), textColor: self.presentationData.theme.list.itemPrimaryTextColor)
        self.linkCard.apply(primary: self.presentationData.theme.list.itemPrimaryTextColor, secondary: self.presentationData.theme.list.itemSecondaryTextColor, accent: self.presentationData.theme.list.itemAccentColor, background: self.presentationData.theme.list.itemHighlightedBackgroundColor)
        if let preview = self.post?.linkPreview, self.post?.unavailable != true {
            self.linkCard.show(preview, opens: true)
        } else {
            self.linkCard.hide()
        }
        self.installPoll(self.post?.poll, copy: copy)
        let rows = tellomiDiscoverDetailCommentRows(bound: self.commentsBound, visible: self.comments.visibleRows(), pending: self.comments.pendingRows())
        self.installComments(rows, color: self.presentationData.theme.list.itemPrimaryTextColor)
        if let post = self.post {
            if self.like == nil || self.like?.postId != post.id {
                self.like = TellomiDiscoverLike(postId: post.id, liked: post.liked, count: post.likeCount, hidden: post.likesHidden, surface: self.surface)
            } else {
                self.like?.bind(postId: post.id, liked: post.liked, count: post.likeCount, likesHidden: post.likesHidden, surface: self.surface)
            }
            let view = self.like?.view()
            let title: String
            if view?.hidden == true {
                title = copy.likes.replacingOccurrences(of: "%d", with: "")
            } else {
                title = tellomiFormatInteger(copy.likes, view?.count ?? post.likeCount)
            }
            self.likeButton.setTitle((view?.liked == true ? "✓ " : "") + title, for: .normal)
            self.likeButton.setTitleColor(self.presentationData.theme.list.itemAccentColor, for: .normal)
            self.commentField.textColor = self.presentationData.theme.list.itemPrimaryTextColor
            self.commentField.attributedPlaceholder = NSAttributedString(string: copy.comments.replacingOccurrences(of: "%d", with: "").trimmingCharacters(in: .whitespaces), attributes: [NSAttributedString.Key.foregroundColor: self.presentationData.theme.list.itemSecondaryTextColor])
            self.moreCommentsButton.setTitle(copy.comments, for: .normal)
        }
    }

    @objc private func likePressed() {
        guard let like = self.like, let request = like.tap() else {
            return
        }
        self.apply()
        self.sendLike(request)
    }

    private func sendLike(_ request: TellomiDiscoverLikeRequest) {
        guard self.like != nil else {
            return
        }
        let operation: TellomiDiscoverOperation = request.on ? .like(postId: request.postId, surface: request.surface) : .unlike(postId: request.postId, surface: request.surface)
        self.loader.run(loggedIn: true, configuration: self.configuration, operation: operation) { [weak self] result in
            guard let self, let like = self.like else {
                return
            }
            if let next = tellomiDiscoverApplyLike(like, request: request, result: result) {
                self.sendLike(next)
            }
            if var post = self.post {
                post.liked = like.view().liked
                post.likeCount = like.view().count
                self.post = post
            }
            self.apply()
        }
    }

    @objc private func commentReturned() {
        guard let send = self.comments.submit(text: self.commentField.text ?? "", parentId: nil, freshNonce: UUID().uuidString), send.ready(), let nonce = send.nonce, let text = send.text else {
            return
        }
        self.loader.run(loggedIn: true, configuration: self.configuration, operation: .comment(postId: self.postId, text: text, parentId: send.parentId, clientNonce: nonce)) { [weak self] result in
            guard let self else {
                return
            }
            if case let .success(.commentCreated(created)) = result, self.comments.finishSend(generation: send.generation, version: send.version, created: created) {
                self.commentField.text = nil
                if var post = self.post, created.state == "ok" {
                    post.commentCount += 1
                    self.post = post
                }
            } else {
                self.comments.failSend(generation: send.generation, version: send.version)
            }
            self.apply()
        }
    }

    @objc private func moreCommentsPressed() {
        guard let load = self.comments.more() else {
            return
        }
        self.loadComments(load)
    }

    func openComments() {
        self.commentsBound = true
        let load = self.comments.open(postId: self.postId)
        self.loadComments(load)
    }

    private func loadComments(_ load: TellomiDiscoverCommentLoad) {
        self.loader.run(loggedIn: true, configuration: self.configuration, operation: .comments(postId: load.postId, cursor: load.cursor)) { [weak self] result in
            guard let self else {
                return
            }
            if case let .success(.commentPage(page)) = result {
                _ = self.comments.accept(generation: load.generation, version: load.version, page: page)
            } else {
                self.comments.failLoad(generation: load.generation, version: load.version)
            }
            self.apply()
        }
    }

    func deleteComment(_ commentId: String) {
        let wasVisible = self.comments.visibleRows().contains { $0.id == commentId }
        guard let request = self.comments.delete(commentId) else {
            return
        }
        self.loader.run(loggedIn: true, configuration: self.configuration, operation: .deleteComment(request.commentId)) { [weak self] result in
            guard let self else {
                return
            }
            let ok: Bool
            if case .success(.acknowledged) = result {
                ok = true
            } else {
                ok = false
            }
            let deleted = self.comments.finishDelete(generation: request.generation, version: request.version, commentId: request.commentId, ok: ok)
            if var post = self.post {
                post.commentCount = tellomiDiscoverPublicCountAfterDelete(count: post.commentCount, wasVisible: wasVisible, deleted: deleted)
                self.post = post
            }
            self.apply()
        }
    }

    private func installPoll(_ poll: TellomiDiscoverPoll?, copy: TellomiDiscoverCopy) {
        for button in self.pollButtons {
            button.removeFromSuperview()
        }
        guard self.isNodeLoaded, let poll else {
            self.pollButtons = []
            return
        }
        let hasVoted = !poll.voted.isEmpty
        self.pollButtons = poll.options.enumerated().map { index, option in
            let button = UIButton(type: .system)
            var title = option.text
            if hasVoted || option.votes > 0 {
                title += " · " + tellomiFormatInteger(copy.votes, option.votes)
            }
            button.setTitle(title, for: .normal)
            button.contentHorizontalAlignment = .left
            button.tag = index
            button.isEnabled = !hasVoted
            button.accessibilityIdentifier = "tellomi.discover.vote.\(index)"
            button.setTitleColor(poll.voted.contains(index) ? self.presentationData.theme.list.itemAccentColor : self.presentationData.theme.list.itemPrimaryTextColor, for: .normal)
            button.addTarget(self, action: #selector(self.votePressed(_:)), for: .touchUpInside)
            self.scrollView.addSubview(button)
            return button
        }
    }

    private func installComments(_ comments: [TellomiDiscoverComment], color: UIColor) {
        for row in self.commentRows {
            row.removeFromSuperview()
        }
        guard self.isNodeLoaded else {
            self.commentRows = []
            return
        }
        self.commentRows = comments.map { comment in
            let row = TellomiDiscoverCommentRow(comment: comment, color: color)
            row.reportButton.accessibilityIdentifier = "tellomi.discover.report.comment.\(comment.id)"
            row.onReport = { [weak self] in
                guard let self else {
                    return
                }
                tellomiPresentDiscoverReport(host: self, context: self.context, loggedIn: self.loggedIn, configuration: self.configuration, loader: self.loader, target: .comment(postId: self.postId, commentId: comment.id))
            }
            if self.comments.canDelete(comment.id) {
                row.deleteButton.isHidden = false
                row.deleteButton.accessibilityIdentifier = "tellomi.discover.delete.comment.\(comment.id)"
                row.onDelete = { [weak self] in
                    self?.deleteComment(comment.id)
                }
            }
            self.scrollView.addSubview(row)
            return row
        }
    }

    private func installImages() {
        for task in self.imageTasks {
            task.cancel()
        }
        self.imageTasks = []
        for view in self.imageViews {
            view.removeFromSuperview()
        }
        self.imageViews = []
        guard self.isNodeLoaded, let post = self.post else {
            return
        }
        let remote = post.moderation == .published ? post.images.compactMap { tellomiDiscoverImageURL(image: $0, mediaBaseURL: self.mediaBaseURL) } : []
        let local = post.moderation == .pending ? (self.previews?.images(account: self.previewAccount, postId: self.postId) ?? []) : []
        let source = tellomiDiscoverImagePreviewSource(moderation: post.moderation, remoteURLs: remote, hasLocalBytes: !local.isEmpty)
        switch source {
        case .remote:
            self.previews?.drop(account: self.previewAccount, postId: self.postId)
            for url in remote {
                let view = self.makeImageView(image: nil)
                let task = self.imageSession.dataTask(with: url) { [weak self, weak view] data, response, _ in
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data, let image = UIImage(data: data) else {
                        return
                    }
                    DispatchQueue.main.async {
                        view?.image = image
                        guard let self, let layout = self.currentlyAppliedLayout else {
                            return
                        }
                        self.containerLayoutUpdated(layout, transition: .immediate)
                    }
                }
                task.resume()
                self.imageTasks.append(task)
            }
        case .local:
            for data in local {
                _ = self.makeImageView(image: UIImage(data: data))
            }
        case .none:
            break
        }
    }

    private func makeImageView(image: UIImage?) -> UIImageView {
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 8.0
        view.backgroundColor = self.presentationData.theme.list.itemSecondaryTextColor.withAlphaComponent(0.12)
        self.scrollView.addSubview(view)
        self.imageViews.append(view)
        return view
    }
}

private final class TellomiDiscoverCommentRow: UIView {
    var onReport: (() -> Void)?
    var onDelete: (() -> Void)?
    let reportButton = UIButton(type: .system)
    let deleteButton = UIButton(type: .system)
    private let label = UILabel()

    init(comment: TellomiDiscoverComment, color: UIColor) {
        super.init(frame: .zero)
        var title = comment.authorName
        if !comment.text.isEmpty {
            if title.isEmpty {
                title = comment.text
            } else {
                title += "\n" + comment.text
            }
        }
        self.label.text = title
        self.label.textColor = color
        self.label.font = Font.regular(15.0)
        self.label.numberOfLines = 0
        self.reportButton.setTitle("…", for: .normal)
        self.reportButton.addTarget(self, action: #selector(self.reportPressed), for: .touchUpInside)
        self.deleteButton.setTitle("×", for: .normal)
        self.deleteButton.isHidden = true
        self.deleteButton.addTarget(self, action: #selector(self.deletePressed), for: .touchUpInside)
        self.addSubview(self.label)
        self.addSubview(self.reportButton)
        self.addSubview(self.deleteButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func layout(width: CGFloat) -> CGFloat {
        let buttonWidth: CGFloat = 44.0
        let buttons: CGFloat = self.deleteButton.isHidden ? buttonWidth : buttonWidth * 2
        let textWidth = max(1, width - buttons)
        let textSize = self.label.sizeThatFits(CGSize(width: textWidth, height: 400))
        let height = max(44.0, textSize.height)
        self.label.frame = CGRect(x: 0, y: 0, width: textWidth, height: height)
        self.deleteButton.frame = CGRect(x: textWidth, y: 0, width: self.deleteButton.isHidden ? 0 : buttonWidth, height: height)
        self.reportButton.frame = CGRect(x: textWidth + (self.deleteButton.isHidden ? 0 : buttonWidth), y: 0, width: buttonWidth, height: height)
        return height
    }

    @objc private func reportPressed() {
        self.onReport?()
    }

    @objc private func deletePressed() {
        self.onDelete?()
    }
}
