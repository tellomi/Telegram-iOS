import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import TextFormat

struct TellomiAgreementParts {
    var lead: String
    var terms: String
    var mid: String
    var privacy: String
    var tail: String
}

private func tellomiAgreementKey(_ languageCode: String) -> String {
    let code = languageCode.lowercased().replacingOccurrences(of: "_", with: "-")
    if code.hasPrefix("zh-hant") || code.hasPrefix("zh-tw") || code.hasPrefix("zh-hk") || code.hasPrefix("zh-mo") {
        return "zh-hant"
    }
    if code == "zh" || code.hasPrefix("zh-") {
        return "zh-hans"
    }
    if let primary = code.split(separator: "-").first {
        return String(primary)
    }
    return "en"
}

func tellomiAgreementParts(languageCode: String, kind: TellomiSignUpAgreement.Kind) -> TellomiAgreementParts {
    let key = tellomiAgreementKey(tellomiChromeLanguageCode(savedLanguageCode: languageCode))
    let signUp = kind == .signUp
    switch key {
    case "zh-hans":
        if signUp {
            return TellomiAgreementParts(lead: "我已阅读并同意", terms: "《用户服务协议》", mid: "和", privacy: "《隐私政策》", tail: "")
        }
        return TellomiAgreementParts(lead: "已阅读并同意 ", terms: "用户协议", mid: " 和 ", privacy: "隐私政策", tail: "")
    case "zh-hant":
        if signUp {
            return TellomiAgreementParts(lead: "我已閱讀並同意", terms: "《用戶服務協議》", mid: "和", privacy: "《隱私政策》", tail: "")
        }
        return TellomiAgreementParts(lead: "已閱讀並同意 ", terms: "用戶協議", mid: " 和 ", privacy: "隱私政策", tail: "")
    case "ar":
        return TellomiAgreementParts(lead: "لقد قرأت وأوافق على ", terms: "شروط الخدمة", mid: " و", privacy: "سياسة الخصوصية", tail: "")
    case "be":
        return TellomiAgreementParts(lead: "Я прачытаў(-ла) і згаджаюся з ", terms: "Умовамі", mid: " і ", privacy: "Палітыкай прыватнасці", tail: "")
    case "ca":
        return TellomiAgreementParts(lead: "He llegit i accepto les ", terms: "Condicions", mid: " i la ", privacy: "Política de privadesa", tail: "")
    case "de":
        return TellomiAgreementParts(lead: "Ich habe die ", terms: "Nutzungsbedingungen", mid: " und die ", privacy: "Datenschutzrichtlinie", tail: " gelesen und stimme zu")
    case "es":
        return TellomiAgreementParts(lead: "He leído y acepto los ", terms: "Términos", mid: " y la ", privacy: "Política de privacidad", tail: "")
    case "fa":
        return TellomiAgreementParts(lead: "شرایط ", terms: "خدمات", mid: " و ", privacy: "سیاست حریم خصوصی", tail: " را خوانده‌ام و می‌پذیرم")
    case "fr":
        return TellomiAgreementParts(lead: "J'ai lu et j'accepte les ", terms: "Conditions", mid: " et la ", privacy: "Politique de confidentialité", tail: "")
    case "id":
        return TellomiAgreementParts(lead: "Saya telah membaca dan menyetujui ", terms: "Ketentuan", mid: " dan ", privacy: "Kebijakan Privasi", tail: "")
    case "it":
        return TellomiAgreementParts(lead: "Ho letto e accetto i ", terms: "Termini", mid: " e l'", privacy: "Informativa sulla privacy", tail: "")
    case "ko":
        return TellomiAgreementParts(lead: "", terms: "이용약관", mid: " 및 ", privacy: "개인정보 처리방침", tail: "을 읽었으며 동의합니다")
    case "ms":
        return TellomiAgreementParts(lead: "Saya telah membaca dan bersetuju dengan ", terms: "Terma", mid: " dan ", privacy: "Dasar Privasi", tail: "")
    case "nl":
        return TellomiAgreementParts(lead: "Ik heb de ", terms: "Voorwaarden", mid: " en het ", privacy: "Privacybeleid", tail: " gelezen en ga akkoord")
    case "pl":
        return TellomiAgreementParts(lead: "Przeczytałem(-am) i akceptuję ", terms: "Warunki", mid: " oraz ", privacy: "Politykę prywatności", tail: "")
    case "pt":
        return TellomiAgreementParts(lead: "Li e concordo com os ", terms: "Termos", mid: " e a ", privacy: "Política de Privacidade", tail: "")
    case "ru":
        return TellomiAgreementParts(lead: "Я прочитал(а) и принимаю ", terms: "Условия", mid: " и ", privacy: "Политику конфиденциальности", tail: "")
    case "tr":
        return TellomiAgreementParts(lead: "", terms: "Koşullar", mid: " ve ", privacy: "Gizlilik Politikası", tail: "'nı okudum ve kabul ediyorum")
    case "uk":
        return TellomiAgreementParts(lead: "Я прочитав(-ла) і приймаю ", terms: "Умови", mid: " та ", privacy: "Політику конфіденційності", tail: "")
    case "uz":
        return TellomiAgreementParts(lead: "", terms: "Shartlar", mid: " va ", privacy: "Maxfiylik siyosati", tail: "ni o‘qidim va roziman")
    default:
        if signUp {
            return TellomiAgreementParts(lead: "I have read and agree to the ", terms: "Terms of Service", mid: " and ", privacy: "Privacy Policy", tail: "")
        }
        return TellomiAgreementParts(lead: "I have read and agree to the ", terms: "Terms", mid: " and ", privacy: "Privacy Policy", tail: "")
    }
}

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
    private var kind: Kind = .signUp
    private var languageCode = "zh-hans"
    private var appliedTheme: PresentationTheme?
    private weak var node: ImmediateTextNode?
    private var openUrl: ((String) -> Void)?
    private var changed: ((Bool) -> Void)?
    private var tapRecognizer: UITapGestureRecognizer?
    private var togglesOnText = true
    private var centeredBody = false

    /// `togglesOnText` is false on the agreement card, which has its own buttons.
    /// `centered` forces that card's body to center even for the phone-home wording.
    ///
    /// The stock text-node recognizer waits for a double tap and only hits glyph bounds.
    /// This installs a single-tap recognizer and expands the hit rect.
    func install(on node: ImmediateTextNode, theme: PresentationTheme, kind: Kind = .signUp, chinese: Bool = true, languageCode: String? = nil, togglesOnText: Bool = true, centered: Bool = false, openUrl: @escaping (String) -> Void, changed: @escaping (Bool) -> Void) {
        self.kind = kind
        self.languageCode = languageCode ?? (chinese ? "zh-hans" : "en")
        self.appliedTheme = theme
        self.node = node
        self.openUrl = openUrl
        self.changed = changed
        self.togglesOnText = togglesOnText
        self.centeredBody = centered
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
        let width = node.constrainedSize?.width ?? node.bounds.width
        if width > 0.0 {
            _ = node.updateLayout(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        }
    }

    func setKind(_ kind: Kind) {
        self.kind = kind
        self.applyText()
    }

    /// Rewrites the sentence after a pre-login language change. The tap recognizer stays.
    /// Pass the chrome language (`tellomiInterfaceLanguageCode`). An empty code used to
    /// read as English once the system pack flag was set, so a Chinese login kept the
    /// English agreement.
    func refreshLanguage(languageCode: String) {
        self.languageCode = tellomiChromeLanguageCode(savedLanguageCode: languageCode)
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
        let font = TellomiLoginChrome.scaledFont(size: 13.0)
        let body = TellomiLoginChrome.secondaryText
        let accent = TellomiLoginChrome.palette(dark: self.appliedTheme?.overallDarkAppearance ?? false).link
        let result = NSMutableAttributedString()
        func toggle(_ s: String, color: UIColor) {
            result.append(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, TellomiSignUpAgreement.toggleAttribute: true]))
        }
        func link(_ s: String, _ url: String) {
            result.append(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: accent, NSAttributedString.Key(rawValue: TelegramTextAttributes.URL): url]))
        }
        let parts = tellomiAgreementParts(languageCode: self.languageCode, kind: self.kind)
        toggle(parts.lead, color: body)
        link(parts.terms, TellomiSignUpAgreement.termsURL)
        toggle(parts.mid, color: body)
        link(parts.privacy, TellomiSignUpAgreement.privacyURL)
        if !parts.tail.isEmpty {
            toggle(parts.tail, color: body)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = (self.centeredBody || self.kind != .phone) ? .center : .left
        paragraph.lineBreakMode = .byWordWrapping
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }
}
