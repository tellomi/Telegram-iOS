import Foundation

/// Set only when the person picks a language. A fresh install has no value, so the
/// system language is used. Reinstalling clears it.
public let tellomiPreferredInterfaceLanguageKey = "TellomiPreferredInterfaceLanguage"

/// The system language list. `Locale.preferredLanguages` drops languages the bundle
/// does not ship, so an English-only lookup reports `en` on a Chinese phone.
public func tellomiDevicePreferredLanguages() -> [String] {
    if let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String], !global.isEmpty {
        return global
    }
    return Locale.preferredLanguages
}

/// Built-in localization for the welcome and for `lang_code`.
/// An explicit choice wins. Otherwise the first preferred language that we ship
/// (`zh-Hans`, `zh-Hant`, `en`) is used. `zh-Hans-US`, `zh-Hans-CN`, `zh-Hant-TW`
/// and `zh-Hant-HK` keep their script. Anything else is English.
public func tellomiResolvedBuiltinLanguage(preferredLanguages: [String], explicitChoice: String?) -> String {
    if let explicit = explicitChoice?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
        return tellomiCanonicalBuiltinLanguage(explicit)
    }
    for language in preferredLanguages {
        if let match = tellomiMatchBuiltinLanguage(language) {
            return match
        }
    }
    return "en"
}

public func tellomiCanonicalBuiltinLanguage(_ raw: String) -> String {
    return tellomiMatchBuiltinLanguage(raw) ?? raw
}

public func tellomiRememberExplicitLanguage(_ languageCode: String) {
    UserDefaults.standard.set(languageCode, forKey: tellomiPreferredInterfaceLanguageKey)
}

/// `initConnection.lang_code`. A saved English pack is not a choice: `zh-Hans-US` is still `zh-Hans`.
public func tellomiNetworkLanguageCode(savedLanguageCode: String?) -> String {
    if let explicit = UserDefaults.standard.string(forKey: tellomiPreferredInterfaceLanguageKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
        return tellomiCanonicalBuiltinLanguage(explicit)
    }
    let saved = savedLanguageCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !saved.isEmpty && saved.lowercased() != "en" {
        return tellomiCanonicalBuiltinLanguage(saved)
    }
    return tellomiResolvedBuiltinLanguage(preferredLanguages: tellomiDevicePreferredLanguages(), explicitChoice: nil)
}

private func tellomiMatchBuiltinLanguage(_ raw: String) -> String? {
    let code = raw.lowercased().replacingOccurrences(of: "_", with: "-")
    if code.isEmpty {
        return nil
    }
    if code == "zh-hant" || code.hasPrefix("zh-hant-") || code == "zh-tw" || code.hasPrefix("zh-tw-") || code == "zh-hk" || code.hasPrefix("zh-hk-") || code == "zh-mo" || code.hasPrefix("zh-mo-") {
        return "zh-Hant"
    }
    if code == "zh" || code == "zh-hans" || code.hasPrefix("zh-hans-") || code == "zh-cn" || code.hasPrefix("zh-cn-") || code.hasPrefix("zh-") {
        return "zh-Hans"
    }
    if code == "en" || code.hasPrefix("en-") {
        return "en"
    }
    return nil
}
