import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SolidRoundedButtonNode
import TelegramPresentationData

func tellomiSymbol(_ name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight = .regular) -> UIImage? {
    let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    return UIImage(systemName: name, withConfiguration: configuration)
}

func tellomiCheckboxImage(checked: Bool, dark: Bool = false) -> UIImage? {
    let diameter: CGFloat = 18.0
    let palette = TellomiLoginChrome.palette(dark: dark)
    return generateImage(CGSize(width: diameter, height: diameter), rotatedContext: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        let rect = CGRect(x: 1.0, y: 1.0, width: size.width - 2.0, height: size.height - 2.0)
        if checked {
            context.setFillColor(palette.checkbox.cgColor)
            context.fillEllipse(in: rect)
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(1.6)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: CGPoint(x: 5.0, y: 9.2))
            context.addLine(to: CGPoint(x: 7.6, y: 12.0))
            context.addLine(to: CGPoint(x: 13.0, y: 6.2))
            context.strokePath()
        } else {
            context.setStrokeColor(UIColor(rgb: 0xC7C7CC).cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: rect.insetBy(dx: 0.5, dy: 0.5))
        }
    })
}

func tellomiGoogleMark(side: CGFloat) -> UIImage? {
    return generateImage(CGSize(width: side, height: side), rotatedContext: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        let radius = size.width * 0.36
        let width = size.width * 0.16
        context.setLineWidth(width)
        context.setLineCap(.butt)
        let colors: [(UIColor, CGFloat, CGFloat)] = [
            (UIColor(rgb: 0x4285F4), -.pi / 5.0, .pi * 0.55),
            (UIColor(rgb: 0x34A853), .pi * 0.55, .pi),
            (UIColor(rgb: 0xFBBC05), .pi, .pi * 1.38),
            (UIColor(rgb: 0xEA4335), .pi * 1.38, .pi * 1.8)
        ]
        for (color, start, end) in colors {
            context.setStrokeColor(color.cgColor)
            context.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            context.strokePath()
        }
        context.setStrokeColor(UIColor(rgb: 0x4285F4).cgColor)
        context.setLineWidth(width)
        context.setLineCap(.butt)
        let barY = center.y
        context.move(to: CGPoint(x: center.x, y: barY))
        context.addLine(to: CGPoint(x: center.x + radius + width * 0.15, y: barY))
        context.strokePath()
    })
}

func tellomiDotsImage(side: CGFloat) -> UIImage? {
    return generateImage(CGSize(width: side, height: side), rotatedContext: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        context.setFillColor(UIColor(rgb: 0x111111).cgColor)
        let dot: CGFloat = 3.2
        let y = (size.height - dot) / 2.0
        let gap: CGFloat = 5.0
        let total = dot * 3.0 + gap * 2.0
        var x = (size.width - total) / 2.0
        for _ in 0 ..< 3 {
            context.fillEllipse(in: CGRect(x: x, y: y, width: dot, height: dot))
            x += dot + gap
        }
    })
}

/// Circle plus the agreement sentence. The circle is a 44pt control, so the
/// checkbox is tappable without relying on glyph hit-testing.
final class TellomiAgreementRow: ASDisplayNode {
    let textNode: ImmediateTextNode
    private let checkbox = ASImageNode()
    private let checkboxButton = HighlightableButtonNode()
    var onToggle: (() -> Void)?
    private var centered = false
    private var measuredText = CGSize()
    private var dark = false
    private var checked = false

    init(textNode: ImmediateTextNode) {
        self.textNode = textNode
        super.init()
        self.checkbox.image = tellomiCheckboxImage(checked: false)
        self.checkbox.isUserInteractionEnabled = false
        self.checkboxButton.accessibilityTraits = [.button]
        self.checkboxButton.accessibilityIdentifier = "Auth.Agreement.Checkbox"
        self.addSubnode(self.textNode)
        self.addSubnode(self.checkbox)
        self.addSubnode(self.checkboxButton)
        self.checkboxButton.addTarget(self, action: #selector(self.checkboxPressed), forControlEvents: .touchUpInside)
    }

    func setChecked(_ checked: Bool) {
        self.checked = checked
        self.checkbox.image = tellomiCheckboxImage(checked: checked, dark: self.dark)
        self.checkboxButton.accessibilityValue = checked ? "1" : "0"
    }

    func setDark(_ dark: Bool) {
        self.dark = dark
        self.setChecked(self.checked)
    }

    func updateLayout(width: CGFloat, centered: Bool) -> CGSize {
        self.centered = centered
        let box: CGFloat = 18.0
        let gap: CGFloat = 8.0
        let textWidth = max(0.0, width - box - gap)
        let textSize = self.textNode.updateLayout(CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude))
        self.measuredText = textSize
        let height = max(44.0, textSize.height + 16.0)
        return CGSize(width: width, height: height)
    }

