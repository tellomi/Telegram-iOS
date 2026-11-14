import Foundation

/// A language-pack value wins when the pack has the key. Otherwise the bundled
/// string for that langpack language is used. The three literals are only the
/// last resort when a key is absent from both.
public func tellomiLocalizedPackString(languageCode: String, pack: [String: String], key: String, english: String, simplified: String, traditional: String) -> String {
    if let value = pack[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, value != key {
        return value
    }
    if let bundled = tellomiBundledString(languageCode: languageCode, key: key) {
        return bundled
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
