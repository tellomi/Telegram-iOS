import Foundation

/// Calling codes the login field and the country list accept.
/// The default is mainland China. Assign `allowedCallingCodes` to open more later.
public enum TellomiCallingCodePolicy {
    public static var allowedCallingCodes: Set<Int32> = [86]

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
