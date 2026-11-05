import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Discover link cards. The phone reads Open Graph itself. Nothing here calls
/// teamgram linkpreview, port 8801, `account.getWebPagePreview`, or
/// `POST /internal/v1/link-preview`.
public enum TellomiDiscoverLink {
    public static let titleLimit = 200
    public static let descriptionLimit = 300
    public static let urlLimit = 2048

    /// Fields stored with a post. Absent strings are omitted from `publishFields`.
    public struct Preview: Equatable {
        public var url: String
        public var title: String?
        public var description: String?
        public var image: String?

        public init(url: String, title: String?, description: String?, image: String?) {
            self.url = url
            self.title = title
            self.description = description
            self.image = image
        }

        public func titleLine() -> String {
            if let title, !title.isEmpty {
                return title
            }
            if let name = TellomiDiscoverLink.host(self.url), !name.isEmpty {
                return name
            }
            return self.url
        }

        /// Host under a real title. Nil when the title line is already the host.
        public func siteLine() -> String? {
            guard let title, !title.isEmpty else {
                return nil
            }
            guard let name = TellomiDiscoverLink.host(self.url), !name.isEmpty, name.caseInsensitiveCompare(title) != .orderedSame else {
                return nil
            }
            return name
        }
    }

    public struct PublishFields: Equatable {
        public var url: String
        public var title: String?
        public var description: String?
        public var image: String?

        public var orderedKeys: [String] {
            var keys = ["url"]
            if let title, !title.isEmpty {
                keys.append("title")
            }
            if let description, !description.isEmpty {
                keys.append("description")
            }
            if let image, !image.isEmpty {
                keys.append("image")
            }
            return keys
        }

        public var object: [String: String] {
            var value = ["url": self.url]
            if let title, !title.isEmpty {
                value["title"] = title
            }
            if let description, !description.isEmpty {
                value["description"] = description
            }
            if let image, !image.isEmpty {
                value["image"] = image
            }
            return value
        }
    }

    /// First http(s) URL in `text`. An email is not a URL.
    public static func firstUrl(_ text: String?) -> String? {
        guard let text, !text.isEmpty else {
            return nil
        }
        let ns = text as NSString
        var from = 0
        while from < ns.length {
            let http = self.indexOfIgnoreCase(ns, "http://", from)
            let https = self.indexOfIgnoreCase(ns, "https://", from)
            let start: Int
            if http < 0 {
                start = https
            } else if https < 0 {
                start = http
            } else {
                start = min(http, https)
            }
            if start < 0 {
                return nil
            }
            if start > 0 && self.glued(ns.character(at: start - 1)) {
                from = start + 1
                continue
            }
            var end = start
            while end < ns.length && !self.stop(ns.character(at: end)) {
                end += 1
            }
            let raw = self.trimTail(ns.substring(with: NSRange(location: start, length: end - start)))
            if self.httpUrl(raw) != nil {
                return raw
            }
            from = start + 1
        }
        return nil
    }

    /// True when the phone may open this URL. Literal private, loopback, and
    /// link-local hosts are refused. A public name is allowed; the fetch checks
    /// DNS before connecting.
    public static func fetchable(_ raw: String?) -> Bool {
        guard let url = self.httpUrl(raw), let name = self.host(url), !name.isEmpty else {
            return false
        }
        if self.blockedName(name) || self.blockedLiteral(name) {
            return false
        }
        return name.contains(".") || name.contains(":")
    }

    public static func host(_ raw: String?) -> String? {
        guard let url = self.httpUrl(raw) else {
            return nil
        }
        guard var name = self.hostName(url)?.lowercased() else {
            return nil
        }
        while name.hasSuffix(".") {
            name.removeLast()
        }
        return name.isEmpty ? nil : name
    }