    @objc private func checkboxPressed() {
        self.onToggle?()
    }

    override func layout() {
        super.layout()
        let box: CGFloat = 18.0
        let gap: CGFloat = 8.0
        let textY: CGFloat = 13.0
        let measured = self.measuredText.width > 0.0 ? self.measuredText : CGSize(width: max(0.0, self.bounds.width - box - gap), height: max(0.0, self.bounds.height - textY))
        let groupWidth = box + gap + measured.width
        let originX: CGFloat
        if self.centered {
            originX = max(0.0, floor((self.bounds.width - groupWidth) / 2.0))
        } else {
            originX = 0.0
        }
        let boxY = textY + 1.0
        self.checkbox.frame = CGRect(x: originX, y: boxY, width: box, height: box)
        self.checkboxButton.frame = CGRect(x: max(0.0, originX - 13.0), y: 0.0, width: 44.0, height: 44.0)
        self.textNode.frame = CGRect(x: originX + box + gap, y: textY, width: measured.width, height: max(measured.height, 22.0))
    }
}

final class TellomiSocialRowNode: HighlightableButtonNode {
    private let iconNode = ASImageNode()
    /// Not `titleNode`: `ASButtonNode` already has that property, and a stored override does not compile.
    private let labelNode = ImmediateTextNode()

    init(title: String, icon: UIImage?, dark: Bool = false) {
        super.init()
        let palette = TellomiLoginChrome.palette(dark: dark)
        self.backgroundColor = palette.rowBackground
        self.cornerRadius = 12.0
        self.borderWidth = 1.0
        self.borderColor = palette.rowBorder.cgColor
        self.clipsToBounds = true
        self.iconNode.image = icon
        self.iconNode.contentMode = .scaleAspectFit
        self.iconNode.isUserInteractionEnabled = false
        self.labelNode.attributedText = NSAttributedString(string: title, font: Font.regular(16.0), textColor: palette.rowText)
        self.labelNode.isUserInteractionEnabled = false
        self.accessibilityLabel = title
        self.accessibilityTraits = [.button]
        self.addSubnode(self.iconNode)
        self.addSubnode(self.labelNode)
    }

    func applyPalette(dark: Bool) {
        let palette = TellomiLoginChrome.palette(dark: dark)
        self.backgroundColor = palette.rowBackground
        self.borderColor = palette.rowBorder.cgColor
        if let title = self.accessibilityLabel {
            self.labelNode.attributedText = NSAttributedString(string: title, font: Font.regular(16.0), textColor: palette.rowText)
        }
    }

    override func layout() {
        super.layout()
        let maxSide: CGFloat = 22.0
        let imageSize = self.iconNode.image?.size ?? CGSize(width: maxSide, height: maxSide)
        let scale = min(maxSide / max(imageSize.width, 1.0), maxSide / max(imageSize.height, 1.0))
        let iconSize = CGSize(width: floor(imageSize.width * scale), height: floor(imageSize.height * scale))
        self.iconNode.frame = CGRect(x: 16.0 + (maxSide - iconSize.width) / 2.0, y: floor((self.bounds.height - iconSize.height) / 2.0), width: iconSize.width, height: iconSize.height)
        let titleSize = self.labelNode.updateLayout(CGSize(width: self.bounds.width - 80.0, height: self.bounds.height))
        self.labelNode.frame = CGRect(x: floor((self.bounds.width - titleSize.width) / 2.0), y: floor((self.bounds.height - titleSize.height) / 2.0), width: titleSize.width, height: titleSize.height)
    }
}

final class TellomiCircleButtonNode: HighlightableButtonNode {
    private let iconNode = ASImageNode()

    init(icon: UIImage?, accessibilityLabel: String) {
        super.init()
        let palette = TellomiLoginChrome.palette(dark: false)
        self.backgroundColor = palette.rowBackground
        self.cornerRadius = 26.0
        self.borderWidth = 1.0
        self.borderColor = palette.rowBorder.cgColor
        self.clipsToBounds = true
        self.iconNode.image = icon
        self.iconNode.contentMode = .scaleAspectFit
        self.iconNode.isUserInteractionEnabled = false
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityTraits = [.button]
        self.addSubnode(self.iconNode)
    }

