import Foundation

/// One in-flight Moments request. A newer call bumps `current`, and a response applies only when it still owns that number.
public struct MomentsQueryGeneration: Equatable {
    public private(set) var current: Int

    public init(current: Int = 0) {
        self.current = current
    }

    public mutating func begin() -> Int {
        self.current += 1
        return self.current
    }

    public func accepts(_ generation: Int) -> Bool {
        return momentsSearchResultApplies(responseGeneration: generation, latestGeneration: self.current)
    }
}

/// A search (or any other) response applies only when it is the latest request.
public func momentsSearchResultApplies(responseGeneration: Int, latestGeneration: Int) -> Bool {
    return responseGeneration > 0 && responseGeneration == latestGeneration
}

public enum MomentsFeedPlace: Equatable {
    case topic(name: String, offset: CGFloat)
    case post(id: String)
    case media(postId: String, index: Int)
    case author(telegramUserId: Int64)
    case notifications(filter: String, offset: CGFloat)
    case following(profileId: String, offset: CGFloat)
    case followers(profileId: String, offset: CGFloat)
}

/// The place still on screen after the top place is popped. Topic, notification filter and list offset ride on that place.
public func momentsFeedPlaceAfterBack(_ stack: [MomentsFeedPlace]) -> MomentsFeedPlace? {
    guard stack.count >= 2 else {
        return nil
    }
    return stack[stack.count - 2]
}

/// Pushing a post, its media, its author, or another topic leaves the list underneath where it was.
public func momentsListAnchorSurvives(_ stack: [MomentsFeedPlace]) -> Bool {
    guard stack.count >= 2, let opening = stack.last else {
        return false
    }
    switch opening {
    case .post, .media, .author, .topic:
        return true
    case .notifications, .following, .followers:
        return false
    }
}

public enum MomentsNotificationDestination: Equatable {
    case post(id: String, commentId: String?)
    case peer(telegramUserId: Int64)
    case unavailable
}

/// Like, comment, reply, mention, repost, quote and new-post open the post (and the comment, when one was named).
/// Follow opens the actor. Anything else, including a deleted target, is an explicit unavailable state.
public func momentsNotificationDestination(_ item: MomentsNotification) -> MomentsNotificationDestination {
    if item.unavailable {
        return .unavailable
    }
    let postId = item.postId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let commentId = item.commentId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let comment = commentId.isEmpty ? nil : commentId
    switch item.kind {
    case .follow, .mutual:
        if let id = item.actors.first?.telegramUserId, id != 0 {
            return .peer(telegramUserId: id)
        }
        if !postId.isEmpty {
            return .post(id: postId, commentId: comment)
        }
        return .unavailable
    case .like, .comment, .reply, .mention, .repost, .quote, .newPost:
        if postId.isEmpty {
            return .unavailable
        }
        return .post(id: postId, commentId: comment)
    case .system, .all:
        if !postId.isEmpty {
            return .post(id: postId, commentId: comment)
        }
        return .unavailable
    }
}

public enum MomentsCommentFocus: Equatable {
    case located(id: String)
    case missing
}

/// `nil` means the notification did not name a comment. `.missing` is the fallback the screen must show.
public func momentsCommentFocus(commentId: String?, comments: [MomentsComment]) -> MomentsCommentFocus? {
    let trimmed = commentId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else {
        return nil
    }
    for comment in comments {
        if comment.id == trimmed {
            return .located(id: trimmed)
        }
        if comment.replies.contains(where: { $0.id == trimmed }) {
            return .located(id: trimmed)
        }
    }
    return .missing
}

public func momentsTopicName(_ raw: String) -> String? {
    var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while name.hasPrefix("#") {
        name.removeFirst()
    }
    name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty {
        return nil
    }
    return name
}

public enum MomentsListLoadResult: Equatable {
    case hidden
    case failed
    case ignore
}

/// Whether the first page of `GET /v1/feed/profiles/{id}/posts` has any post.
/// `unknown` is before the cache and the network have answered, so the rest of
/// the profile can appear. `.failed` is a request that did not answer and had
/// no cached posts: it is not a confirmed empty profile, and a later open can
/// ask again. A later failure keeps a cached non-empty page (`.present`).
public enum MomentsProfilePostsPresence: Equatable {
    case unknown
    case failed
    case empty
    case present
}

/// Cache is read before the network. A remote page replaces the cache. A failed
/// request does not hide posts the cache already showed, and it does not become
/// `.empty`. `.empty` is only a remote page whose count is zero.
public func momentsProfilePostsPresence(cachedCount: Int?, remoteCount: Int?, failed: Bool) -> MomentsProfilePostsPresence {
    if let remoteCount {
        return remoteCount > 0 ? .present : .empty
    }
    if failed {
        if let cachedCount, cachedCount > 0 {
            return .present
        }
        return .failed
    }
    if let cachedCount {
        return cachedCount > 0 ? .present : .empty
    }
    return .unknown
}

