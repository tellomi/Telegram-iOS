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
    public var voicePostMaxDuration: Double
    public var voiceCommentMaxDuration: Double
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
        textLimit: Int = 500,
        textCounterFrom: Int = 400,
        collapsedLineCount: Int = 5,
        imageLimit: Int = 10,
        videoLimit: Int = 3,
        videoMaxDuration: Double = 60,
        voicePostMaxDuration: Double = 60,
        voiceCommentMaxDuration: Double = 60,
        commentTextLimit: Int = 1000,
        mentionLimit: Int = 10,
        topicLimit: Int = 3,
        topicNameLength: ClosedRange<Int> = 2...32,
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
        self.voicePostMaxDuration = voicePostMaxDuration
        self.voiceCommentMaxDuration = voiceCommentMaxDuration
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
        if let value = momentsPositiveOverride(config.textLimit) { copy.textLimit = value }
        if let value = momentsPositiveOverride(config.imageLimit) { copy.imageLimit = value }
        if let value = momentsPositiveOverride(config.videoLimit) { copy.videoLimit = value }
        if let value = momentsPositiveOverride(config.videoMaxDuration) { copy.videoMaxDuration = value }
        if let value = momentsPositiveOverride(config.voicePostMaxDuration) { copy.voicePostMaxDuration = value }
        if let value = momentsPositiveOverride(config.voiceCommentMaxDuration) { copy.voiceCommentMaxDuration = value }
        if let value = momentsPositiveOverride(config.commentTextLimit) { copy.commentTextLimit = value }
        if let value = momentsPositiveOverride(config.pageSize) { copy.pageSize = value }
        if let value = momentsPositiveOverride(config.mentionLimit) { copy.mentionLimit = value }
        if let value = momentsPositiveOverride(config.topicLimit) { copy.topicLimit = value }
        if let value = momentsPositiveOverride(config.newPostsProbeInterval) { copy.newPostsProbeInterval = value }
        if let value = momentsPositiveOverride(config.notificationRetentionDays) { copy.notificationRetentionDays = value }
        return copy
    }
}

/// Voice posts and voice comments are different caps. `comment` selects `voice_comment_max_seconds`.
public func momentsVoiceMaxDuration(_ limits: MomentsLimits, comment: Bool) -> Double {
    if comment {
        return limits.voiceCommentMaxDuration
    }
    return limits.voicePostMaxDuration
}

public struct MomentsRemoteConfig: Equatable {
    public var textLimit: Int?
    public var imageLimit: Int?
    public var videoLimit: Int?
    public var videoMaxDuration: Double?
    public var voicePostMaxDuration: Double?
    public var voiceCommentMaxDuration: Double?
    public var commentTextLimit: Int?
    public var pageSize: Int?
    public var mentionLimit: Int?
    public var topicLimit: Int?
    public var newPostsProbeInterval: TimeInterval?
    public var notificationRetentionDays: Int?
    public var tabs: [String]
    /// From `GET /v1/feed/config`. Image and other media keys are joined onto this. Not a feed host.
    public var mediaBaseURL: String?
    /// Top-level `personalization_toggle_visible`. Missing or non-boolean hides the settings switch.
    public var personalizationToggleVisible: Bool

    public init(textLimit: Int? = nil, imageLimit: Int? = nil, videoLimit: Int? = nil, videoMaxDuration: Double? = nil, voicePostMaxDuration: Double? = nil, voiceCommentMaxDuration: Double? = nil, commentTextLimit: Int? = nil, pageSize: Int? = nil, mentionLimit: Int? = nil, topicLimit: Int? = nil, newPostsProbeInterval: TimeInterval? = nil, notificationRetentionDays: Int? = nil, tabs: [String] = [], mediaBaseURL: String? = nil, personalizationToggleVisible: Bool = false) {
        self.textLimit = textLimit
        self.imageLimit = imageLimit
        self.videoLimit = videoLimit
        self.videoMaxDuration = videoMaxDuration
        self.voicePostMaxDuration = voicePostMaxDuration
        self.voiceCommentMaxDuration = voiceCommentMaxDuration
        self.commentTextLimit = commentTextLimit
        self.pageSize = pageSize
        self.mentionLimit = mentionLimit
        self.topicLimit = topicLimit
        self.newPostsProbeInterval = newPostsProbeInterval
        self.notificationRetentionDays = notificationRetentionDays
        self.tabs = tabs
        self.mediaBaseURL = mediaBaseURL
        self.personalizationToggleVisible = personalizationToggleVisible
    }
}

