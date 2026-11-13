import Foundation

/// Calling codes the login field accepts. The screen still opens on +86.
/// 999 is the hidden test country from `help.getCountriesList` (iso2 XT, prefix 66).
/// The picker still drops `country.hidden` and any iso2 Locale cannot name, so Test is not a row.
public enum TellomiCallingCodePolicy {
    public static var allowedCallingCodes: Set<Int32> = [86, 999]

    public static func allows(_ code: Int32) -> Bool {
        return self.allowedCallingCodes.contains(code)
    }

    public static func message(languageCode: String) -> String {
        let code = languageCode.lowercased().replacingOccurrences(of: "_", with: "-")
        if code == "zh-hant" || code.hasPrefix("zh-hant") || code == "zh-tw" || code.hasPrefix("zh-tw") || code == "zh-hk" || code.hasPrefix("zh-hk") || code == "zh-mo" || code.hasPrefix("zh-mo") {
            return "目前僅支援中國大陸手機號（+86）。"
        }
        if code == "zh" || code.hasPrefix("zh-") {
            return "目前仅支持中国大陆手机号（+86）。"
        }
        return "Only mainland China numbers (+86) can be used right now."
    }
}
