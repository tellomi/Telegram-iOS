import Foundation

/// Tellomi's public link host and custom URL scheme.
/// `tell.cc` replaces `t.me`, `telegram.me`, and `telegram.dog`. Path shape is unchanged.
public enum TellomiLinks {
    /// Public username and invite links. New links are generated with this host.
    public static let host = "tell.cc"
    /// Older public links. Parsed the same way as `host`, not used when generating a link.
    public static let legacyHosts = ["t.me", "telegram.me", "telegram.dog"]
    /// Help, FAQ, privacy, and terms pages.
    public static let siteHost = "tellomi.cn"
    public static let urlScheme = "tellomi"

    public static var httpsPrefix: String { "https://\(host)" }

    public static var linkHosts: [String] { [host] + legacyHosts }

    public static var shortLinkHosts: [String] {
        linkHosts.flatMap { ["a.\($0)", "k.\($0)", "z.\($0)"] }
    }

    public static func isPublicLinkHost(_ value: String?) -> Bool {
        guard let value = value?.lowercased() else {
            return false
        }
        return linkHosts.contains(value)
    }

    public static func hasPublicLinkPrefix(_ url: String) -> Bool {
        let lowercased = url.lowercased()
        for linkHost in linkHosts {
            if lowercased.hasPrefix("https://\(linkHost)/") || lowercased.hasPrefix("http://\(linkHost)/") || lowercased.hasPrefix("\(linkHost)/") {
                return true
            }
        }
        return false
    }

    /// Drops `https://<link host>/<path>` when `value` starts with one. `path` includes its trailing slash when the remainder is a slug.
    public static func strippingPublicLinkPrefix(_ value: String, path: String) -> String {
        for linkHost in linkHosts {
            let prefix = "https://\(linkHost)/\(path)"
            if value.hasPrefix(prefix) {
                return String(value.dropFirst(prefix.count))
            }
        }
        return value
    }

    /// `path` is a site path such as `faq#general` or `/privacy`.
    public static func siteURL(_ path: String) -> String {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return "https://\(siteHost)/\(trimmed)"
    }

    /// A bundled or langpack help, FAQ, privacy, or terms URL. The path and fragment stay; the host becomes `siteHost`.
    public static func localizedSiteURL(_ url: String, fallback path: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("://"), var components = URLComponents(string: trimmed), let host = components.host?.lowercased() else {
            return siteURL(path)
        }
        if host == "telegram.org" || host == "www.telegram.org" || host == siteHost {
            components.scheme = "https"
            components.host = siteHost
            if let rewritten = components.string {
                return rewritten
            }
        }
        return siteURL(path)
    }

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
