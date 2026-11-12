import Foundation
import Postbox

public enum MomentsAudienceKind: String, Codable, Equatable, CaseIterable {
    case everyone = "public"
    case contacts
    case closeFriends = "close_friends"
    case selected
    case mutualFollowers = "mutual_followers"
}

public struct MomentsAudience: Codable, Equatable {
    public var kind: MomentsAudienceKind
    public var exclude: [Int64]
    public var include: [Int64]

    public init(kind: MomentsAudienceKind, exclude: [Int64] = [], include: [Int64] = []) {
        self.kind = kind
        self.exclude = exclude
        self.include = include
    }

    public var isPublic: Bool {
        return self.kind == .everyone
    }
}

public enum MomentsCommentPolicy: String, Codable, Equatable, CaseIterable {
    case everyoneWhoCanView = "everyone_who_can_view"
    case authorFollowing = "author_following"
    case mutualFollowers = "mutual_followers"
    case mentionedOnly = "mentioned_only"
    case closed
}

public enum MomentsMediaType: String, Codable, Equatable {
    case image
    case video
    case audio
    case sticker
    case gif
}

public func momentsAudience(from privacy: EngineStoryPrivacy) -> MomentsAudience {
    let peerIds = privacy.additionallyIncludePeers.map { $0.toInt64() }
    switch privacy.base {
    case .everyone:
        return MomentsAudience(kind: .everyone, exclude: peerIds)
    case .contacts:
        return MomentsAudience(kind: .contacts, exclude: peerIds)
    case .closeFriends:
        return MomentsAudience(kind: .closeFriends)
    case .nobody:
        return MomentsAudience(kind: .selected, include: peerIds)
    case .mutualFollowers:
        return MomentsAudience(kind: .mutualFollowers)
    }
}

public func momentsStoryPrivacy(_ audience: MomentsAudience) -> EngineStoryPrivacy {
    let peers = (audience.kind == .selected ? audience.include : audience.exclude).map { id in
        PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(id))
    }
    let base: EngineStoryPrivacy.Base
    switch audience.kind {
    case .everyone:
        base = .everyone
    case .contacts:
        base = .contacts
    case .closeFriends:
        base = .closeFriends
    case .selected:
        base = .nobody
    case .mutualFollowers:
        base = .mutualFollowers
    }
    return EngineStoryPrivacy(base: base, additionallyIncludePeers: peers)
}

public struct MomentsRendition: Codable, Equatable {
    public var key: String
    public var url: String?
    public var width: Int
    public var height: Int

    public init(key: String, url: String? = nil, width: Int = 0, height: Int = 0) {
        self.key = key
        self.url = url
        self.width = width
        self.height = height
    }
}

public struct MomentsMedia: Codable, Equatable {
    public var type: MomentsMediaType
    public var key: String
    public var width: Int
    public var height: Int
    public var durationMs: Int
    public var coverKey: String?
    public var isOriginal: Bool
    public var order: Int
    public var remoteURL: String?
    public var renditions: [MomentsRendition]
    public var poster: MomentsRendition?

