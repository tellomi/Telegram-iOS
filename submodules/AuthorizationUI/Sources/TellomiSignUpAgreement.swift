import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import TextFormat

/// Tellomi: the sign-up screen's "我已阅读并同意《用户协议》和《隐私政策》" checkbox.
/// Continue stays disabled until it is checked. There is no in-app terms popup.
/// It takes over the stock terms label on the sign-up screen; see Tellomi/UPSTREAM_PATCHES.md.
final class TellomiSignUpAgreement {
    static let termsURL = "https://tellomi.cn/legal/terms/"
    static let privacyURL = "https://tellomi.cn/legal/privacy/"
    static let toggleAttribute = NSAttributedString.Key(rawValue: "TellomiSignUpAgreementToggle")

    private(set) var agreed = false

    /// Shows the agreement on `node` and handles taps: a link opens the document, anything else toggles.
    func install(on node: ImmediateTextNode, theme: PresentationTheme, openUrl: @escaping (String) -> Void, changed: @escaping (Bool) -> Void) {
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
                node.attributedText = self.text(theme: theme)
                changed(self.agreed)
            }
        }
    }

    func text(theme: PresentationTheme) -> NSAttributedString {
        let font = Font.regular(13.0)
        let body = theme.list.itemSecondaryTextColor
        let accent = theme.list.itemAccentColor
        let result = NSMutableAttributedString()
        func toggle(_ s: String, color: UIColor) {
            result.append(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, TellomiSignUpAgreement.toggleAttribute: true]))
        }
        func link(_ s: String, _ url: String) {
            result.append(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: accent, NSAttributedString.Key(rawValue: TelegramTextAttributes.URL): url]))
        }
        toggle(self.agreed ? "☑ " : "☐ ", color: self.agreed ? accent : body)
        toggle("我已阅读并同意", color: body)
        link("《用户协议》", TellomiSignUpAgreement.termsURL)
        toggle("和", color: body)
        link("《隐私政策》", TellomiSignUpAgreement.privacyURL)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }
}
