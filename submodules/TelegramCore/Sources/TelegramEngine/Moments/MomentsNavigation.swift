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
