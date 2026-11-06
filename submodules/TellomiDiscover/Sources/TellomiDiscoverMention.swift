import Foundation

/// `@username` spans inside a Discover post.
///
/// The local shape matches `ChangeUsernameActivity.checkUserName` and
/// `TellomiUsername`: a name does not start or end with `_`, does not start
/// with a digit, and is only `0-9`, `A-Z`, `a-z`, and `_`. The shortest name
/// is 4 (`addressNameMinimumLength` / `TellomiUsername.MIN_LENGTH`). The
/// longest is 32. This does not call `account.checkUsername`.
///
/// `POST /v1/feed/posts` has no mentions field. A mention stays inside `text`.
/// The content engine is what would turn that into a discover mention
/// notification. This client does not invent that request.
public enum TellomiDiscoverMention {
    public static let minLength = 4
    public static let maxLength = 32
    public static let suggestionLimit = 6

    public struct Mention: Equatable {
        public var username: String
        public var start: Int
        public var end: Int

        public init(username: String, start: Int, end: Int) {
            self.username = username
            self.start = start
            self.end = end
        }
    }

    /// The `@` token that contains the caret. `prefix` is the text after `@` up to the caret.
    /// Offsets are UTF-16, the same units `UITextView` uses.
    public struct Query: Equatable {
        public var at: Int
        public var end: Int
        public var prefix: String

        public init(at: Int, end: Int, prefix: String) {
            self.at = at
            self.end = end
            self.prefix = prefix
        }
    }

    public struct Insertion: Equatable {
        public var text: String
        public var caret: Int

        public init(text: String, caret: Int) {
            self.text = text
            self.caret = caret
        }
    }

    public struct Person: Equatable {
        public var username: String
        public var name: String

        public init(username: String, name: String) {
            self.username = username
            self.name = name
        }
    }

    public static func usernameChar(_ ch: unichar) -> Bool {
        return (ch >= 48 && ch <= 57) || (ch >= 97 && ch <= 122) || (ch >= 65 && ch <= 90) || ch == 95
    }

    public static func validUsername(_ raw: String?) -> Bool {
        guard var name = raw, !name.isEmpty else {
            return false
        }
        if name.hasPrefix("@") {
            name.removeFirst()
        }
        let count = (name as NSString).length
        if count == 0 {
            return false
        }
        let ns = name as NSString
        let first = ns.character(at: 0)
        let last = ns.character(at: count - 1)
        if first == 95 || last == 95 {
            return false
        }
        if first >= 48 && first <= 57 {
            return false
        }
        for index in 0 ..< count {
            if !self.usernameChar(ns.character(at: index)) {
                return false
            }
        }
        return count >= self.minLength && count <= self.maxLength
    }

    public static func parse(_ text: String?) -> [Mention] {
        guard let text, !text.isEmpty else {
            return []
        }
        let ns = text as NSString
        var mentions: [Mention] = []
        var index = 0
        while index < ns.length {
            let at = self.indexOf(ns, 64, index)
            if at < 0 {
                break
            }
            let end = self.tokenEnd(ns, at)
            if end > at + 1 {
                let name = ns.substring(with: NSRange(location: at + 1, length: end - at - 1))
                if self.validUsername(name) {
                    mentions.append(Mention(username: name, start: at, end: end))
                }
                index = end
            } else {
                index = at + 1
            }
        }
        return mentions
    }

    /// Non-empty `@` tokens that fail `validUsername`. A lone `@` is not one of these.
    public static func invalid(_ text: String?) -> [String] {
        guard let text, !text.isEmpty else {
            return []
        }
        let ns = text as NSString
        var names: [String] = []
        var index = 0
        while index < ns.length {
            let at = self.indexOf(ns, 64, index)
            if at < 0 {
                break
            }
            let end = self.tokenEnd(ns, at)
            if end > at + 1 {
                let name = ns.substring(with: NSRange(location: at + 1, length: end - at - 1))
                if !self.validUsername(name) {
                    names.append(name)
                }
                index = end
            } else {
                index = at + 1
            }
        }
        return names
    }

