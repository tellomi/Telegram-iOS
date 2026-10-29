import Foundation

/// Tellomi's public link host and custom URL scheme.
/// `tell.cc` replaces `t.me`, `telegram.me`, and `telegram.dog`. Path shape is unchanged.
public enum TellomiLinks {
    public static let host = "tell.cc"
    public static let urlScheme = "tellomi"

    public static var httpsPrefix: String { "https://\(host)" }

    /// `tg://` stays accepted. `tellomi://` uses the same host and query routes.
    public static func isDeepLinkScheme(_ scheme: String?) -> Bool {
        switch scheme?.lowercased() {
        case "tg", urlScheme:
            return true
        default:
            return false
        }
    }

    public static func hasDeepLinkPrefix(_ url: String) -> Bool {
        let lowercased = url.lowercased()
        return lowercased.hasPrefix("tg://") || lowercased.hasPrefix("\(urlScheme)://")
    }
}
