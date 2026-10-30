import Foundation

extension TellomiEmojiBlocklist {
    /// `help.getAppConfig` field. An array of emoji strings or codepoint sequences replaces the built-in list.
    /// The key being absent, or a value that is not an array of strings, keeps the built-in default.
    /// An empty array blocks nothing.
    public static let appConfigKey = "emoji_blocklist"

    public static func apply(appConfiguration: AppConfiguration) {
        apply(entries: entries(in: appConfiguration.data))
    }

    static func entries(in data: JSON?) -> [String]? {
        guard case let .dictionary(fields)? = data, let value = fields[appConfigKey] else {
            return nil
        }
        guard case let .array(items) = value else {
            return nil
        }
        let strings = items.compactMap { item -> String? in
            if case let .string(string) = item {
                return string
            }
            return nil
        }
        if strings.isEmpty, !items.isEmpty {
            return nil
        }
        return strings
    }
}
