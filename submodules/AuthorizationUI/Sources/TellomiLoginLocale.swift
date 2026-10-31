import Foundation
import TelegramCore
import TelegramPresentationData

/// Set after zh-hans / zh-hant has been applied once. A later choice in Settings is left alone.
/// Reinstalling the app clears this key together with the saved langpack.
public let tellomiSystemLangPackDefaultsKey = "TellomiDidApplySystemLangPack"

/// The system language list, not the list filtered by the app's `en.lproj`.
/// An English-only bundle makes `Locale.preferredLanguages` report `en` on a Chinese phone.
public func tellomiDevicePreferredLanguages() -> [String] {
    if let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String], !global.isEmpty {
        return global
    }
    return Locale.preferredLanguages
}

/// Server langpack for a Chinese system language. Nil for every other language.
public func tellomiSystemLangPackCode() -> String? {
    return tellomiLangPackCode(preferredLanguages: tellomiDevicePreferredLanguages())
}

public func tellomiMarkSystemLangPackApplied() {
    UserDefaults.standard.set(true, forKey: tellomiSystemLangPackDefaultsKey)
}

/// Language the Tellomi welcome and login chrome should use.
/// Pass `primaryComponent.languageCode`. `baseLanguageCode` is the pack's English fallback
/// once zh-hans is applied, which kept the login screens in English after 「开始使用」.
/// A Chinese system shows Chinese immediately. Once the automatic pack has been applied,
/// a later choice in Settings wins.
public func tellomiChromeLanguageCode(savedLanguageCode: String) -> String {
    if UserDefaults.standard.bool(forKey: tellomiSystemLangPackDefaultsKey) {
        return savedLanguageCode
    }
    let saved = savedLanguageCode.lowercased()
    if saved == "zh" || saved.hasPrefix("zh-") {
        return savedLanguageCode
    }
    if let system = tellomiSystemLangPackCode() {
        return system
    }
    return savedLanguageCode
}

/// Langpack to download when the system language is Chinese and this install has not applied it yet.
/// Returns nil when the saved language should be kept.
public func tellomiLangPackCodePendingApplication(currentLanguageCode: String) -> String? {
    if UserDefaults.standard.bool(forKey: tellomiSystemLangPackDefaultsKey) {
        return nil
    }
    guard let code = tellomiSystemLangPackCode() else {
        return nil
    }
    if currentLanguageCode == code {
        tellomiMarkSystemLangPackApplied()
        return nil
    }
    return code
}

/// Login and settings chrome. Uses the active pack, not its English base language.
public func tellomiInterfaceLanguageCode(_ strings: PresentationStrings) -> String {
    return tellomiChromeLanguageCode(savedLanguageCode: strings.primaryComponent.languageCode)
}
