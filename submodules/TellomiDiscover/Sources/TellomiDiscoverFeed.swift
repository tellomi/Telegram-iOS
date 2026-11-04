import Foundation

/// Discover feed client (M3 / C-M3a).
///
/// The server flag `tellomi_discover_feed_enabled` defaults off. While it is off, or the
/// account is logged out, nothing here builds a credential RPC or an engine URL.
/// Location leaves this module as a city name only. Visibility is the Stories four-way
/// choice (`everyone`, `contacts`, `closeFriends`, selected people); this file does not
/// invent a second privacy model.

public let tellomiDiscoverFeedEnabledKey = "tellomi_discover_feed_enabled"
public let tellomiDiscoverFeedBaseURLKey = "tellomi_discover_feed_base_url"
public let tellomiDiscoverDefaultBaseURLString = "https://feed.tellomi.cn"

/// Refresh this long before `exp`. The engine allows 60 seconds of clock skew after
/// expiry; the client stops using the token earlier than that.
public let tellomiDiscoverCredentialRefreshMargin: Int64 = 120

public let tellomiDiscoverFeedPageSize = 20
public let tellomiDiscoverPostTextLimit = 4000

public enum TellomiDiscoverConfigField: Equatable {
    case missing
    case bool(Bool)
    case number(Double)
    case string(String)
}

public func tellomiDiscoverEnabled(_ field: TellomiDiscoverConfigField) -> Bool {
    switch field {
    case .missing:
        return false
    case let .bool(value):
        return value
    case let .number(value):
        return value != 0
    case let .string(value):
        switch value.lowercased() {
        case "1", "true", "yes", "enabled", "on":
            return true
        case "0", "false", "no", "disabled", "off":
            return false
        default:
            return false
        }
    }
}

public struct TellomiDiscoverConfiguration: Equatable {
    public var enabled: Bool
    public var baseURL: URL?

    public init(enabled: Bool, baseURL: URL?) {
        self.enabled = enabled
        self.baseURL = baseURL
    }

    /// A missing URL uses `feed.tellomi.cn` only when the flag is on. An `http` URL, a URL
    /// with a user, or a URL that already has a path does not turn the client on.
    public static func resolve(enabledField: TellomiDiscoverConfigField, baseURLField: TellomiDiscoverConfigField) -> TellomiDiscoverConfiguration {
        guard tellomiDiscoverEnabled(enabledField) else {
            return TellomiDiscoverConfiguration(enabled: false, baseURL: nil)
        }
        let raw: String?
        if case let .string(value) = baseURLField {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            raw = trimmed.isEmpty ? nil : trimmed
        } else {
            raw = nil
        }
        guard let baseURL = tellomiDiscoverBaseURL(string: raw) else {
            return TellomiDiscoverConfiguration(enabled: false, baseURL: nil)
        }
        return TellomiDiscoverConfiguration(enabled: true, baseURL: baseURL)
    }
}

public func tellomiDiscoverBaseURL(string: String?) -> URL? {
    let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = (raw?.isEmpty == false) ? raw! : tellomiDiscoverDefaultBaseURLString
    guard let components = URLComponents(string: value), components.url != nil else {
        return nil
    }
    guard components.scheme?.lowercased() == "https" else {
        return nil
    }
    guard components.user == nil, components.password == nil else {
        return nil
    }
    guard let host = components.host, !host.isEmpty else {
        return nil
    }
    let path = components.path
    guard path.isEmpty || path == "/" else {
        return nil
    }
    guard components.query == nil, components.fragment == nil else {
        return nil
    }
    var origin = URLComponents()
    origin.scheme = "https"
    origin.host = host
    origin.port = components.port
    return origin.url
}

public enum TellomiDiscoverFeedKind: Equatable {
    case recommend
    case following
    case nearby
}

public enum TellomiDiscoverSurface: Equatable {
    case legacyEmpty(postUnavailable: Bool)
    case feed
    case cityPrompt
    case detail(String)
}

