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
        let copy = TellomiTabCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode)
        self.title = copy.feed
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
        let copy = TellomiDiscoverCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode)
        let legacy = TellomiTabCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode)
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
    }
}
