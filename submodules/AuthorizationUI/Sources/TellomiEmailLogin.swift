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
    if tellomiLoginPrefersChinese(languageCode: languageCode) {
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
    }
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

