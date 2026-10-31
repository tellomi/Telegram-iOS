import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import TextFormat

/// Tellomi: the sign-up screen's "我已阅读并同意《用户服务协议》和《隐私政策》" checkbox.
/// Continue stays disabled until it is checked. There is no in-app terms popup.
/// It takes over the stock terms label on the sign-up screen; see Tellomi/UPSTREAM_PATCHES.md.
final class TellomiSignUpAgreement {
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
    private var chinese = true
    private var appliedTheme: PresentationTheme?
    private weak var node: ImmediateTextNode?

    /// Shows the agreement on `node` and handles taps: a link opens the document, anything else toggles.
    /// There is no in-app agreement modal. `openUrl` is the login flow's Safari opener.
    func install(on node: ImmediateTextNode, theme: PresentationTheme, kind: Kind = .signUp, chinese: Bool = true, openUrl: @escaping (String) -> Void, changed: @escaping (Bool) -> Void) {
        self.kind = kind
        self.chinese = chinese
        self.appliedTheme = theme
        self.node = node
        node.attributedText = self.text(theme: theme)
        node.accessibilityIdentifier = "Auth.SetName.AgreementCheckbox"
        let urlKey = NSAttributedString.Key(rawValue: TelegramTextAttributes.URL)
        node.highlightAttributeAction = { attributes in
            if attributes[urlKey] != nil {
                return urlKey
            }
            return attributes[TellomiSignUpAgreement.toggleAttribute] != nil ? TellomiSignUpAgreement.toggleAttribute : nil
        }
        node.tapAttributeAction = { [weak self, weak node] attributes, _ in
            guard let self, let node else {
                return
            }
            if let url = attributes[urlKey] as? String, !url.isEmpty {
                openUrl(url)
            } else if attributes[TellomiSignUpAgreement.toggleAttribute] != nil {
                self.agreed = !self.agreed
                node.attributedText = self.text(theme: self.appliedTheme ?? theme)
                changed(self.agreed)
            }
        }
    }

    func setKind(_ kind: Kind) {
        self.kind = kind
        guard let node = self.node, let theme = self.appliedTheme else {
            return
        }
        node.attributedText = self.text(theme: theme)
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
        toggle(self.agreed ? "☑ " : "☐ ", color: self.agreed ? TellomiLoginChrome.accent : body)
        if self.chinese {
            switch self.kind {
            case .signUp:
                toggle("我已阅读并同意", color: body)
                link("《用户服务协议》", TellomiSignUpAgreement.termsURL)
                toggle("和", color: body)
                link("《隐私政策》", TellomiSignUpAgreement.privacyURL)
            case .phone:
                toggle("已阅读并同意", color: body)
                link("用户协议", TellomiSignUpAgreement.termsURL)
                toggle("和", color: body)
                link("隐私政策", TellomiSignUpAgreement.privacyURL)
                toggle("以及", color: body)
                link("运营商服务协议", TellomiLoginChrome.legalURL)
                toggle("。运营商将对你提供的手机号进行验证", color: body)
            case .email:
                toggle("已阅读并同意", color: body)
                link("用户协议", TellomiSignUpAgreement.termsURL)
                toggle("和", color: body)
                link("隐私政策", TellomiSignUpAgreement.privacyURL)
            }
        } else {
            switch self.kind {
            case .signUp, .email:
                toggle("I have read and agree to the ", color: body)
                link("Terms", TellomiSignUpAgreement.termsURL)
                toggle(" and ", color: body)
                link("Privacy Policy", TellomiSignUpAgreement.privacyURL)
            case .phone:
                toggle("I have read and agree to the ", color: body)
                link("Terms", TellomiSignUpAgreement.termsURL)
                toggle(" and ", color: body)
                link("Privacy Policy", TellomiSignUpAgreement.privacyURL)
                toggle(". The carrier will verify this phone number.", color: body)
            }
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = self.kind == .phone ? .left : .center
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }
}