    override func layout() {
        super.layout()
        let maxSide: CGFloat = 22.0
        let imageSize = self.iconNode.image?.size ?? CGSize(width: maxSide, height: maxSide)
        let scale = min(maxSide / max(imageSize.width, 1.0), maxSide / max(imageSize.height, 1.0))
        let iconSize = CGSize(width: floor(imageSize.width * scale), height: floor(imageSize.height * scale))
        self.iconNode.frame = CGRect(x: floor((self.bounds.width - iconSize.width) / 2.0), y: floor((self.bounds.height - iconSize.height) / 2.0), width: iconSize.width, height: iconSize.height)
    }
}

final class TellomiOrDividerNode: ASDisplayNode {
    private let left = ASDisplayNode()
    private let right = ASDisplayNode()
    private let label = ImmediateTextNode()

    override init() {
        super.init()
        self.left.backgroundColor = UIColor(rgb: 0xE6E6E6)
        self.right.backgroundColor = UIColor(rgb: 0xE6E6E6)
        self.isUserInteractionEnabled = false
        self.addSubnode(self.left)
        self.addSubnode(self.right)
        self.addSubnode(self.label)
    }

    func setTitle(_ title: String) {
        self.label.attributedText = NSAttributedString(string: title, font: Font.regular(13.0), textColor: TellomiLoginChrome.secondaryText)
    }

    override func layout() {
        super.layout()
        let labelSize = self.label.updateLayout(CGSize(width: 80.0, height: self.bounds.height))
        let labelFrame = CGRect(x: floor((self.bounds.width - labelSize.width) / 2.0), y: floor((self.bounds.height - labelSize.height) / 2.0), width: labelSize.width, height: labelSize.height)
        self.label.frame = labelFrame
        let y = floor(self.bounds.height / 2.0)
        self.left.frame = CGRect(x: 0.0, y: y, width: max(0.0, labelFrame.minX - 12.0), height: UIScreenPixel)
        self.right.frame = CGRect(x: labelFrame.maxX + 12.0, y: y, width: max(0.0, self.bounds.width - labelFrame.maxX - 12.0), height: UIScreenPixel)
    }
}

/// Password row. Phone login puts the eye on the left; email login puts it on the right.
final class TellomiPasswordFieldNode: ASDisplayNode, UITextFieldDelegate {
    let textField: TextFieldNode
    private let backgroundNode = ASDisplayNode()
    private let divider = ASDisplayNode()
    private let eyeButton = HighlightableButtonNode()
    private var eyeOnLeft: Bool
    var textChanged: ((String) -> Void)?
    var returnPressed: (() -> Void)?

    var text: String {
        return self.textField.textField.text ?? ""
    }

    init(theme: PresentationTheme, placeholder: String, eyeOnLeft: Bool) {
        self.eyeOnLeft = eyeOnLeft
        self.textField = TextFieldNode()
        super.init()

        self.textField.textField.font = Font.regular(17.0)
        self.textField.textField.textColor = TellomiLoginChrome.palette(dark: theme.overallDarkAppearance).fieldText
        self.textField.textField.autocorrectionType = .no
        self.textField.textField.autocapitalizationType = .none
        self.textField.textField.isSecureTextEntry = true
        self.textField.textField.returnKeyType = .done
        self.textField.textField.keyboardAppearance = theme.rootController.keyboardColor.keyboardAppearance
        self.textField.textField.tintColor = TellomiLoginChrome.accent
        self.textField.textField.disableAutomaticKeyboardHandling = [.forward, .backward]
        self.textField.textField.accessibilityIdentifier = "Auth.PhoneEntry.PasswordField"
        if #available(iOSApplicationExtension 12.0, iOS 12.0, *) {
            self.textField.textField.textContentType = .password
        }
        self.setPlaceholder(placeholder)

        TellomiLoginChrome.applyField(self.backgroundNode, dark: theme.overallDarkAppearance)
        self.divider.backgroundColor = UIColor(rgb: 0xE4E4E7)
        self.divider.isHidden = !eyeOnLeft
        self.eyeButton.accessibilityLabel = placeholder
        self.eyeButton.accessibilityTraits = [.button]
        self.updateEye()

