import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import TextFormat

/// Agreement sentence for sign-up and the login screens. The circle is a real
/// button on `TellomiAgreementRow`. This object owns the sentence and its taps:
/// a link opens the document, and the rest of the sentence toggles the box.
/// Login also presents `TellomiAgreementPromptController` when the box is unchecked.
/// See Tellomi/UPSTREAM_PATCHES.md.
final class TellomiSignUpAgreement: NSObject {
    enum Kind {
        case signUp
        case phone
        case email
    }

    static let termsURL = "https://tellomi.cn/legal/terms/"
    static let privacyURL = "https://tellomi.cn/legal/privacy/"
    static let toggleAttribute = NSAttributedString.Key(rawValue: "TellomiSignUpAgreementToggle")

    private(set) var agreed = false
    /// The code `refreshLanguage` last built the sentence from. Empty until the first refresh.
    private var resolvedLanguageCode = ""
    private var appliedTheme: PresentationTheme?
    private weak var node: ImmediateTextNode?
    private var openUrl: ((String) -> Void)?
    private var changed: ((Bool) -> Void)?
    private var tapRecognizer: UITapGestureRecognizer?
    private var togglesOnText = true

    /// `togglesOnText` is false on the agreement card, which has its own buttons.
    /// `centered` forces that card's body to center even for the phone-home wording.
    ///
    /// The stock text-node recognizer waits for a double tap and only hits glyph bounds.
    /// This installs a single-tap recognizer and expands the hit rect.
    func install(on node: ImmediateTextNode, theme: PresentationTheme, kind: Kind = .signUp, chinese: Bool = true, togglesOnText: Bool = true, centered: Bool = false, openUrl: @escaping (String) -> Void, changed: @escaping (Bool) -> Void) {
        _ = chinese
        self.appliedTheme = theme
        self.node = node
        self.openUrl = openUrl
        self.changed = changed
        self.togglesOnText = togglesOnText
        _ = kind
        _ = centered
        node.accessibilityIdentifier = "Auth.SetName.AgreementCheckbox"
        node.isUserInteractionEnabled = true
        node.displaysAsynchronously = false
        node.hitTestSlop = UIEdgeInsets(top: -4.0, left: -28.0, bottom: -16.0, right: -8.0)
        node.highlightAttributeAction = nil
        node.tapAttributeAction = nil
        node.attributedText = self.text(theme: theme)
        if self.tapRecognizer == nil {
            let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(_:)))
            node.view.addGestureRecognizer(tap)
            self.tapRecognizer = tap
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let node = self.node else {
            return
        }
        let point = gesture.location(in: node.view)
        let urlKey = NSAttributedString.Key(rawValue: TelegramTextAttributes.URL)
        if let (_, attributes) = node.attributesAtPoint(point, orNearest: false), let url = attributes[urlKey] as? String, !url.isEmpty {
            self.openUrl?(url)
            return
        }
        if let (index, _) = node.attributesAtPoint(point, orNearest: true), let text = node.currentText, index >= 0, index < text.length, let url = text.attribute(urlKey, at: index, effectiveRange: nil) as? String, !url.isEmpty, self.point(point, hitsLinkAt: index, in: node) {
            self.openUrl?(url)
            return
        }
        if self.togglesOnText {
            self.setAgreed(!self.agreed)
        }
    }

    private func point(_ point: CGPoint, hitsLinkAt index: Int, in node: ImmediateTextNode) -> Bool {
        guard let rects = node.attributeRects(name: TelegramTextAttributes.URL, at: index) else {
            return false
        }
        for rect in rects {
            if rect.insetBy(dx: -8.0, dy: -8.0).contains(point) {
                return true
            }
        }
        return false
    }

    private func applyText() {
        guard let node = self.node, let theme = self.appliedTheme else {
            return
        }
        node.attributedText = self.text(theme: theme)
        let sentence = node.attributedText?.string ?? ""
        node.accessibilityLabel = sentence
        node.supernode?.accessibilityLabel = sentence
        let width = node.constrainedSize?.width ?? node.bounds.width
        if width > 0.0 {
            _ = node.updateLayout(CGSize(width: width, height: 240.0))
        }
        node.setNeedsDisplay()
    }

    func setKind(_ kind: Kind) {
        _ = kind
        self.applyText()
    }

    /// Rewrites the sentence from the same language code the rest of the login chrome uses.
    /// The tap recognizer stays. `languageCode` is already resolved (`tellomiInterfaceLanguageCode`).
    func refreshLanguage(languageCode: String) {
        self.resolvedLanguageCode = languageCode
        guard self.node != nil else {
            return
        }
        self.applyText()
    }

    func setAgreed(_ agreed: Bool) {
        self.agreed = agreed
        self.applyText()
        self.changed?(agreed)
    }

    func text(theme _: PresentationTheme) -> NSAttributedString {
        let font = Font.regular(13.0)
        let body = TellomiLoginChrome.secondaryText
        let accent = TellomiLoginChrome.link
        let result = NSMutableAttributedString()
        func toggle(_ s: String, color: UIColor) {
            result.append(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, TellomiSignUpAgreement.toggleAttribute: true]))
        }
        func link(_ s: String, _ url: String) {
            result.append(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: accent, NSAttributedString.Key(rawValue: TelegramTextAttributes.URL): url]))
        }
        // One sentence on every login and sign-up screen. The kind no longer changes the wording.
        // Use the code from the last refresh, not a second lookup with an empty saved language,
        // which stayed English after the picker had already switched the rest of the screen.
        let script = tellomiLoginScript(languageCode: self.resolvedLanguageCode.isEmpty ? tellomiChromeLanguageCode(savedLanguageCode: "") : self.resolvedLanguageCode)
        if script == .hant {
            toggle("已閱讀並同意", color: body)
            link("用戶協議", TellomiSignUpAgreement.termsURL)
            toggle("和", color: body)
            link("隱私政策", TellomiSignUpAgreement.privacyURL)
        } else if script == .hans {
            toggle("已阅读并同意", color: body)
            link("用户协议", TellomiSignUpAgreement.termsURL)
            toggle("和", color: body)
            link("隐私政策", TellomiSignUpAgreement.privacyURL)
        } else {
            toggle("I have read and agree to the ", color: body)
            link("Terms", TellomiSignUpAgreement.termsURL)
            toggle(" and ", color: body)
            link("Privacy Policy", TellomiSignUpAgreement.privacyURL)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }
}
