import Foundation
import UIKit
import SafariServices
import AsyncDisplayKit
import Display
import SolidRoundedButtonNode
import TelegramPresentationData
import TextFormat

func tellomiDisclosureChevron(color: UIColor) -> UIImage? {
    return generateImage(CGSize(width: 10.0, height: 6.0), rotatedContext: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        context.setFillColor(color.cgColor)
        context.move(to: CGPoint())
        context.addLine(to: CGPoint(x: size.width, y: 0.0))
        context.addLine(to: CGPoint(x: size.width / 2.0, y: size.height))
        context.closePath()
        context.fillPath()
    })
}

func tellomiSymbol(_ name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight = .regular) -> UIImage? {
    let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    return UIImage(systemName: name, withConfiguration: configuration)
}

/// Drawn size of the agreement circle. The control around it stays 44pt.
let tellomiCheckboxSide: CGFloat = 22.0

func tellomiCheckboxImage(checked: Bool, palette: TellomiLoginChrome.Palette) -> UIImage? {
    let diameter = tellomiCheckboxSide
    return generateImage(CGSize(width: diameter, height: diameter), rotatedContext: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        let rect = CGRect(x: 1.0, y: 1.0, width: size.width - 2.0, height: size.height - 2.0)
        if checked {
            context.setFillColor(palette.checkbox.cgColor)
            context.fillEllipse(in: rect)
            context.setStrokeColor(palette.checkboxTick.cgColor)
            context.setLineWidth(2.0)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            let scale = diameter / 18.0
            context.move(to: CGPoint(x: 5.0 * scale, y: 9.2 * scale))
            context.addLine(to: CGPoint(x: 7.6 * scale, y: 12.0 * scale))
            context.addLine(to: CGPoint(x: 13.0 * scale, y: 6.2 * scale))
            context.strokePath()
        } else {
            context.setStrokeColor(palette.checkboxStroke.cgColor)
            context.setLineWidth(2.0)
            context.strokeEllipse(in: rect.insetBy(dx: 0.75, dy: 0.75))
        }
    })
}

func tellomiCheckboxImage(checked: Bool, dark: Bool = false) -> UIImage? {
    return tellomiCheckboxImage(checked: checked, palette: TellomiLoginChrome.palette(dark: dark))
}

func tellomiMailIcon(dark: Bool) -> UIImage? {
    return tellomiMailIcon(palette: TellomiLoginChrome.palette(dark: dark))
}

func tellomiMailIcon(theme: PresentationTheme) -> UIImage? {
    return tellomiMailIcon(palette: TellomiLoginChrome.palette(theme: theme))
}

func tellomiMailIcon(palette: TellomiLoginChrome.Palette) -> UIImage? {
    return tellomiSymbol("envelope", pointSize: 16.0)?.withTintColor(palette.rowText, renderingMode: .alwaysOriginal)
}

/// Circle plus the agreement sentence. The circle is a 44pt control, so the
/// checkbox is tappable without relying on glyph hit-testing.
final class TellomiAgreementRow: ASDisplayNode {
    let textNode: ImmediateTextNode
    /// Visible sentence. TextNode truncates this line (ellipsis, empty accessibility label) even with an unlimited line count.
    private let label = UILabel()
    private let checkbox = ASImageNode()
    private let checkboxButton = HighlightableButtonNode()
    var onToggle: (() -> Void)?
    var onLink: ((String) -> Void)?
    /// Fired when `layout()` finds the row is shorter than the wrapped text, so the parent can grow the frame.
    var onPreferredHeight: ((CGFloat) -> Void)?
    private var centered = false
    private var measuredText = CGSize()
    private var dark = false
    private var palette = TellomiLoginChrome.palette(dark: false)
    private var checked = false
    private var labelTapInstalled = false
    private var reportingHeight = false

