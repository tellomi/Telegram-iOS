import Foundation

func momentsObject(_ value: Any?) -> [String: Any]? {
    return value as? [String: Any]
}

func momentsArray(_ value: Any?) -> [[String: Any]] {
    return value as? [[String: Any]] ?? []
}

func momentsString(_ json: [String: Any], _ keys: String...) -> String? {
    for key in keys {
        if let value = json[key] as? String, !value.isEmpty {
            return value
        }
    }
    return nil
}

func momentsInt64(_ json: [String: Any], _ keys: String...) -> Int64 {
    for key in keys {
        if let value = json[key] as? Int64 {
            return value
        }
        if let value = json[key] as? Int {
            return Int64(value)
        }
        if let value = json[key] as? NSNumber {
            return value.int64Value
        }
        if let value = json[key] as? String, let parsed = Int64(value) {
            return parsed
        }
    }
    return 0
}

func momentsInt(_ json: [String: Any], _ keys: String...) -> Int {
    guard let first = keys.first else {
        return 0
    }
    let second = keys.count > 1 ? keys[1] : first
    let value = momentsInt64(json, first, second)
    if value > Int64(Int.max) || value < Int64(Int.min) {
        return 0
    }
    return Int(value)
}

/// `{id}` plus at most `reason` and `type:post`. That is a list ref, not a card.
func momentsBarePostRef(_ json: [String: Any]) -> Bool {
    guard momentsString(json, "id") != nil else {
        return false
    }
    if let type = momentsString(json, "type"), !type.isEmpty, type != "post" {
        return false
    }
    let allowed: Set<String> = ["id", "reason", "type"]
    return json.keys.allSatisfy { allowed.contains($0) }
}

/// The cards API wraps a post as `{id, card:{...}}` or `{id, post:{...}}`. The inner object is the card.
func momentsUnwrapCardJSON(_ json: [String: Any]) -> [String: Any] {
    if let card = momentsObject(json["card"]) {
        var body = card
        if momentsString(body, "id") == nil, let id = momentsString(json, "id") {
            body["id"] = id
        }
        return body
    }
    if let post = momentsObject(json["post"]), momentsObject(json["author"]) == nil, momentsString(json, "text") == nil {
        var body = post
        if momentsString(body, "id") == nil, let id = momentsString(json, "id") {
            body["id"] = id
        }
        return body
    }
    return json
}

func momentsBool(_ json: [String: Any], _ keys: String...) -> Bool {
    for key in keys {
        if let value = json[key] as? Bool {
            return value
        }
        if let value = json[key] as? NSNumber {
            return value.boolValue
        }
    }
    return false
}

func momentsAuthor(_ json: [String: Any]?, mediaBaseURL: String? = nil) -> MomentsAuthor? {
    guard let json, let id = momentsString(json, "id", "profile_id") else {
        return nil
    }
    let avatarURL = momentsString(json, "avatar_url")
    let avatarKey = momentsString(json, "avatar_key", "avatar")
    let avatar = avatarURL ?? momentsMediaURL(base: mediaBaseURL, key: avatarKey) ?? avatarKey
    let native = momentsObject(json["native"])
    return MomentsAuthor(
        id: id,
        telegramUserId: momentsInt64(json, "telegram_user_id", "user_id") != 0 ? momentsInt64(json, "telegram_user_id", "user_id") : momentsInt64(native ?? [:], "user_id", "telegram_user_id"),
        displayName: momentsString(json, "display_name", "name") ?? "",
        username: momentsString(json, "username", "handle"),
        avatarKey: avatar,
        followed: momentsBool(json, "followed", "following"),
        followsViewer: momentsBool(json, "follows_viewer", "follows_me")
    )
}

