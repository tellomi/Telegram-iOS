import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramCore
import SwiftSignalKit
import LegacyComponents
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import AttachmentUI
import WallpaperGalleryScreen
import ThemeAccentColorScreen

private func availableGradients(dark: Bool) -> [[UInt32]] {
    return tellomiAvailableGradients(dark: dark)
}

private func availableColors(dark: Bool) -> [UInt32] {
    return tellomiAvailableSolidColors(dark: dark)
}

public final class ThemeColorsGridController: ViewController, AttachmentContainable {
    public enum Mode {
        case `default`
        case peer(EnginePeer)

        var galleryMode: WallpaperGalleryController.Mode {
            switch self {
            case .default:
                return .default
            case let .peer(peer):
                return .peer(peer, false)
            }
        }

        var colorPickerMode: ThemeAccentColorController.ResultMode {
            switch self {
            case .default:
                return .default
            case let .peer(peer):
                return .peer(peer)
            }
        }
    }

    private var controllerNode: ThemeColorsGridControllerNode {
        return self.displayNode as! ThemeColorsGridControllerNode
    }

    private let _ready = Promise<Bool>()
    public override var ready: Promise<Bool> {
        return self._ready
    }

    private let context: AccountContext
    let mode: Mode

    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?

    private var validLayout: ContainerViewLayout?

    private var previousContentOffset: GridNodeVisibleContentOffset?

    fileprivate var mainButtonState: AttachmentMainButtonState?

    var pushController: (ViewController) -> Void = { _ in }
    var dismissControllers: (() -> Void)?
    var openGallery: (() -> Void)?

