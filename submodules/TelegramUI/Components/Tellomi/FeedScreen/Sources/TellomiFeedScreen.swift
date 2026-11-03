import AccountContext
import AppBundle
import AsyncDisplayKit
import ContextUI
import Display
import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import UIKit
import UIKitRuntimeUtils

/// Placeholder for the Discover tab (M2 / D-37). The feed itself is M3.
/// This is not `NewsScreen`.
public final class TellomiFeedScreen: ViewController {
    private let context: AccountContext
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?
    public private(set) var openedPostId: String?

    private var feedNode: TellomiFeedScreenNode {
        return self.displayNode as! TellomiFeedScreenNode
    }

    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))

        self.tabBarItemContextActionType = .always
        self.applyChrome()

        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else {
                return
            }
            self.presentationData = presentationData
            self.applyChrome()
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
    }

    /// D-57. The post body arrives with M3. Until then the empty state says it cannot be opened.
    public func openPost(id: String) {
        self.openedPostId = id
        guard self.isNodeLoaded else {
            return
        }
        self.feedNode.update(presentationData: self.presentationData, postUnavailable: true)
        if let layout = self.currentlyAppliedLayout {
            self.containerLayoutUpdated(layout, transition: .immediate)
        }
    }

    override public func loadDisplayNode() {
        self.displayNode = TellomiFeedScreenNode(presentationData: self.presentationData)
        if self.openedPostId != nil {
            self.feedNode.update(presentationData: self.presentationData, postUnavailable: true)
        }
        self.displayNodeDidLoad()
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let navigationHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.feedNode.updateLayout(size: layout.size, topInset: navigationHeight, bottomInset: layout.intrinsicInsets.bottom, transition: transition)
    }

    override public func tabBarItemContextAction(sourceView: ContextExtractedContentContainingView, gesture: ContextGesture) {
        guard tellomiBottomNavigationEnabled(appConfiguration: self.context.currentAppConfiguration.with { $0 }) else {
            return
        }
        let copy = TellomiTabCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode)
        let items: [ContextMenuItem] = [
            .action(ContextMenuActionItem(text: copy.hideFeed, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Peer Info/HideIcon"), color: theme.contextMenu.primaryColor)
            }, action: { [weak self] controller, _ in
                controller?.dismiss(completion: {
                    guard let self else {
                        return
                    }
                    let _ = updateTellomiTabSettingsInteractively(accountManager: self.context.sharedContext.accountManager, { settings in
                        return settings.withUpdatedShowFeedTab(false)
                    }).start()
                })
            }))
        ]
        let contextController = makeContextController(presentationData: self.presentationData, source: .reference(TellomiFeedTabBarContextReferenceContentSource(controller: self, sourceView: sourceView)), items: .single(ContextController.Items(content: .list(items))), recognizer: nil, gesture: gesture)
        self.context.sharedContext.mainWindow?.presentInGlobalOverlay(contextController)
    }

    private func applyChrome() {
        let copy = TellomiTabCopy.resolve(languageCode: self.presentationData.strings.primaryComponent.languageCode)
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.title = copy.feed
        self.navigationItem.title = copy.feed
        self.tabBarItem.title = copy.feed
        self.tabBarItem.image = tellomiFeedTabIcon(filled: false)
        self.tabBarItem.selectedImage = tellomiFeedTabIcon(filled: true)
        self.tabBarItem.animationName = nil
        self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: self.presentationData), transition: .immediate)
        if self.isNodeLoaded {
            self.feedNode.update(presentationData: self.presentationData, postUnavailable: self.openedPostId != nil)
        }
    }
}

private func tellomiFeedTabIcon(filled: Bool) -> UIImage? {
    let side: CGFloat = 28.0
    UIGraphicsBeginImageContextWithOptions(CGSize(width: side, height: side), false, 0.0)
    defer {
        UIGraphicsEndImageContext()
    }
    let circle = UIBezierPath(ovalIn: CGRect(x: 2.5, y: 2.5, width: 23.0, height: 23.0))
    circle.lineWidth = 1.6
    UIColor.black.setStroke()
    circle.stroke()

    let needle = UIBezierPath()
    needle.move(to: CGPoint(x: 14.0, y: 7.0))
    needle.addLine(to: CGPoint(x: 18.5, y: 16.5))
    needle.addLine(to: CGPoint(x: 14.0, y: 21.0))
    needle.addLine(to: CGPoint(x: 9.5, y: 16.5))
    needle.close()
    UIColor.black.setFill()
    UIColor.black.setStroke()
    if filled {
        needle.fill()
    } else {
        needle.lineWidth = 1.4
        needle.stroke()
    }
    UIBezierPath(ovalIn: CGRect(x: 12.4, y: 12.4, width: 3.2, height: 3.2)).fill()
    return UIGraphicsGetImageFromCurrentImageContext()?.withRenderingMode(.alwaysTemplate)
}

private final class TellomiFeedTabBarContextReferenceContentSource: ContextReferenceContentSource {
    let keepInPlace: Bool = true

    private let controller: ViewController
    private let sourceView: ContextExtractedContentContainingView

    init(controller: ViewController, sourceView: ContextExtractedContentContainingView) {
        self.controller = controller
        self.sourceView = sourceView
    }

    func transitionInfo() -> ContextControllerReferenceViewInfo? {
        let _ = self.controller
        return ContextControllerReferenceViewInfo(
            referenceView: self.sourceView.contentView,
            contentAreaInScreenSpace: mainWindowScreenBounds,
            actionsPosition: .top
        )
    }
}
