import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import SolidRoundedButtonNode

/// Shared login chrome. Primary buttons are black on white; the pink in the
/// owner mockups is layout only. See Tellomi/UPSTREAM_PATCHES.md.
enum TellomiLoginChrome {
    static let buttonBackground = UIColor(rgb: 0x111111)
    static let buttonForeground = UIColor.white
    static let buttonDisabledBackground = UIColor(rgb: 0xE5E5E5)
    static let buttonDisabledForeground = UIColor(rgb: 0x8E8E93)
    static let link = UIColor(rgb: 0x111111)
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
    static let helpURL = "https://tellomi.cn/help/"
    static let fieldCornerRadius: CGFloat = 12.0

    /// Body text that grows with the system text size, capped so a login column
    /// still fits a 4-inch phone. `Font.regular` is a fixed point size.
    static func scaledFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: font, maximumPointSize: size * 1.35)
    }

    /// Login column. Frames stay in screen coordinates: the scroll view fills the
    /// controller, and `contentInset.bottom` is the keyboard or the home indicator.
    static func makeFormScroll() -> ASScrollNode {
        let scroll = ASScrollNode()
        scroll.scrollableDirections = [.up, .down]
        scroll.view.alwaysBounceVertical = false
        scroll.view.showsVerticalScrollIndicator = true
        scroll.view.contentInsetAdjustmentBehavior = .never
        scroll.view.keyboardDismissMode = .interactive
        scroll.backgroundColor = .clear
        return scroll
    }

    static func applyFormScroll(_ scroll: ASScrollNode, layoutSize: CGSize, bottomInset: CGFloat, contentBottom: CGFloat) {
        scroll.frame = CGRect(origin: CGPoint(), size: layoutSize)
        let inset = UIEdgeInsets(top: 0.0, left: 0.0, bottom: bottomInset, right: 0.0)
        scroll.view.contentInset = inset
        scroll.view.verticalScrollIndicatorInsets = inset
        let visibleHeight = max(0.0, layoutSize.height - bottomInset)
        scroll.view.contentSize = CGSize(width: layoutSize.width, height: max(contentBottom, visibleHeight))
        if contentBottom <= visibleHeight + 1.0 {
            scroll.view.contentOffset = CGPoint()
        }
    }

    struct Palette {
        let buttonBackground: UIColor
        let buttonForeground: UIColor
        let buttonDisabledBackground: UIColor
        let buttonDisabledForeground: UIColor
        let link: UIColor
        let error: UIColor
        let accent: UIColor
        let checkbox: UIColor
        let fieldFill: UIColor
        let fieldText: UIColor
        let secondaryText: UIColor
        let placeholder: UIColor
        let rowBorder: UIColor
        let rowBackground: UIColor
        let rowText: UIColor
    }

    /// Light matches the owner colors. Dark inverts the button and the field so
    /// `#111111` is not drawn on a dark page and typed text is not white on `#F2F3F5`.
    static func palette(dark: Bool) -> Palette {
        if dark {
            return Palette(
                buttonBackground: UIColor.white,
                buttonForeground: UIColor(rgb: 0x111111),
                buttonDisabledBackground: UIColor(rgb: 0x3A3A3C),
                buttonDisabledForeground: UIColor(rgb: 0x8E8E93),
                link: UIColor.white,
                error: UIColor(rgb: 0xFF453A),
                accent: UIColor.white,
                checkbox: UIColor.white,
                fieldFill: UIColor(rgb: 0x2C2C2E),
                fieldText: UIColor.white,
                secondaryText: UIColor(rgb: 0x8E8E93),
                placeholder: UIColor(rgb: 0x8E8E93),
                rowBorder: UIColor(rgb: 0x3A3A3C),
                rowBackground: UIColor(rgb: 0x1C1C1E),
                rowText: UIColor.white
            )
        }
        return Palette(
            buttonBackground: self.buttonBackground,
            buttonForeground: self.buttonForeground,
            buttonDisabledBackground: self.buttonDisabledBackground,
            buttonDisabledForeground: self.buttonDisabledForeground,
            link: self.link,
            error: self.error,
            accent: self.accent,
            checkbox: self.checkbox,
            fieldFill: self.fieldFill,
            fieldText: UIColor(rgb: 0x111111),
            secondaryText: self.secondaryText,
            placeholder: self.placeholder,
            rowBorder: self.rowBorder,
            rowBackground: UIColor.white,
            rowText: UIColor(rgb: 0x111111)
        )
    }

    static func buttonTheme(dark: Bool = false) -> SolidRoundedButtonTheme {
        let palette = self.palette(dark: dark)
        return SolidRoundedButtonTheme(
            backgroundColor: palette.buttonBackground,
            foregroundColor: palette.buttonForeground,
            disabledBackgroundColor: palette.buttonDisabledBackground,
            disabledForegroundColor: palette.buttonDisabledForeground
        )
    }

    static func applyField(_ node: ASDisplayNode, dark: Bool = false) {
        node.backgroundColor = self.palette(dark: dark).fieldFill
        node.cornerRadius = self.fieldCornerRadius
        node.clipsToBounds = true
    }
}