    /// http(s) URL with a host and no user info. The original spelling is kept.
    public static func httpUrl(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let value = self.trim(raw)
        if value.isEmpty || (value as NSString).length > self.urlLimit || self.hasSpace(value) {
            return nil
        }
        guard let scheme = self.scheme(value), scheme == "http" || scheme == "https" else {
            return nil
        }
        if self.authorityHasUserInfo(value) {
            return nil
        }
        guard let name = self.hostName(value), !name.isEmpty else {
            return nil
        }
        return value
    }

    public static func urlOnly(_ raw: String?) -> Preview? {
        guard let url = self.httpUrl(raw), self.fetchable(url) else {
            return nil
        }
        return Preview(url: url, title: nil, description: nil, image: nil)
    }

    /// Open Graph, then Twitter card, then `<title>` and `meta name=description`.
    /// `pageUrl` is the final page address.
    public static func parseHtml(_ html: String?, pageUrl: String?) -> Preview? {
        guard let pageUrl, self.fetchable(pageUrl) else {
            return nil
        }
        let source = html ?? ""
        var title = self.meta(source, "og:title", self.titleLimit)
        if title == nil {
            title = self.meta(source, "twitter:title", self.titleLimit)
        }
        if title == nil {
            title = self.titleTag(source)
        }
        var description = self.meta(source, "og:description", self.descriptionLimit)
        if description == nil {
            description = self.meta(source, "twitter:description", self.descriptionLimit)
        }
        if description == nil {
            description = self.meta(source, "description", self.descriptionLimit)
        }
        var image = self.imageMeta(source, pageUrl, "og:image:secure_url")
        if image == nil {
            image = self.imageMeta(source, pageUrl, "og:image")
        }
        if image == nil {
            image = self.imageMeta(source, pageUrl, "twitter:image")
        }
        if image == nil {
            image = self.imageMeta(source, pageUrl, "twitter:image:src")
        }
        return Preview(url: pageUrl, title: self.clip(title, self.titleLimit), description: self.clip(description, self.descriptionLimit), image: image)
    }

    /// One stored object, the shape `POST /v1/feed/posts` sends. `site_name` is ignored.
    public static func parseStored(url: String?, title: String?, description: String?, image: String?) -> Preview? {
        guard let url = self.httpUrl(url), self.fetchable(url) else {
            return nil
        }
        let picture = self.absoluteImage(url, image)
        return Preview(url: url, title: self.clip(title, self.titleLimit), description: self.clip(description, self.descriptionLimit), image: picture)
    }

    /// Body for `link_preview`. Nil when there is no public URL.
    /// Only `url`, `title`, `description`, and `image`.
    public static func publishFields(_ preview: Preview?) -> PublishFields? {
        guard let preview, self.fetchable(preview.url) else {
            return nil
        }
        let image = self.absoluteImage(preview.url, preview.image)
        return PublishFields(
            url: preview.url,
            title: self.clip(preview.title, self.titleLimit),
            description: self.clip(preview.description, self.descriptionLimit),
            image: image
        )
    }

