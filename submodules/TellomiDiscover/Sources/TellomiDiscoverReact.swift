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
    public var version: Int
    public var postId: String
    public var on: Bool
    public var surface: String
    public var intentVersion: Int
    public var automatic: Bool

    public init(generation: Int, version: Int, postId: String, on: Bool, surface: String, intentVersion: Int, automatic: Bool) {
        self.generation = generation
        self.version = version
        self.postId = postId
        self.on = on
        self.surface = surface
        self.intentVersion = intentVersion
        self.automatic = automatic
    }
}

/// One desired like. A failed call restores the last confirmed count.
/// A response for another generation or version is ignored. An uncertain
/// failure sends at most one idempotent follow-up. 403 and 404 do not.
public final class TellomiDiscoverLike {
    public private(set) var postId: String
    public private(set) var surface: String
    private var generation = 1
    private var nextVersion = 1
    private var intentVersion = 0
    private var confirmedLiked: Bool
    private var targetLiked: Bool
    private var confirmedCount: Int
    private var hidden: Bool
    private var inflight: TellomiDiscoverLikeRequest?
    public private(set) var failure: TellomiDiscoverClientError?

    public init(postId: String, liked: Bool, count: Int, hidden: Bool, surface: String) {
        self.postId = postId
        self.surface = tellomiDiscoverLikeSurface(surface)
        self.confirmedLiked = liked
        self.targetLiked = liked
        self.confirmedCount = max(0, count)
        self.hidden = hidden
    }

    public func generationValue() -> Int {
        return self.generation
    }

    public func idle() -> Bool {
        return self.inflight == nil && self.targetLiked == self.confirmedLiked
    }

    public func close() {
        self.generation += 1
        self.inflight = nil
        self.targetLiked = self.confirmedLiked
        self.failure = nil
    }

    public func adopt(liked: Bool, count: Int, likesHidden: Bool) {
        if !self.idle() {
            return
        }
        self.confirmedLiked = liked
        self.targetLiked = liked
        self.confirmedCount = max(0, count)
        self.hidden = likesHidden
    }

    public func bind(postId: String, liked: Bool, count: Int, likesHidden: Bool, surface: String) {
        self.surface = tellomiDiscoverLikeSurface(surface)
        if postId == self.postId {
            self.adopt(liked: liked, count: count, likesHidden: likesHidden)
            return
        }
        self.generation += 1
        self.inflight = nil
        self.postId = postId
        self.confirmedLiked = liked
        self.targetLiked = liked
        self.confirmedCount = max(0, count)
        self.hidden = likesHidden
    }

    public func view() -> TellomiDiscoverLikeView {
        var count = self.confirmedCount
        if !self.hidden {
            if self.targetLiked && !self.confirmedLiked {
                count += 1
            }
            if !self.targetLiked && self.confirmedLiked {
                count = max(0, count - 1)
            }
        }
        return TellomiDiscoverLikeView(liked: self.targetLiked, hidden: self.hidden, count: count)
    }

    public func tap() -> TellomiDiscoverLikeRequest? {
        self.intentVersion += 1
        self.targetLiked.toggle()
        self.failure = nil
        if self.inflight != nil {
            return nil
        }
        return self.send(automatic: false)
    }

    public func finish(generation: Int, version: Int, error: TellomiDiscoverClientError?) -> TellomiDiscoverLikeRequest? {
        guard self.generation == generation, let sent = self.inflight, sent.version == version else {
            return nil
        }
        let sentOn = sent.on
        self.inflight = nil
        if error == nil {
            if !self.hidden {
                if sentOn && !self.confirmedLiked {
                    self.confirmedCount += 1
                }
                if !sentOn && self.confirmedLiked {
                    self.confirmedCount = max(0, self.confirmedCount - 1)
                }
            }
            self.confirmedLiked = sentOn
            self.failure = nil
            if self.targetLiked != self.confirmedLiked {
                return self.send(automatic: false)
            }
            return nil
        }
        if tellomiDiscoverPermanentLikeFailure(error!) || sent.automatic || sent.intentVersion == self.intentVersion {
            self.targetLiked = self.confirmedLiked
            self.failure = error
            return nil
        }
        self.failure = nil
        return self.send(automatic: true)
    }

    private func send(automatic: Bool) -> TellomiDiscoverLikeRequest {
        let request = TellomiDiscoverLikeRequest(generation: self.generation, version: self.nextVersion, postId: self.postId, on: self.targetLiked, surface: self.surface, intentVersion: self.intentVersion, automatic: automatic)
        self.nextVersion += 1
        self.inflight = request
        return request
    }
}