    public init(type: MomentsMediaType, key: String, width: Int = 0, height: Int = 0, durationMs: Int = 0, coverKey: String? = nil, isOriginal: Bool = false, order: Int = 0, remoteURL: String? = nil, renditions: [MomentsRendition] = [], poster: MomentsRendition? = nil) {
        self.type = type
        self.key = key
        self.width = width
        self.height = height
        self.durationMs = durationMs
        self.coverKey = coverKey
        self.isOriginal = isOriginal
        self.order = order
        self.remoteURL = remoteURL
        self.renditions = renditions
        self.poster = poster
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case key
        case width
        case height
        case durationMs
        case coverKey
        case isOriginal
        case order
        case remoteURL
        case renditions
        case poster
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(MomentsMediaType.self, forKey: .type)
        self.key = try container.decode(String.self, forKey: .key)
        self.width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 0
        self.height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 0
        self.durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0
        self.coverKey = try container.decodeIfPresent(String.self, forKey: .coverKey)
        self.isOriginal = try container.decodeIfPresent(Bool.self, forKey: .isOriginal) ?? false
        self.order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        self.remoteURL = try container.decodeIfPresent(String.self, forKey: .remoteURL)
        self.renditions = try container.decodeIfPresent([MomentsRendition].self, forKey: .renditions) ?? []
        self.poster = try container.decodeIfPresent(MomentsRendition.self, forKey: .poster)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.type, forKey: .type)
        try container.encode(self.key, forKey: .key)
        try container.encode(self.width, forKey: .width)
        try container.encode(self.height, forKey: .height)
        try container.encode(self.durationMs, forKey: .durationMs)
        try container.encodeIfPresent(self.coverKey, forKey: .coverKey)
        try container.encode(self.isOriginal, forKey: .isOriginal)
        try container.encode(self.order, forKey: .order)
        try container.encodeIfPresent(self.remoteURL, forKey: .remoteURL)
        if !self.renditions.isEmpty {
            try container.encode(self.renditions, forKey: .renditions)
        }
        try container.encodeIfPresent(self.poster, forKey: .poster)
    }
}

public struct MomentsAuthor: Codable, Equatable {
    public var id: String
    public var telegramUserId: Int64
    public var displayName: String
    public var username: String?
    public var avatarKey: String?
    public var followed: Bool
    public var followsViewer: Bool

    public init(id: String, telegramUserId: Int64, displayName: String, username: String? = nil, avatarKey: String? = nil, followed: Bool = false, followsViewer: Bool = false) {
        self.id = id
        self.telegramUserId = telegramUserId
        self.displayName = displayName
        self.username = username
        self.avatarKey = avatarKey
        self.followed = followed
        self.followsViewer = followsViewer
    }

    public var isMutual: Bool {
        return self.followed && self.followsViewer
    }
}

public struct MomentsLinkPreview: Codable, Equatable {
    public var url: String
    public var title: String?
    public var description: String?
    public var image: String?

    public init(url: String, title: String? = nil, description: String? = nil, image: String? = nil) {
        self.url = url
        self.title = title
        self.description = description
        self.image = image
    }
}

public struct MomentsPlace: Codable, Equatable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct MomentsLocation: Codable, Equatable {
    public var city: String?
    public var cityName: String?
    public var place: MomentsPlace?
    public var allowNearby: Bool
    /// Server-computed band (SG-09). Absent when the post has no place (FR-131). Never a coordinate.
    public var distanceBand: String?

    public init(city: String? = nil, cityName: String? = nil, place: MomentsPlace? = nil, allowNearby: Bool = false, distanceBand: String? = nil) {
        self.city = city
        self.cityName = cityName
        self.place = place
        self.allowNearby = allowNearby
        self.distanceBand = distanceBand
    }
}

public struct MomentsPollOption: Codable, Equatable {
    public var id: String
    public var text: String
    public var count: Int
    public var chosen: Bool

    public init(id: String, text: String, count: Int = 0, chosen: Bool = false) {
        self.id = id
        self.text = text
        self.count = count
        self.chosen = chosen
    }
}

/// A file copied beside the draft. It is not on the post until upload returns a key.
public struct MomentsComposerLocalMedia: Codable, Equatable {
    public var path: String
    public var filename: String
    public var mimeType: String
    public var type: MomentsMediaType
    public var width: Int
    public var height: Int
    public var durationMs: Int
    public var order: Int

    public init(path: String, filename: String, mimeType: String, type: MomentsMediaType, width: Int, height: Int, durationMs: Int, order: Int) {
        self.path = path
        self.filename = filename
        self.mimeType = mimeType
        self.type = type
        self.width = width
        self.height = height
        self.durationMs = durationMs
        self.order = order
    }

    public func uploadFile() -> MomentsUploadFile {
        return MomentsUploadFile(path: self.path, filename: self.filename, mimeType: self.mimeType, type: self.type, width: self.width, height: self.height, durationMs: self.durationMs, order: self.order)
    }
}