    public static func charsetName(_ data: Data?, contentType: String?) -> String {
        if let header = self.charsetToken(contentType) {
            return header
        }
        guard let data, !data.isEmpty else {
            return "UTF-8"
        }
        let length = min(data.count, 2048)
        let ascii = String(data: data.prefix(length), encoding: .isoLatin1)?.lowercased() ?? ""
        guard let marker = ascii.range(of: "charset") else {
            return "UTF-8"
        }
        let after = ascii[marker.upperBound...]
        guard let eq = after.firstIndex(of: "=") else {
            return "UTF-8"
        }
        if ascii.distance(from: marker.lowerBound, to: eq) > 16 {
            return "UTF-8"
        }
        var start = ascii.index(after: eq)
        while start < ascii.endIndex {
            let ch = ascii[start]
            if ch == " " || ch == "\"" || ch == "'" {
                start = ascii.index(after: start)
            } else {
                break
            }
        }
        var end = start
        while end < ascii.endIndex {
            let ch = ascii[end]
            let ok = (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch == "-" || ch == "_"
            if ok {
                end = ascii.index(after: end)
            } else {
                break
            }
        }
        if end == start {
            return "UTF-8"
        }
        return self.knownCharset(String(ascii[start..<end]))
    }

    public static func blockedLiteral(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else {
            return false
        }
        if let v4 = self.ipv4(host) {
            return self.blockedBytes(v4)
        }
        if !host.contains(":") {
            return false
        }
        var raw = [UInt8](repeating: 0, count: 16)
        let parsed: Int32 = host.withCString { pointer in
            raw.withUnsafeMutableBytes { buffer in
                guard let base = buffer.baseAddress else {
                    return Int32(0)
                }
                return inet_pton(AF_INET6, pointer, base)
            }
        }
        if parsed != 1 {
            return true
        }
        return self.blockedBytes(raw)
    }

    public static func blockedName(_ host: String?) -> Bool {
        guard var name = host?.lowercased() else {
            return false
        }
        while name.hasSuffix(".") {
            name.removeLast()
        }
        return name == "localhost" || name.hasSuffix(".localhost") || name.hasSuffix(".local")
    }

    public static func blockedBytes(_ raw: [UInt8]) -> Bool {
        if raw.count == 4 {
            let a = Int(raw[0])
            let b = Int(raw[1])
            if a == 0 || a == 10 || a == 127 {
                return true
            }
            if a == 169 && b == 254 {
                return true
            }
            if a == 172 && b >= 16 && b <= 31 {
                return true
            }
            if a == 192 && b == 168 {
                return true
            }
            if a == 100 && b >= 64 && b <= 127 {
                return true
            }
            if a == 192 && b == 0 && raw[2] == 0 {
                return true
            }
            if a == 192 && b == 0 && raw[2] == 2 {
                return true
            }
            if a == 198 && b == 51 && raw[2] == 100 {
                return true
            }
            if a == 203 && b == 0 && raw[2] == 113 {
                return true
            }
            if a == 198 && (b == 18 || b == 19) {
                return true
            }
            return a >= 224
        }
        if raw.count == 16 {
            let a = Int(raw[0])
            if a == 0xFF {
                return true
            }
            if (a & 0xFE) == 0xFC {
                return true
            }
            if a == 0xFE && (Int(raw[1]) & 0xC0) == 0x80 {
                return true
            }
            var mapped = raw[10] == 0xFF && raw[11] == 0xFF
            if mapped {
                for index in 0 ..< 10 where raw[index] != 0 {
                    mapped = false
                }
            }
            if mapped {
                return self.blockedBytes([raw[12], raw[13], raw[14], raw[15]])
            }
            var zeros = true
            for index in 0 ..< 15 where raw[index] != 0 {
                zeros = false
            }
            return zeros && (raw[15] == 0 || raw[15] == 1)
        }
        return true
    }

    static func absoluteImage(_ pageUrl: String?, _ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let ref = self.trim(raw)
        if ref.isEmpty || (ref as NSString).length > self.urlLimit {
            return nil
        }
        let lower = ref.lowercased()
        if lower.hasPrefix("data:") || lower.hasPrefix("javascript:") || lower.hasPrefix("blob:") {
            return nil
        }
        let absolute: String
        if lower.hasPrefix("//") {
            absolute = "https:" + ref
        } else if self.httpUrl(ref) != nil {
            absolute = ref
        } else if let pageUrl, let base = URL(string: pageUrl), let resolved = URL(string: ref, relativeTo: base)?.absoluteURL.absoluteString {
            absolute = resolved
        } else {
            return nil
        }
        return self.fetchable(absolute) ? absolute : nil
    }

    private static func imageMeta(_ html: String, _ pageUrl: String, _ key: String) -> String? {
        let ns = html as NSString
        var from = 0
        while from < ns.length {
            let start = self.indexOfIgnoreCase(ns, "<meta", from)
            if start < 0 {
                return nil
            }
            let end = self.tagEnd(ns, start)
            if end < 0 {
                return nil
            }
            let attributes = self.attributes(ns.substring(with: NSRange(location: start + 5, length: end - start - 5)))
            let property = attributes["property"]
            let name = attributes["name"]
            let content = attributes["content"]
            let match = (property?.caseInsensitiveCompare(key) == .orderedSame) || (name?.caseInsensitiveCompare(key) == .orderedSame)
            if match, let content, let image = self.absoluteImage(pageUrl, self.clip(content, self.urlLimit)) {
                return image
            }
            from = end + 1
        }
        return nil
    }

    private static func meta(_ html: String, _ key: String, _ limit: Int) -> String? {
        let ns = html as NSString
        var from = 0
        while from < ns.length {
            let start = self.indexOfIgnoreCase(ns, "<meta", from)
            if start < 0 {
                return nil
            }
            let end = self.tagEnd(ns, start)
            if end < 0 {
                return nil
            }
            let attributes = self.attributes(ns.substring(with: NSRange(location: start + 5, length: end - start - 5)))
            let property = attributes["property"]
            let name = attributes["name"]
            let content = attributes["content"]
            let match = (property?.caseInsensitiveCompare(key) == .orderedSame) || (name?.caseInsensitiveCompare(key) == .orderedSame)
            if match, let content, let text = self.clip(content, limit) {
                return text
            }
            from = end + 1
        }
        return nil
    }

    private static func titleTag(_ html: String) -> String? {
        let ns = html as NSString
        let start = self.indexOfIgnoreCase(ns, "<title", 0)
        if start < 0 {
            return nil
        }
        let open = ns.range(of: ">", options: [], range: NSRange(location: start, length: ns.length - start)).location
        if open == NSNotFound {
            return nil
        }
        let close = self.indexOfIgnoreCase(ns, "</title>", open)
        if close < 0 || close < open {
            return nil
        }
        return self.clip(ns.substring(with: NSRange(location: open + 1, length: close - open - 1)), self.titleLimit)
    }

    private static func attributes(_ tag: String) -> [String: String] {
        let ns = tag as NSString
        var values: [String: String] = [:]
        var index = 0
        while index < ns.length {
            while index < ns.length && self.isWhitespace(ns.character(at: index)) {
                index += 1
            }
            if index >= ns.length || ns.character(at: index) == 47 || ns.character(at: index) == 62 {
                break
            }
            let nameStart = index
            while index < ns.length {
                let ch = ns.character(at: index)
                if ch == 61 || self.isWhitespace(ch) || ch == 47 || ch == 62 {
                    break
                }
                index += 1
            }
            let name = ns.substring(with: NSRange(location: nameStart, length: index - nameStart)).lowercased()
            while index < ns.length && self.isWhitespace(ns.character(at: index)) {
                index += 1
            }
            if index >= ns.length || ns.character(at: index) != 61 {
                if !name.isEmpty {
                    values[name] = ""
                }
                continue
            }
            index += 1
            while index < ns.length && self.isWhitespace(ns.character(at: index)) {
                index += 1
            }
            if index >= ns.length {
                break
            }
            let quote = ns.character(at: index)
            let value: String
            if quote == 34 || quote == 39 {
                index += 1
                let valueStart = index
                while index < ns.length && ns.character(at: index) != quote {
                    index += 1
                }
                value = ns.substring(with: NSRange(location: valueStart, length: index - valueStart))
                if index < ns.length {
                    index += 1
                }
            } else {
                let valueStart = index
                while index < ns.length && !self.isWhitespace(ns.character(at: index)) && ns.character(at: index) != 62 {
                    index += 1
                }
                value = ns.substring(with: NSRange(location: valueStart, length: index - valueStart))
            }
            if !name.isEmpty {
                values[name] = value
            }
        }
        return values
    }

    private static func tagEnd(_ html: NSString, _ start: Int) -> Int {
        var quoted = false
        var quote: unichar = 0
        var index = start
        while index < html.length {
            let ch = html.character(at: index)
            if quoted {
                if ch == quote {
                    quoted = false
                }
            } else if ch == 34 || ch == 39 {
                quoted = true
                quote = ch
            } else if ch == 62 {
                return index
            }
            index += 1
        }
        return -1
    }

    static func clip(_ raw: String?, _ limit: Int) -> String? {
        guard let raw else {
            return nil
        }
        let decoded = self.decode(raw)
        var collapsed = ""
        var space = false
        for scalar in decoded.unicodeScalars {
            if self.isWhitespace(scalar) || scalar.value == 0x00A0 {
                space = !collapsed.isEmpty
                continue
            }
            if space {
                collapsed.append(" ")
                space = false
            }
            collapsed.unicodeScalars.append(scalar)
        }
        var value = self.trim(collapsed)
        if value.isEmpty {
            return nil
        }
        let scalars = Array(value.unicodeScalars)
        if scalars.count > limit {
            value = String(String.UnicodeScalarView(scalars.prefix(limit)))
        }
        return value
    }

    private static func decode(_ raw: String) -> String {
        let ns = raw as NSString
        var out = ""
        var index = 0
        while index < ns.length {
            let ch = ns.character(at: index)
            if ch != 38 {
                out.append(self.unit(ch))
                index += 1
                continue
            }
            let rest = ns.substring(from: index + 1)
            guard let semi = rest.range(of: ";") else {
                out.append("&")
                index += 1
                continue
            }
            let token = String(rest[..<semi.lowerBound])
            if (token as NSString).length > 11 {
                out.append("&")
                index += 1
                continue
            }
            guard let replaced = self.entity(token) else {
                out.append("&")
                index += 1
                continue
            }
            out.append(replaced)
            index += 1 + (token as NSString).length + 1
        }
        return out
    }

    private static func entity(_ token: String) -> String? {
        switch token {
        case "amp":
            return "&"
        case "lt":
            return "<"
        case "gt":
            return ">"
        case "quot":
            return "\""
        case "apos":
            return "'"
        case "nbsp":
            return " "
        default:
            break
        }
        let code: Int
        if token.hasPrefix("#x") || token.hasPrefix("#X") {
            guard let value = Int(token.dropFirst(2), radix: 16) else {
                return nil
            }
            code = value
        } else if token.hasPrefix("#") {
            guard let value = Int(token.dropFirst()) else {
                return nil
            }
            code = value
        } else {
            return nil
        }
        if code <= 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF) {
            return nil
        }
        guard let scalar = Unicode.Scalar(code) else {
            return nil
        }
        return String(Character(scalar))
    }