public struct TellomiDiscoverChrome: Equatable {
    public var surface: TellomiDiscoverSurface
    public var showsCompose: Bool
    public var loadsFeed: Bool
    public var loadsPost: Bool
    public var failure: Bool

    public var issuesNetwork: Bool {
        return self.loadsFeed || self.loadsPost
    }
}

public func tellomiDiscoverChrome(loggedIn: Bool, enabled: Bool, kind: TellomiDiscoverFeedKind, city: String?, openedPostId: String?, failed: Bool) -> TellomiDiscoverChrome {
    let postId = openedPostId.flatMap(tellomiDiscoverPostId)
    guard loggedIn, enabled else {
        return TellomiDiscoverChrome(
            surface: .legacyEmpty(postUnavailable: postId != nil || (openedPostId?.isEmpty == false)),
            showsCompose: false,
            loadsFeed: false,
            loadsPost: false,
            failure: false
        )
    }
    if let postId {
        return TellomiDiscoverChrome(
            surface: .detail(postId),
            showsCompose: false,
            loadsFeed: false,
            loadsPost: true,
            failure: failed
        )
    }
    if kind == .nearby, tellomiDiscoverNormalizedCity(city ?? "") == nil {
        return TellomiDiscoverChrome(
            surface: .cityPrompt,
            showsCompose: true,
            loadsFeed: false,
            loadsPost: false,
            failure: false
        )
    }
    return TellomiDiscoverChrome(
        surface: .feed,
        showsCompose: true,
        loadsFeed: true,
        loadsPost: false,
        failure: failed
    )
}

public struct TellomiDiscoverCredential: Equatable {
    public var token: String
    public var expires: Int64
    public var region: String

    public init(token: String, expires: Int64, region: String) {
        self.token = token
        self.expires = expires
        self.region = region
    }
}

public func tellomiDiscoverCredentialNeedsRefresh(expires: Int64, now: Int64) -> Bool {
    return now >= expires - tellomiDiscoverCredentialRefreshMargin
}

public enum TellomiDiscoverStoryBase: Equatable {
    case everyone
    case contacts
    case closeFriends
    case nobody
}

public enum TellomiDiscoverVisibility: String, Equatable {
    case everyone
    case contacts
    case closeFriends = "close_friends"
    case selected
}

public struct TellomiDiscoverAudienceChoice: Equatable {
    public var visibility: TellomiDiscoverVisibility
    /// False when the engine still needs an audience token (selected people, or an
    /// exclusion list). Those peer ids stay on the device and are not posted.
    public var publishable: Bool
    public var reason: String?

    public init(visibility: TellomiDiscoverVisibility, publishable: Bool, reason: String?) {
        self.visibility = visibility
        self.publishable = publishable
        self.reason = reason
    }
}

/// Stories `Privacy.Base` plus its include list. `nobody` with people is "selected".
/// `nobody` with an empty list is not a Discover audience. Exclusions on everyone or
/// contacts cannot be sent until teamgram signs an audience token.
public func tellomiDiscoverAudience(base: TellomiDiscoverStoryBase, includePeerIds: [Int64]) -> TellomiDiscoverAudienceChoice? {
    switch base {
    case .everyone:
        if includePeerIds.isEmpty {
            return TellomiDiscoverAudienceChoice(visibility: .everyone, publishable: true, reason: nil)
        }
        return TellomiDiscoverAudienceChoice(visibility: .everyone, publishable: false, reason: "excluded_peers")
    case .contacts:
        if includePeerIds.isEmpty {
            return TellomiDiscoverAudienceChoice(visibility: .contacts, publishable: true, reason: nil)
        }
        return TellomiDiscoverAudienceChoice(visibility: .contacts, publishable: false, reason: "excluded_peers")
    case .closeFriends:
        return TellomiDiscoverAudienceChoice(visibility: .closeFriends, publishable: true, reason: nil)
    case .nobody:
        if includePeerIds.isEmpty {
            return nil
        }
        return TellomiDiscoverAudienceChoice(visibility: .selected, publishable: false, reason: "needs_audience_token")
    }
}

