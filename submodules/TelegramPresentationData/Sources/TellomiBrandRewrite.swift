import Foundation

/// User-visible product name. Same tokens as Android `TellomiBrand.rewrite`.
/// Protocol identifiers and class names are not passed through here.
public func tellomiRewriteBrand(_ value: String) -> String {
    if value.isEmpty {
        return value
    }
    let folded = value.lowercased()
    let deadSitePaths = ["tellomi.cn/faq", "tellomi.cn/tos", "tellomi.cn/terms", "tellomi.cn/privacy-tpa", "tellomi.cn/apps"]
    if !folded.contains("telegram") && !folded.contains("t.me") && !deadSitePaths.contains(where: { folded.contains($0) }) && !value.contains("电报") && !value.contains("تيليجرام") && !value.contains("텔레그램") && !value.contains("टेलीग्राम") {
        return value
    }
    var result = value
    let tokens = ["Telegram", "تيليجرام", "텔레그램", "टेलीग्राम", "电报"]
    for token in tokens {
        if result.contains(token) {
            result = result.replacingOccurrences(of: token, with: "Tellomi")
        }
    }
    // Longer site URLs first. Website hosts go to pages that exist on tellomi.cn.
    // Short links (t.me, telegram.me, telegram.dog) stay on tell.cc below.
    // support@tellomi.app is the address published on tellomi.cn/support/.
    let hosts = [
        ("https://tellomi.cn/faq#q-can-i-delete-my-messages", "https://tellomi.cn/account/delete/"),
        ("https://tellomi.cn/faq#general-questions", "https://tellomi.cn/help"),
        ("https://tellomi.cn/faq#general", "https://tellomi.cn/help"),
        ("https://tellomi.cn/faq#passport", "https://tellomi.cn/help"),
        ("https://tellomi.cn/faq#secret-chats", "https://tellomi.cn/help"),
        ("https://tellomi.cn/faq", "https://tellomi.cn/help"),
        ("https://tellomi.cn/tos/bot-developers", "https://tellomi.cn/legal/terms/"),
        ("https://tellomi.cn/tos/mini-apps", "https://tellomi.cn/legal/terms/"),
        ("https://tellomi.cn/tos/stars", "https://tellomi.cn/legal/terms/"),
        ("https://tellomi.cn/tos", "https://tellomi.cn/legal/terms/"),
        ("https://tellomi.cn/terms", "https://tellomi.cn/legal/terms/"),
        ("https://tellomi.cn/privacy-tpa", "https://tellomi.cn/legal/privacy/"),
        ("https://tellomi.cn/apps", "https://tellomi.cn/download/"),
        ("https://core.telegram.org/bots/webapps#launching-the-main-mini-app", "https://tellomi.cn/help"),
        ("https://ads.telegram.org/guidelines", "https://tellomi.cn/legal/community/"),
        ("https://telegram.org/blog/coronavirus", "https://tellomi.cn/help"),
        ("https://telegram.org/update", "https://tellomi.cn/help/install/update/"),
        ("https://telegram.org/dl", "https://tellomi.cn/download/"),
        ("https://telegram.org/faq", "https://tellomi.cn/help"),
        ("https://telegram.org/privacy", "https://tellomi.cn/legal/privacy/"),
        ("https://telegram.org/terms", "https://tellomi.cn/legal/terms/"),
        ("https://telegram.org/tos", "https://tellomi.cn/legal/terms/"),
        ("https://telegram.org/ads", "https://tellomi.cn/legal/privacy/"),
        ("https://telegram.org/blog", "https://tellomi.cn/help"),
        ("https://ads.telegram.org", "https://tellomi.cn/legal/community/"),
        ("https://promote.telegram.org", "https://tellomi.cn/support/"),
        ("https://getdesktop.telegram.org", "https://tellomi.cn/help/start/link-desktop/"),
        ("https://desktop.telegram.org", "https://tellomi.cn/help/start/link-desktop/"),
        ("https://web.telegram.org", "https://tellomi.cn"),
        ("https://translations.telegram.org", "https://tellomi.cn/help"),
        ("https://core.telegram.org", "https://tellomi.cn/help"),
        ("https://www.telegram.org", "https://tellomi.cn"),
        ("https://telegram.org", "https://tellomi.cn"),
        ("getdesktop.telegram.org", "tellomi.cn/help/start/link-desktop/"),
        ("desktop.telegram.org", "tellomi.cn/help/start/link-desktop/"),
        ("web.telegram.org", "tellomi.cn"),
        ("ads.telegram.org", "tellomi.cn"),
        ("promote.telegram.org", "tellomi.cn"),
        ("translations.telegram.org", "tellomi.cn"),
        ("core.telegram.org", "tellomi.cn"),
        ("www.telegram.org", "tellomi.cn"),
        ("sms@telegram.org", "support@tellomi.app"),
        ("recover@telegram.org", "support@tellomi.app"),
    ]
    for (from, to) in hosts {
        if result.contains(from) {
            result = result.replacingOccurrences(of: from, with: to)
        }
    }
    result = tellomiReplaceHostBoundary(result, from: "telegram.org", to: "tellomi.cn")
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
