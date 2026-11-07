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

/// Live server: the 11th code in a day is `400 PHONE_NUMBER_FLOOD`.
/// A resend inside 60 seconds is `420 FLOOD_WAIT_X`. Those are not the same limit.
public enum TellomiSendCodeThrottle: Equatable {
    case none
    case dailyLimit
    case resendWait(Int32)
}

public func tellomiFloodWaitSeconds(_ description: String) -> Int32? {
    let prefix = "FLOOD_WAIT_"
    guard description.hasPrefix(prefix) else {
        return nil
    }
    guard let seconds = Int32(description.dropFirst(prefix.count)), seconds > 0 else {
        return nil
    }
    return seconds
}

public func tellomiSendCodeThrottle(description: String) -> TellomiSendCodeThrottle {
    if description == "PHONE_NUMBER_FLOOD" {
        return .dailyLimit
    }
    if let seconds = tellomiFloodWaitSeconds(description) {
        return .resendWait(seconds)
    }
    return .none
}

/// The day cap keeps resend off. A short `FLOOD_WAIT` only pauses for those seconds.
public func tellomiResendLockedForTheDay(_ throttle: TellomiSendCodeThrottle) -> Bool {
    if case .dailyLimit = throttle {
        return true
    }
    return false
}

/// A pasted number whose calling code is outside the whitelist stays on `fallback` and shows the notice.
public func tellomiPastedCallingCode(recognized: Int32?, allowed: Set<Int32>, fallback: Int32) -> (code: Int32, rejected: Bool) {
    guard let recognized else {
        return (fallback, false)
    }
    if allowed.contains(recognized) {
        return (recognized, false)
    }
    return (fallback, true)
}

public func tellomiResendPauseSeconds(_ throttle: TellomiSendCodeThrottle) -> Int32? {
    if case let .resendWait(seconds) = throttle {
        return seconds
    }
    return nil
}

public func tellomiBundledPhoneTitle(languageCode: String) -> String {
    let code = languageCode.lowercased().replacingOccurrences(of: "_", with: "-")
    if code == "zh-hant" || code.hasPrefix("zh-hant") || code == "zh-tw" || code.hasPrefix("zh-tw") || code == "zh-hk" || code.hasPrefix("zh-hk") || code == "zh-mo" || code.hasPrefix("zh-mo") {
        return "登入發現更多精彩"
    }
    if code == "zh" || code.hasPrefix("zh-") {
        return "登录发现更多精彩"
    }
    return "Log in to see more"
}

public func tellomiResendWaitSentence(languageCode: String, seconds: Int32) -> String {
    let code = languageCode.lowercased().replacingOccurrences(of: "_", with: "-")
    if code == "zh-hant" || code.hasPrefix("zh-hant") || code == "zh-tw" || code.hasPrefix("zh-tw") || code == "zh-hk" || code.hasPrefix("zh-hk") || code == "zh-mo" || code.hasPrefix("zh-mo") {
        return "發送過於頻繁，請在 \(seconds) 秒後再試。"
    }
    if code == "zh" || code.hasPrefix("zh-") {
        return "发送过于频繁，请在 \(seconds) 秒后再试。"
    }
    return "Too many attempts. Try again in \(seconds) seconds."
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
