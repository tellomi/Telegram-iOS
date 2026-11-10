import Foundation

/// A post the composer is ready to send. `clientNonce` is a UUID and stays the same for every retry of this draft.
public struct MomentsPostDraft: Equatable {
    public var text: String
    public var audience: MomentsAudience
    public var mediaKeys: [String]
    public var allowNearby: Bool
    public var city: String?
    public var placeId: String?
    public var quoteOf: String?
    public var clientNonce: String

    public init(text: String, audience: MomentsAudience, mediaKeys: [String] = [], allowNearby: Bool = false, city: String? = nil, placeId: String? = nil, quoteOf: String? = nil, clientNonce: String) {
        self.text = text
        self.audience = audience
        self.mediaKeys = mediaKeys
        self.allowNearby = allowNearby
        self.city = city
        self.placeId = placeId
        self.quoteOf = quoteOf
        self.clientNonce = clientNonce
    }
}

public enum MomentsPostEncodeError: Equatable, Error {
    /// Include or exclude was chosen but the id list is empty. This is not a public post.
    case audienceTokenRequired
    /// The selection cannot be represented by the engine (for example contacts plus an exclude list). Do not publish it as public.
    case audienceNotRepresentable
    case invalidClientNonce
}

public enum MomentsEncodedPost {
    case ready([String: Any])
    /// Selected or excluded people. Fetch `discover.getAudienceToken` and encode again. Never substitute `public`.
    case needsAudienceToken(kind: String, userIds: [Int64])
}

public struct MomentsAudienceGrant: Equatable {
    public var token: String
    public var expiresAt: Int64

    public init(token: String, expiresAt: Int64) {
        self.token = token
        self.expiresAt = expiresAt
    }

    /// Refetch before `expires`. The 60 second margin is the same clock slack the feed credential uses; it is not extra lifetime.
    public func needsRefresh(now: Int64, margin: Int64 = MomentsCredential.refreshMargin) -> Bool {
        return now + margin >= self.expiresAt
    }
}

public func momentsIsClientNonce(_ value: String) -> Bool {
    return UUID(uuidString: value) != nil
}

/// JSON object for `POST /v1/feed/posts`. Only keys the engine decodes with `DisallowUnknownFields` are present.
public func momentsEncodePost(_ draft: MomentsPostDraft, audienceToken: String?) -> Result<MomentsEncodedPost, MomentsPostEncodeError> {
    guard momentsIsClientNonce(draft.clientNonce) else {
        return .failure(.invalidClientNonce)
    }
    let wire: (visibility: String, tokenKind: String?, userIds: [Int64])
    switch momentsWireAudience(draft.audience) {
    case let .failure(error):
        return .failure(error)
    case let .success(resolved):
        wire = resolved
    }
    if let tokenKind = wire.tokenKind {
        let token = audienceToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if token.isEmpty {
            return .success(.needsAudienceToken(kind: tokenKind, userIds: wire.userIds))
        }
        return .success(.ready(momentsPostJSON(draft, visibility: wire.visibility, audienceToken: token)))
    }
    return .success(.ready(momentsPostJSON(draft, visibility: wire.visibility, audienceToken: nil)))
}

/// The audience the user picked. A token failure returns this value unchanged.
public func momentsAudienceKeptAfterTokenFailure(_ audience: MomentsAudience) -> MomentsAudience {
    return audience
}

public struct MomentsCommentComposerState: Equatable {
    public var text: String
    public var parentId: String?
    public var mediaKey: String?
    public var sticker: Bool
    public var clientNonce: String

    public init(text: String = "", parentId: String? = nil, mediaKey: String? = nil, sticker: Bool = false, clientNonce: String = "") {
        self.text = text
        self.parentId = parentId
        self.mediaKey = mediaKey
        self.sticker = sticker
        self.clientNonce = clientNonce
    }
}

public enum MomentsCommentEncodeError: Equatable, Error {
    case empty
    case invalidClientNonce
}

/// Same text, reply target and attachment keep `clientNonce`. Any edit mints a new one.
public func momentsCommentComposerForSend(previous: MomentsCommentComposerState, text: String, parentId: String?, mediaKey: String?, sticker: Bool, makeNonce: () -> String = { UUID().uuidString }) -> MomentsCommentComposerState {
    let samePayload = previous.text == text && previous.parentId == parentId && previous.mediaKey == mediaKey && previous.sticker == sticker
    let nonce = samePayload && momentsIsClientNonce(previous.clientNonce) ? previous.clientNonce : makeNonce()
    return MomentsCommentComposerState(text: text, parentId: parentId, mediaKey: mediaKey, sticker: sticker, clientNonce: nonce)
}

/// A failed send leaves the draft exactly as it was, including the nonce.
public func momentsCommentComposerAfterFailure(_ state: MomentsCommentComposerState) -> MomentsCommentComposerState {
    return state
}

