import Foundation

/// Suggested defaults from the moments spec (SG-*). Kept in one place so a product change is a value change,
/// not a search through the screens. The engine's `GET /config` overrides a copy of this at runtime.
public struct MomentsLimits: Equatable {
    public var pageSize: Int
    public var textLimit: Int
    public var textCounterFrom: Int
    public var collapsedLineCount: Int
    public var imageLimit: Int
    public var videoLimit: Int
    public var videoMaxDuration: Double
    public var voiceMaxDuration: Double
    public var commentTextLimit: Int
    public var mentionLimit: Int
    public var topicLimit: Int
    public var topicNameLength: ClosedRange<Int>
    public var pollOptionCount: ClosedRange<Int>
    public var pinLimit: Int
    public var draftLimit: Int
    public var uploadRetryLimit: Int
    public var newPostsProbeInterval: TimeInterval
    public var notificationRetentionDays: Int
    public var maxContentWidth: CGFloat
    public var linkBase: String
    /// Tellomi builds keep the upstream News tab off (TBD-04). The moments tab does not borrow that switch.
    public var newsStaysOff: Bool
    /// Local kill switch. The tab is shown only when this is on and app config publishes a feed origin.
    public var tabEnabled: Bool

    public init(
        pageSize: Int = 20,
        textLimit: Int = 2000,
        textCounterFrom: Int = 1800,
        collapsedLineCount: Int = 5,
        imageLimit: Int = 12,
        videoLimit: Int = 3,
        videoMaxDuration: Double = 60,
        voiceMaxDuration: Double = 180,
        commentTextLimit: Int = 1000,
        mentionLimit: Int = 10,
        topicLimit: Int = 3,
        topicNameLength: ClosedRange<Int> = 1...32,
        pollOptionCount: ClosedRange<Int> = 2...10,
        pinLimit: Int = 3,
        draftLimit: Int = 20,
        uploadRetryLimit: Int = 3,
        newPostsProbeInterval: TimeInterval = 60,
        notificationRetentionDays: Int = 90,
        maxContentWidth: CGFloat = 640,
        linkBase: String = "https://tell.cc/m#",
        newsStaysOff: Bool = true,
        tabEnabled: Bool = true
    ) {
        self.pageSize = pageSize
        self.textLimit = textLimit
        self.textCounterFrom = textCounterFrom
        self.collapsedLineCount = collapsedLineCount
        self.imageLimit = imageLimit
        self.videoLimit = videoLimit
        self.videoMaxDuration = videoMaxDuration
        self.voiceMaxDuration = voiceMaxDuration
        self.commentTextLimit = commentTextLimit
        self.mentionLimit = mentionLimit
        self.topicLimit = topicLimit
        self.topicNameLength = topicNameLength
        self.pollOptionCount = pollOptionCount
        self.pinLimit = pinLimit
        self.draftLimit = draftLimit
        self.uploadRetryLimit = uploadRetryLimit
        self.newPostsProbeInterval = newPostsProbeInterval
        self.notificationRetentionDays = notificationRetentionDays
        self.maxContentWidth = maxContentWidth
        self.linkBase = linkBase
        self.newsStaysOff = newsStaysOff
        self.tabEnabled = tabEnabled
    }

    public static let standard = MomentsLimits()

    public func applying(config: MomentsRemoteConfig?) -> MomentsLimits {
        guard let config else {
            return self
        }
        var copy = self
        if let value = config.textLimit { copy.textLimit = value }
        if let value = config.imageLimit { copy.imageLimit = value }
        if let value = config.videoLimit { copy.videoLimit = value }
        if let value = config.videoMaxDuration { copy.videoMaxDuration = value }
        if let value = config.voiceMaxDuration { copy.voiceMaxDuration = value }
        if let value = config.commentTextLimit { copy.commentTextLimit = value }
        if let value = config.pageSize { copy.pageSize = value }
        return copy
    }
}

public struct MomentsRemoteConfig: Equatable {
    public var textLimit: Int?
    public var imageLimit: Int?
    public var videoLimit: Int?
    public var videoMaxDuration: Double?
    public var voiceMaxDuration: Double?
    public var commentTextLimit: Int?
    public var pageSize: Int?
    public var tabs: [String]
    /// From `GET /v1/feed/config`. Image and other media keys are joined onto this. Not a feed host.
    public var mediaBaseURL: String?