public func tellomiDiscoverNormalizedCity(_ raw: String) -> String? {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if let comma = value.firstIndex(where: { $0 == "," || $0 == "，" }) {
        value = String(value[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard !value.isEmpty, value.count <= 40 else {
        return nil
    }
    if value.contains(where: { $0.isNewline || $0 == "/" || $0 == "\\" || $0 == "?" || $0 == "#" || $0 == "&" }) {
        return nil
    }
    if tellomiDiscoverLooksLikeCoordinate(value) {
        return nil
    }
    return value
}

/// Street and state are accepted so a caller cannot confuse them with the city by
/// dropping a parameter. Only `city` is returned.
public func tellomiDiscoverCity(street: String?, city: String?, state: String?) -> String? {
    // `street` and `state` are part of the signature so a placemark is reduced in one
    // place. They are not a city and are not returned.
    let _ = street
    let _ = state
    guard let city else {
        return nil
    }
    return tellomiDiscoverNormalizedCity(city)
}

private func tellomiDiscoverLooksLikeCoordinate(_ value: String) -> Bool {
    let pattern = #"^-?\d{1,3}(\.\d+)?$"#
    return value.range(of: pattern, options: .regularExpression) != nil
}

public func tellomiDiscoverPostId(_ raw: String) -> String? {
    let identifier = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !identifier.isEmpty, identifier.count <= 128 else {
        return nil
    }
    guard identifier != ".", identifier != "..", !identifier.contains("..") else {
        return nil
    }
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-")
    guard identifier.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
        return nil
    }
    return identifier
}

public enum TellomiDiscoverOperation: Equatable {
    case feed(TellomiDiscoverFeedKind, cursor: String?, city: String?)
    case post(String)
    case publish(text: String, visibility: TellomiDiscoverVisibility)
}

public struct TellomiDiscoverHTTPCall: Equatable {
    public var method: String
    public var url: URL
    public var body: Data?
    public var token: String
    public var contentType: String?

    public init(method: String, url: URL, body: Data?, token: String, contentType: String?) {
        self.method = method
        self.url = url
        self.body = body
        self.token = token
        self.contentType = contentType
    }
}

public func tellomiDiscoverHTTPCall(base: URL, operation: TellomiDiscoverOperation, token: String) -> TellomiDiscoverHTTPCall? {
    let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedToken.isEmpty else {
        return nil
    }
    switch operation {
    case let .feed(kind, cursor, city):
        guard let url = tellomiDiscoverFeedURL(base: base, kind: kind, cursor: cursor, city: city) else {
            return nil
        }
        return TellomiDiscoverHTTPCall(method: "GET", url: url, body: nil, token: trimmedToken, contentType: nil)
    case let .post(identifier):
        guard let url = tellomiDiscoverPostURL(base: base, id: identifier) else {
            return nil
        }
        return TellomiDiscoverHTTPCall(method: "GET", url: url, body: nil, token: trimmedToken, contentType: nil)
    case let .publish(text, visibility):
        guard let body = tellomiDiscoverPublishBody(text: text, visibility: visibility) else {
            return nil
        }
        guard let url = tellomiDiscoverPostsURL(base: base) else {
            return nil
        }
        return TellomiDiscoverHTTPCall(method: "POST", url: url, body: body, token: trimmedToken, contentType: "application/json")
    }
}

public func tellomiDiscoverFeedURL(base: URL, kind: TellomiDiscoverFeedKind, cursor: String?, city: String?) -> URL? {
    let path: String
    var query: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(tellomiDiscoverFeedPageSize))]
    switch kind {
    case .recommend:
        path = "/v1/feed/recommend"
    case .following:
        path = "/v1/feed/following"
    case .nearby:
        guard let city = tellomiDiscoverNormalizedCity(city ?? "") else {
            return nil
        }
        path = "/v1/feed/nearby"
        query.append(URLQueryItem(name: "city", value: city))
    }
    if let cursor, !cursor.isEmpty {
        query.append(URLQueryItem(name: "cursor", value: cursor))
    }
    return tellomiDiscoverURL(base: base, path: path, query: query)
}

