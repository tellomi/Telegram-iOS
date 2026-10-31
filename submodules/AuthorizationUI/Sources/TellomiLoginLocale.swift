import Foundation

/// Set after zh-hans / zh-hant has been applied once. A later choice in Settings is left alone.
/// Reinstalling the app clears this key together with the saved langpack.
public let tellomiSystemLangPackDefaultsKey = "TellomiDidApplySystemLangPack"

/// Server langpack for a Chinese system language. Nil for every other language.
public func tellomiSystemLangPackCode() -> String? {
    guard let language = Locale.preferredLanguages.first?.lowercased() else {
        return nil
    }
    if language.hasPrefix("zh-hant") || language.hasPrefix("zh-tw") || language.hasPrefix("zh-hk") || language.hasPrefix("zh-mo") {
        return "zh-hant"
    }
    if language.hasPrefix("zh-hans") || language.hasPrefix("zh-cn") || language == "zh" || language.hasPrefix("zh-") {
        return "zh-hans"
    }
    return nil
}

public func tellomiMarkSystemLangPackApplied() {
    UserDefaults.standard.set(true, forKey: tellomiSystemLangPackDefaultsKey)
}

/// Language the Tellomi welcome and login chrome should use.
/// A Chinese system shows Chinese immediately. The bundled pack is English, and the server
/// langpack is only applied after Start, so `PresentationStrings.baseLanguageCode` is still `en`
/// on that first screen. Once the automatic pack has been applied, a later choice in Settings wins.
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