/// Which login-home screen is showing. Change Phone Number does not use this.
enum TellomiLoginSurface: Equatable {
    case phoneCode
    case emailCode

    var isEmail: Bool {
        return self == .emailCode
    }

    /// Phone home pins the agreement to the bottom of the screen. Email centers it under the button.
    var agreementPinnedToBottom: Bool {
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
    /// Email code. SMS uses `wrongSmsCode`.
    let wrongCode: String
    let wrongSmsCode: String
    let startMessaging: String
    let ok: String
    let bindPhoneTitle: String
    let bindPhoneAction: String
    let bindPhoneNotice: String
    let bindEmailTitle: String
    let emailLabel: String
    let alreadyAuthorized: String
    let switchToAccount: String
    let phoneConfirm: String
    let edit: String
    let yes: String
    let signUpTitle: String
    let signUpHelp: String
    let firstNamePlaceholder: String
    let lastNamePlaceholder: String
    let chooseLanguage: String
    let codeSentApp: String
    let codeSentCallFormat: String
    let useSms: String
    let cancel: String

    func codeSentPhone(_ number: String) -> String {
        return String(format: self.codeSentPhoneFormat, number)
    }

    func codeSentEmail(_ address: String) -> String {
        return String(format: self.codeSentEmailFormat, address)
    }

    func codeSentCall(_ number: String) -> String {
        return String(format: self.codeSentCallFormat, number)
    }

    func resendCountdown(_ seconds: Int) -> String {
        return String(format: self.resendCountdownFormat, seconds)
    }
}

public func tellomiAccountLabels(languageCode: String) -> (email: String, bindPhone: String, bindAction: String, bindEmail: String) {
    let copy = tellomiLoginCopy(languageCode: languageCode)
    return (copy.emailLabel, copy.bindPhoneTitle, copy.bindPhoneAction, copy.bindEmailTitle)
}

func tellomiLoginCopy(languageCode: String) -> TellomiLoginCopy {
    switch tellomiLoginScript(languageCode: tellomiChromeLanguageCode(savedLanguageCode: languageCode)) {
    case .hant:
        return tellomiLoginCopyHant()
    case .hans:
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
            codeNotReceived: "收不到验证码？",
            wrongCode: "请输入正确的验证码",
            wrongSmsCode: "验证码错误，请重新输入",
            startMessaging: "开始聊天",
            ok: "好",
            bindPhoneTitle: "绑定手机号",
            bindPhoneAction: "绑定",
            bindPhoneNotice: "绑定后可使用手机号登录",
            bindEmailTitle: "绑定邮箱",
            emailLabel: "邮箱",
            alreadyAuthorized: "该账号已登录",
            switchToAccount: "切换到该账号",
            phoneConfirm: "这个号码正确吗？",
            edit: "编辑",
            yes: "是",
            signUpTitle: "你的信息",
            signUpHelp: "输入你的名字和添加头像.",
            firstNamePlaceholder: "名字",
            lastNamePlaceholder: "姓氏",
            chooseLanguage: "选择语言 / Language",
            codeSentApp: "验证码已发送到你在其他设备上登录的 Tellomi",
            codeSentCallFormat: "正在拨打 %@ 播报验证码",
            useSms: "改用短信接收",
            cancel: "取消"
        )
    case .english:
        let copy = TellomiLoginCopy(
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
        codeNotReceived: "Didn't get the code?",
        wrongCode: "Enter the correct code",
        wrongSmsCode: "Wrong code. Please enter it again.",
        startMessaging: "Start Messaging",
        ok: "OK",
        bindPhoneTitle: "Link a phone number",
        bindPhoneAction: "Link",
        bindPhoneNotice: "You can sign in with this number after linking it.",
        bindEmailTitle: "Link an email",
        emailLabel: "Email",
        alreadyAuthorized: "This account is already signed in",
        switchToAccount: "Switch to this account",
        phoneConfirm: "Is this the correct number?",
        edit: "Edit",
        yes: "Yes",
        signUpTitle: "Your Info",
        signUpHelp: "Enter your name and add a profile photo.",
        firstNamePlaceholder: "First Name",
        lastNamePlaceholder: "Last Name",
        chooseLanguage: "选择语言 / Language",
        codeSentApp: "The code was sent to the Tellomi app on your other devices.",
        codeSentCallFormat: "Calling %@ to dictate the code.",
        useSms: "Get the code by SMS",
        cancel: "Cancel"
    )
        let resolved = tellomiChromeLanguageCode(savedLanguageCode: languageCode)
        if tellomiLoginCopyFollowsPack(resolved), let strings = tellomiAppliedPackStrings(matching: resolved) {
            return tellomiLoginCopyApplyingPack(copy, strings: strings)
        }
        return copy
    }
}