    public init(textLimit: Int? = nil, imageLimit: Int? = nil, videoLimit: Int? = nil, videoMaxDuration: Double? = nil, voiceMaxDuration: Double? = nil, commentTextLimit: Int? = nil, pageSize: Int? = nil, tabs: [String] = [], mediaBaseURL: String? = nil) {
        self.textLimit = textLimit
        self.imageLimit = imageLimit
        self.videoLimit = videoLimit
        self.videoMaxDuration = videoMaxDuration
        self.voiceMaxDuration = voiceMaxDuration
        self.commentTextLimit = commentTextLimit
        self.pageSize = pageSize
        self.tabs = tabs
        self.mediaBaseURL = mediaBaseURL
    }
}

public struct MomentsFeedEndpoint: Equatable {
    public var baseURL: String

    public init(baseURL: String) {
        self.baseURL = baseURL
    }
}

/// The feed is on only when app config has both keys. Anything else stays off. No default host.
public func momentsFeedEndpoint(appConfiguration: AppConfiguration) -> MomentsFeedEndpoint? {
    guard let data = appConfiguration.data else {
        return nil
    }
    guard data["tellomi_discover_feed_enabled"] as? Bool == true else {
        return nil
    }
    guard let raw = data["tellomi_discover_feed_base_url"] as? String else {
        return nil
    }
    guard let baseURL = momentsFeedBaseURL(raw) else {
        return nil
    }
    return MomentsFeedEndpoint(baseURL: baseURL)
}

public func isMomentsFeedEnabled(appConfiguration: AppConfiguration) -> Bool {
    guard MomentsLimits.standard.tabEnabled else {
        return false
    }
    return momentsFeedEndpoint(appConfiguration: appConfiguration) != nil
}

/// `https://host` or `https://host:port`. No user, path, query, or fragment. `region` is not accepted.
public func momentsFeedBaseURL(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let components = URLComponents(string: trimmed), components.scheme == "https" else {
        return nil
    }
    guard components.user == nil, components.password == nil else {
        return nil
    }
    guard let host = components.host, !host.isEmpty, host != "cn", host != "global" else {
        return nil
    }
    if let path = components.path.isEmpty ? nil : components.path, path != "/" {
        return nil
    }
    guard components.query == nil, components.fragment == nil else {
        return nil
    }
    if let port = components.port, !(1...65535).contains(port) {
        return nil
    }
    let renderedHost = host.contains(":") ? "[\(host)]" : host
    if let port = components.port {
        return "https://\(renderedHost):\(port)"
    }
    return "https://\(renderedHost)"
}

/// Join a relative media key onto `media_base_url`. Absolute https URLs are left alone.
public func momentsMediaURL(base: String?, key: String?) -> String? {
    guard let key, !key.isEmpty else {
        return nil
    }
    if key.hasPrefix("https://") || key.hasPrefix("http://") {
        return key
    }
    guard let base, base.hasPrefix("https://") else {
        return nil
    }
    let root = base.hasSuffix("/") ? String(base.dropLast()) : base
    let suffix = key.hasPrefix("/") ? String(key.dropFirst()) : key
    return root + "/" + suffix
}

/// Where a moments object is being shown. The server's `canView` is the authority; the client uses the
/// surface only to decide which local hides apply (FR-093…FR-095 apply to the four feeds only).
public enum MomentsSurface: String, Equatable {
    case recommend
    case following
    case friends
    case nearby
    case profile
    case search
    case topic
    case link
    case detail
    case saved
    case liked
    case quoteEmbed
    case notification
    case sharePreview

    public var isFeed: Bool {
        switch self {
        case .recommend, .following, .friends, .nearby:
            return true
        default:
            return false
        }
    }
}

public enum MomentsFeedKind: String, Equatable, CaseIterable {
    case recommend
    case following
    case friends
    case nearby

    public var surface: MomentsSurface {
        switch self {
        case .recommend:
            return .recommend
        case .following:
            return .following
        case .friends:
            return .friends
        case .nearby:
            return .nearby
        }
    }

    /// SG-02: the three chronological feeds probe; recommend only refreshes on pull.
    public var probesForNewPosts: Bool {
        switch self {
        case .recommend:
            return false
        case .following, .friends, .nearby:
            return true
        }
    }
}
