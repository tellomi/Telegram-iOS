import Foundation

/// User-visible product name. Same tokens as Android `TellomiBrand.rewrite`.
/// Protocol identifiers and class names are not passed through here.
public func tellomiRewriteBrand(_ value: String) -> String {
    if value.isEmpty {
        return value
    }
    let folded = value.lowercased()
    if !folded.contains("telegram") && !folded.contains("t.me") && !value.contains("电报") && !value.contains("تيليجرام") && !value.contains("텔레그램") && !value.contains("टेलीग्राम") {
        return value
    }
    var result = value
    let tokens = ["Telegram", "تيليجرام", "텔레그램", "टेलीग्राम", "电报"]
    for token in tokens {
        if result.contains(token) {
            result = result.replacingOccurrences(of: token, with: "Tellomi")
        }
    }
    let hosts = [
        ("getdesktop.telegram.org", "tellomi.cn/download"),
        ("desktop.telegram.org", "tellomi.cn/download"),
        ("web.telegram.org", "tell.cc"),
        ("ads.telegram.org", "tell.cc"),
        ("promote.telegram.org", "tell.cc"),
        ("translations.telegram.org", "tellomi.cn"),
        ("core.telegram.org", "tellomi.cn"),
        ("sms@telegram.org", "support@tellomi.cn"),
        ("recover@telegram.org", "support@tellomi.cn"),
        ("www.telegram.org", "tell.cc"),
    ]
    for (from, to) in hosts {
        if result.contains(from) {
            result = result.replacingOccurrences(of: from, with: to)
        }
    }
    result = tellomiReplaceHostBoundary(result, from: "telegram.org", to: "tell.cc")
    if result.contains("telegram.me") {
        result = result.replacingOccurrences(of: "telegram.me", with: "tell.cc")
    }
    if result.contains("telegram.dog") {
        result = result.replacingOccurrences(of: "telegram.dog", with: "tell.cc")
    }
    result = tellomiReplaceHostBoundary(result, from: "t.me", to: "tell.cc")
    return result
}

public func tellomiRewriteBrandDictionary(_ dict: [String: String]) -> [String: String] {
    var rewritten: [String: String] = [:]
    rewritten.reserveCapacity(dict.count)
    for (key, value) in dict {
        rewritten[key] = tellomiRewriteBrand(value)
    }
    return rewritten
}

private func tellomiReplaceHostBoundary(_ value: String, from: String, to: String) -> String {
    if from == to || !value.contains(from) {
        return value
    }
    var result = ""
    result.reserveCapacity(value.count)
    var index = value.startIndex
    var changed = false
    while index < value.endIndex {
        guard let range = value.range(of: from, range: index..<value.endIndex) else {
            break
        }
        let boundary: Bool
        if range.lowerBound > value.startIndex {
            let previous = value[value.index(before: range.lowerBound)]
            if previous == "@" || previous == "." || previous.isLetter || previous.isNumber {
                boundary = false
            } else {
                boundary = true
            }
        } else {
            boundary = true
        }
        let endOK: Bool
        if range.upperBound < value.endIndex {
            let next = value[range.upperBound]
            endOK = !(next.isLetter || next.isNumber)
        } else {
            endOK = true
        }
        result.append(contentsOf: value[index..<range.lowerBound])
        if boundary && endOK {
            result.append(to)
            changed = true
        } else {
            result.append(contentsOf: value[range])
        }
        index = range.upperBound
    }
    if !changed {
        return value
    }
    result.append(contentsOf: value[index..<value.endIndex])
    return result
}
