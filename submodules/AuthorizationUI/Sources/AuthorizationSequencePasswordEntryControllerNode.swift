import Foundation
import LottieSettings
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AuthorizationUtils
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import SolidRoundedButtonNode

final class AuthorizationSequencePasswordEntryControllerNode: ASDisplayNode, UITextFieldDelegate {
    private let strings: PresentationStrings
    private let theme: PresentationTheme
    
    private let animationNode: AnimatedStickerNode
    private let titleNode: ASTextNode
    private let titleActivateAreaNode: AccessibilityAreaNode
    private let noticeNode: ASTextNode
    private let noticeActivateAreaNode: AccessibilityAreaNode
    private let forgotNode: HighlightableButtonNode
    private let resetNode: HighlightableButtonNode
    private let proceedNode: SolidRoundedButtonNode
    
    private let codeField: TextFieldNode
    private let codeSeparatorNode: ASDisplayNode
    private let tellomiFieldBackground = ASDisplayNode()
    
    private var layoutArguments: (ContainerViewLayout, CGFloat)?
    private var tellomiFormScroll: ASScrollNode?
    
    var currentPassword: String {
        return self.codeField.textField.text ?? ""
    }
    
    var loginWithCode: ((String) -> Void)?
    var forgot: (() -> Void)?
    var reset: (() -> Void)?
    
    var didForgotWithNoRecovery = false
    var suggestReset = false
    
    private var clearOnce: Bool = false
    
    var inProgress: Bool = false {
        didSet {
            self.codeField.alpha = self.inProgress ? 0.6 : 1.0
            
            if self.inProgress != oldValue {
                if self.inProgress {
                    self.proceedNode.transitionToProgress()
                } else {
                    self.proceedNode.transitionFromProgress()
                }
            }
        }
    }
    
    private var timer: SwiftSignalKit.Timer?
    
    private let appearanceTimestamp = CACurrentMediaTime()
    
