import Foundation

public struct TellomiSignUpAvatarFailure: Equatable {
    public var code: Int32
    public var description: String

    public init(code: Int32, description: String) {
        self.code = code
        self.description = description
    }
}

public enum TellomiSignUpAvatarStep: Equatable {
    case working
    case uploaded
    case failed(TellomiSignUpAvatarFailure)
}

public enum TellomiSignUpAvatarDecision: Equatable {
    /// A progress event. Signup stays in flight and is not cancelled.
    case wait
    /// Store the account. No alert.
    case createAccount
    /// Store the account, then show this text. The upload can be retried.
    case createAccountAndShowError(TellomiSignUpAvatarFailure)
}

/// An avatar upload failure does not cancel account creation.
public func tellomiSignUpAvatarDecision(_ step: TellomiSignUpAvatarStep) -> TellomiSignUpAvatarDecision {
    switch step {
    case .working:
        return .wait
    case .uploaded:
        return .createAccount
    case let .failed(failure):
        return .createAccountAndShowError(failure)
    }
}

public func tellomiSignUpAvatarErrorLabel(code: Int32, description: String) -> String {
    let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty {
        return "\(code)"
    }
    return "\(code) \(text)"
}

/// `Tellomi.SignUp.AvatarFailed` is a format string with one `%@` for the error label.
public func tellomiSignUpAvatarFailureText(code: Int32, description: String, languageCode: String, pack: [String: String] = [:]) -> String {
    let label = tellomiSignUpAvatarErrorLabel(code: code, description: description)
    let template = tellomiSignUpAvatarTemplate(languageCode: languageCode, pack: pack)
    if template.contains("%@") {
        return String(format: template, label)
    }
    return template + " " + label
}

public func tellomiSignUpAvatarRetryTitle(languageCode: String, pack: [String: String] = [:]) -> String {
    return tellomiSignUpAvatarPackString(languageCode: languageCode, pack: pack, key: "Tellomi.SignUp.AvatarRetry", english: "Retry", simplified: "重试", traditional: "重試")
}

private func tellomiSignUpAvatarTemplate(languageCode: String, pack: [String: String]) -> String {
    return tellomiSignUpAvatarPackString(languageCode: languageCode, pack: pack, key: "Tellomi.SignUp.AvatarFailed", english: "Couldn't upload the profile photo (%@)", simplified: "头像上传失败（%@）", traditional: "頭像上傳失敗（%@）")
}

private func tellomiSignUpAvatarPackString(languageCode: String, pack: [String: String], key: String, english: String, simplified: String, traditional: String) -> String {
    if let value = pack[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, value != key {
        return value
    }
    let code = languageCode.lowercased()
    if code == "zh-hant" || code.hasPrefix("zh-hant") || code == "zh-tw" || code.hasPrefix("zh-tw") || code == "zh-hk" || code.hasPrefix("zh-hk") || code == "zh-mo" || code.hasPrefix("zh-mo") {
        return traditional
    }
    if code == "zh" || code.hasPrefix("zh") {
        return simplified
    }
    return english
}
