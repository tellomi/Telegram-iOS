import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

/// Set after zh-hans / zh-hant has been applied once. A later choice in Settings is left alone.
/// Reinstalling the app clears this key together with the saved langpack.
public let tellomiSystemLangPackDefaultsKey = "TellomiDidApplySystemLangPack"

/// Server langpack for a built-in Chinese localization. Nil for English and every other language.
/// `zh-Hans-US` and `zh-Hans-CN` are `zh-Hans`. `zh-Hant-TW` and `zh-Hant-HK` are `zh-Hant`.
public func tellomiLangPackCode(preferredLanguages: [String]) -> String? {
    let resolved = tellomiResolvedBuiltinLanguage(preferredLanguages: preferredLanguages, explicitChoice: nil)
    return resolved == "en" ? nil : resolved
}

/// Server langpack for a Chinese system language. Nil for every other language.
public func tellomiSystemLangPackCode() -> String? {
    return tellomiLangPackCode(preferredLanguages: tellomiDevicePreferredLanguages())
}

/// `FLOOD_WAIT_N` as a sentence. A pack that already translated `Login.CodeFloodWait` wins.
/// Simplified and Traditional stay in this client when the pack is still the English string.
public func tellomiLocalizedLoginFloodWait(seconds: Int32?, strings: PresentationStrings) -> String {
    guard let seconds, seconds > 0 else {
        return tellomiLocalizedLoginFloodFallback(strings: strings)
    }
    let count = String(seconds)
    let pack = strings.Login_CodeFloodWait(count).string
    let english = "Try again in \(count) seconds."
    if pack != english && !pack.isEmpty && pack != "Login.CodeFloodWait" {
        return pack
    }
    switch tellomiLoginScript(languageCode: tellomiChromeLanguageCode(savedLanguageCode: strings.primaryComponent.languageCode)) {
    case .hans:
        return "请在 \(count) 秒后重试。"
    case .hant:
        return "請在 \(count) 秒後再試。"
    case .english:
        return english
    }
}

private func tellomiLocalizedLoginFloodFallback(strings: PresentationStrings) -> String {
    let pack = strings.Login_CodeFloodError
    let english = "Too many attempts, please try again later."
    if pack != english && !pack.isEmpty {
        return pack
    }
    switch tellomiLoginScript(languageCode: tellomiChromeLanguageCode(savedLanguageCode: strings.primaryComponent.languageCode)) {
    case .hans:
        return "尝试次数过多，请稍后再试。"
    case .hant:
        return "嘗試次數過多，請稍後再試。"
    case .english:
        return english
    }
}

public func tellomiMarkSystemLangPackApplied() {
    UserDefaults.standard.set(true, forKey: tellomiSystemLangPackDefaultsKey)
}

/// Written by the login language button and by Settings ▸ Language. Login chrome reads this
/// before the saved pack, so a pre-login choice applies with no network and survives restart.

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

/// Remembers the choice. Does not write an empty pack: that used to replace
/// `localizationSettings` with version 0 and no strings, so the UI kept `en.lproj`
/// except for the locally written agreement sentence.
public func tellomiApplyInterfaceLanguage(accountManager: AccountManager<TelegramAccountManagerTypes>, languageCode: String) {
    let _ = accountManager
    tellomiRememberInterfaceLanguage(languageCode)
}

/// Languages whose login chrome is the bundled Tellomi copy (简体, 繁體, English).
/// Every other code follows the downloaded `ios` pack, with that English copy as the
/// fallback for keys the pack does not have.
public func tellomiLoginCopyFollowsPack(_ languageCode: String) -> Bool {
    let code = languageCode.lowercased().replacingOccurrences(of: "_", with: "-")
    if code == "en" || code.hasPrefix("en-") {
        return false
    }
    return tellomiLoginScript(languageCode: code) == .english
}

private let tellomiAppliedPack = Atomic<(code: String, strings: PresentationStrings)?>(value: nil)

public func tellomiNoteAppliedPack(_ strings: PresentationStrings) {
    let _ = tellomiAppliedPack.swap((strings.primaryComponent.languageCode, strings))
}

func tellomiAppliedPackStrings(matching languageCode: String) -> PresentationStrings? {
    return tellomiAppliedPack.with { noted in
        guard let noted, tellomiLanguageCodesMatch(noted.code, languageCode) else {
            return nil
        }
        return noted.strings
    }
}

func tellomiPresentationStrings(_ settings: LocalizationSettings) -> PresentationStrings {
    let primary = settings.primaryComponent
    return PresentationStrings(primaryComponent: PresentationStrings.Component(languageCode: primary.languageCode, localizedName: primary.localizedName, pluralizationRulesCode: primary.customPluralizationCode, dict: dictFromLocalization(primary.localization)), secondaryComponent: settings.secondaryComponent.flatMap({ PresentationStrings.Component(languageCode: $0.languageCode, localizedName: $0.localizedName, pluralizationRulesCode: $0.customPluralizationCode, dict: dictFromLocalization($0.localization)) }), groupingSeparator: "")
}

