import Foundation

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

    public init(type: MomentsMediaType, key: String, width: Int = 0, height: Int = 0, durationMs: Int = 0, coverKey: String? = nil, isOriginal: Bool = false, order: Int = 0, remoteURL: String? = nil) {
        self.type = type
        self.key = key
        self.width = width
        self.height = height
        self.durationMs = durationMs
        self.coverKey = coverKey
        self.isOriginal = isOriginal
        self.order = order
        self.remoteURL = remoteURL
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

    public init(id: String, postId: String, rootId: String, replyToName: String? = nil, author: MomentsAuthor? = nil, text: String, attachment: MomentsMedia? = nil, createdAt: Int64 = 0, likeCount: Int = 0, liked: Bool = false) {
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

    public init(id: String, postId: String, author: MomentsAuthor? = nil, text: String, attachment: MomentsMedia? = nil, createdAt: Int64 = 0, likeCount: Int = 0, liked: Bool = false, replies: [MomentsReply] = [], replyCount: Int = 0) {
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

public struct MomentsCity: Codable, Equatable {
    public var code: String
    public var name: String

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
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
    public var baseURL: String
    public var expiresAt: Int64?

    public init(token: String, baseURL: String, expiresAt: Int64? = nil) {
        self.token = token
        self.baseURL = baseURL
        self.expiresAt = expiresAt
    }

    public func isExpired(now: Int64) -> Bool {
        guard let expiresAt = self.expiresAt else {
            return false
        }
        return now >= expiresAt
    }
}