public struct MomentsComposerDraft: Codable, Equatable {
    public var text: String
    public var privacyBase: Int32
    public var peerIds: [Int64]
    public var allowNearby: Bool
    public var quoteId: String?
    public var media: [MomentsMedia]
    /// Drafts written before this field were put back on screen as an already chosen audience.
    public var audienceChosen: Bool
    public var clientNonce: String?
    public var localMedia: [MomentsComposerLocalMedia]

    public init(text: String, privacyBase: Int32, peerIds: [Int64], allowNearby: Bool, quoteId: String?, media: [MomentsMedia], audienceChosen: Bool = true, clientNonce: String? = nil, localMedia: [MomentsComposerLocalMedia] = []) {
        self.text = text
        self.privacyBase = privacyBase
        self.peerIds = peerIds
        self.allowNearby = allowNearby
        self.quoteId = quoteId
        self.media = media
        self.audienceChosen = audienceChosen
        self.clientNonce = clientNonce
        self.localMedia = localMedia
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case privacyBase
        case peerIds
        case allowNearby
        case quoteId
        case media
        case audienceChosen
        case clientNonce
        case localMedia
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.privacyBase = try container.decodeIfPresent(Int32.self, forKey: .privacyBase) ?? EngineStoryPrivacy.Base.everyone.rawValue
        self.peerIds = try container.decodeIfPresent([Int64].self, forKey: .peerIds) ?? []
        self.allowNearby = try container.decodeIfPresent(Bool.self, forKey: .allowNearby) ?? false
        self.quoteId = try container.decodeIfPresent(String.self, forKey: .quoteId)
        self.media = try container.decodeIfPresent([MomentsMedia].self, forKey: .media) ?? []
        self.audienceChosen = try container.decodeIfPresent(Bool.self, forKey: .audienceChosen) ?? true
        self.clientNonce = try container.decodeIfPresent(String.self, forKey: .clientNonce)
        self.localMedia = try container.decodeIfPresent([MomentsComposerLocalMedia].self, forKey: .localMedia) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.text, forKey: .text)
        try container.encode(self.privacyBase, forKey: .privacyBase)
        try container.encode(self.peerIds, forKey: .peerIds)
        try container.encode(self.allowNearby, forKey: .allowNearby)
        try container.encodeIfPresent(self.quoteId, forKey: .quoteId)
        try container.encode(self.media, forKey: .media)
        try container.encode(self.audienceChosen, forKey: .audienceChosen)
        try container.encodeIfPresent(self.clientNonce, forKey: .clientNonce)
        try container.encode(self.localMedia, forKey: .localMedia)
    }
}

public struct MomentsStoredAudience: Codable, Equatable {
    public var base: Int32
    public var peers: [Int64]

    public init(base: Int32, peers: [Int64]) {
        self.base = base
        self.peers = peers
    }
}

public struct MomentsUploadFile: Equatable {
    public var path: String
    public var filename: String
    public var mimeType: String
    public var type: MomentsMediaType
    public var width: Int
    public var height: Int
    public var durationMs: Int
    public var order: Int

    public init(path: String, filename: String, mimeType: String, type: MomentsMediaType, width: Int, height: Int, durationMs: Int, order: Int) {
        self.path = path
        self.filename = filename
        self.mimeType = mimeType
        self.type = type
        self.width = width
        self.height = height
        self.durationMs = durationMs
        self.order = order
    }
}

public struct MomentsPollOptionVoters: Equatable {
    public var id: String
    public var text: String
    public var voters: [MomentsAuthor]

    public init(id: String, text: String, voters: [MomentsAuthor]) {
        self.id = id
        self.text = text
        self.voters = voters
    }
}

public struct MomentsPoll: Codable, Equatable {
    public var question: String
    public var options: [MomentsPollOption]
    public var multiple: Bool
    public var anonymous: Bool
    public var closesAt: Int64?
    public var closedAt: Int64?
    public var closedByAuthor: Bool
    public var totalVoters: Int
    public var voted: Bool