func momentsPositiveOverride(_ value: Int?) -> Int? {
    guard let value, value > 0 else {
        return nil
    }
    return value
}

func momentsPositiveOverride(_ value: Double?) -> Double? {
    guard let value, value > 0 else {
        return nil
    }
    return value
}

/// JSON `true`/`false` only. Numbers and strings are not booleans.
func momentsStrictBool(_ value: Any?) -> Bool? {
    guard let number = value as? NSNumber else {
        return nil
    }
    if CFGetTypeID(number) != CFBooleanGetTypeID() {
        return nil
    }
    return number.boolValue
}

/// A positive whole number. `0`, fractions, strings and booleans are missing.
func momentsPositiveWholeNumber(_ value: Any?) -> Int? {
    if momentsStrictBool(value) != nil {
        return nil
    }
    guard let number = value as? NSNumber else {
        return nil
    }
    let doubleValue = number.doubleValue
    guard doubleValue.isFinite, doubleValue >= 1, doubleValue <= Double(Int.max), doubleValue.rounded() == doubleValue else {
        return nil
    }
    return Int(doubleValue)
}

func momentsPositiveSeconds(_ value: Any?) -> Double? {
    guard let whole = momentsPositiveWholeNumber(value) else {
        return nil
    }
    return Double(whole)
}

/// `GET /v1/feed/config`. Limits are the nested `limits` object. The keys are the ones content-engine writes.
/// A missing key, or a value that is not a positive whole number, stays nil so the caller keeps its default.
func momentsRemoteConfig(data: Data) -> MomentsRemoteConfig {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return MomentsRemoteConfig()
    }
    let limits = momentsObject(json["limits"]) ?? [:]
    return MomentsRemoteConfig(
        textLimit: momentsPositiveWholeNumber(limits["post_text_chars"]),
        imageLimit: momentsPositiveWholeNumber(limits["post_images"]),
        videoLimit: momentsPositiveWholeNumber(limits["post_videos"]),
        videoMaxDuration: momentsPositiveSeconds(limits["video_max_seconds"]),
        voicePostMaxDuration: momentsPositiveSeconds(limits["voice_post_max_seconds"]),
        voiceCommentMaxDuration: momentsPositiveSeconds(limits["voice_comment_max_seconds"]),
        commentTextLimit: momentsPositiveWholeNumber(limits["comment_text_chars"]),
        pageSize: momentsPositiveWholeNumber(limits["page_size"]),
        mentionLimit: momentsPositiveWholeNumber(limits["max_mentions"]),
        topicLimit: momentsPositiveWholeNumber(limits["max_topics"]),
        newPostsProbeInterval: momentsPositiveSeconds(limits["probe_interval_seconds"]),
        notificationRetentionDays: momentsPositiveWholeNumber(limits["notification_days"]),
        tabs: momentsStringList(json["tabs"]),
        mediaBaseURL: momentsConfigMediaBase(data),
        personalizationToggleVisible: momentsStrictBool(json["personalization_toggle_visible"]) == true
    )
}

/// `personalized` is a JSON boolean. Other fields already on the document are kept.
func momentsPreferenceBody(current: [String: Any], personalized: Bool) -> [String: Any] {
    var body = current
    body["personalized"] = personalized
    return body
}

/// Nil when the key is missing or not a JSON boolean.
func momentsPersonalizedFlag(data: Data) -> Bool? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    return momentsStrictBool(json["personalized"])
}

/// Off adds `personalized=false` on recommend only. On leaves that request unchanged.
func momentsFeedRequestQuery(kind: MomentsFeedKind, cursor: String?, city: String?, sort: String?, pageSize: Int, personalized: Bool) -> [String: String] {
    var query: [String: String] = ["limit": "\(pageSize)"]
    if let cursor, !cursor.isEmpty {
        query["cursor"] = cursor
    }
    if kind == .nearby {
        if let city {
            query["city"] = city
        }
        query["sort"] = sort ?? "latest"
    }
    if kind == .recommend, !personalized {
        query["personalized"] = "false"
    }
    return query
}

public struct MomentsFeedStatus: Equatable {
    public var visible: Bool

    public init(visible: Bool) {
        self.visible = visible
    }
}

func momentsCapabilityTabs(_ data: Data) -> [String] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return []
    }
    var raw = momentsStringList(json["tabs"])
    if raw.isEmpty, let feed = momentsObject(json["feed"]) {
        raw = momentsStringList(feed["tabs"])
    }
    if raw.isEmpty, let config = momentsObject(json["config"]) {
        raw = momentsStringList(config["tabs"])
    }
    return raw.filter { !$0.isEmpty }
}

