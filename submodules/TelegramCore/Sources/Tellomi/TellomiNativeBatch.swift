import Foundation

/// Self-hosted chat translation. Only English to Chinese, only
/// `messages.translateText` / `messages.translateRichMessage`. Apple, Google,
/// Bailian, and Telegram's hosted fallback are not used.
public enum TellomiTranslationRoute: Equatable {
    case server
    case refused
    case unavailable
}

public func tellomiNormalizeTranslationLanguage(_ code: String?) -> String? {
    guard var code = code?.lowercased(), !code.isEmpty else {
        return nil
    }
    if let dash = code.firstIndex(of: "-") {
        code = String(code[..<dash])
    }
    if code == "nb" {
        code = "no"
    }
    return code
}

public func tellomiSelfHostedTranslationEnabled(explicitlyDisabled: Bool) -> Bool {
    return !explicitlyDisabled
}

public func tellomiTranslationDisabledValue(_ value: Any?) -> Bool {
    if let value = value as? Bool {
        return !value
    }
    if let value = value as? String {
        return tellomiTranslationExplicitlyDisabled(value)
    }
    if let value = value as? Int {
        return value == 0
    }
    if let value = value as? Double {
        return value == 0
    }
    return false
}

public func tellomiTranslationExplicitlyDisabled(_ raw: String?) -> Bool {
    guard let raw else {
        return false
    }
    switch raw.lowercased() {
    case "0", "false", "disabled", "off":
        return true
    default:
        return false
    }
}

public func tellomiTranslationRoute(from: String?, to: String?, enabled: Bool, healthy: Bool) -> TellomiTranslationRoute {
    guard enabled else {
        return .refused
    }
    guard healthy else {
        return .unavailable
    }
    let source = tellomiNormalizeTranslationLanguage(from) ?? "en"
    let target = tellomiNormalizeTranslationLanguage(to)
    if source == "en" && target == "zh" {
        return .server
    }
    return .refused
}

/// Local and third-party engines stay off even when the app config asks for them.
public func tellomiTranslationAllowsLocalEngine() -> Bool {
    return false
}

public func tellomiTranslationAllowsAlternativeEngine() -> Bool {
    return false
}

public func tellomiTranslationUnavailableText(languageCode: String) -> String {
    let code = languageCode.lowercased()
    if code.hasPrefix("zh") {
        return "翻译服务暂不可用。"
    }
    return "Translation is unavailable."
}

public func tellomiTranslationOnlyEnglishToChineseText(languageCode: String) -> String {
    let code = languageCode.lowercased()
    if code.hasPrefix("zh") {
        return "目前只支持把英文翻译成中文。"
    }
    return "Only English to Chinese is available."
}

/// `PHONE_NUMBER_FLOOD` is the daily cap of 10 codes. `FLOOD_WAIT` is a short resend wait.
public enum TellomiCodeRequestLimit: Equatable {
    case daily
    case shortWait
    case none
}

public func tellomiCodeRequestLimit(_ description: String) -> TellomiCodeRequestLimit {
    if description == "PHONE_NUMBER_FLOOD" {
        return .daily
    }
    if description.hasPrefix("FLOOD_WAIT") {
        return .shortWait
    }
    return .none
}

public enum TellomiDictationOutcome: Equatable {
    case insertDraft(String)
    case unavailable
}

/// A dictation result is typed into the draft. It does not send a voice message.
public func tellomiDictationOutcome(transcript: String?, healthy: Bool) -> TellomiDictationOutcome {
    guard healthy, let transcript else {
        return .unavailable
    }
    let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty {
        return .unavailable
    }
    return .insertDraft(text)
}

public func tellomiDictationSendsVoice() -> Bool {
    return false
}