/// Detail draws only the comment thread. Once the thread is bound, an empty
/// visible and pending list stays empty. The card snapshot is not drawn again.
public func tellomiDiscoverDetailCommentRows(bound: Bool, visible: [TellomiDiscoverComment], pending: [TellomiDiscoverComment]) -> [TellomiDiscoverComment] {
    if !bound {
        return []
    }
    return visible + pending
}

/// A pending or held comment was never added to the public total.
public func tellomiDiscoverPublicCountAfterDelete(count: Int, wasVisible: Bool, deleted: Bool) -> Int {
    guard deleted, wasVisible else {
        return count
    }
    return max(0, count - 1)
}

public func tellomiDiscoverPermanentLikeFailure(_ error: TellomiDiscoverClientError) -> Bool {
    switch error {
    case .notFound, .hidden, .unauthorized, .profileRequired, .invalidText, .invalidNonce, .invalidParent, .commentsClosed, .replyNotAllowed, .harassmentGuard, .notCommentable, .badCursor:
        return true
    default:
        return false
    }
}

public func tellomiDiscoverApplyLike(_ like: TellomiDiscoverLike, request: TellomiDiscoverLikeRequest?, result: Result<TellomiDiscoverDecoded, TellomiDiscoverClientError>?) -> TellomiDiscoverLikeRequest? {
    guard let request, request.generation == like.generationValue() else {
        return nil
    }
    let error: TellomiDiscoverClientError?
    if let result, case .success = result {
        error = nil
    } else if let result, case let .failure(value) = result {
        error = value
    } else {
        error = .unavailable
    }
    return like.finish(generation: request.generation, version: request.version, error: error)
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

public struct TellomiDiscoverCommentLoad: Equatable {
    public var generation: Int
    public var version: Int
    public var postId: String
    public var cursor: String?
}

public struct TellomiDiscoverCommentSend: Equatable {
    public var generation: Int
    public var version: Int
    public var postId: String?
    public var text: String?
    public var parentId: String?
    public var nonce: String?
    public var error: TellomiDiscoverClientError?

    public func ready() -> Bool {
        return self.error == nil
    }
}

public struct TellomiDiscoverCommentDelete: Equatable {
    public var generation: Int
    public var version: Int
    public var commentId: String
}

/// Public comments for one post. Pending rows stay out of `publicCount()`.
public final class TellomiDiscoverComments {
    public private(set) var postId: String = ""
    private var generation = 1
    private var nextVersion = 1
    private var loading = false
    private var loadVersion = 0
    private var cursor: String?
    private var ended = false
    private var writing = false
    private var writeVersion = 0
    private var lastText = ""
    private var lastParent: String?
    private var lastNonce: String?
    private var lastSucceeded = true
    private var visible: [String: TellomiDiscoverComment] = [:]
    private var visibleOrder: [String] = []
    private var pending: [String: TellomiDiscoverComment] = [:]
    private var pendingOrder: [String] = []
    private var own: Set<String> = []

    public init() {
    }

    public func generationValue() -> Int {
        return self.generation
    }

    public func close() {
        self.generation += 1
        self.loading = false
        self.writing = false
    }

    public func open(postId: String) -> TellomiDiscoverCommentLoad {
        self.generation += 1
        self.postId = postId
        self.visible.removeAll()
        self.visibleOrder.removeAll()
        self.pending.removeAll()
        self.pendingOrder.removeAll()
        self.own.removeAll()
        self.cursor = nil
        self.ended = false
        self.loading = false
        self.writing = false
        self.lastText = ""
        self.lastParent = nil
        self.lastNonce = nil
        self.lastSucceeded = true
        return self.load(pageCursor: nil)
    }

    public func more() -> TellomiDiscoverCommentLoad? {
        if self.loading || self.ended || self.cursor == nil {
            return nil
        }
        return self.load(pageCursor: self.cursor)
    }

    private func load(pageCursor: String?) -> TellomiDiscoverCommentLoad {
        self.loading = true
        self.loadVersion = self.nextVersion
        self.nextVersion += 1
        return TellomiDiscoverCommentLoad(generation: self.generation, version: self.loadVersion, postId: self.postId, cursor: pageCursor)
    }

    public func accept(generation: Int, version: Int, page: TellomiDiscoverCommentPage?) -> Bool {
        guard self.generation == generation, self.loading, version == self.loadVersion, let page else {
            return false
        }
        self.loading = false
        for comment in page.comments {
            if self.visible[comment.id] != nil || self.pending[comment.id] != nil {
                continue
            }
            if let post = comment.postId, !self.postId.isEmpty, post != self.postId {
                continue
            }
            if comment.state != "ok" {
                continue
            }
            self.visible[comment.id] = comment
            self.visibleOrder.append(comment.id)
            if comment.own {
                self.own.insert(comment.id)
            }
        }
        if page.cursor == nil || page.cursor?.isEmpty == true {
            self.ended = true
            self.cursor = nil
        } else {
            self.cursor = page.cursor
            self.ended = false
        }
        return true
    }

    public func failLoad(generation: Int, version: Int) {
        guard self.generation == generation, version == self.loadVersion else {
            return
        }
        self.loading = false
    }

    public func publicCount() -> Int {
        return self.visible.count
    }

    public func visibleRows() -> [TellomiDiscoverComment] {
        return self.visibleOrder.compactMap { self.visible[$0] }
    }

    public func pendingRows() -> [TellomiDiscoverComment] {
        return self.pendingOrder.compactMap { self.pending[$0] }
    }

    public func hasMore() -> Bool {
        return !self.ended && self.cursor != nil && !self.loading
    }

    public func canDelete(_ commentId: String) -> Bool {
        return self.own.contains(commentId)
    }

    public func replyTo(_ comment: TellomiDiscoverComment) -> String? {
        guard self.visible[comment.id] != nil else {
            return nil
        }
        if let post = comment.postId, !self.postId.isEmpty, post != self.postId {
            return nil
        }
        if comment.state != "ok" {
            return nil
        }
        return comment.id
    }

    public func submit(text: String, parentId: String?, freshNonce: String) -> TellomiDiscoverCommentSend? {
        if self.writing {
            return nil
        }
        var parent = parentId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if parent?.isEmpty == true {
            parent = nil
        }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parent, self.visible[parent] == nil {
            return TellomiDiscoverCommentSend(generation: 0, version: 0, postId: nil, text: nil, parentId: nil, nonce: nil, error: .invalidParent)
        }
        let same = body == self.lastText && parent == self.lastParent
        let nonce = !self.lastSucceeded && same && self.lastNonce != nil ? self.lastNonce! : freshNonce
        if let error = tellomiDiscoverCommentError(text: body, parentId: parent, nonce: nonce) {
            return TellomiDiscoverCommentSend(generation: 0, version: 0, postId: nil, text: nil, parentId: nil, nonce: nil, error: error)
        }
        self.writing = true
        self.writeVersion = self.nextVersion
        self.nextVersion += 1
        self.lastText = body
        self.lastParent = parent
        self.lastNonce = nonce
        self.lastSucceeded = false
        return TellomiDiscoverCommentSend(generation: self.generation, version: self.writeVersion, postId: self.postId, text: body, parentId: parent, nonce: nonce, error: nil)
    }

    public func finishSend(generation: Int, version: Int, created: TellomiDiscoverCommentCreated?) -> Bool {
        guard self.generation == generation, self.writing, version == self.writeVersion, let created else {
            return false
        }
        self.writing = false
        self.lastSucceeded = true
        let text = self.lastText
        let parent = self.lastParent
        self.lastNonce = nil
        self.own.insert(created.id)
        if created.state != "ok" {
            if self.pending[created.id] == nil {
                self.pendingOrder.append(created.id)
            }
            self.pending[created.id] = TellomiDiscoverComment(id: created.id, text: text, authorName: "", state: created.state, own: true, parentId: parent, postId: self.postId)
            return true
        }
        if self.visible[created.id] == nil {
            self.visibleOrder.append(created.id)
            self.visible[created.id] = TellomiDiscoverComment(id: created.id, text: text, authorName: "", state: "ok", own: true, parentId: parent, postId: self.postId)
        }
        return true
    }

    public func failSend(generation: Int, version: Int) {
        guard self.generation == generation, version == self.writeVersion else {
            return
        }
        self.writing = false
    }

    public func delete(_ commentId: String) -> TellomiDiscoverCommentDelete? {
        if self.writing || !self.canDelete(commentId) {
            return nil
        }
        self.writing = true
        self.writeVersion = self.nextVersion
        self.nextVersion += 1
        return TellomiDiscoverCommentDelete(generation: self.generation, version: self.writeVersion, commentId: commentId)
    }

    public func finishDelete(generation: Int, version: Int, commentId: String, ok: Bool) -> Bool {
        guard self.generation == generation, self.writing, version == self.writeVersion else {
            return false
        }
        self.writing = false
        if !ok {
            return false
        }
        self.visible.removeValue(forKey: commentId)
        self.visibleOrder.removeAll { $0 == commentId }
        self.pending.removeValue(forKey: commentId)
        self.pendingOrder.removeAll { $0 == commentId }
        self.own.remove(commentId)
        return true
    }
}