    public init(context: AccountContext, mode: Mode = .default, canDelete: Bool = false) {
        self.context = context
        self.mode = mode
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))

        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style

        self.scrollToTop = { [weak self] in
            if let strongSelf = self {
                strongSelf.controllerNode.scrollToTop()
            }
        }

        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            if let strongSelf = self {
                let previousTheme = strongSelf.presentationData.theme
                let previousStrings = strongSelf.presentationData.strings

                strongSelf.presentationData = presentationData

                if previousTheme !== presentationData.theme || previousStrings !== presentationData.strings {
                    strongSelf.updateThemeAndStrings()
                }
            }
        })

        if case .peer = mode {
            self.title = self.presentationData.strings.Conversation_Theme_ChooseColorTitle
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "___close", style: .plain, target: self, action: #selector(self.cancelPressed))
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Conversation_Theme_SetCustomColor, style: .plain, target: self, action: #selector(self.customPressed))
        } else {
            self.title = self.presentationData.strings.WallpaperColors_Title
        }

        self.pushController = { [weak self] controller in
            self?.push(controller)
        }

        self.mainButtonState = AttachmentMainButtonState(text: self.presentationData.strings.Conversation_Theme_SetPhotoWallpaper, font: .regular, background: .color(.clear), textColor: self.presentationData.theme.actionSheet.controlAccentColor, isVisible: true, progress: .none, isEnabled: true, hasShimmer: false)
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
    }

    @objc private func cancelPressed() {
        self.dismiss()
    }

    @objc private func customPressed() {
        self.presentColorPicker()
    }

    private func updateThemeAndStrings() {
        self.title = self.presentationData.strings.WallpaperColors_Title
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: self.presentationData), transition: .immediate)

        if self.isNodeLoaded {
            self.controllerNode.updatePresentationData(self.presentationData)
        }
    }

    private func presentColorPicker() {
        let _ = (self.context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.presentationThemeSettings])
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] sharedData in
            guard let strongSelf = self else {
                return
            }
            let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.presentationThemeSettings]?.get(PresentationThemeSettings.self) ?? PresentationThemeSettings.defaultSettings

            let autoNightModeTriggered = strongSelf.presentationData.autoNightModeTriggered
            let themeReference: PresentationThemeReference
            if autoNightModeTriggered {
                themeReference = settings.automaticThemeSwitchSetting.theme
            } else {
                themeReference = settings.theme
            }

            let controller = ThemeAccentColorController(context: strongSelf.context, mode: .background(themeReference: themeReference), resultMode: strongSelf.mode.colorPickerMode)
            controller.completion = { [weak self, weak controller] in
                if let strongSelf = self {
                    if let dismissControllers = strongSelf.dismissControllers {
                        dismissControllers()
                        controller?.dismiss(animated: true)
                    } else if let navigationController = strongSelf.navigationController as? NavigationController {
                        var controllers = navigationController.viewControllers
                        controllers = controllers.filter { controller in
                            if controller is ThemeColorsGridController {
                                return false
                            }
                            return true
                        }
                        navigationController.setViewControllers(controllers, animated: false)
                        controllers = controllers.filter { controller in
                            if controller is ThemeAccentColorController {
                                return false
                            }
                            return true
                        }
                        navigationController.setViewControllers(controllers, animated: true)
                    }
                }
            }
            strongSelf.pushController(controller)
        })
    }

    public override func loadDisplayNode() {
        var dark = false
        if case .default = self.mode {
            dark = self.presentationData.theme.overallDarkAppearance
        }
        self.displayNode = ThemeColorsGridControllerNode(context: self.context, presentationData: self.presentationData, controller: self, gradients: availableGradients(dark: dark), colors: availableColors(dark: dark), push: { [weak self] controller in
            self?.pushController(controller)
        }, pop: { [weak self] in
            if let strongSelf = self, let navigationController = strongSelf.navigationController as? NavigationController {
                let _ = navigationController.popViewController(animated: true)
            }
        }, presentColorPicker: { [weak self] in
            if let strongSelf = self {
                strongSelf.presentColorPicker()
            }
        })

        self.controllerNode.gridNode.visibleContentOffsetChanged = { [weak self] offset in
            if let strongSelf = self {
                strongSelf.previousContentOffset = offset
            }
        }

        self._ready.set(self.controllerNode.ready.get())


        self.displayNodeDidLoad()
    }

    public override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
    }

    @objc fileprivate func mainButtonPressed() {
        self.dismiss(animated: true)
        self.openGallery?()
    }

    public var requestAttachmentMenuExpansion: () -> Void = {}
    public var updateNavigationStack: (@escaping ([AttachmentContainable]) -> ([AttachmentContainable], AttachmentMediaPickerContext?)) -> Void = { _ in }
    public var parentController: () -> ViewController? = {
        return nil
    }
    public var updateTabBarAlpha: (CGFloat, ContainedViewLayoutTransition) -> Void = { _, _ in }
    public var updateTabBarVisibility: (Bool, ContainedViewLayoutTransition) -> Void = { _, _ in }
    public var cancelPanGesture: () -> Void = { }
    public var isContainerPanning: () -> Bool = { return false }
    public var isContainerExpanded: () -> Bool = { return false }
    public var isMinimized: Bool = false

    public var mediaPickerContext: AttachmentMediaPickerContext? {
        return ThemeColorsGridContext(controller: self)
    }
}

private final class ThemeColorsGridContext: AttachmentMediaPickerContext {
    private weak var controller: ThemeColorsGridController?

    public var mainButtonState: Signal<AttachmentMainButtonState?, NoError> {
        return .single(self.controller?.mainButtonState)
    }

    init(controller: ThemeColorsGridController) {
        self.controller = controller
    }

    func mainButtonAction() {
        self.controller?.mainButtonPressed()
    }
}


public func standaloneColorPickerController(
    context: AccountContext,
    updatedPresentationData: (initial: PresentationData, signal: Signal<PresentationData, NoError>)? = nil,
    peer: EnginePeer,
    push: @escaping (ViewController) -> Void,
    openGallery: @escaping () -> Void
) -> ViewController {
    let controller = AttachmentController(context: context, updatedPresentationData: updatedPresentationData, chatLocation: nil, buttons: [.standalone], initialButton: .standalone, fromMenu: false, hasTextInput: false)
    controller.requestController = { [weak controller] _, present in
        let colorPickerController = ThemeColorsGridController(context: context, mode: .peer(peer))
        colorPickerController.pushController = { controller in
            push(controller)
        }
        colorPickerController.dismissControllers = { [weak controller] in
            controller?.dismiss(animated: true)
        }
        colorPickerController.openGallery = openGallery
        present(colorPickerController, colorPickerController.mediaPickerContext)
        return true
    }
    controller.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .portrait)
    return controller
}