/// Login labels for a language that is not the bundled 简体 / 繁體 / English copy.
/// Fields that exist in the `ios` pack come from that pack (and its English base).
/// Tellomi-only lines (email login, bind phone) stay the English product copy.
func tellomiLoginCopyApplyingPack(_ base: TellomiLoginCopy, strings: PresentationStrings) -> TellomiLoginCopy {
    return TellomiLoginCopy(
        phoneTitle: strings.Login_PhoneTitle,
        phonePlaceholder: strings.Login_PhonePlaceholder,
        verifyAndLogin: strings.Login_Continue,
        codeTitlePhone: strings.Login_Code,
        codeTitleEmail: strings.Login_Code,
        login: strings.Login_Continue,
        codePlaceholder: strings.Login_Code,
        resend: strings.Conversation_MessageDialogRetry,
        codeSentToast: base.codeSentToast,
        help: base.help,
        continueAction: strings.Login_Continue,
        cloudPasswordTitle: strings.LoginPassword_Title,
        codeSentPhoneFormat: base.codeSentPhoneFormat,
        codeSentEmailFormat: base.codeSentEmailFormat,
        resendCountdownFormat: base.resendCountdownFormat,
        passwordLogin: base.passwordLogin,
        codeLogin: base.codeLogin,
        orDivider: base.orDivider,
        appleLogin: base.appleLogin,
        googleLogin: base.googleLogin,
        emailLogin: base.emailLogin,
        otherLogin: base.otherLogin,
        recoverAccount: base.recoverAccount,
        phonePasswordTitle: strings.LoginPassword_Title,
        emailPasswordTitle: strings.LoginPassword_Title,
        passwordPlaceholder: strings.LoginPassword_PasswordPlaceholder,
        agreeAndLogin: strings.Login_Continue,
        disagree: strings.Common_Cancel,
        agreementTitle: base.agreementTitle,
        unavailableTitle: base.unavailableTitle,
        unavailableBody: base.unavailableBody,
        codeNotReceived: strings.Login_HaveNotReceivedCodeInternal,
        wrongCode: strings.Login_InvalidCodeError,
        wrongSmsCode: strings.Login_InvalidCodeError,
        startMessaging: base.startMessaging,
        ok: strings.Common_OK,
        bindPhoneTitle: base.bindPhoneTitle,
        bindPhoneAction: base.bindPhoneAction,
        bindPhoneNotice: base.bindPhoneNotice,
        bindEmailTitle: base.bindEmailTitle,
        emailLabel: base.emailLabel,
        alreadyAuthorized: base.alreadyAuthorized,
        switchToAccount: base.switchToAccount,
        phoneConfirm: base.phoneConfirm,
        edit: base.edit,
        yes: base.yes,
        signUpTitle: strings.Login_InfoTitle,
        signUpHelp: strings.Login_InfoHelp,
        firstNamePlaceholder: strings.Login_InfoFirstNamePlaceholder,
        lastNamePlaceholder: strings.Login_InfoLastNamePlaceholder,
        chooseLanguage: strings.Settings_AppLanguage,
        codeSentApp: base.codeSentApp,
        codeSentCallFormat: base.codeSentCallFormat,
        useSms: base.useSms,
        cancel: strings.Common_Cancel
    )
}