    public init(question: String, options: [MomentsPollOption], multiple: Bool = false, anonymous: Bool = true, closesAt: Int64? = nil, closedAt: Int64? = nil, closedByAuthor: Bool = false, totalVoters: Int = 0, voted: Bool = false) {
        self.question = question
        self.options = options
        self.multiple = multiple
        self.anonymous = anonymous
        self.closesAt = closesAt
        self.closedAt = closedAt
        self.closedByAuthor = closedByAuthor
        self.totalVoters = totalVoters
        self.voted = voted
    }

    public var isClosed: Bool {
        if self.closedAt != nil || self.closedByAuthor {
            return true
        }
        if let closesAt = self.closesAt {
            return Int64(Date().timeIntervalSince1970) >= closesAt
        }
        return false
    }

    /// FR-113: results after a vote, or for everyone once the poll has ended.
    public var showsResults: Bool {
        return self.voted || self.isClosed
    }
}

public struct MomentsCounts: Codable, Equatable {
    public var likes: Int
    public var comments: Int
    public var reposts: Int

    public init(likes: Int = 0, comments: Int = 0, reposts: Int = 0) {
        self.likes = likes
        self.comments = comments
        self.reposts = reposts
    }
}

public struct MomentsViewerState: Codable, Equatable {
    public var liked: Bool
    public var saved: Bool
    public var reposted: Bool
    public var canComment: Bool
    public var commentDeniedReason: String?

    public init(liked: Bool = false, saved: Bool = false, reposted: Bool = false, canComment: Bool = true, commentDeniedReason: String? = nil) {
        self.liked = liked
        self.saved = saved
        self.reposted = reposted
        self.canComment = canComment
        self.commentDeniedReason = commentDeniedReason
    }
}

/// A quoted card. Unavailable quotes keep the quoting post's own text and carry no author, body or media (FR-097).
public struct MomentsQuote: Codable, Equatable {
    public var id: String
    public var unavailable: Bool
    public var authorName: String?
    public var text: String?
    public var hasMedia: Bool

    public init(id: String, unavailable: Bool, authorName: String? = nil, text: String? = nil, hasMedia: Bool = false) {
        self.id = id
        self.unavailable = unavailable
        self.authorName = authorName
        self.text = text
        self.hasMedia = hasMedia
    }
}

public struct MomentsCard: Codable, Equatable {
    public var id: String
    public var version: Int64
    public var state: String
    public var author: MomentsAuthor?
    public var text: String
    public var createdAt: Int64
    public var editedAt: Int64?
    public var audience: MomentsAudience?
    public var commentPolicy: MomentsCommentPolicy
    public var media: [MomentsMedia]
    public var linkPreview: MomentsLinkPreview?
    public var quote: MomentsQuote?
    public var poll: MomentsPoll?
    public var location: MomentsLocation?
    public var topics: [String]
    public var counts: MomentsCounts
    public var viewer: MomentsViewerState
    public var repostedBy: MomentsAuthor?
    public var pinned: Bool

    public init(id: String, version: Int64 = 0, state: String = "published", author: MomentsAuthor? = nil, text: String = "", createdAt: Int64 = 0, editedAt: Int64? = nil, audience: MomentsAudience? = nil, commentPolicy: MomentsCommentPolicy = .everyoneWhoCanView, media: [MomentsMedia] = [], linkPreview: MomentsLinkPreview? = nil, quote: MomentsQuote? = nil, poll: MomentsPoll? = nil, location: MomentsLocation? = nil, topics: [String] = [], counts: MomentsCounts = MomentsCounts(), viewer: MomentsViewerState = MomentsViewerState(), repostedBy: MomentsAuthor? = nil, pinned: Bool = false) {
        self.id = id
        self.version = version
        self.state = state
        self.author = author
        self.text = text
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.audience = audience
        self.commentPolicy = commentPolicy
        self.media = media
        self.linkPreview = linkPreview
        self.quote = quote
        self.poll = poll
        self.location = location
        self.topics = topics
        self.counts = counts
        self.viewer = viewer
        self.repostedBy = repostedBy
        self.pinned = pinned
    }