public func tellomiDiscoverPostURL(base: URL, id: String) -> URL? {
    guard let identifier = tellomiDiscoverPostId(id) else {
        return nil
    }
    return tellomiDiscoverURL(base: base, path: "/v1/feed/posts/\(identifier)", query: [])
}

public func tellomiDiscoverPostsURL(base: URL) -> URL? {
    return tellomiDiscoverURL(base: base, path: "/v1/feed/posts", query: [])
}

public func tellomiDiscoverPublishBody(text: String, visibility: TellomiDiscoverVisibility) -> Data? {
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty, body.count <= tellomiDiscoverPostTextLimit else {
        return nil
    }
    guard visibility != .selected else {
        return nil
    }
    let object: [String: String] = [
        "text": body,
        "visibility": visibility.rawValue
    ]
    return try? JSONSerialization.data(withJSONObject: object, options: [])
}

private func tellomiDiscoverURL(base: URL, path: String, query: [URLQueryItem]) -> URL? {
    guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
        return nil
    }
    guard components.scheme?.lowercased() == "https" else {
        return nil
    }
    components.path = path
    components.queryItems = query.isEmpty ? nil : query
    guard let url = components.url else {
        return nil
    }
    let absolute = url.absoluteString
    if absolute.contains("latitude=") || absolute.contains("longitude=") || absolute.contains("lat=") || absolute.contains("lng=") {
        return nil
    }
    return url
}

public enum TellomiDiscoverTL {
    public static let getEngineCredentialId: Int32 = Int32(bitPattern: 0xA80A7F76)
    public static let engineCredentialId: Int32 = 0x0578CCAA

    public static func encodeRequest() -> Data {
        var data = Data()
        appendInt32(self.getEngineCredentialId, to: &data)
        return data
    }

    public static func decodeCredential(_ data: Data) -> TellomiDiscoverCredential? {
        var offset = 0
        guard let constructor = readInt32(data, &offset), constructor == self.engineCredentialId else {
            return nil
        }
        guard let token = readString(data, &offset), !token.isEmpty else {
            return nil
        }
        guard let expires = readInt32(data, &offset) else {
            return nil
        }
        guard let region = readString(data, &offset), region == "cn" || region == "global" else {
            return nil
        }
        guard offset == data.count else {
            return nil
        }
        return TellomiDiscoverCredential(token: token, expires: Int64(expires), region: region)
    }
}

private func appendInt32(_ value: Int32, to data: inout Data) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { bytes in
        data.append(contentsOf: bytes)
    }
}

private func readInt32(_ data: Data, _ offset: inout Int) -> Int32? {
    guard offset + 4 <= data.count else {
        return nil
    }
    let value = data.withUnsafeBytes { raw -> Int32 in
        raw.loadUnaligned(fromByteOffset: offset, as: Int32.self)
    }
    offset += 4
    return Int32(littleEndian: value)
}

private func readString(_ data: Data, _ offset: inout Int) -> String? {
    guard offset < data.count else {
        return nil
    }
    let first = Int(data[data.index(data.startIndex, offsetBy: offset)])
    offset += 1
    let length: Int
    let padding: Int
    if first == 254 {
        guard offset + 3 <= data.count else {
            return nil
        }
        var raw: Int32 = 0
        for index in 0 ..< 3 {
            let byte = Int32(data[data.index(data.startIndex, offsetBy: offset + index)])
            raw |= byte << (8 * index)
        }
        offset += 3
        length = Int(raw)
        padding = (4 - (length % 4)) % 4
    } else {
        length = first
        let padded = length + 1
        padding = (4 - (padded % 4)) % 4
    }
    guard length >= 0, offset + length + padding <= data.count else {
        return nil
    }
    let start = data.index(data.startIndex, offsetBy: offset)
    let end = data.index(start, offsetBy: length)
    let bytes = data[start ..< end]
    offset += length + padding
    return String(data: Data(bytes), encoding: .utf8)
}
