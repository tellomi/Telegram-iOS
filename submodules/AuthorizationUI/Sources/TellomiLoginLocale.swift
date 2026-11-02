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
    let info = tellomiBuiltinInterfaceLanguages().first(where: { $0.languageCode.lowercased() == languageCode.lowercased() })
    tellomiApplyInterfaceLanguage(accountManager: accountManager, info: info ?? LocalizationInfo(languageCode: languageCode, baseLanguageCode: "en", customPluralizationCode: nil, title: languageCode, localizedTitle: languageCode, isOfficial: true, totalStringCount: 0, translatedStringCount: 0, platformUrl: ""))
}

public func tellomiApplyInterfaceLanguage(accountManager: AccountManager<TelegramAccountManagerTypes>, info: LocalizationInfo) {
    tellomiRememberInterfaceLanguage(info.languageCode)
    let _ = tellomiStoreInterfaceLanguage(accountManager: accountManager, languageCode: info.languageCode, localizedName: info.localizedTitle, pluralizationCode: info.customPluralizationCode).start()
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

/// Languages the client can offer before `langpack.getLanguages` returns.
///
/// The login card used to hardcode three rows. The app's `empty_languages` list
/// (plus English and Traditional Chinese, which has bundled login copy) is the
/// set of codes this binary is built to display. Translated UI strings for the
/// codes other than English still come from the server langpack. Login chrome
/// itself is bundled for zh-hans, zh-hant, and English; any other code falls
/// back to English chrome until that pack is applied.
public func tellomiBuiltinInterfaceLanguages() -> [LocalizationInfo] {
    return tellomiClientInterfaceLanguages
}

/// Server rows replace a bundled row with the same code. Bundled rows the server
/// did not return stay, so a langpack that only lists three languages does not
/// hide the rest of the client catalog.
public func tellomiMergedInterfaceLanguages(server: [LocalizationInfo]) -> [LocalizationInfo] {
    var byCode: [String: LocalizationInfo] = [:]
    for info in tellomiClientInterfaceLanguages {
        byCode[info.languageCode.lowercased()] = info
    }
    for info in server {
        let code = info.languageCode.lowercased()
        if !code.isEmpty {
            byCode[code] = info
        }
    }
    return byCode.values.sorted { lhs, rhs in
        if lhs.localizedTitle != rhs.localizedTitle {
            return lhs.localizedTitle.localizedCompare(rhs.localizedTitle) == .orderedAscending
        }
        return lhs.languageCode < rhs.languageCode
    }
}

private func tellomiLanguage(_ code: String, plural: String?, title: String, native: String) -> LocalizationInfo {
    return LocalizationInfo(languageCode: code, baseLanguageCode: code == "en" ? nil : "en", customPluralizationCode: plural, title: title, localizedTitle: native, isOfficial: true, totalStringCount: 0, translatedStringCount: 0, platformUrl: "")
}

/// Codes match `Telegram/BUILD` `empty_languages`, plus `en` and `zh-hant`.
private let tellomiClientInterfaceLanguages: [LocalizationInfo] = [
    tellomiLanguage("ar", plural: "ar", title: "Arabic", native: "العربية"),
    tellomiLanguage("be", plural: "be", title: "Belarusian", native: "Беларуская"),
    tellomiLanguage("ca", plural: "ca", title: "Catalan", native: "Català"),
    tellomiLanguage("de", plural: "de", title: "German", native: "Deutsch"),
    tellomiLanguage("en", plural: nil, title: "English", native: "English"),
    tellomiLanguage("es", plural: "es", title: "Spanish", native: "Español"),
    tellomiLanguage("fa", plural: "fa", title: "Persian", native: "فارسی"),
    tellomiLanguage("fr", plural: "fr", title: "French", native: "Français"),
    tellomiLanguage("id", plural: "id", title: "Indonesian", native: "Bahasa Indonesia"),
    tellomiLanguage("it", plural: "it", title: "Italian", native: "Italiano"),
    tellomiLanguage("ko", plural: "ko", title: "Korean", native: "한국어"),
    tellomiLanguage("ms", plural: "ms", title: "Malay", native: "Bahasa Melayu"),
    tellomiLanguage("nl", plural: "nl", title: "Dutch", native: "Nederlands"),
    tellomiLanguage("pl", plural: "pl", title: "Polish", native: "Polski"),
    tellomiLanguage("pt", plural: "pt", title: "Portuguese", native: "Português"),
    tellomiLanguage("ru", plural: "ru", title: "Russian", native: "Русский"),
    tellomiLanguage("tr", plural: "tr", title: "Turkish", native: "Türkçe"),
    tellomiLanguage("uk", plural: "uk", title: "Ukrainian", native: "Українська"),
    tellomiLanguage("uz", plural: "uz", title: "Uzbek", native: "Oʻzbek"),
    tellomiLanguage("zh-hans", plural: "zh", title: "Chinese (Simplified)", native: "简体中文"),
    tellomiLanguage("zh-hant", plural: "zh", title: "Chinese (Traditional)", native: "繁體中文"),
]