    init(textNode: ImmediateTextNode) {
        self.textNode = textNode
        super.init()
        self.label.numberOfLines = 0
        self.label.lineBreakMode = .byWordWrapping
        self.label.backgroundColor = .clear
        self.clipsToBounds = false
        self.label.isUserInteractionEnabled = true
        self.label.isAccessibilityElement = true
        self.label.accessibilityTraits = .staticText
        self.label.accessibilityIdentifier = "Auth.Login.Agreement"
        self.checkbox.image = tellomiCheckboxImage(checked: false, palette: self.palette)
        self.checkbox.isUserInteractionEnabled = false
        self.checkboxButton.accessibilityTraits = [.button]
        self.checkboxButton.accessibilityIdentifier = "Auth.Agreement.Checkbox"
        self.textNode.isHidden = true
        self.textNode.isAccessibilityElement = false
        self.addSubnode(self.textNode)
        self.addSubnode(self.checkbox)
        self.addSubnode(self.checkboxButton)
        self.checkboxButton.addTarget(self, action: #selector(self.checkboxPressed), forControlEvents: .touchUpInside)
        self.isAccessibilityElement = false
    }

    func setChecked(_ checked: Bool) {
        self.checked = checked
        self.checkbox.image = tellomiCheckboxImage(checked: checked, palette: self.palette)
        self.checkboxButton.accessibilityValue = checked ? "1" : "0"
    }

    func setDark(_ dark: Bool) {
        self.dark = dark
        self.palette = TellomiLoginChrome.palette(dark: dark)
        self.setChecked(self.checked)
    }

    func apply(theme: PresentationTheme) {
        self.dark = theme.overallDarkAppearance
        self.palette = TellomiLoginChrome.palette(theme: theme)
        self.setChecked(self.checked)
    }

    func updateLayout(width: CGFloat, centered: Bool) -> CGSize {
        self.centered = centered
        self.textNode.isHidden = true
        self.textNode.isAccessibilityElement = false
        let measured = self.measureText(rowWidth: width)
        self.measuredText = measured
        // Apply here, not only from layout(). Switching language keeps the row frame the same
        // when both sentences are one line, so layout() would not run and the label would
        // stay at the previous string's width.
        self.placeContents(rowWidth: width, measured: measured)
        return CGSize(width: width, height: self.rowHeight(for: measured))
    }

    /// Wrapped size at the width the row actually has: the row minus the checkbox and the gap.
    /// The label always occupies that full width when the sentence wraps, so a later layout pass
    /// cannot shrink it back to the first line.
    private func measureText(rowWidth: CGFloat) -> CGSize {
        let textWidth = self.textWidth(in: rowWidth)
        let text = self.wrappingText(self.textNode.attributedText ?? NSAttributedString())
        guard text.length > 0, textWidth > 1.0 else {
            return CGSize(width: textWidth, height: 18.0)
        }
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0.0
        container.lineBreakMode = .byWordWrapping
        container.maximumNumberOfLines = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let height = ceil(max(used.height, 18.0))
        // Always the row's text column, never the previous string's intrinsic width.
        // A Chinese one-line measure (about 205pt) must not stay in place after switching to English.
        return CGSize(width: textWidth, height: height)
    }

    private func textWidth(in rowWidth: CGFloat) -> CGFloat {
        return max(1.0, rowWidth - tellomiCheckboxSide - 8.0)
    }

    private func rowHeight(for text: CGSize) -> CGFloat {
        return max(44.0, text.height + 16.0)
    }

    private func wrappingText(_ source: NSAttributedString) -> NSAttributedString {
        let text = NSMutableAttributedString(attributedString: source)
        guard text.length > 0 else {
            return text
        }
        let paragraph = (text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        return text
    }

    private func applyLabelText() {
        let text = self.wrappingText(self.textNode.attributedText ?? NSAttributedString())
        self.label.numberOfLines = 0
        self.label.lineBreakMode = .byWordWrapping
        self.label.attributedText = text
        self.label.lineBreakMode = .byWordWrapping
        self.label.numberOfLines = 0
        let plain = text.string
        self.label.accessibilityLabel = plain
        self.accessibilityLabel = plain
    }

    @objc private func checkboxPressed() {
        self.onToggle?()
    }

    @objc private func labelTapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else {
            return
        }
        let point = gesture.location(in: self.label)
        if let url = self.linkURL(at: point), !url.isEmpty {
            self.onLink?(url)
        } else {
            self.onToggle?()
        }
    }

    private func linkURL(at point: CGPoint) -> String? {
        guard let text = self.label.attributedText, text.length > 0, self.label.bounds.width > 0.0 else {
            return nil
        }
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: self.label.bounds.width, height: max(self.label.bounds.height, 10000.0)))
        container.lineFragmentPadding = 0.0
        container.lineBreakMode = .byWordWrapping
        container.maximumNumberOfLines = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        let glyphIndex = manager.glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: nil)
        let glyphRect = manager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
        guard glyphRect.insetBy(dx: -8.0, dy: -8.0).contains(point) else {
            return nil
        }
        let characterIndex = manager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex >= 0, characterIndex < text.length else {
            return nil
        }
        return text.attribute(NSAttributedString.Key(rawValue: TelegramTextAttributes.URL), at: characterIndex, effectiveRange: nil) as? String
    }

    private func installLabelIfNeeded() {
        guard self.isNodeLoaded, self.label.superview == nil else {
            return
        }
        self.view.addSubview(self.label)
        if !self.labelTapInstalled {
            self.label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.labelTapped(_:))))
            self.labelTapInstalled = true
        }
    }

    override func didLoad() {
        super.didLoad()
        self.installLabelIfNeeded()
    }

    override func layout() {
        super.layout()
        self.installLabelIfNeeded()
        let rowWidth = self.bounds.width > 1.0 ? self.bounds.width : (self.measuredText.width + tellomiCheckboxSide + 8.0)
        let measured = self.measureText(rowWidth: rowWidth)
        self.measuredText = measured
        let needed = self.rowHeight(for: measured)
        if !self.reportingHeight, self.bounds.height > 1.0, needed > self.bounds.height + 1.0 {
            self.reportingHeight = true
            self.onPreferredHeight?(needed)
            self.reportingHeight = false
        }
        self.placeContents(rowWidth: rowWidth, measured: measured)
    }

    private func placeContents(rowWidth: CGFloat, measured: CGSize) {
        self.installLabelIfNeeded()
        self.applyLabelText()
        let box = tellomiCheckboxSide
        let gap: CGFloat = 8.0
        let textY: CGFloat = 13.0
        let textWidth = self.textWidth(in: rowWidth)
        self.label.preferredMaxLayoutWidth = textWidth
        self.label.numberOfLines = 0
        self.label.lineBreakMode = .byWordWrapping
        let originX: CGFloat = 0.0
        let boxY = textY + 1.0
        self.checkbox.frame = CGRect(x: originX, y: boxY, width: box, height: box)
        self.checkboxButton.frame = CGRect(x: max(0.0, originX - 13.0), y: 0.0, width: 44.0, height: 44.0)
        let textFrame = CGRect(x: originX + box + gap, y: textY, width: textWidth, height: max(measured.height, 22.0))
        self.label.frame = textFrame
        self.textNode.frame = textFrame
        if self.isNodeLoaded {
            self.view.bringSubviewToFront(self.checkbox.view)
            self.view.bringSubviewToFront(self.checkboxButton.view)
        }
    }
}