        self.textField.textField.delegate = self
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.divider)
        self.addSubnode(self.textField)
        self.addSubnode(self.eyeButton)
        self.textField.textField.addTarget(self, action: #selector(self.editingChanged), for: .editingChanged)
        self.eyeButton.addTarget(self, action: #selector(self.eyePressed), forControlEvents: .touchUpInside)
    }

    func setEyeOnLeft(_ eyeOnLeft: Bool) {
        guard self.eyeOnLeft != eyeOnLeft else {
            return
        }
        self.eyeOnLeft = eyeOnLeft
        if !self.bounds.isEmpty {
            self.layout()
        }
    }

    func setPlaceholder(_ placeholder: String) {
        self.textField.textField.attributedPlaceholder = NSAttributedString(string: placeholder, font: Font.regular(17.0), textColor: TellomiLoginChrome.placeholder)
    }

    func applyPalette(dark: Bool, theme: PresentationTheme) {
        let palette = TellomiLoginChrome.palette(dark: dark)
        self.textField.textField.textColor = palette.fieldText
        self.textField.textField.tintColor = palette.accent
        self.textField.textField.keyboardAppearance = theme.rootController.keyboardColor.keyboardAppearance
        TellomiLoginChrome.applyField(self.backgroundNode, dark: dark)
        let placeholder = self.textField.textField.placeholder ?? self.textField.textField.attributedPlaceholder?.string ?? ""
        self.textField.textField.attributedPlaceholder = NSAttributedString(string: placeholder, font: Font.regular(17.0), textColor: palette.placeholder)
        self.updateEye()
    }

    @objc private func editingChanged() {
        self.textChanged?(self.text)
    }

    @objc private func eyePressed() {
        self.textField.textField.isSecureTextEntry = !self.textField.textField.isSecureTextEntry
        self.updateEye()
    }

    private func updateEye() {
        let name = self.textField.textField.isSecureTextEntry ? "eye.slash" : "eye"
        let image = tellomiSymbol(name, pointSize: 16.0)?.withTintColor(TellomiLoginChrome.secondaryText, renderingMode: .alwaysOriginal)
        self.eyeButton.setImage(image, for: .normal)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.returnPressed?()
        return false
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 24.0
        let size = self.bounds.size
        let fieldHeight: CGFloat = 52.0
        let fieldFrame = CGRect(x: inset, y: floor((size.height - fieldHeight) / 2.0), width: max(0.0, size.width - inset * 2.0), height: fieldHeight)
        self.backgroundNode.frame = fieldFrame
        let eyeSide: CGFloat = 44.0
        if self.eyeOnLeft {
            // Same column as the phone field's country code, so the password text
            // starts where the phone number starts. The eye stays 44pt so the glyph is not stretched.
            let codeColumn: CGFloat = 78.0
            self.eyeButton.frame = CGRect(x: fieldFrame.minX + floor((codeColumn - eyeSide) / 2.0), y: fieldFrame.minY, width: eyeSide, height: fieldHeight)
            self.divider.isHidden = false
            self.divider.frame = CGRect(x: fieldFrame.minX + codeColumn, y: fieldFrame.minY + 16.0, width: UIScreenPixel, height: fieldHeight - 32.0)
            self.textField.frame = CGRect(x: fieldFrame.minX + codeColumn + 12.0, y: fieldFrame.minY, width: max(0.0, fieldFrame.width - codeColumn - 24.0), height: fieldHeight)
        } else {
            self.divider.isHidden = true
            self.eyeButton.frame = CGRect(x: fieldFrame.maxX - eyeSide, y: fieldFrame.minY, width: eyeSide, height: fieldHeight)
            self.textField.frame = CGRect(x: fieldFrame.minX + 16.0, y: fieldFrame.minY, width: max(0.0, fieldFrame.width - eyeSide - 16.0), height: fieldHeight)
        }
    }
}

final class TellomiAgreementPromptController: ViewController {
    private let kind: TellomiSignUpAgreement.Kind
    private let chinese: Bool
    private let openUrl: (String) -> Void
    var agreed: (() -> Void)?

    init(kind: TellomiSignUpAgreement.Kind, chinese: Bool, openUrl: @escaping (String) -> Void) {
        self.kind = kind
        self.chinese = chinese
        self.openUrl = openUrl
        super.init(navigationBarPresentationData: nil)
        self.statusBar.statusBarStyle = .Ignore
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = TellomiAgreementPromptNode(kind: self.kind, chinese: self.chinese, openUrl: { [weak self] url in
            self?.openUrl(url)
        }, agree: { [weak self] in
            self?.agreed?()
            self?.dismiss()
        }, dismiss: { [weak self] in
            self?.dismiss()
        })
        self.displayNodeDidLoad()
    }
}