    private static func knownCharset(_ token: String) -> String {
        if token == "utf8" || token == "utf-8" {
            return "UTF-8"
        }
        if token == "gbk" || token == "gb2312" || token == "gb18030" {
            return token.uppercased()
        }
        if token == "iso-8859-1" || token == "latin1" {
            return "ISO-8859-1"
        }
        if token == "windows-1252" {
            return "windows-1252"
        }
        if token == "utf-16" || token == "utf-16le" || token == "utf-16be" {
            return token.uppercased()
        }
        return "UTF-8"
    }

    private static func charsetToken(_ contentType: String?) -> String? {
        guard let contentType else {
            return nil
        }
        let lower = contentType.lowercased()
        guard let marker = lower.range(of: "charset"), let eq = lower.range(of: "=", range: marker.upperBound..<lower.endIndex) else {
            return nil
        }
        var token = self.trim(String(lower[eq.upperBound...]))
        if let semi = token.firstIndex(of: ";") {
            token = String(token[..<semi])
        }
        token = self.trim(token).replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
        return token.isEmpty ? nil : self.knownCharset(token)
    }

    private static func ipv4(_ host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count != 4 {
            return nil
        }
        var raw = [UInt8](repeating: 0, count: 4)
        for index in 0 ..< 4 {
            let part = parts[index]
            if part.isEmpty || part.count > 3 {
                return nil
            }
            var value = 0
            for ch in part {
                guard let digit = ch.wholeNumberValue, ch >= "0" && ch <= "9" else {
                    return nil
                }
                value = value * 10 + digit
            }
            if value > 255 {
                return nil
            }
            raw[index] = UInt8(value)
        }
        return raw
    }