func momentsMedia(_ json: [String: Any], mediaBaseURL: String? = nil) -> MomentsMedia? {
    guard let key = momentsString(json, "key", "id"), let rawType = momentsString(json, "type") else {
        return nil
    }
    let normalizedType = rawType == "voice" ? "audio" : rawType
    guard let type = MomentsMediaType(rawValue: normalizedType) else {
        return nil
    }
    let cover = momentsString(json, "cover_key", "cover")
    return MomentsMedia(
        type: type,
        key: key,
        width: momentsInt(json, "w", "width"),
        height: momentsInt(json, "h", "height"),
        durationMs: momentsInt(json, "duration_ms", "duration"),
        coverKey: momentsMediaURL(base: mediaBaseURL, key: cover) ?? cover,
        isOriginal: momentsBool(json, "is_original", "original"),
        order: momentsInt(json, "order"),
        remoteURL: momentsMediaURL(base: mediaBaseURL, key: momentsString(json, "url") ?? key)
    )
}

func momentsCard(json: [String: Any], mediaBaseURL: String? = nil) -> MomentsCard? {
    let json = momentsUnwrapCardJSON(json)
    guard let id = momentsString(json, "id") else {
        return nil
    }
    if momentsBarePostRef(json) {
        return MomentsCard(id: id, state: "unavailable")
    }
    let state = momentsString(json, "state") ?? "published"
    if state == "unavailable" || state == "deleted" {
        return MomentsCard(id: id, state: "unavailable")
    }
    let media = momentsArray(json["media"]).compactMap { momentsMedia($0, mediaBaseURL: mediaBaseURL) }
    var quote: MomentsQuote?
    if let quoteJSON = momentsObject(json["quote_of"] ?? json["quote"]) {
        if momentsString(quoteJSON, "state") == "unavailable" || momentsBool(quoteJSON, "unavailable") {
            quote = MomentsQuote(id: momentsString(quoteJSON, "id") ?? "", unavailable: true)
        } else if let quotedId = momentsString(quoteJSON, "id") {
            let quotedAuthor = momentsAuthor(momentsObject(quoteJSON["author"]))
            quote = MomentsQuote(
                id: quotedId,
                unavailable: false,
                authorName: quotedAuthor?.displayName,
                text: momentsString(quoteJSON, "text"),
                hasMedia: !momentsArray(quoteJSON["media"]).isEmpty
            )
        }
    }
    var poll: MomentsPoll?
    if let pollJSON = momentsObject(json["poll"]) {
        let options = momentsArray(pollJSON["options"]).map { option in
            MomentsPollOption(
                id: momentsString(option, "id") ?? UUID().uuidString,
                text: momentsString(option, "text") ?? "",
                count: momentsInt(option, "count", "votes"),
                chosen: momentsBool(option, "chosen", "selected")
            )
        }
        poll = MomentsPoll(
            question: momentsString(pollJSON, "question") ?? "",
            options: options,
            multiple: momentsBool(pollJSON, "multiple"),
            anonymous: pollJSON["anonymous"] == nil ? true : momentsBool(pollJSON, "anonymous"),
            closesAt: pollJSON["closes_at"] == nil ? nil : momentsInt64(pollJSON, "closes_at"),
            closedAt: pollJSON["closed_at"] == nil ? nil : momentsInt64(pollJSON, "closed_at"),
            closedByAuthor: momentsBool(pollJSON, "closed_by_author"),
            totalVoters: momentsInt(pollJSON, "total_voters", "total"),
            voted: momentsBool(pollJSON, "voted")
        )
    }
    var link: MomentsLinkPreview?
    if let linkJSON = momentsObject(json["link_preview"]) , let url = momentsString(linkJSON, "url") {
        link = MomentsLinkPreview(url: url, title: momentsString(linkJSON, "title"), description: momentsString(linkJSON, "description"), image: momentsString(linkJSON, "image"))
    }
    var location: MomentsLocation?
    if let locationJSON = momentsObject(json["location"]) {
        var place: MomentsPlace?
        if let placeJSON = momentsObject(locationJSON["place"]), let placeId = momentsString(placeJSON, "id") {
            place = MomentsPlace(id: placeId, name: momentsString(placeJSON, "name") ?? "")
        }
        location = MomentsLocation(
            city: momentsString(locationJSON, "city"),
            cityName: momentsString(locationJSON, "city_name", "city_label"),
            place: place,
            allowNearby: momentsBool(locationJSON, "allow_nearby"),
            distanceBand: momentsString(locationJSON, "distance_band", "distance")
        )
    }
    let audienceKind = MomentsAudienceKind(rawValue: momentsString(momentsObject(json["audience"]) ?? [:], "kind") ?? "")
    let audience = audienceKind.map { MomentsAudience(kind: $0) }
    let policy = MomentsCommentPolicy(rawValue: momentsString(json, "comment_policy") ?? "") ?? .everyoneWhoCanView
    let countsJSON = momentsObject(json["counts"]) ?? json
    let viewerJSON = momentsObject(json["viewer"]) ?? [:]
    let topics = momentsStringList(json["topics"])
    var author = momentsAuthor(momentsObject(json["author"]))
    if var value = author, !value.followed, momentsBool(viewerJSON, "following", "followed") {
        value.followed = true
        author = value
    }
    return MomentsCard(
        id: id,
        version: momentsInt64(json, "version"),
        state: state,
        author: author,
        text: momentsString(json, "text") ?? "",
        createdAt: momentsInt64(json, "created_at"),
        editedAt: json["edited_at"] == nil ? nil : momentsInt64(json, "edited_at"),
        audience: audience,
        commentPolicy: policy,
        media: media,
        linkPreview: link,
        quote: quote,
        poll: poll,
        location: location,
        topics: topics,
        counts: MomentsCounts(
            likes: momentsInt(countsJSON, "likes", "like_count"),
            comments: momentsInt(countsJSON, "comments", "comment_count"),
            reposts: momentsInt(countsJSON, "reposts", "repost_count")
        ),
        viewer: MomentsViewerState(
            liked: momentsBool(viewerJSON, "liked"),
            saved: momentsBool(viewerJSON, "saved"),
            reposted: momentsBool(viewerJSON, "reposted"),
            canComment: viewerJSON["can_comment"] == nil ? true : momentsBool(viewerJSON, "can_comment"),
            commentDeniedReason: momentsString(viewerJSON, "comment_denied_reason")
        ),
        repostedBy: momentsAuthor(momentsObject(json["reposted_by"])),
        pinned: momentsBool(json, "pinned")
    )
}