/// The first page is one shared opening (cache, then one request). A refresh or a
/// later page is its own request. The opening and the list must not each fetch.
public enum MomentsProfilePostsFetch: Equatable {
    case sharedOpening
    case page(cursor: String?)
}

public struct MomentsProfilePostsSnapshot: Equatable {
    public var items: [MomentsCard]
    public var nextCursor: String?
    public var cachedCount: Int?
    public var remoteCount: Int?
    public var failed: Bool

    public init(items: [MomentsCard], nextCursor: String?, cachedCount: Int?, remoteCount: Int?, failed: Bool) {
        self.items = items
        self.nextCursor = nextCursor
        self.cachedCount = cachedCount
        self.remoteCount = remoteCount
        self.failed = failed
    }

    public var presence: MomentsProfilePostsPresence {
        return momentsProfilePostsPresence(cachedCount: self.cachedCount, remoteCount: self.remoteCount, failed: self.failed)
    }
}

public func momentsProfilePostsFetch(refresh: Bool, cursor: String?) -> MomentsProfilePostsFetch {
    if refresh {
        return .page(cursor: nil)
    }
    if let cursor, !cursor.isEmpty {
        return .page(cursor: cursor)
    }
    return .sharedOpening
}

/// Why a profile opening is being asked for again.
public enum MomentsProfileOpeningReason: Equatable {
    /// The profile screen subscribed. A failed opening waits out
    /// `momentsProfileOpeningFailureThrottle`. A confirmed-empty opening
    /// is requested again on this visit.
    case profileOpen
    /// The account left `waitingForNetwork` and reached `.online`.
    case reconnect
    /// The signed-in account's publish succeeded. Not throttled.
    case viewerPublished
    /// A confirmed-empty opening has been sitting for `momentsProfileOpeningEmptyTTL`.
    case ttl
}

public enum MomentsProfileOpeningDecision: Equatable {
    /// Keep delivering the stored snapshot. Do not start another request.
    case reuse
    /// Start another request. Subscribers of the existing opening receive it.
    case refresh
}

/// A failed opening is not requested again on every appearance. 15 seconds is
/// long enough that an offline profile does not stampede, and short enough
/// that leaving and coming back retries.
public let momentsProfileOpeningFailureThrottle: Int64 = 15

/// A reconnect retries a failed opening on its own. A second reconnect inside
/// this window does not, so a flapping link does not restamp the request.
public let momentsProfileOpeningReconnectThrottle: Int64 = 5

/// A confirmed-empty profile left on screen is checked again after this many
/// seconds. The next open checks it sooner.
public let momentsProfileOpeningEmptyTTL: Int64 = 60

/// In-memory openings kept per account. Older profiles are dropped so a long
/// session does not retain every profile it opened.
public let momentsProfileOpeningMemoryLimit = 32

public struct MomentsProfileOpeningEntry: Equatable {
    public var generation: Int
    public var snapshot: MomentsProfilePostsSnapshot?
    public var inFlight: Bool
    public var lastAttemptAt: Int64
    public var settledAt: Int64?
    public var lastUsedAt: Int64
    /// Set when the network returns while this opening is failed or still in
    /// flight. The next reconnect decision refreshes once without waiting out
    /// the profile-open throttle. Beginning a request clears it.
    public var reconnectBypass: Bool

    public init(generation: Int = 0, snapshot: MomentsProfilePostsSnapshot? = nil, inFlight: Bool = false, lastAttemptAt: Int64 = 0, settledAt: Int64? = nil, lastUsedAt: Int64 = 0, reconnectBypass: Bool = false) {
        self.generation = generation
        self.snapshot = snapshot
        self.inFlight = inFlight
        self.lastAttemptAt = lastAttemptAt
        self.settledAt = settledAt
        self.lastUsedAt = lastUsedAt
        self.reconnectBypass = reconnectBypass
    }
}

public struct MomentsProfileOpeningBegin: Equatable {
    public var generation: Int
    public var evicted: [String]

    public init(generation: Int, evicted: [String]) {
        self.generation = generation
        self.evicted = evicted
    }
}

public struct MomentsProfileOpeningNote: Equatable {
    public var applied: Bool
    public var reconnectFollowUp: Bool
    public var confirmedEmpty: Bool

    public init(applied: Bool, reconnectFollowUp: Bool, confirmedEmpty: Bool) {
        self.applied = applied
        self.reconnectFollowUp = reconnectFollowUp
        self.confirmedEmpty = confirmedEmpty
    }
}

