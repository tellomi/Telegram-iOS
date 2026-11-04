import CoreFoundation
import Foundation

public struct TellomiDiscoverPost: Equatable {
    public var id: String
    public var text: String
    public var authorName: String
    public var authorUsername: String?
    public var authorUserId: Int64?
    public var createdAt: TimeInterval?
    public var visibility: String?
    public var city: String?
    public var shareable: Bool
    public var aiGenerated: Bool
    public var badge: String?
    public var likeCount: Int
    public var commentCount: Int
    public var repostCount: Int
    public var imageCount: Int
    public var quoteDeleted: Bool
    public var quoteText: String?

    public init(id: String, text: String, authorName: String, authorUsername: String?, authorUserId: Int64?, createdAt: TimeInterval?, visibility: String?, city: String?, shareable: Bool, aiGenerated: Bool, badge: String?, likeCount: Int, commentCount: Int, repostCount: Int, imageCount: Int, quoteDeleted: Bool, quoteText: String?) {
        self.id = id
        self.text = text
        self.authorName = authorName
        self.authorUsername = authorUsername
        self.authorUserId = authorUserId
        self.createdAt = createdAt
        self.visibility = visibility
        self.city = city
        self.shareable = shareable
        self.aiGenerated = aiGenerated
        self.badge = badge
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.repostCount = repostCount
        self.imageCount = imageCount
        self.quoteDeleted = quoteDeleted
        self.quoteText = quoteText
    }
}

public struct TellomiDiscoverPage: Equatable {
    public var posts: [TellomiDiscoverPost]
    public var nextCursor: String?

    public init(posts: [TellomiDiscoverPost], nextCursor: String?) {
        self.posts = posts
        self.nextCursor = nextCursor
    }
}

/// Paths are the content-engine routes named in the M3 appendix
/// (`/v1/feed/recommend`, `/following`, `/nearby`, `/posts/{id}`).
/// The private engine document was not readable from this client change, so the JSON
/// is the snake_case shape those routes already imply (`text`, `visibility`, `city`,
/// `quote_of`, `shareable`, `ai_generated`, `user_id`), plus a few aliases.
public func tellomiDiscoverParsePage(_ data: Data) -> TellomiDiscoverPage? {
    guard let json = TellomiJSON.parse(data) else {
        return nil
    }
    if case .array = json {
        guard let posts = posts(in: json) else {
            return nil
        }
        return TellomiDiscoverPage(posts: posts, nextCursor: nil)
    }
    guard case let .object(object) = json else {
        return nil
    }
    let list = object["posts"] ?? object["items"]
    if let list {
        guard let posts = posts(in: list) else {
            return nil
        }
        return TellomiDiscoverPage(posts: posts, nextCursor: cursor(in: object))
    }
    if object["id"] != nil {
        guard let post = tellomiDiscoverParsePost(json) else {
            return nil
        }
        return TellomiDiscoverPage(posts: [post], nextCursor: nil)
    }
    if object.isEmpty {
        return TellomiDiscoverPage(posts: [], nextCursor: nil)
    }
    return nil
}

public func tellomiDiscoverParsePost(_ data: Data) -> TellomiDiscoverPost? {
    guard let json = TellomiJSON.parse(data) else {
        return nil
    }
    if case let .object(object) = json, let wrapped = object["post"] {
        return tellomiDiscoverParsePost(wrapped)
    }
    return tellomiDiscoverParsePost(json)
}

private func tellomiDiscoverParsePost(_ json: TellomiJSON) -> TellomiDiscoverPost? {
    guard case let .object(object) = json else {
        return nil
    }
    guard let identifier = stringValue(object["id"]).flatMap(tellomiDiscoverPostId) else {
        return nil
    }
    let text = stringValue(object["text"]) ?? stringValue(object["body"]) ?? stringValue(object["content"]) ?? ""
    let author = object["author"]
    let authorName = stringValue(object["author_name"])
        ?? objectValue(author).flatMap { stringValue($0["name"]) ?? stringValue($0["display_name"]) }
        ?? ""
    let username = stringValue(object["author_username"])
        ?? objectValue(author).flatMap { stringValue($0["username"]) }
    let userId = int64Value(object["user_id"]) ?? objectValue(author).flatMap { int64Value($0["user_id"]) }
    let quote = object["quote_of"] ?? object["quote"]
    var quoteDeleted = boolValue(object["quote_deleted"]) ?? false
    var quoteText: String?
    if let quote {
        if boolValue(quote) == true || boolValue(objectValue(quote)?["deleted"]) == true {
            quoteDeleted = true
        } else if let nested = tellomiDiscoverParsePost(quote) {
            quoteText = nested.text
            if nested.text.isEmpty, nested.quoteDeleted {
                quoteDeleted = true
            }
        } else if case .null = quote {
            quoteText = nil
        }
    }
    return TellomiDiscoverPost(
        id: identifier,
        text: text,
        authorName: authorName,
        authorUsername: username,
        authorUserId: userId,
        createdAt: timeValue(object["created_at"] ?? object["createdAt"]),
        visibility: stringValue(object["visibility"]),
        city: cityValue(object),
        shareable: boolValue(object["shareable"]) ?? false,
        aiGenerated: boolValue(object["ai_generated"]) ?? boolValue(object["aiGenerated"]) ?? false,
        badge: stringValue(object["badge"]),
        likeCount: intValue(object["like_count"]) ?? intValue(objectValue(object["counts"])?["likes"]) ?? 0,
        commentCount: intValue(object["comment_count"]) ?? intValue(objectValue(object["counts"])?["comments"]) ?? 0,
        repostCount: intValue(object["repost_count"]) ?? intValue(objectValue(object["counts"])?["reposts"]) ?? 0,
        imageCount: imageCount(object["media"]),
        quoteDeleted: quoteDeleted,
        quoteText: quoteText
    )
}

private func posts(in json: TellomiJSON) -> [TellomiDiscoverPost]? {
    guard case let .array(values) = json else {
        return nil
    }
    var posts: [TellomiDiscoverPost] = []
    for value in values {
        guard let post = tellomiDiscoverParsePost(value) else {
            return nil
        }
        posts.append(post)
    }
    return posts
}

private func cursor(in object: [String: TellomiJSON]) -> String? {
    let value = stringValue(object["next_cursor"]) ?? stringValue(object["next"]) ?? stringValue(object["cursor"])
    guard let value, !value.isEmpty else {
        return nil
    }
    return value
}

private func cityValue(_ object: [String: TellomiJSON]) -> String? {
    if let city = stringValue(object["city"]) {
        return tellomiDiscoverNormalizedCity(city)
    }
    guard let location = objectValue(object["location"]) else {
        return nil
    }
    let city = stringValue(location["city"]) ?? stringValue(location["locality"])
    guard let city else {
        return nil
    }
    return tellomiDiscoverNormalizedCity(city)
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
        let kind = (stringValue(object["kind"]) ?? stringValue(object["type"]) ?? "image").lowercased()
        if kind == "image" || kind == "photo" || kind == "picture" {
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

private func timeValue(_ json: TellomiJSON?) -> TimeInterval? {
    guard let json else {
        return nil
    }
    switch json {
    case let .number(value):
        if value > 10_000_000_000 {
            return value / 1000
        }
        return value
    case let .string(value):
        if let date = ISO8601DateFormatter().date(from: value) {
            return date.timeIntervalSince1970
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.date(from: value)?.timeIntervalSince1970
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
