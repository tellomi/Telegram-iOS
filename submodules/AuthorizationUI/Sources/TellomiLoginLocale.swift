import Foundation
import SwiftSignalKit
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

/// Written by the login language button and by Settings ▸ Language. Login chrome reads this
/// before the saved pack, so a pre-login choice applies with no network and survives restart.
public let tellomiPreferredInterfaceLanguageKey = "TellomiPreferredInterfaceLanguage"

public enum TellomiLoginScript: Equatable {
    case hans
    case hant
    case english
}

/// 简体中文, 繁體中文, or English. Traditional is matched before the generic `zh` prefix.
/// Classifies `languageCode` as given. Callers that want the login choice pass
/// `tellomiChromeLanguageCode` first.
public func tellomiLoginScript(languageCode: String) -> TellomiLoginScript {
    let code = languageCode.lowercased().replacingOccurrences(of: "_", with: "-")
    if code == "zh-hant" || code.hasPrefix("zh-hant") || code == "zh-tw" || code.hasPrefix("zh-tw") || code == "zh-hk" || code.hasPrefix("zh-hk") || code == "zh-mo" || code.hasPrefix("zh-mo") {
        return .hant
    }
    if code == "zh" || code.hasPrefix("zh-") {
        return .hans
    }
    return .english
}

/// `简体中文 ▾` / `繁體中文 ▾` / `English ▾`.
public func tellomiLanguageButtonTitle(languageCode: String) -> String {
    let name: String
    switch tellomiLoginScript(languageCode: tellomiChromeLanguageCode(savedLanguageCode: languageCode)) {
    case .hans:
        name = "简体中文"
    case .hant:
        name = "繁體中文"
    case .english:
        name = "English"
    }
    return name + " \u{25BE}"
}

public func tellomiRememberInterfaceLanguage(_ languageCode: String) {
    UserDefaults.standard.set(languageCode, forKey: tellomiPreferredInterfaceLanguageKey)
    tellomiMarkSystemLangPackApplied()
}

/// Persists the built-in choice and marks it applied, so a later Settings pack is what wins
/// only after that screen writes the same key.
public func tellomiApplyInterfaceLanguage(accountManager: AccountManager<TelegramAccountManagerTypes>, languageCode: String) {
    tellomiRememberInterfaceLanguage(languageCode)
    let info = tellomiBuiltinInterfaceLanguages().first(where: { $0.languageCode == languageCode })
    let _ = tellomiStoreInterfaceLanguage(accountManager: accountManager, languageCode: languageCode, localizedName: info?.localizedTitle ?? languageCode, pluralizationCode: info?.customPluralizationCode).start()
}

/// Language the Tellomi welcome and login chrome should use.
/// Pass `primaryComponent.languageCode`. `baseLanguageCode` is the pack's English fallback
/// once zh-hans is applied, which kept the login screens in English after 「开始使用」.
/// A choice from the login language button wins immediately. Otherwise a Chinese system shows
/// Chinese until the automatic pack has been applied, and a later choice in Settings wins.
public func tellomiChromeLanguageCode(savedLanguageCode: String) -> String {
    if let stored = UserDefaults.standard.string(forKey: tellomiPreferredInterfaceLanguageKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
        return stored
    }
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

/// Rows the language screen always offers, even before `langpack.getLanguages` returns.
/// Selecting one still downloads that pack. A later server list keeps its own copy of the same code.
public func tellomiBuiltinInterfaceLanguages() -> [LocalizationInfo] {
    return [
        LocalizationInfo(languageCode: "zh-hans", baseLanguageCode: "en", customPluralizationCode: "zh", title: "Chinese (Simplified)", localizedTitle: "简体中文", isOfficial: true, totalStringCount: 0, translatedStringCount: 0, platformUrl: ""),
        LocalizationInfo(languageCode: "zh-hant", baseLanguageCode: "en", customPluralizationCode: "zh", title: "Chinese (Traditional)", localizedTitle: "繁體中文", isOfficial: true, totalStringCount: 0, translatedStringCount: 0, platformUrl: ""),
        LocalizationInfo(languageCode: "en", baseLanguageCode: nil, customPluralizationCode: nil, title: "English", localizedTitle: "English", isOfficial: true, totalStringCount: 0, translatedStringCount: 0, platformUrl: ""),
    ]
}
