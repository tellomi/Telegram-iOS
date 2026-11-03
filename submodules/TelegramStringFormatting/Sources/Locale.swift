import Foundation
import TelegramPresentationData

private let systemLocaleRegionSuffix: String = {
    let identifier = Locale.current.identifier
    if let range = identifier.range(of: "_") {
        return String(identifier[range.lowerBound...])
    } else {
        return ""
    }
}()

public let usEnglishLocale = Locale(identifier: "en_US")

public func localeWithStrings(_ strings: PresentationStrings) -> Locale {
    let languageCode = localeIdentifierLanguageCode(baseLanguageCode: strings.baseLanguageCode, primaryLanguageCode: strings.primaryComponent.languageCode)
    let code = languageCode + systemLocaleRegionSuffix
    return Locale(identifier: code)
}

/// Language half of the `Locale` identifier used for geocoding and `MKDistanceFormatter`.
/// `baseLanguageCode` is the fallback pack (`base_lang_code`). Tellomi packs report `en`
/// for every language, so a Chinese UI was still geocoding and measuring in English.
/// When that base is English and the UI language is not, use the UI language.
/// An English UI stays on the base code, and a pack whose base is already not English
/// (upstream official packs) keeps that base.
public func localeIdentifierLanguageCode(baseLanguageCode: String, primaryLanguageCode: String) -> String {
    if !primaryLanguageCode.isEmpty, localeLanguageCodeIsEnglish(baseLanguageCode), !localeLanguageCodeIsEnglish(primaryLanguageCode) {
        return primaryLanguageCode
    }
    return baseLanguageCode
}

private func localeLanguageCodeIsEnglish(_ code: String) -> Bool {
    let normalized = code.lowercased().replacingOccurrences(of: "_", with: "-")
    return normalized == "en" || normalized.hasPrefix("en-")
}