    init(strings: PresentationStrings, theme: PresentationTheme) {
        self.strings = strings
        self.theme = theme
        
        self.animationNode = DefaultAnimatedStickerNodeImpl(lottieSettings: .noAccountFallback)
        self.animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: "IntroPassword"), width: 256, height: 256, playbackMode: .still(.start), mode: .direct(cachePathPrefix: nil))
        
        self.titleNode = ASTextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.displaysAsynchronously = false
        self.titleNode.maximumNumberOfLines = 0
        self.titleNode.attributedText = NSAttributedString(string: tellomiLoginCopy(languageCode: tellomiInterfaceLanguageCode(strings)).cloudPasswordTitle, font: Font.semibold(22.0), textColor: self.theme.list.itemPrimaryTextColor)
        
        self.titleActivateAreaNode = AccessibilityAreaNode()
        self.titleActivateAreaNode.accessibilityTraits = .staticText
        
        self.noticeNode = ASTextNode()
        self.noticeNode.isUserInteractionEnabled = false
        self.noticeNode.displaysAsynchronously = false
        self.noticeNode.maximumNumberOfLines = 0
        self.noticeNode.lineSpacing = 0.1
        self.noticeNode.attributedText = NSAttributedString(string: strings.TwoStepAuth_EnterPasswordHelp, font: Font.regular(17.0), textColor: self.theme.list.itemPrimaryTextColor, paragraphAlignment: .center)
        
        self.noticeActivateAreaNode = AccessibilityAreaNode()
        self.noticeActivateAreaNode.accessibilityTraits = .staticText
        
        self.forgotNode = HighlightableButtonNode()
        self.forgotNode.displaysAsynchronously = false
        self.forgotNode.setAttributedTitle(NSAttributedString(string: self.strings.TwoStepAuth_EnterPasswordForgot, font: Font.regular(16.0), textColor: self.theme.list.itemAccentColor, paragraphAlignment: .center), for: [])
        self.forgotNode.accessibilityLabel = self.strings.TwoStepAuth_EnterPasswordForgot
        self.forgotNode.accessibilityTraits = [.button]
        
        self.resetNode = HighlightableButtonNode()
        self.resetNode.displaysAsynchronously = false
        self.resetNode.setAttributedTitle(NSAttributedString(string: self.strings.LoginPassword_ResetAccount, font: Font.regular(16.0), textColor: self.theme.list.itemDestructiveColor, paragraphAlignment: .center), for: [])
        
        self.codeSeparatorNode = ASDisplayNode()
        self.codeSeparatorNode.isHidden = true
        
        self.codeField = TextFieldNode()
        self.codeField.textField.font = Font.regular(20.0)
        self.codeField.textField.textColor = TellomiLoginChrome.palette(dark: self.theme.overallDarkAppearance).fieldText
        self.codeField.textField.textAlignment = .natural
        self.codeField.textField.isSecureTextEntry = true
        self.codeField.textField.returnKeyType = .done
        self.codeField.textField.keyboardAppearance = self.theme.rootController.keyboardColor.keyboardAppearance
        self.codeField.textField.disableAutomaticKeyboardHandling = [.forward, .backward]
        self.codeField.textField.tintColor = TellomiLoginChrome.palette(dark: self.theme.overallDarkAppearance).accent
        self.codeField.textField.font = Font.regular(17.0)
        self.codeField.textField.accessibilityHint = self.strings.Login_VoiceOver_Password
        
        self.proceedNode = SolidRoundedButtonNode(title: tellomiLoginCopy(languageCode: tellomiInterfaceLanguageCode(strings)).login, theme: TellomiLoginChrome.buttonTheme(dark: theme.overallDarkAppearance), glass: false, height: 50.0, cornerRadius: 25.0)
        self.proceedNode.progressType = .embedded
        self.proceedNode.isEnabled = false
        
        super.init()
        
        self.setViewBlock({
            return UITracingLayerView()
        })
        
        self.backgroundColor = self.theme.list.plainBackgroundColor
        
        self.codeField.textField.delegate = self
        self.codeField.textField.addTarget(self, action: #selector(self.textDidChange), for: .editingChanged)
        
        TellomiLoginChrome.applyField(self.tellomiFieldBackground, dark: theme.overallDarkAppearance)
        self.addSubnode(self.tellomiFieldBackground)
        self.addSubnode(self.codeSeparatorNode)
        self.addSubnode(self.codeField)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.titleActivateAreaNode)
        self.addSubnode(self.forgotNode)
        self.addSubnode(self.resetNode)
        self.addSubnode(self.noticeNode)
        self.addSubnode(self.noticeActivateAreaNode)
        self.addSubnode(self.animationNode)
        self.addSubnode(self.proceedNode)

        let scroll = TellomiLoginChrome.makeFormScroll()
        self.tellomiFormScroll = scroll
        self.addSubnode(scroll)
        for node in [
            self.tellomiFieldBackground,
            self.codeSeparatorNode,
            self.codeField,
            self.titleNode,
            self.titleActivateAreaNode,
            self.forgotNode,
            self.resetNode,
            self.noticeNode,
            self.noticeActivateAreaNode,
            self.animationNode,
            self.proceedNode
        ] {
            node.removeFromSupernode()
            scroll.addSubnode(node)
        }
        
        self.forgotNode.addTarget(self, action: #selector(self.forgotPressed), forControlEvents: .touchUpInside)
        self.resetNode.addTarget(self, action: #selector(self.resetPressed), forControlEvents: .touchUpInside)
        
        self.proceedNode.pressed = { [weak self] in
            if let strongSelf = self {
                strongSelf.loginWithCode?(strongSelf.currentPassword)
            }
        }
        
        self.timer = SwiftSignalKit.Timer(timeout: 7.5, repeat: true, completion: { [weak self] in
            self?.animationNode.playOnce()
        }, queue: Queue.mainQueue())
        self.timer?.start()
    }
    
    deinit {
        self.timer?.invalidate()
    }
    
    func updateData(hint: String, didForgotWithNoRecovery: Bool, suggestReset: Bool) {
        self.didForgotWithNoRecovery = didForgotWithNoRecovery
        self.suggestReset = suggestReset
        self.codeField.textField.attributedPlaceholder = NSAttributedString(string: hint, font: Font.regular(17.0), textColor: TellomiLoginChrome.placeholder)
        if let (layout, navigationHeight) = self.layoutArguments {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .immediate)
        }
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let previousInputHeight = self.layoutArguments?.0.inputHeight ?? 0.0
        let newInputHeight = layout.inputHeight ?? 0.0
        
        self.layoutArguments = (layout, navigationBarHeight)
        
        var layout = layout
        if CACurrentMediaTime() - self.appearanceTimestamp < 2.0, newInputHeight < previousInputHeight {
            layout = layout.withUpdatedInputHeight(previousInputHeight)
        }
        
        // iPhone Duo: beside a side strip the content keeps to the band between the side insets. With equal
        // insets (every other phone) it keeps the full width.
        let insetsDiffer = layout.safeInsets.left != layout.safeInsets.right
        let bandMinX: CGFloat = insetsDiffer ? layout.safeInsets.left : 0.0
        let bandWidth: CGFloat = insetsDiffer ? layout.size.width - layout.safeInsets.left - layout.safeInsets.right : layout.size.width
        
        let inset: CGFloat = 24.0
        let maximumWidth: CGFloat = min(430.0, bandWidth)
        
        // The bottom button spans iPhone Duo's side strip; it keeps clear only of a corner block at the bottom.
        let bottomSideInsets = layout.bottomEdgeSideInsets()
        let bottomBandMinX: CGFloat = insetsDiffer ? bottomSideInsets.left : 0.0
        let bottomBandWidth: CGFloat = insetsDiffer ? layout.size.width - bottomSideInsets.left - bottomSideInsets.right : layout.size.width
        let bottomMaximumWidth: CGFloat = min(430.0, bottomBandWidth)
        
        var insets = layout.insets(options: [])
        insets.top = layout.statusBarHeight ?? 20.0
        if let inputHeight = layout.inputHeight, !inputHeight.isZero {
            insets.bottom = max(inputHeight, insets.bottom)
        }
        
        let titleInset: CGFloat = layout.size.width > 320.0 ? 18.0 : 0.0
        
        let passwordCopy = tellomiCloudPasswordCopy(languageCode: tellomiInterfaceLanguageCode(self.strings))
        self.titleNode.attributedText = NSAttributedString(string: passwordCopy.title, font: TellomiLoginChrome.scaledFont(size: 22.0, weight: .semibold), textColor: self.theme.list.itemPrimaryTextColor)
        self.noticeNode.attributedText = NSAttributedString(string: passwordCopy.notice, font: TellomiLoginChrome.scaledFont(size: 16.0), textColor: TellomiLoginChrome.secondaryText, paragraphAlignment: .center)
        self.forgotNode.setAttributedTitle(NSAttributedString(string: passwordCopy.forgot, font: Font.regular(16.0), textColor: TellomiLoginChrome.palette(dark: self.theme.overallDarkAppearance).link, paragraphAlignment: .center), for: [])
        self.forgotNode.accessibilityLabel = passwordCopy.forgot
        
        let animationSize = CGSize(width: 100.0, height: 100.0)
        let titleSize = self.titleNode.measure(CGSize(width: maximumWidth, height: CGFloat.greatestFiniteMagnitude))
        
        let noticeSize = self.noticeNode.measure(CGSize(width: maximumWidth - 28.0, height: CGFloat.greatestFiniteMagnitude))
        let forgotSize = self.forgotNode.measure(CGSize(width: maximumWidth, height: CGFloat.greatestFiniteMagnitude))
        let resetSize = self.resetNode.measure(CGSize(width: maximumWidth, height: CGFloat.greatestFiniteMagnitude))
        let proceedHeight = self.proceedNode.updateLayout(width: bottomMaximumWidth - inset * 2.0, transition: transition)
        let proceedSize = CGSize(width: bottomMaximumWidth - inset * 2.0, height: proceedHeight)
        
        var items: [AuthorizationLayoutItem] = []
        items.append(AuthorizationLayoutItem(node: self.titleNode, size: titleSize, spacingBefore: AuthorizationLayoutItemSpacing(weight: titleInset, maxValue: titleInset), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        items.append(AuthorizationLayoutItem(node: self.noticeNode, size: noticeSize, spacingBefore: AuthorizationLayoutItemSpacing(weight: 18.0, maxValue: 18.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        
        items.append(AuthorizationLayoutItem(node: self.codeField, size: CGSize(width: maximumWidth - 80.0, height: 52.0), spacingBefore: AuthorizationLayoutItemSpacing(weight: 32.0, maxValue: 60.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        
        items.append(AuthorizationLayoutItem(node: self.forgotNode, size: forgotSize, spacingBefore: AuthorizationLayoutItemSpacing(weight: 48.0, maxValue: 100.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        
        if self.didForgotWithNoRecovery || self.suggestReset {
            self.resetNode.isHidden = false
            items.append(AuthorizationLayoutItem(node: self.resetNode, size: resetSize, spacingBefore: AuthorizationLayoutItemSpacing(weight: 10.0, maxValue: 10.0), spacingAfter: AuthorizationLayoutItemSpacing(weight: 0.0, maxValue: 0.0)))
        } else {
            self.resetNode.isHidden = true
        }
        
        self.animationNode.isHidden = true
        self.animationNode.visibility = false
        self.proceedNode.isHidden = false
        self.animationNode.updateLayout(size: animationSize)

        // Keep the title under the navigation bar. The button stays at the bottom
        // when the column fits above the keyboard; otherwise it follows the fields
        // and the scroll view brings it back into view.
        let pinnedTop = max(insets.top, navigationBarHeight)
        let floatingButtonY = layout.size.height - insets.bottom - proceedSize.height - inset
        let available = floatingButtonY - 16.0 - pinnedTop
        let slack = items.reduce(CGFloat(0.0)) { partial, item in
            partial + item.size.height + item.spacingBefore.maxValue + item.spacingAfter.maxValue
        }
        let _ = layoutAuthorizationItems(bounds: CGRect(origin: CGPoint(x: bandMinX, y: pinnedTop), size: CGSize(width: bandWidth, height: max(available, slack))), items: items, transition: transition, failIfDoesNotFit: false)
        var buttonY = floatingButtonY
        if slack > available + 1.0 {
            var lowest = pinnedTop
            for item in items {
                if let node = item.node, !node.isHidden {
                    lowest = max(lowest, node.frame.maxY)
                }
            }
            buttonY = lowest + 16.0
        }
        transition.updateFrame(node: self.proceedNode, frame: CGRect(origin: CGPoint(x: bottomBandMinX + floorToScreenPixels((bottomBandWidth - proceedSize.width) / 2.0), y: buttonY), size: proceedSize))
        
        self.titleActivateAreaNode.accessibilityLabel = self.titleNode.attributedText?.string ?? ""
        self.noticeActivateAreaNode.accessibilityLabel = self.noticeNode.attributedText?.string ?? ""
        
        self.titleActivateAreaNode.frame = self.titleNode.frame
        self.noticeActivateAreaNode.frame = self.noticeNode.frame
        let fieldFrame = CGRect(x: bandMinX + 24.0, y: self.codeField.frame.minY, width: max(0.0, bandWidth - 48.0), height: max(self.codeField.frame.height, 52.0))
        self.tellomiFieldBackground.frame = fieldFrame
        self.codeField.frame = fieldFrame.insetBy(dx: 16.0, dy: 0.0)
        self.proceedNode.title = tellomiLoginCopy(languageCode: tellomiInterfaceLanguageCode(self.strings)).login
        self.tellomiUpdateFormScroll(layout: layout, bottomInset: insets.bottom)
    }

    private func tellomiUpdateFormScroll(layout: ContainerViewLayout, bottomInset: CGFloat) {
        guard let scroll = self.tellomiFormScroll else {
            return
        }
        var contentBottom: CGFloat = 0.0
        for node in scroll.subnodes ?? [] {
            if node.isHidden {
                continue
            }
            contentBottom = max(contentBottom, node.frame.maxY)
        }
        TellomiLoginChrome.applyFormScroll(scroll, layoutSize: layout.size, bottomInset: bottomInset, contentBottom: contentBottom + 16.0)
    }
    
    func activateInput() {
        self.codeField.textField.becomeFirstResponder()
    }
    
    func animateError() {
        self.codeField.layer.addShakeAnimation()
    }
    
    func passwordIsInvalid() {
        self.clearOnce = true
    }
    
    @objc func textDidChange() {
        self.proceedNode.isEnabled = !(self.codeField.textField.text ?? "").isEmpty
    }
        
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if self.clearOnce {
            self.clearOnce = false
            if range.length > string.count {
                textField.text = ""
                return false
            }
        }
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.loginWithCode?(self.currentPassword)
        return false
    }
    
    @objc func forgotPressed() {
        self.forgot?()
    }
    
    @objc func resetPressed() {
        self.reset?()
    }
}
