import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SolidRoundedButtonNode

/// Shared login chrome. Primary buttons are black on white; the pink in the
/// owner mockups is layout only. See Tellomi/UPSTREAM_PATCHES.md.
enum TellomiLoginChrome {
    static let buttonBackground = UIColor(rgb: 0x111111)
    static let buttonForeground = UIColor.white
    static let buttonDisabledBackground = UIColor(rgb: 0xE5E5E5)
    static let buttonDisabledForeground = UIColor(rgb: 0x8E8E93)
    static let link = UIColor(rgb: 0x3478F6)
    static let error = UIColor(rgb: 0xFF3B30)
    /// Caret and focused field. Same black as the primary button.
    static let accent = UIColor(rgb: 0x111111)
    static let checkbox = UIColor(rgb: 0x111111)
    static let fieldFill = UIColor(rgb: 0xF2F3F5)
    static let secondaryText = UIColor(rgb: 0x8A8A8E)
    static let placeholder = UIColor(rgb: 0xB0B0B6)
    static let rowBorder = UIColor(rgb: 0xE6E6E6)
    /// Terms, privacy, and the carrier note all open on this host, in Safari.
    static let legalURL = "https://tellomi.cn/legal"
    static let helpURL = "https://tellomi.cn/faq"
    static let fieldCornerRadius: CGFloat = 12.0

    static func buttonTheme() -> SolidRoundedButtonTheme {
        return SolidRoundedButtonTheme(
            backgroundColor: self.buttonBackground,
            foregroundColor: self.buttonForeground,
            disabledBackgroundColor: self.buttonDisabledBackground,
            disabledForegroundColor: self.buttonDisabledForeground
        )
    }

    static func applyField(_ node: ASDisplayNode) {
        node.backgroundColor = self.fieldFill
        node.cornerRadius = self.fieldCornerRadius
        node.clipsToBounds = true
    }
}

/// Which login-home screen is showing. Change Phone Number does not use this.
enum TellomiLoginSurface: Equatable {
    case phoneCode
    case phonePassword
    case emailCode
    case emailPassword

    var isEmail: Bool {
        switch self {
        case .emailCode, .emailPassword:
            return true
        case .phoneCode, .phonePassword:
            return false
        }
    }

    var isPassword: Bool {
        switch self {
        case .phonePassword, .emailPassword:
            return true
        case .phoneCode, .emailCode:
            return false
        }
    }

    /// Phone OTP home is the only screen whose agreement mentions the carrier.
    var showsCarrierAgreement: Bool {
        return self == .phoneCode
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
    let passwordLogin: String
    let codeLogin: String
    let orDivider: String
    let appleLogin: String
    let googleLogin: String
    let emailLogin: String
    let otherLogin: String
    let recoverAccount: String
    let phonePasswordTitle: String
    let emailPasswordTitle: String
    let passwordPlaceholder: String
    let agreeAndLogin: String
    let disagree: String
    let agreementTitle: String
    let unavailableTitle: String
    let unavailableBody: String
    let codeNotReceived: String
    let wrongCode: String
    let wrongPassword: String
    let startMessaging: String
    let ok: String

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
    if tellomiLoginPrefersChinese(languageCode: languageCode) {
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
            resendCountdownFormat: "%d 秒后重新发送",
            passwordLogin: "密码登录",
            codeLogin: "验证码登录",
            orDivider: "或",
            appleLogin: "Apple 登录",
            googleLogin: "Google 登录",
            emailLogin: "邮箱登录",
            otherLogin: "其他登录方式",
            recoverAccount: "找回账号",
            phonePasswordTitle: "手机号密码登录",
            emailPasswordTitle: "邮箱密码登录",
            passwordPlaceholder: "请输入密码",
            agreeAndLogin: "同意并登录",
            disagree: "不同意",
            agreementTitle: "用户协议及隐私政策",
            unavailableTitle: "暂未开放",
            unavailableBody: "该登录方式即将开放，请先使用手机号或邮箱。",
            codeNotReceived: "收不到验证码?",
            wrongCode: "请输入正确的验证码",
            wrongPassword: "账号或密码错误，请重试。",
            startMessaging: "开始聊天",
            ok: "好"
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
        resendCountdownFormat: "Resend in %d s",
        passwordLogin: "Password",
        codeLogin: "Verification code",
        orDivider: "or",
        appleLogin: "Sign in with Apple",
        googleLogin: "Sign in with Google",
        emailLogin: "Email",
        otherLogin: "Other methods",
        recoverAccount: "Recover account",
        phonePasswordTitle: "Phone password",
        emailPasswordTitle: "Email password",
        passwordPlaceholder: "Password",
        agreeAndLogin: "Agree and log in",
        disagree: "Decline",
        agreementTitle: "Terms and Privacy",
        unavailableTitle: "Not available yet",
        unavailableBody: "This sign-in method isn't open yet. Use a phone number or email.",
        codeNotReceived: "Didn't get a code?",
        wrongCode: "Enter the correct code",
        wrongPassword: "Incorrect account or password. Try again.",
        startMessaging: "Start Messaging",
        ok: "OK"
    )
}

func tellomiLoginLanguageIsChinese(_ languageCode: String) -> Bool {
    let code = tellomiChromeLanguageCode(savedLanguageCode: languageCode).lowercased()
    return code == "zh" || code.hasPrefix("zh-")
}

/// Chinese when the langpack or the system language is Chinese. An empty
/// preferred-language list (no signal) stays Chinese: mainland is the default.
func tellomiLoginPrefersChinese(languageCode: String) -> Bool {
    let code = tellomiChromeLanguageCode(savedLanguageCode: languageCode).lowercased()
    return code == "zh" || code.hasPrefix("zh-")
}