/// The in-memory record of profile openings. A failed opening is kept only so
/// the next open and a reconnect can be throttled. A confirmed-empty opening
/// is kept so the next open, a TTL, and a publish can replace it. Entries past
/// `limit` are dropped, least recently used first.
public struct MomentsProfileOpeningStore: Equatable {
    public private(set) var entries: [String: MomentsProfileOpeningEntry]
    public var limit: Int
    public var failureThrottle: Int64
    public var reconnectThrottle: Int64
    public var emptyTTL: Int64

    public init(limit: Int = momentsProfileOpeningMemoryLimit, failureThrottle: Int64 = momentsProfileOpeningFailureThrottle, reconnectThrottle: Int64 = momentsProfileOpeningReconnectThrottle, emptyTTL: Int64 = momentsProfileOpeningEmptyTTL) {
        self.entries = [:]
        self.limit = max(1, limit)
        self.failureThrottle = failureThrottle
        self.reconnectThrottle = reconnectThrottle
        self.emptyTTL = emptyTTL
    }

    public var count: Int {
        return self.entries.count
    }

    public func snapshot(id: String) -> MomentsProfilePostsSnapshot? {
        return self.entries[id]?.snapshot
    }

    public func generation(id: String) -> Int {
        return self.entries[id]?.generation ?? 0
    }

    public func decision(id: String, now: Int64, reason: MomentsProfileOpeningReason) -> MomentsProfileOpeningDecision {
        guard let entry = self.entries[id] else {
            switch reason {
            case .profileOpen, .viewerPublished:
                return .refresh
            case .reconnect, .ttl:
                return .reuse
            }
        }
        if entry.inFlight {
            return reason == .viewerPublished ? .refresh : .reuse
        }
        guard let snapshot = entry.snapshot else {
            switch reason {
            case .profileOpen, .viewerPublished:
                return .refresh
            case .reconnect, .ttl:
                return .reuse
            }
        }
        switch snapshot.presence {
        case .present:
            return reason == .viewerPublished ? .refresh : .reuse
        case .unknown:
            switch reason {
            case .profileOpen, .viewerPublished:
                return .refresh
            case .reconnect, .ttl:
                return .reuse
            }
        case .failed:
            switch reason {
            case .viewerPublished:
                return .refresh
            case .ttl:
                return .reuse
            case .reconnect:
                if entry.reconnectBypass {
                    return .refresh
                }
                let basis = entry.settledAt ?? entry.lastAttemptAt
                return now - basis >= self.reconnectThrottle ? .refresh : .reuse
            case .profileOpen:
                let basis = entry.settledAt ?? entry.lastAttemptAt
                return now - basis >= self.failureThrottle ? .refresh : .reuse
            }
        case .empty:
            switch reason {
            case .viewerPublished, .profileOpen:
                return .refresh
            case .reconnect:
                return .reuse
            case .ttl:
                let basis = entry.settledAt ?? entry.lastAttemptAt
                return now - basis >= self.emptyTTL ? .refresh : .reuse
            }
        }
    }

    public mutating func touch(id: String, now: Int64) {
        guard var entry = self.entries[id] else {
            return
        }
        entry.lastUsedAt = now
        self.entries[id] = entry
    }

    /// Marks failed and in-flight openings so the reconnect that just happened
    /// can refresh them once. Returns the failed openings that are not mid-request.
    public mutating func grantReconnectBypass() -> [String] {
        var ready: [String] = []
        for id in self.entries.keys.sorted() {
            guard var entry = self.entries[id] else {
                continue
            }
            let failed = entry.snapshot?.presence == .failed
            if entry.inFlight || failed {
                entry.reconnectBypass = true
                self.entries[id] = entry
            }
            if failed && !entry.inFlight {
                ready.append(id)
            }
        }
        return ready
    }

    public mutating func begin(id: String, now: Int64) -> MomentsProfileOpeningBegin {
        var entry = self.entries[id] ?? MomentsProfileOpeningEntry()
        entry.generation += 1
        entry.inFlight = true
        entry.lastAttemptAt = now
        entry.lastUsedAt = now
        entry.reconnectBypass = false
        self.entries[id] = entry
        let evicted = self.evict(keeping: id)
        return MomentsProfileOpeningBegin(generation: entry.generation, evicted: evicted)
    }

    /// A list refresh already has this page. It replaces the shared opening and
    /// invalidates a request that is still in flight.
    public mutating func retain(id: String, snapshot: MomentsProfilePostsSnapshot, now: Int64) -> MomentsProfileOpeningBegin {
        var entry = self.entries[id] ?? MomentsProfileOpeningEntry()
        entry.generation += 1
        entry.inFlight = false
        entry.lastAttemptAt = now
        entry.lastUsedAt = now
        entry.settledAt = now
        entry.snapshot = snapshot
        entry.reconnectBypass = false
        self.entries[id] = entry
        let evicted = self.evict(keeping: id)
        return MomentsProfileOpeningBegin(generation: entry.generation, evicted: evicted)
    }