public struct MomentsFeedEndpoint: Equatable {
    public var baseURL: String

    public init(baseURL: String) {
        self.baseURL = baseURL
    }
}

/// Production content-engine. A valid `tellomi_discover_feed_base_url` overrides it.
/// `tellomi_discover_feed_enabled` is ignored: the tab is always built in.
public let momentsProductionFeedBaseURL = "https://feed.tellomi.cn"

/// The host is the app-config URL when that value is an https origin, otherwise production.
/// The tab is not gated on this. An unreachable engine is an in-feed error.
public func momentsFeedEndpoint(appConfiguration: AppConfiguration) -> MomentsFeedEndpoint? {
    if let data = appConfiguration.data, let raw = data["tellomi_discover_feed_base_url"] as? String, let baseURL = momentsFeedBaseURL(raw) {
        return MomentsFeedEndpoint(baseURL: baseURL)
    }
    return MomentsFeedEndpoint(baseURL: momentsProductionFeedBaseURL)
}

public func isMomentsFeedEnabled(appConfiguration _: AppConfiguration) -> Bool {
    return MomentsLimits.standard.tabEnabled
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

/// Public objects are served here. Signed R2 URLs stay absolute and are not rewritten.
public let momentsPublicMediaBaseURL = "https://media.tellomi.app/feed"

/// Join a relative media key onto `media_base_url`, or the public CDN when config has no https base.
/// An absolute https URL (a signed non-public object) is returned unchanged. `http` keys are dropped.
public func momentsMediaURL(base: String?, key: String?) -> String? {
    guard let key, !key.isEmpty else {
        return nil
    }
    if key.hasPrefix("https://") {
        return key
    }
    if key.hasPrefix("http://") {
        return nil
    }
    let chosen: String
    if let base, base.hasPrefix("https://") {
        chosen = base
    } else {
        chosen = momentsPublicMediaBaseURL
    }
    let root = chosen.hasSuffix("/") ? String(chosen.dropLast()) : chosen
    let suffix = key.hasPrefix("/") ? String(key.dropFirst()) : key
    return root + "/" + suffix
}

/// `url` wins when it is already https. Otherwise `key` (or a relative `url`) is joined onto `media_base_url`.
public func momentsResolvedMediaURL(base: String?, key: String?, url: String?) -> String? {
    if let url, url.hasPrefix("https://") {
        return url
    }
    if let url, !url.isEmpty, !url.hasPrefix("http://") {
        return momentsMediaURL(base: base, key: url)
    }
    return momentsMediaURL(base: base, key: key)
}

public let momentsCarouselImagePixels = 360
public let momentsSingleImagePixels = 1080

public func momentsFeedImageTargetPixels(slideCount: Int) -> Int {
    return slideCount > 1 ? momentsCarouselImagePixels : momentsSingleImagePixels
}

public let momentsStandardFeedTabs = ["recommend", "following", "friends", "nearby"]

/// The four home tabs stay, in this order, even when config or capabilities omit `friends`.
public func momentsVisibleFeedTabs(configTabs: [String]) -> [String] {
    let extras = configTabs.filter { !momentsStandardFeedTabs.contains($0) && !$0.isEmpty }
    return momentsStandardFeedTabs + extras
}

/// Image versus video comes from the card's `type`, never from the HTTP content-type.
/// Signed objects often arrive as `application/octet-stream`.
public func momentsPresentsAsVideo(_ type: MomentsMediaType) -> Bool {
    switch type {
    case .video, .gif:
        return true
    case .image, .sticker, .audio:
        return false
    }
}

public func momentsPresentsAsImage(_ type: MomentsMediaType) -> Bool {
    switch type {
    case .image, .sticker:
        return true
    case .video, .gif, .audio:
        return false
    }
}

public func momentsPlaybackMimeType(_ type: MomentsMediaType) -> String {
    switch type {
    case .video, .gif:
        return "video/mp4"
    case .image, .sticker:
        return "image/jpeg"
    case .audio:
        return "audio/mpeg"
    }
}

public func momentsPlaybackFileName(_ type: MomentsMediaType) -> String {
    switch type {
    case .video, .gif:
        return "media.mp4"
    case .image, .sticker:
        return "media.jpg"
    case .audio:
        return "media.mp3"
    }
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
