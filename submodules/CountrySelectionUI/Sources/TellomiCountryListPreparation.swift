import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting

struct TellomiCountryListSnapshot {
    let namesAndCodes: [((String, String), String, [Int])]
    let sections: [(String, [((String, String), String, Int)])]
    let sectionTitles: [String]
}

private let tellomiCountryListCache = Atomic<[String: TellomiCountryListSnapshot]>(value: [:])

private func tellomiCountryListKey(locale: Locale?, countries: [Country]) -> String {
    var hasher = Hasher()
    hasher.combine(locale?.identifier ?? "")
    hasher.combine(countries.count)
    hasher.combine(countries.first?.id ?? "")
    hasher.combine(countries.last?.id ?? "")
    for code in TellomiCallingCodePolicy.allowedCallingCodes.sorted() {
        hasher.combine(code)
    }
    return String(hasher.finalize())
}

func tellomiCachedCountryList(locale: Locale?) -> TellomiCountryListSnapshot? {
    let countries = AuthorizationSequenceCountrySelectionController.countries()
    let key = tellomiCountryListKey(locale: locale, countries: countries)
    return tellomiCountryListCache.with { $0[key] }
}

/// Builds the picker off the main thread and keeps it. The phone screen calls this
/// when it appears, so the tap reads the cache. `CFStringTransform` to pinyin for a
/// Chinese index, done while the controller is being pushed, was the multi-second stall.
public func tellomiWarmCountryList(strings: PresentationStrings, locale: Locale?) {
    let countries = AuthorizationSequenceCountrySelectionController.countries()
    let key = tellomiCountryListKey(locale: locale, countries: countries)
    if tellomiCountryListCache.with({ $0[key] != nil }) {
        return
    }
    let nameLocale = locale ?? localeWithStrings(strings)
    Queue.concurrentDefaultQueue().async {
        let snapshot = tellomiBuildCountryList(countries: countries, nameLocale: nameLocale, sortLocale: locale)
        let _ = tellomiCountryListCache.modify { cache in
            var cache = cache
            cache[key] = snapshot
            return cache
        }
    }
}

func tellomiLoadCountryList(strings: PresentationStrings, locale: Locale?, completion: @escaping (TellomiCountryListSnapshot) -> Void) {
    let countries = AuthorizationSequenceCountrySelectionController.countries()
    let key = tellomiCountryListKey(locale: locale, countries: countries)
    if let cached = tellomiCountryListCache.with({ $0[key] }) {
        completion(cached)
        return
    }
    let nameLocale = locale ?? localeWithStrings(strings)
    Queue.concurrentDefaultQueue().async {
        let snapshot = tellomiBuildCountryList(countries: countries, nameLocale: nameLocale, sortLocale: locale)
        let _ = tellomiCountryListCache.modify { cache in
            var cache = cache
            cache[key] = snapshot
            return cache
        }
        Queue.mainQueue().async {
            completion(snapshot)
        }
    }
}

func tellomiCountryNamesAndCodes(countries: [Country], locale: Locale) -> [((String, String), String, [Int])] {
    var result: [((String, String), String, [Int])] = []
    for country in countries {
        if country.hidden || country.id == "FT" {
            continue
        }
        if let englishCountryName = usEnglishLocale.localizedString(forRegionCode: country.id), let countryName = locale.localizedString(forRegionCode: country.id) {
            var codes: [Int] = []
            for codeValue in country.countryCodes {
                if let code = Int(codeValue.code), TellomiCallingCodePolicy.allows(Int32(code)) {
                    codes.append(code)
                }
            }
            if codes.isEmpty {
                continue
            }
            result.append(((englishCountryName, countryName), country.id, codes))
        }
    }
    return result
}

private func tellomiCountryLatinName(_ name: String) -> String {
    let mutable = NSMutableString(string: name)
    CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
    CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
    return (mutable as String).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func tellomiCountryUsesPinyinIndex(_ locale: Locale?) -> Bool {
    let identifier = locale?.identifier.lowercased() ?? ""
    return identifier == "zh" || identifier.hasPrefix("zh-") || identifier.hasPrefix("zh_")
}

private func tellomiCountrySectionTitle(name: String, locale: Locale?) -> String {
    if tellomiCountryUsesPinyinIndex(locale) {
        let latin = tellomiCountryLatinName(name)
        if let first = latin.first, first.isASCII, first.isLetter {
            return String(first).uppercased()
        }
    }
    guard let first = name.first else {
        return "#"
    }
    return String(first).uppercased(with: locale ?? .current)
}

private func tellomiCountrySortKey(name: String, locale: Locale?) -> String {
    if tellomiCountryUsesPinyinIndex(locale) {
        let latin = tellomiCountryLatinName(name)
        if !latin.isEmpty {
            return latin
        }
    }
    return name
}

private func tellomiBuildCountryList(countries: [Country], nameLocale: Locale, sortLocale: Locale?) -> TellomiCountryListSnapshot {
    let namesAndCodes = tellomiCountryNamesAndCodes(countries: countries, locale: nameLocale)
    var sections: [(String, [((String, String), String, Int)])] = []
    let sorted = namesAndCodes.sorted { lhs, rhs in
        if tellomiCountryUsesPinyinIndex(sortLocale) {
            return tellomiCountrySortKey(name: lhs.0.1, locale: sortLocale).localizedStandardCompare(tellomiCountrySortKey(name: rhs.0.1, locale: sortLocale)) == .orderedAscending
        }
        if let sortLocale {
            return lhs.0.1.compare(rhs.0.1, locale: sortLocale) == .orderedAscending
        }
        return lhs.0.1 < rhs.0.1
    }
    for (names, id, codes) in sorted {
        let title = tellomiCountrySectionTitle(name: names.1, locale: sortLocale)
        if sections.isEmpty || sections[sections.count - 1].0 != title {
            sections.append((title, []))
        }
        for code in codes {
            sections[sections.count - 1].1.append((names, id, code))
        }
    }
    return TellomiCountryListSnapshot(namesAndCodes: namesAndCodes, sections: sections, sectionTitles: sections.map { $0.0 })
}
