import Foundation

/// Emoji hidden from pickers, search, suggestions, recent, and the reaction picker.
/// Message history still draws an emoji that was already sent.
///
/// The built-in list includes the Taiwan flag. `help.getAppConfig` key `emoji_blocklist`
/// (an array of emoji strings or codepoint sequences such as `U+1F1F9 U+1F1FC`) replaces
/// that list when the field is present. See `TellomiEmojiBlocklist.apply(appConfiguration:)`.
public enum TellomiEmojiBlocklist {
    /// U+1F1F9 U+1F1FC.
    public static let taiwanFlag = "\u{1F1F9}\u{1F1FC}"

    public static let defaultEntries: [String] = [taiwanFlag]

    private static let lock = NSLock()
    private static var keys: Set<String> = Set(defaultEntries.map { canonicalKey(ofEntry: $0) })

    /// `nil` restores `defaultEntries`. An empty array blocks nothing.
    /// Each entry is an emoji string or a codepoint sequence (`1F1F9-1F1FC`, `U+1F1F9 U+1F1FC`).
    public static func apply(entries: [String]?) {
        let next: Set<String>
        if let entries {
            next = Set(entries.map { canonicalKey(ofEntry: $0) }.filter { !$0.isEmpty })
        } else {
            next = Set(defaultEntries.map { canonicalKey(ofEntry: $0) })
        }
        lock.lock()
        keys = next
        lock.unlock()
    }

    public static func isBlocked(_ emoji: String) -> Bool {
        return isBlocked(emoji, keys: blockedKeys())
    }

    public static func filtering(_ emoji: [String]) -> [String] {
        let blocked = blockedKeys()
        return emoji.filter { !isBlocked($0, keys: blocked) }
    }

    private static func blockedKeys() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return keys
    }

    private static func isBlocked(_ emoji: String, keys: Set<String>) -> Bool {
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return false
        }
        if blocks(trimmed, keys: keys) {
            return true
        }
        var found = false
        trimmed.enumerateSubstrings(in: trimmed.startIndex ..< trimmed.endIndex, options: .byComposedCharacterSequences) { substring, _, _, stop in
            guard let substring, substring != trimmed else {
                return
            }
            if blocks(substring, keys: keys) {
                found = true
                stop = true
            }
        }
        return found
    }

    private static func blocks(_ emoji: String, keys: Set<String>) -> Bool {
        let key = canonicalKey(ofEmoji: emoji)
        return !key.isEmpty && keys.contains(key)
    }

    /// Picker strings are emoji, not hex descriptions. Variation selectors are ignored.
    private static func canonicalKey(ofEmoji emoji: String) -> String {
        return key(scalars: Array(emoji.unicodeScalars))
    }

    /// Blocklist entries may be the emoji itself or a codepoint sequence.
    private static func canonicalKey(ofEntry entry: String) -> String {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scalars = codepointScalars(in: trimmed) {
            return key(scalars: scalars)
        }
        return key(scalars: Array(trimmed.unicodeScalars))
    }

    private static func key(scalars: [Unicode.Scalar]) -> String {
        var parts: [String] = []
        parts.reserveCapacity(scalars.count)
        for scalar in scalars {
            if scalar.value == 0xFE0E || scalar.value == 0xFE0F {
                continue
            }
            parts.append(String(scalar.value, radix: 16, uppercase: true))
        }
        return parts.joined(separator: " ")
    }

    /// The whole string is a codepoint sequence, or it is not (`nil` — treat it as an emoji).
    private static func codepointScalars(in entry: String) -> [Unicode.Scalar]? {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",-_"))
        let tokens = entry.components(separatedBy: separators).filter { !$0.isEmpty }
        guard !tokens.isEmpty else {
            return nil
        }
        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(tokens.count)
        for token in tokens {
            var hex = token
            if hex.count > 2 {
                let prefix = hex.prefix(2)
                if prefix == "U+" || prefix == "u+" {
                    hex = String(hex.dropFirst(2))
                }
            }
            guard hex.count >= 4, hex.count <= 6, let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) else {
                return nil
            }
            scalars.append(scalar)
        }
        return scalars
    }
}