    public static func queryAt(_ text: String?, caret: Int) -> Query? {
        guard let text else {
            return nil
        }
        let ns = text as NSString
        var position = caret
        if position < 0 {
            position = 0
        }
        if position > ns.length {
            position = ns.length
        }
        var start = position
        while start > 0 && self.usernameChar(ns.character(at: start - 1)) {
            start -= 1
        }
        if start <= 0 || ns.character(at: start - 1) != 64 {
            return nil
        }
        let at = start - 1
        if !self.boundary(ns, at) {
            return nil
        }
        var end = position
        while end < ns.length && self.usernameChar(ns.character(at: end)) {
            end += 1
        }
        if position < at + 1 || position > end {
            return nil
        }
        let prefix = ns.substring(with: NSRange(location: at + 1, length: position - at - 1))
        return Query(at: at, end: end, prefix: prefix)
    }

    public static func insert(_ text: String?, query: Query?, username: String?) -> Insertion? {
        guard let text, let query, let username, !username.isEmpty else {
            return nil
        }
        let name = username.hasPrefix("@") ? String(username.dropFirst()) : username
        let ns = text as NSString
        if !self.validUsername(name) || query.at < 0 || query.end < query.at || query.end > ns.length || query.at >= ns.length || ns.character(at: query.at) != 64 {
            return nil
        }
        var builder = ns.substring(to: query.at)
        builder.append("@")
        builder.append(name)
        var tail = query.end
        if tail < ns.length && self.isWhitespace(ns.character(at: tail)) {
            builder.append(ns.substring(with: NSRange(location: tail, length: 1)))
            tail += 1
        } else {
            builder.append(" ")
        }
        let caret = (builder as NSString).length
        if tail < ns.length {
            builder.append(ns.substring(from: tail))
        }
        return Insertion(text: builder, caret: caret)
    }

    public static func suggestions(_ people: [Person]?, prefix: String?, limit: Int) -> [Person] {
        let cap = limit > 0 ? limit : self.suggestionLimit
        let needle = (prefix ?? "").lowercased()
        var unique: [String: Person] = [:]
        var order: [String] = []
        if let people {
            for person in people {
                guard self.validUsername(person.username) else {
                    continue
                }
                let key = person.username.lowercased()
                if unique[key] == nil {
                    unique[key] = Person(username: person.username, name: person.name)
                    order.append(key)
                }
            }
        }
        var matched: [Person] = []
        for key in order {
            guard let person = unique[key] else {
                continue
            }
            let username = person.username.lowercased()
            let name = person.name.lowercased()
            if needle.isEmpty || username.hasPrefix(needle) || name.hasPrefix(needle) {
                matched.append(person)
            }
        }
        matched.sort { left, right in
            left.username.caseInsensitiveCompare(right.username) == .orderedAscending
        }
        if matched.count > cap {
            return Array(matched.prefix(cap))
        }
        return matched
    }

    /// `%s` is the Android pack spelling. `%@` is accepted so an iOS override still substitutes.
    /// The line starts with `@` so the fragment is visible in the hint.
    public static func invalidLine(template: String, username: String) -> String {
        let formatted: String
        if let range = template.range(of: "%s") {
            formatted = template.replacingCharacters(in: range, with: username)
        } else if template.contains("%@") {
            formatted = String(format: template, username)
        } else {
            formatted = template
        }
        if formatted.hasPrefix("@") {
            return formatted
        }
        return "@" + formatted
    }

    private static func tokenEnd(_ text: NSString, _ at: Int) -> Int {
        if !self.boundary(text, at) {
            return at
        }
        var end = at + 1
        while end < text.length && self.usernameChar(text.character(at: end)) {
            end += 1
        }
        return end
    }

    private static func boundary(_ text: NSString, _ at: Int) -> Bool {
        if at <= 0 {
            return true
        }
        return !self.usernameChar(text.character(at: at - 1))
    }

    private static func indexOf(_ text: NSString, _ ch: unichar, _ from: Int) -> Int {
        var index = max(0, from)
        while index < text.length {
            if text.character(at: index) == ch {
                return index
            }
            index += 1
        }
        return -1
    }

    private static func isWhitespace(_ ch: unichar) -> Bool {
        switch ch {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x1F, 0x20:
            return true
        default:
            guard ch != 0x00A0, let scalar = Unicode.Scalar(ch) else {
                return false
            }
            return CharacterSet.whitespaces.contains(scalar)
        }
    }
}
