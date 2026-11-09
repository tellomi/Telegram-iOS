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
    return Int(momentsInt64(json, keys[0], keys.count > 1 ? keys[1] : keys[0]))
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

func momentsAuthor(_ json: [String: Any]?) -> MomentsAuthor? {
    guard let json, let id = momentsString(json, "id", "profile_id") else {
        return nil
    }
    return MomentsAuthor(
        id: id,
        telegramUserId: momentsInt64(json, "telegram_user_id", "user_id"),
        displayName: momentsString(json, "display_name", "name") ?? "",
        username: momentsString(json, "username", "handle"),
        avatarKey: momentsString(json, "avatar_key", "avatar"),
        followed: momentsBool(json, "followed", "following"),
        followsViewer: momentsBool(json, "follows_viewer", "follows_me")
    )
}

func momentsMedia(_ json: [String: Any]) -> MomentsMedia? {
    guard let key = momentsString(json, "key", "id"), let rawType = momentsString(json, "type"), let type = MomentsMediaType(rawValue: rawType) else {
        return nil
    }
    return MomentsMedia(
        type: type,
        key: key,
        width: momentsInt(json, "w", "width"),
        height: momentsInt(json, "h", "height"),
        durationMs: momentsInt(json, "duration_ms", "duration"),
        coverKey: momentsString(json, "cover_key", "cover"),
        isOriginal: momentsBool(json, "is_original", "original"),
        order: momentsInt(json, "order"),
        remoteURL: momentsString(json, "url")
    )
}

func momentsCard(json: [String: Any]) -> MomentsCard? {
    guard let id = momentsString(json, "id") else {
        return nil
    }
    let state = momentsString(json, "state") ?? "published"
    if state == "unavailable" || state == "deleted" {
        return MomentsCard(id: id, state: "unavailable")
    }
    let media = momentsArray(json["media"]).compactMap(momentsMedia)
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
    let topics = (json["topics"] as? [String]) ?? []
    return MomentsCard(
        id: id,
        version: momentsInt64(json, "version"),
        state: state,
        author: momentsAuthor(momentsObject(json["author"])),
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

func momentsPage(data: Data) -> MomentsPage? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    let rows = momentsArray(root["items"] ?? root["cards"] ?? root["posts"])
    return MomentsPage(items: rows.compactMap(momentsCard), nextCursor: momentsString(root, "next_cursor", "cursor"))
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
