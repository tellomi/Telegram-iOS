import CoreFoundation
import Foundation

public struct TellomiDiscoverPost: Equatable {
    public var id: String
    public var text: String
    public var authorName: String
    public var authorHandle: String?
    public var tellomiNumber: String?
    public var unavailable: Bool
    public var aiGenerated: Bool
    public var badge: String?
    public var likeCount: Int
    public var commentCount: Int
    public var repostCount: Int
    public var imageCount: Int
    public var quoteState: String?
    public var quoteText: String?
    public var ipRegionLabel: String?
    public var city: String?
    public var comments: [TellomiDiscoverComment]
    public var shareable: Bool
    public var reposted: Bool
    public var poll: TellomiDiscoverPoll?
    public var linkPreview: TellomiDiscoverLink.Preview?

    public init(id: String, text: String, authorName: String, authorHandle: String?, tellomiNumber: String?, unavailable: Bool, aiGenerated: Bool, badge: String?, likeCount: Int, commentCount: Int, repostCount: Int, imageCount: Int, quoteState: String?, quoteText: String?, ipRegionLabel: String?, city: String?, comments: [TellomiDiscoverComment] = [], shareable: Bool = false, reposted: Bool = false, poll: TellomiDiscoverPoll? = nil, linkPreview: TellomiDiscoverLink.Preview? = nil) {
        self.id = id
        self.text = text
        self.authorName = authorName
        self.authorHandle = authorHandle
        self.tellomiNumber = tellomiNumber
        self.unavailable = unavailable
        self.aiGenerated = aiGenerated
        self.badge = badge
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.repostCount = repostCount
        self.imageCount = imageCount
        self.quoteState = quoteState
        self.quoteText = quoteText
        self.ipRegionLabel = ipRegionLabel
        self.city = city
        self.comments = comments
        self.shareable = shareable
        self.reposted = reposted
        self.poll = poll
        self.linkPreview = linkPreview
    }
}

public struct TellomiDiscoverComment: Equatable {
    public var id: String
    public var text: String
    public var authorName: String

    public init(id: String, text: String, authorName: String) {
        self.id = id
        self.text = text
        self.authorName = authorName
    }
}

public struct TellomiDiscoverCapabilities: Equatable {
    public var version: Int
    public var features: [String]

    public init(version: Int, features: [String]) {
        self.version = version
        self.features = features
    }
}

public struct TellomiDiscoverEngineConfig: Equatable {
    public var enabled: Bool
    public var region: String?
    public var tabs: [TellomiDiscoverFeedKind]
    public var recommendMode: String?
    public var personalizationToggleVisible: Bool
    public var postTextChars: Int

    public init(enabled: Bool, region: String?, tabs: [TellomiDiscoverFeedKind], recommendMode: String?, personalizationToggleVisible: Bool, postTextChars: Int) {
        self.enabled = enabled
        self.region = region
        self.tabs = tabs
        self.recommendMode = recommendMode
        self.personalizationToggleVisible = personalizationToggleVisible
        self.postTextChars = postTextChars
    }
}

public struct TellomiDiscoverFeedItem: Equatable {
    public var id: String
    public var reason: String
    public var repostedBy: String?

    public init(id: String, reason: String, repostedBy: String?) {
        self.id = id
        self.reason = reason
        self.repostedBy = repostedBy
    }
}

public struct TellomiDiscoverFeedPage: Equatable {
    public var items: [TellomiDiscoverFeedItem]
    public var cursor: String?

    public init(items: [TellomiDiscoverFeedItem], cursor: String?) {
        self.items = items
        self.cursor = cursor
    }
}

public struct TellomiDiscoverCard: Equatable {
    public var id: String
    public var state: String
    public var version: Int?
    public var text: String
    public var authorName: String
    public var authorHandle: String?
    public var tellomiNumber: String?
    public var authorId: String?
    public var badge: String?
    public var aiGenerated: Bool
    public var edited: Bool
    public var shareable: Bool
    public var likeCount: Int
    public var commentCount: Int
    public var repostCount: Int
    public var imageCount: Int
    public var quoteState: String?
    public var quoteText: String?
    public var ipRegionLabel: String?
    public var city: String?
    public var comments: [TellomiDiscoverComment]
    public var reposted: Bool
    public var poll: TellomiDiscoverPoll?
    public var linkPreview: TellomiDiscoverLink.Preview?

