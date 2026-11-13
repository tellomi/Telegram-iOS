import Foundation

/// The welcome carousel stays in the tree. `true` does not install it: `.empty`
/// (first launch, logout, add account, switch account) is advanced to phone entry.
/// Set this to `false` to show the carousel again.
public let tellomiSkipsWelcomeSplash = true

public enum TellomiLoggedOutRoot: Equatable {
    case welcome
    case phoneEntry(countryCode: Int32)
}

/// Logged-out root. The phone screen keeps the calling code the caller already chose.
public func tellomiLoggedOutRoot(skipsWelcome: Bool, countryCode: Int32) -> TellomiLoggedOutRoot {
    if skipsWelcome {
        return .phoneEntry(countryCode: countryCode)
    }
    return .welcome
}

public enum TellomiPhoneRootBack: Equatable {
    /// Another account is signed in. Close removes this login attempt.
    case dismissAddAccount
    /// The carousel is the screen under the phone field.
    case showWelcome
    /// Nothing is under the phone field. Leaving would be the carousel or an empty stack.
    case stayOnPhone
}

public func tellomiPhoneRootBack(hasOtherAccounts: Bool, skipsWelcome: Bool) -> TellomiPhoneRootBack {
    if hasOtherAccounts {
        return .dismissAddAccount
    }
    if skipsWelcome {
        return .stayOnPhone
    }
    return .showWelcome
}

/// Close is shown when it has somewhere to go. A skipped welcome does not.
public func tellomiPhoneRootShowsDismiss(hasOtherAccounts: Bool, skipsWelcome: Bool) -> Bool {
    if hasOtherAccounts {
        return true
    }
    return !skipsWelcome
}

/// Login language, with the inputs the splash used to apply.
/// A saved choice wins. Otherwise a Chinese system is Chinese before any pack download,
/// including when the welcome carousel is not shown. After the automatic pack is applied,
/// Settings ▸ Language is the saved code.
public func tellomiChromeLanguageCode(savedLanguageCode: String, preferredInterfaceLanguage: String?, systemPackApplied: Bool, systemLangPackCode: String?) -> String {
    if let stored = preferredInterfaceLanguage?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
        return stored
    }
    if systemPackApplied {
        return savedLanguageCode
    }
    let saved = savedLanguageCode.lowercased()
    if saved == "zh" || saved.hasPrefix("zh-") {
        return savedLanguageCode
    }
    if let systemLangPackCode {
        return systemLangPackCode
    }
    return savedLanguageCode
}

/// What `auth.sendCode` asked the login flow to do with an email.
/// An address is never sent as `phone_number`. The phone screen stays the phone screen.
public enum TellomiSentCodeEmailKind: Equatable {
    /// `auth.sentCodeTypeEmailCode`. `setup` is true for the code from `account.sendVerifyEmailCode`.
    case email(setup: Bool)
    /// `auth.sentCodeTypeSetUpEmailRequired`.
    case setupRequired
    case other
}

public enum TellomiOfficialEmailLoginStep: Equatable {
    /// Show `AuthorizationSequenceEmailEntryController` (`.setup`).
    /// Continue calls `account.sendVerifyEmailCode` with `emailVerifyPurposeLoginSetup`.
    case setupEmail
    /// Code screen. Submit `account.verifyEmail` with `emailVerifyPurposeLoginSetup`.
    case verifySetupEmail
    /// Code screen. Submit `auth.signIn` with `email_verification` (`flags.1`), not `phone_code`.
    case signInWithEmailCode
}

public func tellomiOfficialEmailLoginStep(_ kind: TellomiSentCodeEmailKind) -> TellomiOfficialEmailLoginStep? {
    switch kind {
    case .setupRequired:
        return .setupEmail
    case .email(setup: true):
        return .verifySetupEmail
    case .email(setup: false):
        return .signInWithEmailCode
    case .other:
        return nil
    }
}