/// A successful send clears the text, the reply target and the attachment. The next comment gets a new nonce.
public func momentsCommentComposerAfterSuccess() -> MomentsCommentComposerState {
    return MomentsCommentComposerState()
}

public func momentsEncodeComment(_ state: MomentsCommentComposerState) -> Result<[String: Any], MomentsCommentEncodeError> {
    let text = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let mediaKey = state.mediaKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if text.isEmpty && mediaKey.isEmpty {
        return .failure(.empty)
    }
    if !state.clientNonce.isEmpty && !momentsIsClientNonce(state.clientNonce) {
        return .failure(.invalidClientNonce)
    }
    var body: [String: Any] = [:]
    if !text.isEmpty {
        body["text"] = text
    }
    if let parentId = state.parentId?.trimmingCharacters(in: .whitespacesAndNewlines), !parentId.isEmpty {
        body["parent_id"] = parentId
    }
    if !mediaKey.isEmpty {
        body["media_keys"] = [mediaKey]
        if state.sticker {
            body["sticker"] = true
        }
    }
    if momentsIsClientNonce(state.clientNonce) {
        body["client_nonce"] = state.clientNonce
    }
    return .success(body)
}

/// Hot and latest each keep their own cursor. A hot cursor is never sent as a latest cursor.
public struct MomentsCommentCursors: Equatable {
    public var hot: String?
    public var latest: String?

    public init(hot: String? = nil, latest: String? = nil) {
        self.hot = hot
        self.latest = latest
    }

    public func cursor(sort: String) -> String? {
        let value = sort == "latest" ? self.latest : self.hot
        if let value, !value.isEmpty {
            return value
        }
        return nil
    }

    public func storing(sort: String, cursor: String?) -> MomentsCommentCursors {
        var copy = self
        let stored = cursor.flatMap { $0.isEmpty ? nil : $0 }
        if sort == "latest" {
            copy.latest = stored
        } else {
            copy.hot = stored
        }
        return copy
    }
}

/// Leading ids in a fresh first page that are not already on screen. The list itself is not changed.
public func momentsUnseenHeadCount(visibleIds: [String], probedIds: [String]) -> Int {
    let visible = Set(visibleIds)
    var counted = Set<String>()
    var count = 0
    for id in probedIds {
        if visible.contains(id) {
            break
        }
        if counted.insert(id).inserted {
            count += 1
        }
    }
    return count
}

/// Recommend never polls. The other tabs poll only while the feed screen is on screen.
public func momentsFeedShouldProbe(kind: MomentsFeedKind, screenVisible: Bool) -> Bool {
    return screenVisible && kind.probesForNewPosts
}

/// Pull-to-refresh always starts at the first page. A finished cursor does not request another page.
public func momentsShouldLoadFeedPage(loaded: Bool, cursor: String?, refresh: Bool, loading: Bool) -> Bool {
    if loading {
        return false
    }
    if refresh {
        return true
    }
    if !loaded {
        return true
    }
    if let cursor, !cursor.isEmpty {
        return true
    }
    return false
}

private func momentsWireAudience(_ audience: MomentsAudience) -> Result<(visibility: String, tokenKind: String?, userIds: [Int64]), MomentsPostEncodeError> {
    if audience.kind == .selected || !audience.include.isEmpty {
        if audience.include.isEmpty {
            return .failure(.audienceTokenRequired)
        }
        return .success(("include", "include", audience.include))
    }
    if !audience.exclude.isEmpty {
        if audience.kind != .everyone {
            return .failure(.audienceNotRepresentable)
        }
        return .success(("exclude", "exclude", audience.exclude))
    }
    switch audience.kind {
    case .everyone:
        return .success(("public", nil, []))
    case .contacts:
        return .success(("contacts", nil, []))
    case .closeFriends:
        return .success(("close_friends", nil, []))
    case .mutualFollowers:
        return .success(("friends", nil, []))
    case .selected:
        return .failure(.audienceTokenRequired)
    }
}

private func momentsPostJSON(_ draft: MomentsPostDraft, visibility: String, audienceToken: String?) -> [String: Any] {
    var body: [String: Any] = [
        "kind": "post",
        "visibility": visibility,
        "client_nonce": draft.clientNonce
    ]
    let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty {
        body["text"] = text
    }
    let keys = draft.mediaKeys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    if !keys.isEmpty {
        body["media_keys"] = keys
    }
    if let audienceToken {
        body["audience"] = ["audience_token": audienceToken]
    }
    if let quote = draft.quoteOf?.trimmingCharacters(in: .whitespacesAndNewlines), !quote.isEmpty {
        body["quote_of"] = quote
    }
    let nearby = draft.allowNearby && visibility == "public"
    if nearby {
        body["allow_nearby"] = true
        if let city = draft.city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            body["city"] = city
        }
        if let placeId = draft.placeId?.trimmingCharacters(in: .whitespacesAndNewlines), !placeId.isEmpty {
            body["place_id"] = placeId
        }
    }
    return body
}
