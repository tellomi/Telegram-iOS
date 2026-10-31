import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import TextFormat

/// Tellomi: the sign-up screen's "我已阅读并同意《用户服务协议》和《隐私政策》" checkbox.
/// Continue stays disabled until it is checked. There is no in-app terms popup.
/// It takes over the stock terms label on the sign-up screen; see Tellomi/UPSTREAM_PATCHES.md.
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
    private var chinese = true
    private var appliedTheme: PresentationTheme?
    private weak var node: ImmediateTextNode?
    private var openUrl: ((String) -> Void)?
    private var changed: ((Bool) -> Void)?
    private var tapRecognizer: UITapGestureRecognizer?

    /// Shows the agreement on `node` and handles taps: a link opens the document in Safari, anything else toggles.
    /// There is no in-app agreement modal. `openUrl` is the login flow's Safari opener.
    ///
    /// The stock text-node recognizer waits for a double tap and only hits glyph bounds, so the ☐ box
    /// (about 13 pt) never registered. This installs a single-tap recognizer and expands the hit rect.
    func install(on node: ImmediateTextNode, theme: PresentationTheme, kind: Kind = .signUp, chinese: Bool = true, openUrl: @escaping (String) -> Void, changed: @escaping (Bool) -> Void) {
        self.kind = kind
        self.chinese = chinese
        self.appliedTheme = theme
        self.node = node
        self.openUrl = openUrl
        self.changed = changed
        node.accessibilityIdentifier = "Auth.SetName.AgreementCheckbox"
        node.isUserInteractionEnabled = true
        node.displaysAsynchronously = false
        // Negative slop grows the hit rect (Texture). The box sits on the leading edge, above the home indicator.
        node.hitTestSlop = UIEdgeInsets(top: -4.0, left: -28.0, bottom: -16.0, right: -8.0)
        // Drop the delayed attribute recognizer. Setting this before the view loads keeps didLoad from installing it.
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
        // `orNearest` returns the index and an empty attribute dictionary. Read the laid-out string.
        if let (index, _) = node.attributesAtPoint(point, orNearest: true), let text = node.currentText, index >= 0, index < text.length, let url = text.attribute(urlKey, at: index, effectiveRange: nil) as? String, !url.isEmpty, self.point(point, hitsLinkAt: index, in: node) {
            self.openUrl?(url)
            return
        }
        self.agreed = !self.agreed
        self.applyText()
        self.changed?(self.agreed)
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
        guard let node = self.node, let theme = self.appliedTheme else {
            return
        }
        // The caller lays the node out immediately after this. `attributedText` is what that pass reads.
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