private final class TellomiAgreementPromptNode: ASDisplayNode {
    private let dimNode = ASDisplayNode()
    private let cardNode = ASDisplayNode()
    private let titleNode = ImmediateTextNode()
    private let bodyNode = ImmediateTextNode()
    private let agreeButton: SolidRoundedButtonNode
    private let declineNode = HighlightableButtonNode()
    private let agreement = TellomiSignUpAgreement()
    private let dismissPrompt: () -> Void

    init(kind: TellomiSignUpAgreement.Kind, chinese: Bool, openUrl: @escaping (String) -> Void, agree: @escaping () -> Void, dismiss: @escaping () -> Void) {
        self.dismissPrompt = dismiss
        let copy = tellomiLoginCopy(languageCode: chinese ? "zh" : "en")
        self.agreeButton = SolidRoundedButtonNode(title: copy.agreeAndLogin, theme: TellomiLoginChrome.buttonTheme(), glass: false, height: 48.0, cornerRadius: 24.0)
        super.init()

        self.dimNode.backgroundColor = UIColor(white: 0.0, alpha: 0.45)
        self.cardNode.backgroundColor = .white
        self.cardNode.cornerRadius = 16.0
        self.cardNode.clipsToBounds = true

        self.titleNode.attributedText = NSAttributedString(string: copy.agreementTitle, font: Font.semibold(17.0), textColor: UIColor(rgb: 0x111111), paragraphAlignment: .center)
        self.titleNode.maximumNumberOfLines = 0
        self.titleNode.displaysAsynchronously = false

        self.bodyNode.maximumNumberOfLines = 0
        self.bodyNode.displaysAsynchronously = false
        self.bodyNode.isUserInteractionEnabled = true
        self.bodyNode.linkHighlightColor = TellomiLoginChrome.link.withAlphaComponent(0.15)
        self.agreement.install(on: self.bodyNode, theme: defaultPresentationTheme, kind: kind, chinese: chinese, togglesOnText: false, centered: true, openUrl: openUrl, changed: { _ in })

        self.declineNode.setTitle(copy.disagree, with: Font.regular(15.0), with: TellomiLoginChrome.secondaryText, for: .normal)
        self.declineNode.accessibilityTraits = [.button]
        self.agreeButton.pressed = { agree() }
        self.declineNode.addTarget(self, action: #selector(self.declinePressed), forControlEvents: .touchUpInside)

        self.addSubnode(self.dimNode)
        self.addSubnode(self.cardNode)
        self.cardNode.addSubnode(self.titleNode)
        self.cardNode.addSubnode(self.bodyNode)
        self.cardNode.addSubnode(self.agreeButton)
        self.cardNode.addSubnode(self.declineNode)
    }

    @objc private func declinePressed() {
        self.dismissPrompt()
    }

    override func didLoad() {
        super.didLoad()
        self.dimNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.declinePressed)))
    }

    override func layout() {
        super.layout()
        self.dimNode.frame = self.bounds
        let cardWidth = min(320.0, self.bounds.width - 48.0)
        let inner = cardWidth - 40.0
        let titleSize = self.titleNode.updateLayout(CGSize(width: inner, height: 60.0))
        let bodySize = self.bodyNode.updateLayout(CGSize(width: inner, height: 160.0))
        let buttonHeight = self.agreeButton.updateLayout(width: inner, transition: .immediate)
        let declineHeight: CGFloat = 36.0
        let cardHeight = 22.0 + titleSize.height + 14.0 + bodySize.height + 18.0 + buttonHeight + 8.0 + declineHeight + 12.0
        let cardFrame = CGRect(x: floor((self.bounds.width - cardWidth) / 2.0), y: floor((self.bounds.height - cardHeight) / 2.0), width: cardWidth, height: cardHeight)
        self.cardNode.frame = cardFrame
        var y: CGFloat = 22.0
        self.titleNode.frame = CGRect(x: 20.0, y: y, width: inner, height: titleSize.height)
        y += titleSize.height + 14.0
        self.bodyNode.frame = CGRect(x: 20.0, y: y, width: inner, height: bodySize.height)
        y += bodySize.height + 18.0
        self.agreeButton.frame = CGRect(x: 20.0, y: y, width: inner, height: buttonHeight)
        y += buttonHeight + 8.0
        self.declineNode.frame = CGRect(x: 20.0, y: y, width: inner, height: declineHeight)
    }
}
