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

/// `translations_manual_enabled` is the server's health gate. A missing value stays off.
/// `tellomi_translate_enabled` is that same switch when the manual string is absent.
public func tellomiManualTranslationAvailable(manual: String?, flag: Any?) -> Bool {
    if let manual {
        return manual.lowercased() == "enabled"
    }
    if let enabled = flag as? Bool {
        return enabled
    }
    if let text = flag as? String {
        switch text.lowercased() {
        case "enabled", "1", "true":
            return true
        default:
            return false
        }
    }
    if let number = flag as? Double {
        return number != 0
    }
    if let number = flag as? Int {
        return number != 0
    }
    return false
}

/// Whole-chat translation also needs `TELLOMI_TRANSLATE_AUTO=1`, which the server reports as this string.
public func tellomiAutoTranslationAvailable(auto: String?) -> Bool {
    return auto?.lowercased() == "enabled"
}

/// The self-hosted model accepts only these target codes. `zh-hant` is not one of them.
public func tellomiTranslationTargetAccepted(_ code: String?) -> Bool {
    switch code?.lowercased() {
    case "zh", "zh-cn", "zh-hans":
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
    guard tellomiTranslationTargetAccepted(to) else {
        return .refused
    }
    let source = tellomiNormalizeTranslationLanguage(from) ?? "en"
    guard source == "en" else {
        return .refused
    }
    return .server
}

public enum TellomiTranslateFailure: Equatable {
    case invalidLanguage
    case unavailable
    case other
}

public func tellomiTranslateFailure(_ description: String) -> TellomiTranslateFailure {
    switch description {
    case "TO_LANG_INVALID":
        return .invalidLanguage
    case "TRANSLATE_REQ_FAILED", "AICOMPOSE_TIMEOUT":
        return .unavailable
    default:
        return .other
    }
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

public let tellomiDraftAudioByteLimit = 8 * 1024 * 1024

public enum TellomiDraftAudioDecision: Equatable {
    case accepted
    case empty
    case tooLong
    case unsupported
}

public func tellomiDraftAudioDecision(byteCount: Int, fileExtension: String) -> TellomiDraftAudioDecision {
    if byteCount <= 0 {
        return .empty
    }
    if byteCount > tellomiDraftAudioByteLimit {
        return .tooLong
    }
    switch fileExtension.lowercased() {
    case "ogg", "opus", "wav", "mp4":
        return .accepted
    default:
        return .unsupported
    }
}

public enum TellomiDraftTranscriptionError: Equatable {
    case notLoggedIn
    case empty
    case tooLong
    case unavailable
    case failed
}

public func tellomiDraftTranscriptionError(_ description: String) -> TellomiDraftTranscriptionError {
    switch description {
    case "USER_ID_INVALID":
        return .notLoggedIn
    case "MEDIA_EMPTY":
        return .empty
    case "AUDIO_TOO_LONG":
        return .tooLong
    case "TRANSCRIPTION_UNAVAILABLE":
        return .unavailable
    case "TRANSCRIPTION_FAILED":
        return .failed
    default:
        return .unavailable
    }
}

public func tellomiDraftTranscriptionPrompt(_ error: TellomiDraftTranscriptionError, languageCode: String) -> String {
    let chinese = languageCode.lowercased().hasPrefix("zh")
    switch error {
    case .notLoggedIn:
        return chinese ? "请先登录后再听写。" : "Sign in before dictation."
    case .empty:
        return chinese ? "没有可听写的录音。" : "There is no recording to transcribe."
    case .tooLong:
        return chinese ? "录音超过 8 MB。" : "The recording is larger than 8 MB."
    case .unavailable:
        return chinese ? "听写服务暂不可用。" : "Dictation is unavailable."
    case .failed:
        return chinese ? "听写失败。" : "Dictation failed."
    }
}