    public var isUnavailable: Bool {
        return self.state == "unavailable" || self.state == "deleted"
    }

    public var showsEditedMark: Bool {
        return self.editedAt != nil
    }

    public var images: [MomentsMedia] {
        return self.media.filter { $0.type == .image }
    }

    public var videos: [MomentsMedia] {
        return self.media.filter { $0.type == .video }
    }

    public var voice: MomentsMedia? {
        return self.media.first { $0.type == .audio }
    }

    /// FR-062: a link card is hidden once the post carries images, video or a poll.
    public var visibleLinkPreview: MomentsLinkPreview? {
        if self.poll != nil || !self.images.isEmpty || !self.videos.isEmpty {
            return nil
        }
        return self.linkPreview
    }

    /// FR-131: a city alone never shows a distance.
    public var visibleDistanceBand: String? {
        guard self.location?.place != nil else {
            return nil
        }
        return self.location?.distanceBand
    }
}

public struct MomentsPage: Equatable {
    public var items: [MomentsCard]
    public var nextCursor: String?

    public init(items: [MomentsCard], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

/// A reply under a root comment. One level only (FR-102), so this type does not contain further replies.
public struct MomentsReply: Codable, Equatable {
    public var id: String
    public var postId: String
    public var rootId: String
    public var replyToName: String?
    public var author: MomentsAuthor?
    public var text: String
    public var attachment: MomentsMedia?
    public var createdAt: Int64
    public var likeCount: Int
    public var liked: Bool

    public var isAuthor: Bool
    public var ipRegionLabel: String?
    public var disliked: Bool
    /// `me.author` on the comment card: the signed-in viewer wrote this reply.
    public var viewerAuthored: Bool

    public init(id: String, postId: String, rootId: String, replyToName: String? = nil, author: MomentsAuthor? = nil, text: String, attachment: MomentsMedia? = nil, createdAt: Int64 = 0, likeCount: Int = 0, liked: Bool = false, isAuthor: Bool = false, ipRegionLabel: String? = nil, disliked: Bool = false, viewerAuthored: Bool = false) {
        self.id = id
        self.postId = postId
        self.rootId = rootId
        self.replyToName = replyToName
        self.author = author
        self.text = text
        self.attachment = attachment
        self.createdAt = createdAt
        self.likeCount = likeCount
        self.liked = liked
        self.isAuthor = isAuthor
        self.ipRegionLabel = ipRegionLabel
        self.disliked = disliked
        self.viewerAuthored = viewerAuthored
    }
}

public struct MomentsComment: Codable, Equatable {
    public var id: String
    public var postId: String
    public var author: MomentsAuthor?
    public var text: String
    public var attachment: MomentsMedia?
    public var createdAt: Int64
    public var likeCount: Int
    public var liked: Bool
    public var replies: [MomentsReply]
    public var replyCount: Int
    public var isAuthor: Bool
    public var ipRegionLabel: String?
    public var disliked: Bool
    /// `me.author` on the comment card: the signed-in viewer wrote this comment.
    public var viewerAuthored: Bool

    public init(id: String, postId: String, author: MomentsAuthor? = nil, text: String, attachment: MomentsMedia? = nil, createdAt: Int64 = 0, likeCount: Int = 0, liked: Bool = false, replies: [MomentsReply] = [], replyCount: Int = 0, isAuthor: Bool = false, ipRegionLabel: String? = nil, disliked: Bool = false, viewerAuthored: Bool = false) {
        self.id = id
        self.postId = postId
        self.author = author
        self.text = text
        self.attachment = attachment
        self.createdAt = createdAt
        self.likeCount = likeCount
        self.liked = liked
        self.replies = replies
        self.replyCount = replyCount
        self.isAuthor = isAuthor
        self.ipRegionLabel = ipRegionLabel
        self.disliked = disliked
        self.viewerAuthored = viewerAuthored
    }
}

public struct MomentsCommentPage: Equatable {
    public var comments: [MomentsComment]
    public var total: Int
    public var cursor: String?

    public init(comments: [MomentsComment], total: Int, cursor: String?) {
        self.comments = comments
        self.total = total
        self.cursor = cursor
    }
}

public struct MomentsReplyPage: Equatable {
    public var replies: [MomentsReply]
    public var total: Int
    public var cursor: String?

    public init(replies: [MomentsReply], total: Int, cursor: String?) {
        self.replies = replies
        self.total = total
        self.cursor = cursor
    }
}

public enum MomentsNotificationKind: String, Codable, Equatable, CaseIterable {
    case all
    case like
    case comment
    case reply
    case mention
    case follow
    case mutual
    case repost
    case quote
    case newPost = "new_post"
    case system
}

public struct MomentsNotification: Codable, Equatable {
    public var id: String
    public var kind: MomentsNotificationKind
    public var actors: [MomentsAuthor]
    public var extraActorCount: Int
    public var postId: String?
    public var commentId: String?
    public var text: String?
    public var createdAt: Int64
    public var read: Bool
    public var unavailable: Bool

    public init(id: String, kind: MomentsNotificationKind, actors: [MomentsAuthor] = [], extraActorCount: Int = 0, postId: String? = nil, commentId: String? = nil, text: String? = nil, createdAt: Int64 = 0, read: Bool = false, unavailable: Bool = false) {
        self.id = id
        self.kind = kind
        self.actors = actors
        self.extraActorCount = extraActorCount
        self.postId = postId
        self.commentId = commentId
        self.text = text
        self.createdAt = createdAt
        self.read = read
        self.unavailable = unavailable
    }
}

public struct MomentsNotificationSettings: Codable, Equatable {
    public var comments: Bool
    public var replies: Bool
    public var mentions: Bool
    public var follows: Bool
    public var likes: Bool
    public var reposts: Bool
    public var newPosts: Bool

    public init(comments: Bool = true, replies: Bool = true, mentions: Bool = true, follows: Bool = true, likes: Bool = false, reposts: Bool = false, newPosts: Bool = false) {
        self.comments = comments
        self.replies = replies
        self.mentions = mentions
        self.follows = follows
        self.likes = likes
        self.reposts = reposts
        self.newPosts = newPosts
    }

    /// FR-123 defaults: comments, replies, mentions and new follows on; the rest off.
    public static let defaults = MomentsNotificationSettings()
}

public enum MomentsListVisibility: String, Codable, Equatable {
    case everyone = "public"
    case onlyMe = "self"
}

public struct MomentsListVisibilitySettings: Codable, Equatable {
    public var followingList: MomentsListVisibility
    public var followersList: MomentsListVisibility

    public init(followingList: MomentsListVisibility = .everyone, followersList: MomentsListVisibility = .everyone) {
        self.followingList = followingList
        self.followersList = followersList
    }

    public static let defaults = MomentsListVisibilitySettings()
}

public enum MomentsAPIError: Equatable, Error {
    case credentialUnavailable
    case notFound
    case listPrivate
    case rateLimited
    case invalid(String)
    case transport(String)
    case cancelled
}

public struct MomentsCredential: Equatable {
    public var token: String
    /// HTTPS origin from `help.getAppConfig`, never the credential's `region`.
    public var baseURL: String
    public var expiresAt: Int64?
    /// `cn` or `global`. Not a hostname.
    public var region: String

    public init(token: String, baseURL: String, expiresAt: Int64? = nil, region: String) {
        self.token = token
        self.baseURL = baseURL
        self.expiresAt = expiresAt
        self.region = region
    }

    /// Refresh this many seconds before `expires` so a call does not race the server clock.
    public static let refreshMargin: Int64 = 60

    public func needsRefresh(now: Int64) -> Bool {
        guard let expiresAt = self.expiresAt else {
            return true
        }
        return now + MomentsCredential.refreshMargin >= expiresAt
    }
}
