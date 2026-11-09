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
    /// Master switch for the moments tab. On for this client; flip it here to hide the tab.
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

    public init(textLimit: Int? = nil, imageLimit: Int? = nil, videoLimit: Int? = nil, videoMaxDuration: Double? = nil, voiceMaxDuration: Double? = nil, commentTextLimit: Int? = nil, pageSize: Int? = nil, tabs: [String] = []) {
        self.textLimit = textLimit
        self.imageLimit = imageLimit
        self.videoLimit = videoLimit
        self.videoMaxDuration = videoMaxDuration
        self.voiceMaxDuration = voiceMaxDuration
        self.commentTextLimit = commentTextLimit
        self.pageSize = pageSize
        self.tabs = tabs
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