/// Upstream language switch: `langpack.getLanguage` plus `langpack.getLangPack` for the
/// language and its base (`downloadAndApplyLocalization`). The `lang_pack` argument stays
/// `""`, which the session fills from `initConnection` (`"ios"`).
public func tellomiDownloadAndApplyInterfaceLanguage(account: UnauthorizedAccount, accountManager: AccountManager<TelegramAccountManagerTypes>, languageCode: String) -> Signal<PresentationStrings, DownloadAndApplyLocalizationError> {
    return TelegramEngineUnauthorized(account: account).localization.downloadAndApplyLocalization(accountManager: accountManager, languageCode: languageCode)
    |> mapToSignal { _ -> Signal<PresentationStrings, DownloadAndApplyLocalizationError> in
        return accountManager.transaction { transaction -> PresentationStrings? in
            guard let settings = transaction.getSharedData(SharedDataKeys.localizationSettings)?.get(LocalizationSettings.self) else {
                return nil
            }
            return tellomiPresentationStrings(settings)
        }
        |> castError(DownloadAndApplyLocalizationError.self)
        |> mapToSignal { strings -> Signal<PresentationStrings, DownloadAndApplyLocalizationError> in
            if let strings {
                return .single(strings)
            }
            return .fail(.generic)
        }
    }
}

/// A language stored by the old login button: version 0 and no strings, so every
/// key falls back to `en.lproj`. Returns that code so the caller can download the pack.
public func tellomiEmptyStoredLanguageCode(_ settings: LocalizationSettings?) -> String? {
    guard let primary = settings?.primaryComponent else {
        return nil
    }
    let code = primary.languageCode.lowercased()
    if code.isEmpty || code == "en" {
        return nil
    }
    if primary.localization.entries.isEmpty {
        return primary.languageCode
    }
    return nil
}

public func tellomiStartInterfaceLanguageDownload(account: UnauthorizedAccount, accountManager: AccountManager<TelegramAccountManagerTypes>, languageCode: String, disposable: MetaDisposable, applied: @escaping (PresentationStrings) -> Void) {
    // The login pages for 简体 / 繁體 / English are bundled. Remember the choice
    // before the request so the current screen can redraw without waiting on
    // langpack.getLanguage / getLangPack. A missing server pack must not undo that.
    tellomiRememberInterfaceLanguage(languageCode)
    disposable.set((tellomiDownloadAndApplyInterfaceLanguage(account: account, accountManager: accountManager, languageCode: languageCode)
    |> deliverOnMainQueue).start(next: { strings in
        tellomiRememberInterfaceLanguage(languageCode)
        tellomiNoteAppliedPack(strings)
        applied(strings)
    }, error: { _ in
    }))
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

/// Region names for the login country list. `localeWithStrings` uses the pack's
/// English base language, so a 简体中文 login still showed "China".
public func tellomiCountryLocale(languageCode: String) -> Locale {
    let code = tellomiChromeLanguageCode(savedLanguageCode: languageCode).lowercased().replacingOccurrences(of: "_", with: "-")
    if code == "zh" || code == "zh-hans" || code == "zh-cn" || code.hasPrefix("zh-hans") {
        return Locale(identifier: "zh-Hans")
    }
    if code == "zh-hant" || code.hasPrefix("zh-hant") || code == "zh-tw" || code.hasPrefix("zh-tw") || code == "zh-hk" || code.hasPrefix("zh-hk") || code == "zh-mo" || code.hasPrefix("zh-mo") {
        return Locale(identifier: "zh-Hant")
    }
    if code == "en" || code.hasPrefix("en-") {
        return Locale(identifier: "en_US")
    }
    return Locale(identifier: code)
}

public func tellomiRegionLocale(languageCode: String) -> Locale {
    return tellomiCountryLocale(languageCode: languageCode)
}

/// Title and search field for the login country list. The loaded Telegram pack can
/// still be English while the login button has selected another language.
public func tellomiCountryListChrome(languageCode: String) -> (title: String, search: String) {
    let code = tellomiChromeLanguageCode(savedLanguageCode: languageCode).lowercased().replacingOccurrences(of: "_", with: "-")
    if code == "zh-hant" || code.hasPrefix("zh-hant") || code == "zh-tw" || code.hasPrefix("zh-tw") || code == "zh-hk" || code.hasPrefix("zh-hk") || code == "zh-mo" || code.hasPrefix("zh-mo") {
        return (title: "國家/地區", search: "搜尋")
    }
    if code == "zh" || code.hasPrefix("zh-") {
        return (title: "国家/地区", search: "搜索")
    }
    let key = code.split(separator: "-").first.map(String.init) ?? code
    let table: [String: (String, String)] = [
        "en": ("Country", "Search"),
        "ar": ("البلد", "بحث"),
        "be": ("Краіна", "Пошук"),
        "ca": ("País", "Cerca"),
        "de": ("Land", "Suchen"),
        "es": ("País", "Buscar"),
        "fa": ("کشور", "جستجو"),
        "fr": ("Pays", "Rechercher"),
        "id": ("Negara", "Cari"),
        "it": ("Paese", "Cerca"),
        "ko": ("국가", "검색"),
        "ms": ("Negara", "Cari"),
        "nl": ("Land", "Zoeken"),
        "pl": ("Kraj", "Szukaj"),
        "pt": ("País", "Buscar"),
        "ru": ("Страна", "Поиск"),
        "tr": ("Ülke", "Ara"),
        "uk": ("Країна", "Пошук"),
        "uz": ("Mamlakat", "Qidirish")
    ]
    if let pair = table[key] {
        return (title: pair.0, search: pair.1)
    }
    return (title: "Country", search: "Search")
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