extension ViewController {
    /// Agreement links stay inside the login flow. `applicationBindings.openUrl` hands them to Safari.
    func tellomiPresentLegalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }
        let safari = SFSafariViewController(url: url)
        self.present(safari, animated: true)
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

    func setTitle(_ title: String, dark: Bool) {
        let palette = TellomiLoginChrome.palette(dark: dark)
        self.labelNode.attributedText = NSAttributedString(string: title, font: Font.regular(16.0), textColor: palette.rowText)
        self.accessibilityLabel = title
        self.setNeedsLayout()
    }

    func applyPalette(dark: Bool) {
        self.apply(palette: TellomiLoginChrome.palette(dark: dark))
    }

    func apply(theme: PresentationTheme) {
        self.apply(palette: TellomiLoginChrome.palette(theme: theme))
    }

    private func apply(palette: TellomiLoginChrome.Palette) {
        self.backgroundColor = palette.rowBackground
        self.borderColor = palette.rowBorder.cgColor
        if let title = self.accessibilityLabel {
            self.labelNode.attributedText = NSAttributedString(string: title, font: Font.regular(16.0), textColor: palette.rowText)
        }
    }

    func setIcon(_ icon: UIImage?) {
        self.iconNode.image = icon
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
        let existing = self.label.attributedText.flatMap { text -> UIColor? in
            guard text.length > 0 else {
                return nil
            }
            return text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        }
        self.setTitle(title, color: existing ?? TellomiLoginChrome.palette(dark: false).secondaryText)
    }

    func setTitle(_ title: String, color: UIColor) {
        self.label.attributedText = NSAttributedString(string: title, font: Font.regular(13.0), textColor: color)
        self.isAccessibilityElement = true
        self.accessibilityLabel = title
        self.accessibilityTraits = [.staticText]
    }

    func applyPalette(dark: Bool) {
        self.apply(palette: TellomiLoginChrome.palette(dark: dark))
    }

    func apply(theme: PresentationTheme) {
        self.apply(palette: TellomiLoginChrome.palette(theme: theme))
    }

    private func apply(palette: TellomiLoginChrome.Palette) {
        self.left.backgroundColor = palette.rowBorder
        self.right.backgroundColor = palette.rowBorder
        if let title = self.accessibilityLabel {
            self.setTitle(title, color: palette.secondaryText)
        }
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

final class TellomiAgreementPromptController: ViewController {
    private let kind: TellomiSignUpAgreement.Kind
    private let languageCode: String
    private let dark: Bool
    private let openUrl: (String) -> Void
    var agreed: (() -> Void)?

    init(kind: TellomiSignUpAgreement.Kind, languageCode: String, dark: Bool, openUrl: @escaping (String) -> Void) {
        self.kind = kind
        self.languageCode = languageCode
        self.dark = dark
        self.openUrl = openUrl
        super.init(navigationBarPresentationData: nil)
        self.statusBar.statusBarStyle = .Ignore
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = TellomiAgreementPromptNode(kind: self.kind, languageCode: self.languageCode, dark: self.dark, openUrl: { [weak self] url in
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

    init(kind: TellomiSignUpAgreement.Kind, languageCode: String, dark: Bool, openUrl: @escaping (String) -> Void, agree: @escaping () -> Void, dismiss: @escaping () -> Void) {
        self.dismissPrompt = dismiss
        let copy = tellomiLoginCopy(languageCode: languageCode)
        let palette = TellomiLoginChrome.palette(dark: dark)
        self.agreeButton = SolidRoundedButtonNode(title: copy.agreeAndLogin, theme: TellomiLoginChrome.buttonTheme(dark: dark), glass: false, height: 48.0, cornerRadius: 24.0)
        super.init()

        self.dimNode.backgroundColor = UIColor(white: 0.0, alpha: 0.45)
        self.cardNode.backgroundColor = palette.rowBackground
        self.cardNode.cornerRadius = 16.0
        self.cardNode.clipsToBounds = true

        self.titleNode.attributedText = NSAttributedString(string: copy.agreementTitle, font: Font.semibold(17.0), textColor: palette.rowText, paragraphAlignment: .center)
        self.titleNode.maximumNumberOfLines = 0
        self.titleNode.displaysAsynchronously = false

        self.bodyNode.maximumNumberOfLines = 0
        self.bodyNode.displaysAsynchronously = false
        self.bodyNode.isUserInteractionEnabled = true
        self.bodyNode.linkHighlightColor = TellomiLoginChrome.palette(dark: dark).link.withAlphaComponent(0.2)
        let agreementTheme = dark ? defaultDarkPresentationTheme : defaultPresentationTheme
        self.agreement.install(on: self.bodyNode, theme: agreementTheme, kind: kind, languageCode: languageCode, togglesOnText: false, centered: true, openUrl: openUrl, changed: { _ in })

        self.declineNode.setTitle(copy.disagree, with: Font.regular(15.0), with: palette.secondaryText, for: .normal)
        self.declineNode.accessibilityTraits = [.button]
        self.declineNode.accessibilityIdentifier = "Auth.Login.Disagree"
        self.agreeButton.accessibilityIdentifier = "Auth.Login.Agree"
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