    private static func glued(_ ch: unichar) -> Bool {
        return ch == 64 || ch == 95 || (ch >= 48 && ch <= 57) || (ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122)
    }

    private static func stop(_ ch: unichar) -> Bool {
        if self.isWhitespace(ch) || ch == 60 || ch == 62 || ch == 34 || ch == 39 || ch == 96 {
            return true
        }
        switch ch {
        case 0x3002, 0xFF0C, 0x3001, 0xFF01, 0xFF1F, 0xFF09, 0x300D, 0x300B, 0x3011:
            return true
        default:
            return false
        }
    }

    private static func trimTail(_ raw: String) -> String {
        let ns = raw as NSString
        var end = ns.length
        while end > 0 && self.tail(ns.character(at: end - 1)) {
            end -= 1
        }
        var open = 0
        var close = 0
        for index in 0 ..< end {
            let ch = ns.character(at: index)
            if ch == 40 {
                open += 1
            } else if ch == 41 {
                close += 1
            }
        }
        while end > 0 && close > open && ns.character(at: end - 1) == 41 {
            end -= 1
            close -= 1
        }
        return ns.substring(to: end)
    }

    private static func tail(_ ch: unichar) -> Bool {
        switch ch {
        case 46, 44, 59, 58, 33, 63, 93, 125, 39, 34, 0x2026:
            return true
        default:
            return false
        }
    }

