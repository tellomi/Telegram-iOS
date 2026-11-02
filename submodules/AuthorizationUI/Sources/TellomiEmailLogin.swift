import Foundation

/// Tellomi login-home copy. The langpack does not have these strings. Chinese follows the
/// system language (see `tellomiChromeLanguageCode`) until Settings has chosen a pack.
/// See Tellomi/UPSTREAM_PATCHES.md.
struct TellomiEmailLoginCopy: Equatable {
    let switchToEmail: String
    let switchToPhone: String
    let title: String
    let notice: String
    let placeholder: String
    let invalid: String
    let confirm: String
    let unavailable: String
    let nicknameTitle: String
    let nicknameHelp: String
    let nicknamePlaceholder: String
}

func tellomiEmailLoginCopy(languageCode: String) -> TellomiEmailLoginCopy {
    switch tellomiLoginScript(languageCode: tellomiChromeLanguageCode(savedLanguageCode: languageCode)) {
    case .hant:
        return TellomiEmailLoginCopy(
            switchToEmail: "郵箱登入",
            switchToPhone: "使用手機號登入",
            title: "請輸入郵箱地址",
            notice: "未註冊的郵箱驗證通過後將自動註冊",
            placeholder: "請輸入郵箱地址",
            invalid: "請輸入有效的郵箱地址",
            confirm: "將向該郵箱發送驗證碼",
            unavailable: "該郵箱無法使用",
            nicknameTitle: "你的暱稱",
            nicknameHelp: "填寫暱稱即可完成註冊",
            nicknamePlaceholder: "暱稱"
        )
    case .hans:
        return TellomiEmailLoginCopy(
            switchToEmail: "邮箱登录",
            switchToPhone: "使用手机号登录",
            title: "请输入邮箱地址",
            notice: "未注册的邮箱验证通过后将自动注册",
            placeholder: "请输入邮箱地址",
            invalid: "请输入有效的邮箱地址",
            confirm: "将向该邮箱发送验证码",
            unavailable: "该邮箱无法使用",
            nicknameTitle: "你的昵称",
            nicknameHelp: "填写昵称即可完成注册",
            nicknamePlaceholder: "昵称"
        )
    case .english:
        return TellomiEmailLoginCopy(
        switchToEmail: "Email",
        switchToPhone: "Use phone number",
        title: "Enter your email",
        notice: "An unregistered address is signed up after the code is verified.",
        placeholder: "Enter your email",
        invalid: "Please enter a valid email address.",
        confirm: "We'll send a login code to this address.",
        unavailable: "This email can't be used.",
        nicknameTitle: "Your nickname",
        nicknameHelp: "Enter a nickname to finish signing up.",
        nicknamePlaceholder: "Nickname"
    )
    }
}