    public init(id: String, state: String, version: Int?, text: String, authorName: String, authorHandle: String?, tellomiNumber: String?, authorId: String?, badge: String?, aiGenerated: Bool, edited: Bool, shareable: Bool, likeCount: Int, commentCount: Int, repostCount: Int, imageCount: Int, quoteState: String?, quoteText: String?, ipRegionLabel: String?, city: String?, comments: [TellomiDiscoverComment] = [], reposted: Bool = false, poll: TellomiDiscoverPoll? = nil, linkPreview: TellomiDiscoverLink.Preview? = nil) {
        self.id = id
        self.state = state
        self.version = version
        self.text = text
        self.authorName = authorName
        self.authorHandle = authorHandle
        self.tellomiNumber = tellomiNumber
        self.authorId = authorId
        self.badge = badge
        self.aiGenerated = aiGenerated
        self.edited = edited
        self.shareable = shareable
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.repostCount = repostCount
        self.imageCount = imageCount
        self.quoteState = quoteState
        self.quoteText = quoteText
        self.ipRegionLabel = ipRegionLabel
        self.city = city
        self.comments = comments
        self.reposted = reposted
        self.poll = poll
        self.linkPreview = linkPreview
    }
}

public struct TellomiDiscoverCreatedPost: Equatable {
    public var id: String
    public var state: String
    public var version: Int

    public init(id: String, state: String, version: Int) {
        self.id = id
        self.state = state
        self.version = version
    }
}

public func tellomiDiscoverParseCapabilities(_ data: Data) -> TellomiDiscoverCapabilities? {
    guard let object = objectValue(TellomiJSON.parse(data)) else {
        return nil
    }
    guard let version = intValue(object["version"]), version == 1 else {
        return nil
    }
    guard case let .array(values)? = object["features"] else {
        return nil
    }
    let features = values.compactMap { stringValue($0) }
    guard features.count == values.count else {
        return nil
    }
    return TellomiDiscoverCapabilities(version: version, features: features)
}

public func tellomiDiscoverParseStatus(_ data: Data) -> Bool? {
    guard let object = objectValue(TellomiJSON.parse(data)) else {
        return nil
    }
    return boolValue(object["visible"])
}

public func tellomiDiscoverParseEngineConfig(_ data: Data) -> TellomiDiscoverEngineConfig? {
    guard let object = objectValue(TellomiJSON.parse(data)) else {
        return nil
    }
    guard let enabled = boolValue(object["enabled"]) else {
        return nil
    }
    var tabs: [TellomiDiscoverFeedKind] = []
    if case let .array(values)? = object["tabs"] {
        for value in values {
            if let name = stringValue(value), let kind = TellomiDiscoverFeedKind(configName: name), !tabs.contains(kind) {
                tabs.append(kind)
            }
        }
    }
    if tabs.isEmpty {
        tabs = [.recommend, .following]
    }
    let limits = objectValue(object["limits"])
    let textChars = intValue(limits?["post_text_chars"]) ?? tellomiDiscoverPostTextLimit
    return TellomiDiscoverEngineConfig(
        enabled: enabled,
        region: stringValue(object["region"]),
        tabs: tabs,
        recommendMode: stringValue(object["recommend_mode"]),
        personalizationToggleVisible: boolValue(object["personalization_toggle_visible"]) ?? false,
        postTextChars: textChars > 0 ? textChars : tellomiDiscoverPostTextLimit
    )
}

public func tellomiDiscoverParseFeedPage(_ data: Data) -> TellomiDiscoverFeedPage? {
    guard let object = objectValue(TellomiJSON.parse(data)) else {
        return nil
    }
    guard case let .array(values)? = object["items"] else {
        return nil
    }
    var items: [TellomiDiscoverFeedItem] = []
    for value in values {
        guard let item = objectValue(value), let identifier = stringValue(item["id"]).flatMap(tellomiDiscoverPostId) else {
            return nil
        }
        items.append(TellomiDiscoverFeedItem(id: identifier, reason: stringValue(item["reason"]) ?? "", repostedBy: stringValue(item["reposted_by"])))
    }
    let cursor = stringValue(object["cursor"]).flatMap { $0.isEmpty ? nil : $0 }
    return TellomiDiscoverFeedPage(items: items, cursor: cursor)
}

public func tellomiDiscoverParseCards(_ data: Data) -> [TellomiDiscoverCard]? {
    guard let object = objectValue(TellomiJSON.parse(data)), case let .array(values)? = object["cards"] else {
        return nil
    }
    var cards: [TellomiDiscoverCard] = []
    for value in values {
        guard let card = parseCard(value) else {
            return nil
        }
        cards.append(card)
    }
    return cards
}

public func tellomiDiscoverParseCreatedPost(_ data: Data) -> TellomiDiscoverCreatedPost? {
    guard let object = objectValue(TellomiJSON.parse(data)) else {
        return nil
    }
    guard let identifier = stringValue(object["id"]).flatMap(tellomiDiscoverPostId) else {
        return nil
    }
    guard let state = stringValue(object["state"]), !state.isEmpty else {
        return nil
    }
    guard let version = intValue(object["version"]) else {
        return nil
    }
    return TellomiDiscoverCreatedPost(id: identifier, state: state, version: version)
}

