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

/// Native name of a bundled login language. Unknown codes fall back to the code itself.
public func tellomiBuiltinLanguageTitle(_ languageCode: String) -> String {
    let code = languageCode.lowercased().replacingOccurrences(of: "_", with: "-")
    return tellomiBundledLanguageNames[code] ?? tellomiBundledLanguageNames[code.split(separator: "-").first.map(String.init) ?? code] ?? languageCode
}

public func tellomiLanguageCodesMatch(_ lhs: String, _ rhs: String) -> Bool {
    let left = lhs.lowercased().replacingOccurrences(of: "_", with: "-")
    let right = rhs.lowercased().replacingOccurrences(of: "_", with: "-")
    return left == right
}

/// Accessibility name for the globe button: the language it will switch, not a word on the control.
public func tellomiLanguageButtonAccessibilityLabel(languageCode: String) -> String {
    let resolved = tellomiChromeLanguageCode(savedLanguageCode: languageCode)
    return tellomiBuiltinLanguageTitle(resolved)
}

/// `简体中文 ▾` / `繁體中文 ▾` / `English ▾`. The control itself is a globe; this remains for accessibility.
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

/// Region names for the login country button. `localeWithStrings` uses the pack's
/// English base language, so 简体中文 still announced "China mainland".
public func tellomiRegionLocale(languageCode: String) -> Locale {
    switch tellomiLoginScript(languageCode: tellomiChromeLanguageCode(savedLanguageCode: languageCode)) {
    case .hans:
        return Locale(identifier: "zh-Hans")
    case .hant:
        return Locale(identifier: "zh-Hant")
    case .english:
        return Locale(identifier: "en_US")
    }
}

private let tellomiBundledLanguageNames: [String: String] = [
    "zh-hans": "简体中文",
    "zh-hant": "繁體中文",
    "en": "English",
    "ar": "العربية",
    "be": "Беларуская",
    "ca": "Català",
    "de": "Deutsch",
    "es": "Español",
    "fa": "فارسی",
    "fr": "Français",
    "id": "Bahasa Indonesia",
    "it": "Italiano",
    "ko": "한국어",
    "ms": "Bahasa Melayu",
    "nl": "Nederlands",
    "pl": "Polski",
    "pt": "Português",
    "ru": "Русский",
    "tr": "Türkçe",
    "uk": "Українська",
    "uz": "Oʻzbek"
]

/// `*.lproj` folders shipped in the app, including the empty string stubs.
/// The login picker used to offer only zh-hans, zh-hant, and en.
private let tellomiBundledLanguageOrder: [(code: String, english: String, plural: String?)] = [
    ("zh-hans", "Chinese (Simplified)", "zh"),
    ("zh-hant", "Chinese (Traditional)", "zh"),
    ("en", "English", nil),
    ("ar", "Arabic", nil),
    ("be", "Belarusian", nil),
    ("ca", "Catalan", nil),
    ("de", "German", nil),
    ("es", "Spanish", nil),
    ("fa", "Persian", nil),
    ("fr", "French", nil),
    ("id", "Indonesian", nil),
    ("it", "Italian", nil),
    ("ko", "Korean", nil),
    ("ms", "Malay", nil),
    ("nl", "Dutch", nil),
    ("pl", "Polish", nil),
    ("pt", "Portuguese", nil),
    ("ru", "Russian", nil),
    ("tr", "Turkish", nil),
    ("uk", "Ukrainian", nil),
    ("uz", "Uzbek", nil)
]

/// Rows the language screen always offers, even before `langpack.getLanguages` returns.
/// Selecting one still downloads that pack. A later server list keeps its own copy of the same code.
public func tellomiBuiltinInterfaceLanguages() -> [LocalizationInfo] {
    return tellomiBundledLanguageOrder.map { item in
        let native = tellomiBundledLanguageNames[item.code] ?? item.english
        return LocalizationInfo(languageCode: item.code, baseLanguageCode: item.code == "en" ? nil : "en", customPluralizationCode: item.plural, title: item.english, localizedTitle: native, isOfficial: true, totalStringCount: 0, translatedStringCount: 0, platformUrl: "")
    }
}