public struct MomentsFeedRefPage: Equatable {
    public var ids: [String]
    public var cursor: String?

    public init(ids: [String], cursor: String?) {
        self.ids = ids
        self.cursor = cursor
    }
}

/// Feed lists are `{items:[{id,reason}],cursor}`. Full cards come from `POST /v1/feed/cards`.
public func momentsFeedRefPage(data: Data) -> MomentsFeedRefPage? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    let ids = momentsArray(root["items"]).compactMap { item -> String? in
        return momentsString(item, "id")
    }
    return MomentsFeedRefPage(ids: ids, cursor: momentsString(root, "cursor", "next_cursor"))
}

func momentsStringList(_ value: Any?) -> [String] {
    if let list = value as? [String] {
        return list
    }
    if let list = value as? [Any] {
        return list.compactMap { $0 as? String }
    }
    return []
}

func momentsCardRows(_ root: [String: Any]) -> [[String: Any]] {
    let items = momentsArray(root["items"])
    let cards = momentsArray(root["cards"])
    let posts = momentsArray(root["posts"])
    if !items.isEmpty, items.allSatisfy(momentsBarePostRef), !cards.isEmpty {
        return cards
    }
    if !items.isEmpty {
        return items
    }
    if !cards.isEmpty {
        return cards
    }
    return posts
}

/// Cards aligned to the recommend order. A missing id is an unavailable row, not a blank post.
public func momentsHydratedCards(ids: [String], cardsData: Data, mediaBaseURL: String? = nil) -> [MomentsCard] {
    var byId: [String: MomentsCard] = [:]
    if let root = try? JSONSerialization.jsonObject(with: cardsData) as? [String: Any] {
        for row in momentsCardRows(root) {
            let body = momentsUnwrapCardJSON(row)
            guard let card = momentsCard(json: body, mediaBaseURL: mediaBaseURL) else {
                continue
            }
            byId[card.id] = card
        }
    }
    if ids.isEmpty {
        return Array(byId.values)
    }
    return ids.map { id in
        byId[id] ?? MomentsCard(id: id, state: "unavailable")
    }
}