    private static func indexOfIgnoreCase(_ text: NSString, _ needle: String, _ from: Int) -> Int {
        let start = max(0, from)
        if start > text.length {
            return -1
        }
        let range = text.range(of: needle, options: .caseInsensitive, range: NSRange(location: start, length: text.length - start))
        return range.location == NSNotFound ? -1 : range.location
    }

    private static func hasSpace(_ value: String) -> Bool {
        let ns = value as NSString
        for index in 0 ..< ns.length where self.isWhitespace(ns.character(at: index)) {
            return true
        }
        return false
    }

    private static func trim(_ value: String?) -> String {
        guard let value else {
            return ""
        }
        let ns = value as NSString
        var start = 0
        var end = ns.length
        while start < end && self.isWhitespace(ns.character(at: start)) {
            start += 1
        }
        while end > start && self.isWhitespace(ns.character(at: end - 1)) {
            end -= 1
        }
        return ns.substring(with: NSRange(location: start, length: end - start))
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

    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value > 0xFFFF {
            return CharacterSet.whitespaces.contains(scalar)
        }
        return self.isWhitespace(unichar(scalar.value))
    }

    private static func scheme(_ value: String) -> String? {
        guard let range = value.range(of: "://") else {
            return nil
        }
        let name = value[..<range.lowerBound]
        if name.isEmpty || name.contains("/") || name.contains(" ") {
            return nil
        }
        return name.lowercased()
    }

    private static func authorityHasUserInfo(_ value: String) -> Bool {
        guard let range = value.range(of: "://") else {
            return false
        }
        let rest = value[range.upperBound...]
        let end = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? rest.endIndex
        return rest[..<end].contains("@")
    }

    private static func hostName(_ value: String) -> String? {
        if let components = URLComponents(string: value), let host = components.host, !host.isEmpty {
            return host
        }
        guard let range = value.range(of: "://") else {
            return nil
        }
        var rest = value[range.upperBound...]
        if let end = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            rest = rest[..<end]
        }
        if rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            let inner = rest[rest.index(after: rest.startIndex)..<close]
            return inner.isEmpty ? nil : String(inner)
        }
        if let colon = rest.firstIndex(of: ":") {
            rest = rest[..<colon]
        }
        return rest.isEmpty ? nil : String(rest)
    }

    private static func unit(_ ch: unichar) -> String {
        guard let scalar = Unicode.Scalar(ch) else {
            return ""
        }
        return String(Character(scalar))
    }
}
