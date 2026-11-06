import Foundation

/// Discover likes and public text comments.
///
/// A like keeps one desired state. A response whose generation does not match
/// the tap on screen is dropped. This does not call a story reaction API.
public let tellomiDiscoverCommentTextLimit = 500
public let tellomiDiscoverCommentPageLimit = 50

public struct TellomiDiscoverCommentCreated: Equatable {
    public var id: String
    public var state: String
    public var version: Int
    public var held: Bool?

    public init(id: String, state: String, version: Int, held: Bool?) {
        self.id = id
        self.state = state
        self.version = version
        self.held = held
    }
}

public struct TellomiDiscoverCommentPage: Equatable {
    public var comments: [TellomiDiscoverComment]
    public var cursor: String?

    public init(comments: [TellomiDiscoverComment], cursor: String?) {
        self.comments = comments
        self.cursor = cursor
    }
}

public struct TellomiDiscoverLikeView: Equatable {
    public var liked: Bool
    public var hidden: Bool
    public var count: Int

    public init(liked: Bool, hidden: Bool, count: Int) {
        self.liked = liked
        self.hidden = hidden
        self.count = count
    }
}

public struct TellomiDiscoverLikeRequest: Equatable {
    public var generation: Int
    public var postId: String
    public var on: Bool
    public var surface: String

    public init(generation: Int, postId: String, on: Bool, surface: String) {
        self.generation = generation
        self.postId = postId
        self.on = on
        self.surface = surface
    }
}

public struct TellomiDiscoverLikeState: Equatable {
    public var postId: String
    public var surface: String
    public var generation: Int
    public var confirmedLiked: Bool
    public var targetLiked: Bool
    public var confirmedCount: Int
    public var hidden: Bool

    public init(postId: String, liked: Bool, count: Int, hidden: Bool, surface: String) {
        self.postId = postId
        self.surface = tellomiDiscoverLikeSurface(surface)
        self.generation = 0
        self.confirmedLiked = liked
        self.targetLiked = liked
        self.confirmedCount = max(0, count)
        self.hidden = hidden
    }

    public func view() -> TellomiDiscoverLikeView {
        let shown = self.targetLiked
        let delta = (shown ? 1 : 0) - (self.confirmedLiked ? 1 : 0)
        return TellomiDiscoverLikeView(liked: shown, hidden: self.hidden, count: max(0, self.confirmedCount + delta))
    }

    /// One desired like. A hidden count does not send. Returns nil when the tap does not change the target.
    public mutating func tap() -> TellomiDiscoverLikeRequest? {
        if self.hidden {
            return nil
        }
        self.targetLiked.toggle()
        self.generation += 1
        return TellomiDiscoverLikeRequest(generation: self.generation, postId: self.postId, on: self.targetLiked, surface: self.surface)
    }

    /// A mismatched generation is ignored. Failure restores the last confirmed count.
    public mutating func finish(generation: Int, success: Bool) -> TellomiDiscoverLikeView {
        guard generation == self.generation else {
            return self.view()
        }
        if success {
            self.confirmedLiked = self.targetLiked
            self.confirmedCount = self.view().count
        } else {
            self.targetLiked = self.confirmedLiked
        }
        return self.view()
    }
}

/// `recommend` unless the value is one of the engine surfaces. Nearby is not one of them.
public func tellomiDiscoverLikeSurface(_ raw: String) -> String {
    switch raw {
    case "following", "hot", "search", "profile":
        return raw
    default:
        return "recommend"
    }
}

public func tellomiDiscoverCommentError(text: String, parentId: String?, nonce: String) -> TellomiDiscoverClientError? {
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard body.count >= 1, body.count <= tellomiDiscoverCommentTextLimit else {
        return .invalidText
    }
    if let parentId {
        let parent = parentId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !parent.isEmpty, !tellomiDiscoverClientNonce(parent) {
            return .invalidParent
        }
    }
    guard tellomiDiscoverClientNonce(nonce) else {
        return .invalidNonce
    }
    return nil
}

/// `text`, optional `parent_id`, `client_nonce`. No `media_keys` and no `operation_id`.
public func tellomiDiscoverCommentBody(text: String, parentId: String?, nonce: String) -> Data? {
    if tellomiDiscoverCommentError(text: text, parentId: parentId, nonce: nonce) != nil {
        return nil
    }
    var object: [String: Any] = [
        "text": text.trimmingCharacters(in: .whitespacesAndNewlines),
        "client_nonce": nonce
    ]
    if let parentId {
        let parent = parentId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !parent.isEmpty {
            object["parent_id"] = parent
        }
    }
    return try? JSONSerialization.data(withJSONObject: object, options: [])
}

public func tellomiDiscoverReactError(status: Int, code: String?) -> TellomiDiscoverClientError? {
    guard let code else {
        return nil
    }
    if status == 409, code == "profile_required" {
        return .profileRequired
    }
    if status == 400, code == "invalid_text" {
        return .invalidText
    }
    if status == 400, code == "client_nonce" {
        return .invalidNonce
    }
    if status == 400, code == "parent" {
        return .invalidParent
    }
    if status == 400, code == "cursor" || code == "invalid_cursor" {
        return .badCursor
    }
    if status == 403, code == "comments_closed" {
        return .commentsClosed
    }
    if status == 403, code == "reply_not_allowed" {
        return .replyNotAllowed
    }
    if status == 403, code == "harassment_guard" {
        return .harassmentGuard
    }
    if status == 403, code == "not_commentable" {
        return .notCommentable
    }
    return nil
}

