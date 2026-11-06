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
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    private var audienceDisposable: Disposable?
    private let textNode = ImmediateTextNode()
    private let linkCard = TellomiDiscoverLinkCardView()
    private var commentRows: [TellomiDiscoverCommentRow] = []
    private var pollButtons: [UIButton] = []
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

    init(context: AccountContext, postId: String, loader: TellomiDiscoverLoader, configuration: TellomiDiscoverConfiguration, loggedIn: Bool, mediaUpload: Bool = false, mediaBaseURL: URL? = nil, previews: TellomiDiscoverLocalPreviewBook? = nil) {
        self.context = context
        self.postId = postId
        self.loader = loader
        self.configuration = configuration
        self.loggedIn = loggedIn
        self.mediaUpload = mediaUpload
        self.mediaBaseURL = mediaBaseURL
        self.previews = previews
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
        self.presentationDataDisposable?.dispose()
        self.audienceDisposable?.dispose()
        for task in self.imageTasks {
            task.cancel()
        }
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.addSubnode(self.textNode)
        self.textNode.maximumNumberOfLines = 0
        self.displayNodeDidLoad()
        self.displayNode.view.addSubview(self.linkCard)
        self.apply()
        self.loadIfAllowed()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY + 16.0
        let width = max(1, layout.size.width - 32.0)
        let size = self.textNode.updateLayout(CGSize(width: width, height: 4000))
        transition.updateFrame(node: self.textNode, frame: CGRect(x: 16, y: top, width: size.width, height: size.height))
        var commentY = self.textNode.frame.maxY + 12.0
        for imageView in self.imageViews {
            let imageWidth = min(width, 280.0)
            let imageHeight: CGFloat
            if let image = imageView.image, image.size.width > 1, image.size.height > 1 {
                imageHeight = min(320.0, imageWidth * image.size.height / image.size.width)
            } else {
                imageHeight = 160.0
            }
            imageView.frame = CGRect(x: 16.0, y: commentY, width: imageWidth, height: imageHeight)
            commentY = imageView.frame.maxY + 8.0
        }
        if self.linkCard.isHidden {
            self.linkCard.frame = .zero
        } else {
            let cardHeight = self.linkCard.sizeThatFits(CGSize(width: width, height: 200)).height
            self.linkCard.frame = CGRect(x: 16, y: commentY, width: width, height: cardHeight)
            commentY = self.linkCard.frame.maxY + 12.0
        }
        for button in self.pollButtons {
            button.frame = CGRect(x: 16, y: commentY, width: width, height: 40)
            commentY += 48.0
        }
        for row in self.commentRows {
            let height = row.layout(width: width)
            row.frame = CGRect(x: 16, y: commentY, width: width, height: height)
            commentY += height + 8.0
        }
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
        }, published: {}, mediaUpload: self.mediaUpload, configuration: self.configuration, loader: self.loader, previews: self.previews)
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
        self.installComments(self.post?.comments ?? [], color: self.presentationData.theme.list.itemPrimaryTextColor)
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
            self.displayNode.view.addSubview(button)
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
            self.displayNode.view.addSubview(row)
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
        let remote = post.images.compactMap { tellomiDiscoverImageURL(image: $0, mediaBaseURL: self.mediaBaseURL) }
        let local = self.previews?.images(for: self.postId) ?? []
        let source = tellomiDiscoverImagePreviewSource(cardState: post.unavailable ? "unavailable" : "ok", remoteURLs: remote, hasLocalBytes: !local.isEmpty)
        switch source {
        case .remote:
            self.previews?.drop(postId: self.postId)
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
        self.displayNode.view.addSubview(view)
        self.imageViews.append(view)
        return view
    }
}

private final class TellomiDiscoverCommentRow: UIView {
    var onReport: (() -> Void)?
    let reportButton = UIButton(type: .system)
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
        self.addSubview(self.label)
        self.addSubview(self.reportButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func layout(width: CGFloat) -> CGFloat {
        let buttonWidth: CGFloat = 44.0
        let textWidth = max(1, width - buttonWidth)
        let textSize = self.label.sizeThatFits(CGSize(width: textWidth, height: 400))
        let height = max(44.0, textSize.height)
        self.label.frame = CGRect(x: 0, y: 0, width: textWidth, height: height)
        self.reportButton.frame = CGRect(x: textWidth, y: 0, width: buttonWidth, height: height)
        return height
    }

    @objc private func reportPressed() {
        self.onReport?()
    }
}
