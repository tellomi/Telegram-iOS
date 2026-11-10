import Foundation

public enum MomentsAttachmentKind: Equatable {
    case image
    case video
    case voice
    case poll
    case linkPreview
}

public struct MomentsComposerAttachmentState: Equatable {
    public var imageCount: Int
    public var videoCount: Int
    public var hasVoice: Bool
    public var hasPoll: Bool
    public var hasLinkPreview: Bool

    public init(imageCount: Int = 0, videoCount: Int = 0, hasVoice: Bool = false, hasPoll: Bool = false, hasLinkPreview: Bool = false) {
        self.imageCount = imageCount
        self.videoCount = videoCount
        self.hasVoice = hasVoice
        self.hasPoll = hasPoll
        self.hasLinkPreview = hasLinkPreview
    }

    public var isEmpty: Bool {
        return self.imageCount == 0 && self.videoCount == 0 && !self.hasVoice && !self.hasPoll
    }
}

public enum MomentsAttachmentRejection: Equatable {
    case imageLimit
    case videoLimit
    case videoTooLong
    case imagesAndVideos
    case voiceWithVideo
    case voiceWithPoll
    case pollWithMedia
    case voiceTooLong
    case commentAttachmentTaken
    case commentTextLimit
}

/// FR-052, FR-058, FR-060, FR-062. Pure so the composer and the tests share one decision.
public func momentsCanAdd(kind: MomentsAttachmentKind, to state: MomentsComposerAttachmentState, limits: MomentsLimits = .standard, duration: Double? = nil) -> MomentsAttachmentRejection? {
    switch kind {
    case .image:
        if state.videoCount > 0 || state.hasPoll {
            return state.hasPoll ? .pollWithMedia : .imagesAndVideos
        }
        if state.imageCount >= limits.imageLimit {
            return .imageLimit
        }
    case .video:
        if state.imageCount > 0 || state.hasVoice || state.hasPoll {
            if state.hasPoll {
                return .pollWithMedia
            }
            if state.hasVoice {
                return .voiceWithVideo
            }
            return .imagesAndVideos
        }
        if let duration, duration > limits.videoMaxDuration {
            return .videoTooLong
        }
        if state.videoCount >= limits.videoLimit {
            return .videoLimit
        }
    case .voice:
        if state.videoCount > 0 {
            return .voiceWithVideo
        }
        if state.hasPoll {
            return .voiceWithPoll
        }
        if let duration, duration > limits.voiceMaxDuration {
            return .voiceTooLong
        }
        if state.hasVoice {
            return .voiceWithVideo
        }
    case .poll:
        if state.imageCount > 0 || state.videoCount > 0 || state.hasVoice {
            return .pollWithMedia
        }
        if state.hasPoll {
            return .pollWithMedia
        }
    case .linkPreview:
        return nil
    }
    return nil
}

/// FR-062: the preview card is removed when images, video or a poll are attached. Voice + link (no images) keeps it.
public func momentsShowsLinkPreview(_ state: MomentsComposerAttachmentState) -> Bool {
    if !state.hasLinkPreview {
        return false
    }
    if state.imageCount > 0 || state.videoCount > 0 || state.hasPoll {
        return false
    }
    return true
}

/// TBD-06 recommended option: only a public post can be reposted or quoted.
public func momentsCanRepostOrQuote(audience: MomentsAudienceKind?) -> Bool {
    return audience == .everyone
}

/// FR-051: collapse when the rendered height exceeds `limit` lines. The caller measures with the live font and width.
public func momentsTextExceedsLineLimit(fullHeight: CGFloat, lineHeight: CGFloat, limit: Int) -> Bool {
    guard lineHeight > 0, limit > 0, fullHeight > 0 else {
        return false
    }
    return fullHeight > lineHeight * CGFloat(limit)
}

public func momentsRemainingCharacters(count: Int, limit: Int, counterFrom: Int) -> Int? {
    guard count >= counterFrom else {
        return nil
    }
    return limit - count
}

public struct MomentsTextScan: Equatable {
    public var mentions: [String]
    public var topics: [String]
    public var firstURL: String?

    public init(mentions: [String], topics: [String], firstURL: String?) {
        self.mentions = mentions
        self.topics = topics
        self.firstURL = firstURL
    }
}