public func tellomiDiscoverErrorCode(_ data: Data) -> String? {
    guard let object = objectValue(TellomiJSON.parse(data)) else {
        return nil
    }
    return stringValue(object["error"])
}

public func tellomiDiscoverDisplayPost(_ card: TellomiDiscoverCard) -> TellomiDiscoverPost {
    return TellomiDiscoverPost(
        id: card.id,
        text: card.text,
        authorName: card.authorName,
        authorHandle: card.authorHandle,
        tellomiNumber: card.tellomiNumber,
        unavailable: card.state != "ok",
        aiGenerated: card.aiGenerated,
        badge: card.badge,
        likeCount: card.likeCount,
        commentCount: card.commentCount,
        repostCount: card.repostCount,
        imageCount: card.imageCount,
        quoteState: card.quoteState,
        quoteText: card.quoteText,
        ipRegionLabel: card.ipRegionLabel,
        city: card.city,
        comments: card.comments,
        shareable: card.shareable,
        reposted: card.reposted,
        poll: card.poll,
        linkPreview: card.linkPreview
    )
}

private func parseCard(_ json: TellomiJSON) -> TellomiDiscoverCard? {
    guard let entry = objectValue(json) else {
        return nil
    }
    guard let identifier = stringValue(entry["id"]).flatMap(tellomiDiscoverPostId) else {
        return nil
    }
    let state = stringValue(entry["state"]) ?? "ok"
    let body = objectValue(entry["card"])
    let author = objectValue(body?["author"])
    let stats = objectValue(entry["stats"])
    let quoted = objectValue(entry["quoted"])
    let quotedCard = objectValue(quoted?["card"])
    let me = objectValue(entry["me"])
    return TellomiDiscoverCard(
        id: identifier,
        state: state,
        version: intValue(entry["version"]),
        text: stringValue(body?["text"]) ?? "",
        authorName: stringValue(author?["display_name"]) ?? "",
        authorHandle: stringValue(author?["handle"]),
        tellomiNumber: stringValue(author?["tellomi_number"]),
        authorId: stringValue(author?["id"]),
        badge: stringValue(author?["badge"]) ?? stringValue(body?["badge"]),
        aiGenerated: boolValue(body?["ai_generated"]) ?? false,
        edited: boolValue(body?["edited"]) ?? false,
        shareable: boolValue(entry["shareable"]) ?? false,
        likeCount: intValue(stats?["likes"]) ?? 0,
        commentCount: intValue(stats?["comments"]) ?? 0,
        repostCount: intValue(stats?["reposts"]) ?? 0,
        imageCount: imageCount(body?["media"]),
        quoteState: stringValue(quoted?["state"]),
        quoteText: stringValue(quotedCard?["text"]),
        ipRegionLabel: stringValue(body?["ip_region_label"]),
        city: tellomiDiscoverCityCode(stringValue(body?["city"]) ?? stringValue(entry["city"])),
        comments: parseComments(entry["comments"]),
        reposted: boolValue(me?["reposted"]) ?? false,
        poll: parsePoll(labels: body?["poll"], tally: entry["poll"]),
        linkPreview: storedLinkPreview(card: body, entry: entry)
    )
}

/// `card.link_preview`, then the same object beside the card. A private URL is dropped.
private func storedLinkPreview(card: [String: TellomiJSON]?, entry: [String: TellomiJSON]) -> TellomiDiscoverLink.Preview? {
    if let preview = linkPreviewObject(card?["link_preview"]) {
        return preview
    }
    return linkPreviewObject(entry["link_preview"])
}

private func linkPreviewObject(_ json: TellomiJSON?) -> TellomiDiscoverLink.Preview? {
    guard let object = objectValue(json) else {
        return nil
    }
    return TellomiDiscoverLink.parseStored(url: strictString(object["url"]), title: strictString(object["title"]), description: strictString(object["description"]), image: strictString(object["image"]))
}

private func strictString(_ json: TellomiJSON?) -> String? {
    guard let json, case let .string(value) = json else {
        return nil
    }
    return value
}