private func tellomiLoginCopyHant() -> TellomiLoginCopy {
    return TellomiLoginCopy(
        phoneTitle: "登入發現更多精彩",
        phonePlaceholder: "請輸入手機號",
        verifyAndLogin: "驗證並登入",
        codeTitlePhone: "請輸入驗證碼",
        codeTitleEmail: "輸入驗證碼",
        login: "登入",
        codePlaceholder: "請輸入驗證碼",
        resend: "重新發送",
        codeSentToast: "驗證碼發送成功",
        help: "幫助",
        continueAction: "繼續",
        cloudPasswordTitle: "輸入雲端密碼",
        codeSentPhoneFormat: "簡訊已發送至 %@",
        codeSentEmailFormat: "郵件已發送至 %@",
        resendCountdownFormat: "%d 秒後重新發送",
        passwordLogin: "密碼登入",
        codeLogin: "驗證碼登入",
        orDivider: "或",
        appleLogin: "Apple 登入",
        googleLogin: "Google 登入",
        emailLogin: "郵箱登入",
        otherLogin: "其他登入方式",
        recoverAccount: "找回帳號",
        phonePasswordTitle: "手機號密碼登入",
        emailPasswordTitle: "郵箱密碼登入",
        passwordPlaceholder: "請輸入密碼",
        agreeAndLogin: "同意並登入",
        disagree: "不同意",
        agreementTitle: "用戶協議及隱私政策",
        unavailableTitle: "暫未開放",
        unavailableBody: "該登入方式即將開放，請先使用手機號或郵箱。",
        codeNotReceived: "收不到驗證碼？",
        wrongCode: "請輸入正確的驗證碼",
        wrongSmsCode: "驗證碼錯誤，請重新輸入",
        startMessaging: "開始聊天",
        ok: "好",
        bindPhoneTitle: "綁定手機號",
        bindPhoneAction: "綁定",
        bindPhoneNotice: "綁定後可使用手機號登入",
        bindEmailTitle: "綁定郵箱",
        emailLabel: "郵箱",
        alreadyAuthorized: "該帳號已登入",
        switchToAccount: "切換到該帳號",
        phoneConfirm: "這個號碼正確嗎？",
        edit: "編輯",
        yes: "是",
        signUpTitle: "你的資訊",
        signUpHelp: "輸入你的名字和新增頭像.",
        firstNamePlaceholder: "名字",
        lastNamePlaceholder: "姓氏",
        chooseLanguage: "选择语言 / Language",
        codeSentApp: "驗證碼已發送到你在其他裝置上登入的 Tellomi",
        codeSentCallFormat: "正在撥打 %@ 播報驗證碼",
        useSms: "改用簡訊接收",
        cancel: "取消"
    )
}

func tellomiCloudPasswordCopy(languageCode: String) -> (title: String, notice: String, forgot: String) {
    let resolved = tellomiChromeLanguageCode(savedLanguageCode: languageCode)
    if tellomiLoginCopyFollowsPack(resolved), let strings = tellomiAppliedPackStrings(matching: resolved) {
        return (strings.LoginPassword_Title, strings.LoginPassword_PasswordHelp, strings.LoginPassword_ForgotPassword)
    }
    switch tellomiLoginScript(languageCode: resolved) {
    case .hans:
        return ("两步验证", "请输入两步验证密码", "忘记密码？")
    case .hant:
        return ("兩步驟驗證", "請輸入兩步驟驗證密碼", "忘記密碼？")
    case .english:
        return ("Two-step verification", "Enter your two-step verification password.", "Forgot password?")
    }
}

func tellomiLoginLanguageIsChinese(_ languageCode: String) -> Bool {
    let code = tellomiChromeLanguageCode(savedLanguageCode: languageCode).lowercased()
    return code == "zh" || code.hasPrefix("zh-")
}

/// Chinese when the langpack or the system language is Chinese. An empty
/// preferred-language list (no signal) stays Chinese: mainland is the default.
func tellomiLoginPrefersChinese(languageCode: String) -> Bool {
    return tellomiLoginScript(languageCode: tellomiChromeLanguageCode(savedLanguageCode: languageCode)) != .english
}

/// Bundled Chinese for the login and sign-up labels that otherwise come from the
/// English pack fallback. Nil when the chrome language is not Chinese, so another
/// language chosen in Settings keeps that pack.
func tellomiBundledChineseLoginCopy(_ strings: PresentationStrings) -> TellomiLoginCopy? {
    let code = tellomiInterfaceLanguageCode(strings)
    if tellomiLoginPrefersChinese(languageCode: code) {
        return tellomiLoginCopy(languageCode: code)
    }
    return nil
}