/// Append a page. An empty `items` with no cursor is the last page: keep what is on screen and stop.
public func momentsMergeFeed(existing: [MomentsCard], pageItems: [MomentsCard], cursor: String?, refreshing: Bool) -> (items: [MomentsCard], cursor: String?) {
    let nextCursor = cursor.flatMap { $0.isEmpty ? nil : $0 }
    if refreshing {
        var seen = Set<String>()
        let items = pageItems.filter { seen.insert($0.id).inserted }
        return (items, pageItems.isEmpty ? nil : nextCursor)
    }
    if pageItems.isEmpty {
        return (existing, nil)
    }
    var seen = Set(existing.map { $0.id })
    var items = existing
    for card in pageItems where seen.insert(card.id).inserted {
        items.append(card)
    }
    return (items, nextCursor)
}

/// List rows the feed has already applied. Same ids update in place. A different list replaces every row.
public func momentsListEdit(previousIds: [String], nextIds: [String]) -> (deletes: [Int], inserts: [Int], updates: [Int]) {
    if previousIds == nextIds {
        return ([], [], Array(nextIds.indices))
    }
    return (Array(previousIds.indices), Array(nextIds.indices), [])
}

func momentsPage(data: Data, mediaBaseURL: String? = nil) -> MomentsPage? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    let rows = momentsCardRows(root)
    return MomentsPage(items: rows.compactMap { momentsCard(json: $0, mediaBaseURL: mediaBaseURL) }, nextCursor: momentsString(root, "next_cursor", "cursor"))
}

public func momentsTusUploadMetadata(filename: String, mimeType: String) -> String {
    let name = Data(filename.utf8).base64EncodedString()
    let type = Data(mimeType.utf8).base64EncodedString()
    return "filename \(name),filetype \(type)"
}

public func momentsMediaUploadKey(body: Data, headerFields: [AnyHashable: Any], location: String?) -> String? {
    if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let key = momentsString(json, "key", "id"), !key.isEmpty {
        return key
    }
    for (field, value) in headerFields {
        let name = (field as? String) ?? (field as? NSString).map { $0 as String }
        if name?.lowercased() == "upload-key", let text = value as? String, !text.isEmpty {
            return text
        }
    }
    if let location, let url = URL(string: location) {
        let last = url.lastPathComponent
        if !last.isEmpty && last != "uploads" {
            return last
        }
    }
    return nil
}

func momentsResolvedUploadLocation(base: String, location: String) -> String? {
    if location.hasPrefix("https://") {
        return location
    }
    if location.hasPrefix("http://") {
        return nil
    }
    if location.hasPrefix("/") {
        return base + location
    }
    return base + "/" + location
}

func momentsConfigMediaBase(_ data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let raw = momentsString(json, "media_base_url") else {
        return nil
    }
    guard let components = URLComponents(string: raw), components.scheme == "https", components.user == nil, components.password == nil, components.query == nil, components.fragment == nil, let host = components.host, !host.isEmpty else {
        return nil
    }
    var path = components.path
    if path == "/" {
        path = ""
    }
    while path.hasSuffix("/") {
        path.removeLast()
    }
    let renderedHost = host.contains(":") ? "[\(host)]" : host
    let origin = components.port.map { "https://\(renderedHost):\($0)" } ?? "https://\(renderedHost)"
    return origin + path
}

func momentsError(data: Data, status: Int) -> MomentsAPIError {
    let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).flatMap { momentsString($0, "error") } ?? ""
    if status == 404 || code == "not_found" {
        return .notFound
    }
    if status == 403 || code == "list_private" {
        return .listPrivate
    }
    if status == 429 || code == "rate_limited" {
        return .rateLimited
    }
    if code.isEmpty {
        return .transport("http \(status)")
    }
    return .invalid(code)
}

func momentsJSONData(_ object: [String: Any]) -> Data? {
    return try? JSONSerialization.data(withJSONObject: object, options: [])
}