/// Option labels are `card.poll.options` (`[String]`). Counts and this account's
/// choice are the sibling `poll.counts` / `poll.voted`. An empty `voted` is not voted.
private func parsePoll(labels: TellomiJSON?, tally: TellomiJSON?) -> TellomiDiscoverPoll? {
    guard let labelObject = objectValue(labels), case let .array(values)? = labelObject["options"] else {
        return nil
    }
    var texts: [String] = []
    for value in values {
        guard let text = stringValue(value)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        texts.append(text)
    }
    guard texts.count >= tellomiDiscoverPollOptionMinimum else {
        return nil
    }
    let tallyObject = objectValue(tally)
    let counts = intArray(tallyObject?["counts"]) ?? []
    let votedRaw = intArray(tallyObject?["voted"]) ?? []
    var options: [TellomiDiscoverPollOption] = []
    for (index, text) in texts.enumerated() {
        let votes = counts.indices.contains(index) ? max(0, counts[index]) : 0
        options.append(TellomiDiscoverPollOption(text: text, votes: votes))
    }
    let voted = votedRaw.filter { options.indices.contains($0) }
    return TellomiDiscoverPoll(options: options, voted: voted)
}

public func tellomiDiscoverParseVote(_ data: Data) -> TellomiDiscoverVoteTally? {
    guard let object = objectValue(TellomiJSON.parse(data)) else {
        return nil
    }
    guard let counts = intArray(object["counts"]), let voted = intArray(object["voted"]) else {
        return nil
    }
    guard counts.allSatisfy({ $0 >= 0 }), voted.allSatisfy({ $0 >= 0 }) else {
        return nil
    }
    return TellomiDiscoverVoteTally(counts: counts, voted: voted)
}

private func parseComments(_ json: TellomiJSON?) -> [TellomiDiscoverComment] {
    guard let json, case let .array(values) = json else {
        return []
    }
    var comments: [TellomiDiscoverComment] = []
    for value in values {
        guard let object = objectValue(value) else {
            continue
        }
        guard let identifier = stringValue(object["id"]).flatMap(tellomiDiscoverPostId) else {
            continue
        }
        let author = objectValue(object["author"])
        comments.append(TellomiDiscoverComment(
            id: identifier,
            text: stringValue(object["text"]) ?? "",
            authorName: stringValue(author?["display_name"]) ?? stringValue(object["author_name"]) ?? ""
        ))
    }
    return comments
}

private func imageCount(_ json: TellomiJSON?) -> Int {
    guard let json, case let .array(values) = json else {
        return 0
    }
    var count = 0
    for value in values {
        guard let object = objectValue(value) else {
            continue
        }
        let kind = (stringValue(object["type"]) ?? "").lowercased()
        if kind == "image" {
            count += 1
        }
    }
    return count
}

private func objectValue(_ json: TellomiJSON?) -> [String: TellomiJSON]? {
    guard let json, case let .object(object) = json else {
        return nil
    }
    return object
}

private func stringValue(_ json: TellomiJSON?) -> String? {
    guard let json else {
        return nil
    }
    switch json {
    case let .string(value):
        return value
    case let .number(value):
        if value.rounded() == value, value <= Double(Int64.max), value >= Double(Int64.min) {
            return String(Int64(value))
        }
        return nil
    default:
        return nil
    }
}

private func boolValue(_ json: TellomiJSON?) -> Bool? {
    guard let json else {
        return nil
    }
    switch json {
    case let .bool(value):
        return value
    case let .number(value):
        return value != 0
    case let .string(value):
        switch value.lowercased() {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return nil
        }
    default:
        return nil
    }
}

private func intArray(_ json: TellomiJSON?) -> [Int]? {
    guard let json, case let .array(values) = json else {
        return nil
    }
    var numbers: [Int] = []
    for value in values {
        guard let number = intValue(value) else {
            return nil
        }
        numbers.append(number)
    }
    return numbers
}

private func intValue(_ json: TellomiJSON?) -> Int? {
    guard let value = int64Value(json), let narrowed = Int(exactly: value) else {
        return nil
    }
    return narrowed
}

private func int64Value(_ json: TellomiJSON?) -> Int64? {
    guard let json else {
        return nil
    }
    switch json {
    case let .number(value):
        guard value.rounded() == value, value <= Double(Int64.max), value >= Double(Int64.min) else {
            return nil
        }
        return Int64(value)
    case let .string(value):
        return Int64(value)
    default:
        return nil
    }
}


private enum TellomiJSON {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([TellomiJSON])
    case object([String: TellomiJSON])

    static func parse(_ data: Data) -> TellomiJSON? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return TellomiJSON(object)
    }

    init?(_ object: Any) {
        if object is NSNull {
            self = .null
        } else if let value = object as? String {
            self = .string(value)
        } else if let value = object as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        } else if let value = object as? Bool {
            self = .bool(value)
        } else if let value = object as? [Any] {
            self = .array(value.compactMap { TellomiJSON($0) })
        } else if let value = object as? [String: Any] {
            var object: [String: TellomiJSON] = [:]
            for (key, item) in value {
                if let parsed = TellomiJSON(item) {
                    object[key] = parsed
                }
            }
            self = .object(object)
        } else {
            return nil
        }
    }
}