/// Login server alerts use `presentationData.strings.Login_*`, the same mapping Telegram
/// already has. Before a Chinese langpack is applied that pack is English, so a Chinese
/// login screen showed the English sentence. When the chrome language is Chinese and the
/// text is still that English sentence, use the bundled translation. A pack that is already
/// Chinese is left as it is.
func tellomiLocalizedServerAlert(_ text: String, strings: PresentationStrings) -> String {
    let script = tellomiLoginScript(languageCode: tellomiInterfaceLanguageCode(strings))
    guard script != .english else {
        return text
    }
    let simplified = script == .hans
    var table: [String: String] = [:]
    func bind(_ english: String, _ hans: String, _ hant: String) {
        if !english.isEmpty {
            table[english] = simplified ? hans : hant
        }
    }
    let english = defaultPresentationStrings
    let packIsEnglish = tellomiLoginScript(languageCode: strings.primaryComponent.languageCode) == .english
    func row(_ englishText: String, _ live: String, _ hans: String, _ hant: String) {
        bind(englishText, hans, hant)
        if packIsEnglish {
            bind(live, hans, hant)
        }
    }
    row(english.Login_CodeFloodError, strings.Login_CodeFloodError, "尝试次数过多，请稍后再试。", "嘗試次數過多，請稍後再試。")
    row(english.Login_InvalidPhoneError, strings.Login_InvalidPhoneError, "手机号码无效，请重试。", "手機號碼無效，請重試。")
    row(english.Login_PhoneFloodError, strings.Login_PhoneFloodError, "抱歉，你最近删除并重建账号的次数过多。请等待几天后再重新注册。", "抱歉，你最近刪除並重建帳號的次數過多。請等待幾天後再重新註冊。")
    row(english.Login_ErrorAppOutdated, strings.Login_ErrorAppOutdated, "请将 Tellomi 更新到最新版本后再登录。", "請將 Tellomi 更新到最新版本後再登入。")
    row(english.Login_PhoneBannedError, strings.Login_PhoneBannedError, "此手机号码已被封禁。", "此手機號碼已被封鎖。")
    row(english.Login_UnknownError, strings.Login_UnknownError, "发生错误，请稍后再试。", "發生錯誤，請稍後再試。")
    row(english.Login_NetworkError, strings.Login_NetworkError, "请检查网络连接后重试。", "請檢查網路連線後重試。")
    row(english.Login_PhoneNumberHelp, strings.Login_PhoneNumberHelp, "帮助", "幫助")
    row(english.Login_InvalidCodeError, strings.Login_InvalidCodeError, "验证码无效，请重试。", "驗證碼無效，請重試。")
    row(english.Login_CodeExpired, strings.Login_CodeExpired, "验证码已过期，请重新登录。", "驗證碼已過期，請重新登入。")
    row(english.Login_InvalidEmailTokenError, strings.Login_InvalidEmailTokenError, "发生错误，请重试。", "發生錯誤，請重試。")
    row(english.Login_InvalidEmailAddressError, strings.Login_InvalidEmailAddressError, "发生错误，请重试。", "發生錯誤，請重試。")
    row(english.Login_EmailNotConfiguredError, strings.Login_EmailNotConfiguredError, "需要一个邮箱账号，以便把错误详情发给我们。\n\n请到系统设置 > 密码与账户 > 添加账户，设置一个邮箱账号。", "需要一個郵箱帳號，以便把錯誤詳情發給我們。\n\n請到系統設定 > 密碼與帳戶 > 加入帳戶，設定一個郵箱帳號。")
    row(english.Login_ResetAccountProtected_LimitExceeded, strings.Login_ResetAccountProtected_LimitExceeded, "该账号的当前用户取消了你最近的重置请求。请在 7 天后再试。", "該帳號的目前使用者取消了你最近的重設請求。請在 7 天後再試。")
    row(english.Login_ResetAccountProtected_Reset, strings.Login_ResetAccountProtected_Reset, "重置", "重設")
    row(english.TwoStepAuth_RecoveryUnavailable, strings.TwoStepAuth_RecoveryUnavailable, "你在设置密码时没有提供恢复邮箱，现在只能回忆密码或重置账号。", "你在設定密碼時沒有提供恢復郵箱，現在只能回憶密碼或重設帳號。")
    row(english.TwoStepAuth_RecoveryFailed, strings.TwoStepAuth_RecoveryFailed, "你现在只能回忆密码或重置账号。", "你現在只能回憶密碼或重設帳號。")
    row(english.TwoStepAuth_ResetAccountConfirmation, strings.TwoStepAuth_ResetAccountConfirmation, "如果继续重置账号，你将丢失所有聊天、消息以及分享过的媒体和文件。", "如果繼續重設帳號，你將丟失所有聊天、訊息以及分享過的媒體和檔案。")
    row(english.Common_OK, strings.Common_OK, "好", "好")
    row(english.Common_Cancel, strings.Common_Cancel, "取消", "取消")
    row(english.ChatSettings_ConnectionType_UseProxy, strings.ChatSettings_ConnectionType_UseProxy, "使用代理", "使用代理")
    return table[text] ?? text
}
