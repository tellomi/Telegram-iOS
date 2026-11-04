import Foundation

/// A language-pack value wins when the pack has the key. Simplified and traditional
/// Chinese are the fallback for `zh*`. Every other language falls back to English.
public func tellomiLocalizedPackString(languageCode: String, pack: [String: String], key: String, english: String, simplified: String, traditional: String) -> String {
    if let value = pack[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, value != key {
        return value
    }
    let code = languageCode.lowercased()
    if code == "zh-hant" || code.hasPrefix("zh-hant") || code == "zh-tw" || code.hasPrefix("zh-tw") || code == "zh-hk" || code.hasPrefix("zh-hk") || code == "zh-mo" || code.hasPrefix("zh-mo") {
        return traditional
    }
    if code == "zh" || code.hasPrefix("zh") {
        return simplified
    }
    return english
}

public func tellomiFormatInteger(_ template: String, _ value: Int) -> String {
    guard template.contains("%d") else {
        return "\(value) \(template)"
    }
    return String(format: template, value)
}

public func tellomiFormatString(_ template: String, _ value: String) -> String {
    guard template.contains("%@") else {
        return template + value
    }
    return String(format: template, value)
}
