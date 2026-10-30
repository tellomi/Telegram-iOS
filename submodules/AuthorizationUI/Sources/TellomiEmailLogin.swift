import Foundation

/// Tellomi login-home copy. The langpack does not have these strings. Chinese follows the
/// sign-up agreement; every other language uses English. See Tellomi/UPSTREAM_PATCHES.md.
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
    let code = languageCode.lowercased()
    if code == "zh" || code.hasPrefix("zh-") {
        return TellomiEmailLoginCopy(
            switchToEmail: "使用邮箱登录",
            switchToPhone: "使用手机号登录",
            title: "你的邮箱",
            notice: "我们将向该邮箱发送验证码",
            placeholder: "邮箱",
            invalid: "请输入有效的邮箱地址",
            confirm: "将向该邮箱发送验证码",
            unavailable: "该邮箱无法使用",
            nicknameTitle: "你的昵称",
            nicknameHelp: "填写昵称即可完成注册",
            nicknamePlaceholder: "昵称"
        )
    }
    return TellomiEmailLoginCopy(
        switchToEmail: "Log in with email",
        switchToPhone: "Log in with phone number",
        title: "Your email",
        notice: "We'll send a login code to this address.",
        placeholder: "Email",
        invalid: "Please enter a valid email address.",
        confirm: "We'll send a login code to this address.",
        unavailable: "This email can't be used.",
        nicknameTitle: "Your nickname",
        nicknameHelp: "Enter a nickname to finish signing up.",
        nicknamePlaceholder: "Nickname"
    )
}

func tellomiNormalizedLoginEmail(_ raw: String) -> String {
    return raw.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// An address `auth.sendCode` can carry in `phone_number`. One `@`, a dotted domain, no whitespace.
func tellomiIsLoginEmail(_ raw: String) -> Bool {
    let value = tellomiNormalizedLoginEmail(raw)
    if value.count < 3 || value.count > 254 {
        return false
    }
    if value.contains(where: { $0.isWhitespace }) {
        return false
    }
    let parts = value.split(separator: "@", omittingEmptySubsequences: false)
    if parts.count != 2 {
        return false
    }
    let local = parts[0]
    let domain = parts[1]
    if local.isEmpty || local.count > 64 {
        return false
    }
    if domain.count < 3 || !domain.contains(".") || domain.hasPrefix(".") || domain.hasSuffix(".") || domain.contains("..") {
        return false
    }
    return true
}
