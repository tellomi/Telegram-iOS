import Foundation
import UIKit
import Display
import SolidRoundedButtonNode

/// Shared pink / gray / white login chrome. See Tellomi/UPSTREAM_PATCHES.md.
enum TellomiLoginChrome {
    static let accent = UIColor(rgb: 0xFF4B6E)
    static let accentDisabled = UIColor(rgb: 0xFFC1CC)
    static let fieldFill = UIColor(rgb: 0xF2F3F5)
    static let link = UIColor(rgb: 0x2F6BFF)
    static let secondaryText = UIColor(rgb: 0x8A8A8E)
    static let placeholder = UIColor(rgb: 0xB0B0B6)
    /// Terms, privacy, and the carrier note all open on this host, in Safari.
    static let legalURL = "https://tellomi.cn/legal"
    static let helpURL = "https://tellomi.cn/faq"
    static let fieldCornerRadius: CGFloat = 12.0

    static func buttonTheme() -> SolidRoundedButtonTheme {
        return SolidRoundedButtonTheme(
            backgroundColor: self.accent,
            foregroundColor: .white,
            disabledBackgroundColor: self.accentDisabled,
            disabledForegroundColor: .white
        )
    }

    static func applyField(_ node: ASDisplayNode) {
        node.backgroundColor = self.fieldFill
        node.cornerRadius = self.fieldCornerRadius
        node.clipsToBounds = true
    }
}

struct TellomiLoginCopy: Equatable {
    let phoneTitle: String
    let phonePlaceholder: String
    let verifyAndLogin: String
    let codeTitlePhone: String
    let codeTitleEmail: String
    let login: String
    let codePlaceholder: String
    let resend: String
    let codeSentToast: String
    let help: String
    let continueAction: String
    let cloudPasswordTitle: String
    let codeSentPhoneFormat: String
    let codeSentEmailFormat: String
    let resendCountdownFormat: String

    func codeSentPhone(_ number: String) -> String {
        return String(format: self.codeSentPhoneFormat, number)
    }

    func codeSentEmail(_ address: String) -> String {
        return String(format: self.codeSentEmailFormat, address)
    }

    func resendCountdown(_ seconds: Int) -> String {
        return String(format: self.resendCountdownFormat, seconds)
    }
}

func tellomiLoginCopy(languageCode: String) -> TellomiLoginCopy {
    let code = languageCode.lowercased()
    if code == "zh" || code.hasPrefix("zh-") {
        return TellomiLoginCopy(
            phoneTitle: "登录发现更多精彩",
            phonePlaceholder: "请输入手机号",
            verifyAndLogin: "验证并登录",
            codeTitlePhone: "请输入验证码",
            codeTitleEmail: "输入验证码",
            login: "登录",
            codePlaceholder: "请输入验证码",
            resend: "重新发送",
            codeSentToast: "验证码发送成功",
            help: "帮助",
            continueAction: "继续",
            cloudPasswordTitle: "输入云密码",
            codeSentPhoneFormat: "短信已发送至 %@",
            codeSentEmailFormat: "邮件已发送至 %@",
            resendCountdownFormat: "%d 秒后重新发送"
        )
    }
    return TellomiLoginCopy(
        phoneTitle: "Log in to see more",
        phonePlaceholder: "Phone number",
        verifyAndLogin: "Verify and log in",
        codeTitlePhone: "Enter the code",
        codeTitleEmail: "Enter the code",
        login: "Log in",
        codePlaceholder: "Enter the code",
        resend: "Resend",
        codeSentToast: "Code sent",
        help: "Help",
        continueAction: "Continue",
        cloudPasswordTitle: "Cloud password",
        codeSentPhoneFormat: "SMS sent to %@",
        codeSentEmailFormat: "Email sent to %@",
        resendCountdownFormat: "Resend in %d s"
    )
}

func tellomiLoginLanguageIsChinese(_ languageCode: String) -> Bool {
    let code = languageCode.lowercased()
    return code == "zh" || code.hasPrefix("zh-")
}