/// SG-08 caps. The real entity parser (`generateTextEntities`) still runs in the composer; this is the limit check.
public func momentsScanText(_ text: String, limits: MomentsLimits = .standard) -> MomentsTextScan {
    var mentions: [String] = []
    var topics: [String] = []
    var firstURL: String?
    let tokens = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
    for token in tokens {
        let raw = String(token).trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:)]}\"'"))
        if raw.hasPrefix("@"), raw.count > 1 {
            let name = String(raw.dropFirst())
            if mentions.count < limits.mentionLimit, !mentions.contains(name) {
                mentions.append(name)
            }
        } else if raw.hasPrefix("#"), raw.count > 1 {
            let name = String(raw.dropFirst())
            let length = name.count
            if length >= limits.topicNameLength.lowerBound && length <= limits.topicNameLength.upperBound && topics.count < limits.topicLimit && !topics.contains(name) {
                topics.append(name)
            }
        } else if firstURL == nil, raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            firstURL = raw
        }
    }
    return MomentsTextScan(mentions: mentions, topics: topics, firstURL: firstURL)
}

public enum MomentsPlaybackRequest: Equatable {
    case none
    case video(postId: String, index: Int)
    case voice(postId: String)
}

/// FR-056…FR-059 and FR-165. One source at a time. Reduce-motion and the energy autoplay switch block silent autoplay.
public func momentsNextPlayback(current: MomentsPlaybackRequest, event: MomentsPlaybackEvent) -> MomentsPlaybackRequest {
    switch event {
    case .reduceMotion, .autoplayDisabled:
        if case .video = current {
            return .none
        }
        return current
    case let .videoBecameVisible(postId, index):
        if case .voice = current {
            return current
        }
        return .video(postId: postId, index: index)
    case let .videoLeftScreen(postId):
        if case let .video(playing, _) = current, playing == postId {
            return .none
        }
        return current
    case let .voiceStarted(postId):
        return .voice(postId: postId)
    case let .voiceStopped(postId):
        if case let .voice(playing) = current, playing == postId {
            return .none
        }
        return current
    case let .manualVideo(postId, index):
        return .video(postId: postId, index: index)
    case .stop:
        return .none
    }
}

public enum MomentsPlaybackEvent: Equatable {
    case videoBecameVisible(postId: String, index: Int)
    case videoLeftScreen(postId: String)
    case voiceStarted(postId: String)
    case voiceStopped(postId: String)
    case manualVideo(postId: String, index: Int)
    case reduceMotion
    case autoplayDisabled
    case stop
}

/// Local hides. Reported content is hidden on every surface; mute and hide only affect the four feeds (FR-093…FR-142).
public struct MomentsLocalHides: Codable, Equatable {
    public var mutedAuthors: Set<String>
    public var hiddenPosts: Set<String>
    public var notInterested: Set<String>
    public var reportedPosts: Set<String>
    public var reportedTopics: Set<String>

    public init(mutedAuthors: Set<String> = [], hiddenPosts: Set<String> = [], notInterested: Set<String> = [], reportedPosts: Set<String> = [], reportedTopics: Set<String> = []) {
        self.mutedAuthors = mutedAuthors
        self.hiddenPosts = hiddenPosts
        self.notInterested = notInterested
        self.reportedPosts = reportedPosts
        self.reportedTopics = reportedTopics
    }

    public func allows(_ card: MomentsCard, surface: MomentsSurface) -> Bool {
        if card.isUnavailable {
            return false
        }
        if self.reportedPosts.contains(card.id) {
            return false
        }
        if !surface.isFeed {
            return true
        }
        if let author = card.author?.id, self.mutedAuthors.contains(author) {
            return false
        }
        if self.hiddenPosts.contains(card.id) || self.notInterested.contains(card.id) {
            return false
        }
        if self.reportedTopics.contains(where: { card.topics.contains($0) }) {
            return false
        }
        return true
    }
}

public func momentsPostLink(id: String, limits: MomentsLimits = .standard) -> String {
    return limits.linkBase + id
}

/// SG-09 display order. The number itself never reaches the client.
public func momentsDistanceBandRank(_ band: String) -> Int {
    switch band {
    case "<1 km":
        return 0
    case "1–5 km", "1-5 km":
        return 1
    case "5–10 km", "5-10 km":
        return 2
    case "10–50 km", "10-50 km":
        return 3
    case ">50 km":
        return 4
    default:
        return 5
    }
}

/// FR-016: the friends feed is public + mutual-followers only, even when the viewer could see more.
public func momentsBelongsInFriendsFeed(audience: MomentsAudienceKind) -> Bool {
    switch audience {
    case .everyone, .mutualFollowers:
        return true
    case .contacts, .closeFriends, .selected:
        return false
    }
}

/// FR-017: nearby is public posts whose author opted in. Friends-only never qualifies.
public func momentsBelongsInNearbyFeed(audience: MomentsAudienceKind, allowNearby: Bool) -> Bool {
    return audience == .everyone && allowNearby
}

public func momentsTrimDrafts<T>(_ drafts: [T], limit: Int, newer: (T, T) -> Bool) -> [T] {
    guard drafts.count > limit else {
        return drafts
    }
    return drafts.sorted(by: newer).prefix(limit).map { $0 }
}
