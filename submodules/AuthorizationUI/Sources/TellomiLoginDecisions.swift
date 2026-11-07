import Foundation

/// What the login language button does before any network request.
/// Bundled 简体 / 繁體 / English redraw immediately. The langpack download is only a follow-up.
public struct TellomiLanguageApply: Equatable {
    public var code: String
    public var redrawsBeforePackDownload: Bool

    public init(code: String, redrawsBeforePackDownload: Bool) {
        self.code = code
        self.redrawsBeforePackDownload = redrawsBeforePackDownload
    }
}

public func tellomiLanguageApplyPlan(selectedCode: String, currentCode: String) -> TellomiLanguageApply? {
    let selected = selectedCode.lowercased().replacingOccurrences(of: "_", with: "-")
    let current = currentCode.lowercased().replacingOccurrences(of: "_", with: "-")
    if selected == current {
        return nil
    }
    return TellomiLanguageApply(code: selectedCode, redrawsBeforePackDownload: true)
}

/// `auth.sendCode` / `auth.resendCode` daily cap. `FLOOD_WAIT_X` is the same limit with a timer.
public func tellomiCodeRequestIsDailyLimit(_ description: String) -> Bool {
    return description == "PHONE_CODE_FLOOD" || description.hasPrefix("FLOOD_WAIT")
}

public func tellomiResendEnabledAfterCodeLimit(_ limited: Bool) -> Bool {
    return !limited
}

public func tellomiCodeFloodSentence(languageCode: String) -> String {
    let code = languageCode.lowercased().replacingOccurrences(of: "_", with: "-")
    if code == "zh-hant" || code.hasPrefix("zh-hant") || code == "zh-tw" || code.hasPrefix("zh-tw") || code == "zh-hk" || code.hasPrefix("zh-hk") || code == "zh-mo" || code.hasPrefix("zh-mo") {
        return "今天的驗證碼發送次數已達上限（每天最多 10 條），請明天再試。"
    }
    if code == "zh" || code.hasPrefix("zh-") {
        return "今天的验证码发送次数已达上限（每天最多 10 条），请明天再试。"
    }
    return "You can request at most 10 verification codes a day. Try again tomorrow."
}
