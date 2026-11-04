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
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    private let textNode = ImmediateTextNode()
    private var commentRows: [TellomiDiscoverCommentRow] = []
    private var post: TellomiDiscoverPost?
    private var failed = false
    private var started = false

    init(context: AccountContext, postId: String, loader: TellomiDiscoverLoader, configuration: TellomiDiscoverConfiguration, loggedIn: Bool) {
        self.context = context
        self.postId = postId
        self.loader = loader
        self.configuration = configuration
        self.loggedIn = loggedIn
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        let copy = TellomiTabCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode, pack: tellomiStringPack(primary: self.presentationData.strings.primaryComponent.dict, secondary: self.presentationData.strings.secondaryComponent?.dict))
        self.title = copy.feed
        if loggedIn {
            let item = UIBarButtonItem(title: "…", style: .plain, target: self, action: #selector(self.reportPressed))
            item.accessibilityIdentifier = "tellomi.discover.report"
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
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.addSubnode(self.textNode)
        self.textNode.maximumNumberOfLines = 0
        self.displayNodeDidLoad()
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
        for row in self.commentRows {
            let height = row.layout(width: width)
            row.frame = CGRect(x: 16, y: commentY, width: width, height: height)
            commentY += height + 8.0
        }
    }

    @objc private func reportPressed() {
        tellomiPresentDiscoverReport(host: self, context: self.context, loggedIn: self.loggedIn, configuration: self.configuration, loader: self.loader, target: .post(self.postId))
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
            let summary = tellomiDiscoverPostSummary(post: post, copy: copy, list: false)
            body = [summary.title, summary.body, summary.meta].filter { !$0.isEmpty }.joined(separator: "\n\n")
        } else if self.failed || !self.loggedIn || !self.configuration.enabled {
            body = legacy.feedPostUnavailable
        } else {
            body = ""
        }
        self.textNode.attributedText = NSAttributedString(string: body, font: Font.regular(16.0), textColor: self.presentationData.theme.list.itemPrimaryTextColor)
        self.installComments(self.post?.comments ?? [], color: self.presentationData.theme.list.itemPrimaryTextColor)
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