    public mutating func note(id: String, generation: Int, snapshot: MomentsProfilePostsSnapshot, now: Int64) -> MomentsProfileOpeningNote {
        guard var entry = self.entries[id], entry.generation == generation else {
            return MomentsProfileOpeningNote(applied: false, reconnectFollowUp: false, confirmedEmpty: false)
        }
        entry.snapshot = snapshot
        entry.lastUsedAt = now
        let terminal = snapshot.remoteCount != nil || snapshot.failed
        let confirmedEmpty = snapshot.remoteCount == 0 && !snapshot.failed
        var followUp = false
        if terminal {
            entry.inFlight = false
            entry.settledAt = now
            followUp = snapshot.presence == .failed && entry.reconnectBypass
            if snapshot.presence != .failed {
                entry.reconnectBypass = false
            }
        }
        self.entries[id] = entry
        return MomentsProfileOpeningNote(applied: true, reconnectFollowUp: followUp, confirmedEmpty: confirmedEmpty)
    }

    private mutating func evict(keeping id: String) -> [String] {
        var removed: [String] = []
        while self.entries.count > self.limit {
            guard let candidate = self.entries.filter({ $0.key != id }).min(by: { lhs, rhs in
                if lhs.value.lastUsedAt != rhs.value.lastUsedAt {
                    return lhs.value.lastUsedAt < rhs.value.lastUsedAt
                }
                return lhs.key < rhs.key
            }) else {
                break
            }
            self.entries.removeValue(forKey: candidate.key)
            removed.append(candidate.key)
        }
        return removed
    }
}

/// User profiles keep native Stories. Moments is added only when the profile has
/// posts, immediately after Stories, the same way a native pane sits in a fixed
/// slot once its content exists. Stories are not removed. Channels and groups are
/// left as they are. A `nil` list is still loading and stays `nil`. `.unknown`,
/// `.failed`, and `.empty` leave the existing panes alone.
public func momentsProfileTabs<Tab: Equatable>(_ tabs: [Tab]?, isUserProfile: Bool, posts: MomentsProfilePostsPresence, isStories: (Tab) -> Bool, moments: Tab) -> [Tab]? {
    guard isUserProfile, var tabs else {
        return tabs
    }
    tabs.removeAll { $0 == moments }
    guard posts == .present else {
        return tabs
    }
    if let storiesIndex = tabs.firstIndex(where: isStories) {
        tabs.insert(moments, at: storiesIndex + 1)
    } else {
        tabs.insert(moments, at: 0)
    }
    return tabs
}

/// The profile Stories tab. Official Simplified Chinese for `PeerInfo.PaneStories` is 动态, the same word as Moments.
/// A Chinese UI shows 快拍 instead. Every other language keeps the resolved string.
public func momentsProfileStoriesTabTitle(resolved: String, languageCodes: [String]) -> String {
    if languageCodes.contains(where: { $0.lowercased().hasPrefix("zh") }) {
        return "快拍"
    }
    return resolved
}

/// The profile pane is placed under the username card and shifted up by `topInset`.
/// The list uses that inset, so 关注 and 粉丝 start below the card. A missing bottom
/// inset keeps the previous 24pt tail padding.
public func momentsProfileListInsets(topInset: CGFloat, bottomInset: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
    return (topInset, max(bottomInset, 24))
}

/// Following and followers lists use the same visibility errors as the settings call: `list_private` is hidden, a cancelled request is ignored.
public func momentsListLoadResult(_ error: MomentsAPIError) -> MomentsListLoadResult {
    switch error {
    case .listPrivate:
        return .hidden
    case .cancelled:
        return .ignore
    case .notFound, .rateLimited, .credentialUnavailable, .invalid, .transport:
        return .failed
    }
}

/// `nil` marks every notification tab. A named tab marks only that tab.
public func momentsNotificationReadBody(tab: String?) -> [String: String] {
    guard let tab else {
        return [:]
    }
    let trimmed = tab.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return [:]
    }
    return ["tab": trimmed]
}

public struct MomentsPeoplePage: Equatable {
    public var people: [MomentsAuthor]
    public var nextCursor: String?
    public var total: Int?

    public init(people: [MomentsAuthor] = [], nextCursor: String? = nil, total: Int? = nil) {
        self.people = people
        self.nextCursor = nextCursor
        self.total = total
    }
}

public struct MomentsNotificationPage: Equatable {
    public var items: [MomentsNotification]
    public var nextCursor: String?

    public init(items: [MomentsNotification] = [], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}
