import Foundation

public enum TellomiDiscoverClientError: Equatable, Error {
    case signedOut
    case disabled
    case audienceInvalid
    case userInvalid
    case userBlocked
    case notPublishable
    case hidden
    case unavailable
    case unauthorized
    case notFound
    case unreadable
}

public enum TellomiDiscoverDecoded: Equatable {
    case capabilities(TellomiDiscoverCapabilities)
    case status(Bool)
    case engineConfig(TellomiDiscoverEngineConfig)
    case feed(TellomiDiscoverFeedPage)
    case cards([TellomiDiscoverCard])
    case created(TellomiDiscoverCreatedPost)
}

public struct TellomiDiscoverHTTPResult: Equatable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public final class TellomiDiscoverLoader {
    private let now: () -> Int64
    private let fetchCredential: (@escaping (Result<TellomiDiscoverCredential, TellomiDiscoverClientError>) -> Void) -> Void
    private let http: (TellomiDiscoverHTTPCall, @escaping (Result<TellomiDiscoverHTTPResult, TellomiDiscoverClientError>) -> Void) -> Void
    private var credential: TellomiDiscoverCredential?
    private var generation = 0

    public init(
        now: @escaping () -> Int64,
        credential: TellomiDiscoverCredential? = nil,
        fetchCredential: @escaping (@escaping (Result<TellomiDiscoverCredential, TellomiDiscoverClientError>) -> Void) -> Void,
        http: @escaping (TellomiDiscoverHTTPCall, @escaping (Result<TellomiDiscoverHTTPResult, TellomiDiscoverClientError>) -> Void) -> Void
    ) {
        self.now = now
        self.credential = credential
        self.fetchCredential = fetchCredential
        self.http = http
    }

    public func cancel() {
        self.generation += 1
    }

    public func run(loggedIn: Bool, configuration: TellomiDiscoverConfiguration, operation: TellomiDiscoverOperation, completion: @escaping (Result<TellomiDiscoverDecoded, TellomiDiscoverClientError>) -> Void) {
        let ticket = self.generation
        guard loggedIn else {
            completion(.failure(.signedOut))
            return
        }
        guard configuration.enabled, configuration.baseURL != nil else {
            completion(.failure(.disabled))
            return
        }
        self.issue(ticket: ticket, configuration: configuration, operation: operation, retryUnauthorized: true, completion: completion)
    }

    private func issue(ticket: Int, configuration: TellomiDiscoverConfiguration, operation: TellomiDiscoverOperation, retryUnauthorized: Bool, completion: @escaping (Result<TellomiDiscoverDecoded, TellomiDiscoverClientError>) -> Void) {
        guard ticket == self.generation else {
            return
        }
        guard let baseURL = configuration.baseURL else {
            completion(.failure(.disabled))
            return
        }
        if let failure = tellomiDiscoverLocalFailure(operation) {
            completion(.failure(failure))
            return
        }
        if !tellomiDiscoverNeedsCredential(operation) {
            self.send(ticket: ticket, baseURL: baseURL, operation: operation, retryUnauthorized: false, completion: completion)
            return
        }
        let current = self.credential
        if current == nil || tellomiDiscoverCredentialNeedsRefresh(expires: current?.expires ?? 0, now: self.now()) {
            self.fetchCredential { [weak self] result in
                guard let self, ticket == self.generation else {
                    return
                }
                switch result {
                case let .success(credential):
                    guard !credential.token.isEmpty, credential.region == "cn" || credential.region == "global" else {
                        completion(.failure(.unreadable))
                        return
                    }
                    self.credential = credential
                    self.send(ticket: ticket, baseURL: baseURL, operation: operation, retryUnauthorized: retryUnauthorized, completion: completion)
                case let .failure(error):
                    completion(.failure(error))
                }
            }
            return
        }
        self.send(ticket: ticket, baseURL: baseURL, operation: operation, retryUnauthorized: retryUnauthorized, completion: completion)
    }

    private func send(ticket: Int, baseURL: URL, operation: TellomiDiscoverOperation, retryUnauthorized: Bool, completion: @escaping (Result<TellomiDiscoverDecoded, TellomiDiscoverClientError>) -> Void) {
        guard ticket == self.generation else {
            return
        }
        let token = self.credential?.token ?? ""
        guard let call = tellomiDiscoverHTTPCall(base: baseURL, operation: operation, token: token) else {
            completion(.failure(tellomiDiscoverLocalFailure(operation) ?? .unreadable))
            return
        }
        self.http(call) { [weak self] result in
            guard let self, ticket == self.generation else {
                return
            }
            switch result {
            case let .success(response):
                if tellomiDiscoverNeedsCredential(operation), response.status == 401 || response.status == 403 {
                    self.credential = nil
                    guard retryUnauthorized else {
                        completion(.failure(.unauthorized))
                        return
                    }
                    self.issue(ticket: ticket, configuration: TellomiDiscoverConfiguration(enabled: true, baseURL: baseURL), operation: operation, retryUnauthorized: false, completion: completion)
                    return
                }
                completion(tellomiDiscoverDecodeHTTP(operation: operation, result: response))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }
}

private func tellomiDiscoverLocalFailure(_ operation: TellomiDiscoverOperation) -> TellomiDiscoverClientError? {
    switch operation {
    case .capabilities, .status, .engineConfig:
        return nil
    case let .feed(kind, _, _):
        if kind == .nearby {
            return .unavailable
        }
        return nil
    case let .cards(identifiers):
        return tellomiDiscoverCardsBody(identifiers) == nil ? .notFound : nil
    case let .publish(text, visibility, audienceToken, clientNonce, textLimit):
        if tellomiDiscoverPublishBody(text: text, visibility: visibility, audienceToken: audienceToken, clientNonce: clientNonce, textLimit: textLimit) == nil {
            return .notPublishable
        }
        return nil
    }
}

public func tellomiDiscoverDecodeHTTP(operation: TellomiDiscoverOperation, result: TellomiDiscoverHTTPResult) -> Result<TellomiDiscoverDecoded, TellomiDiscoverClientError> {
    if result.status == 404, tellomiDiscoverErrorCode(result.body) == "feed_hidden" {
        return .failure(.hidden)
    }
    switch result.status {
    case 200, 201:
        break
    case 401, 403:
        return .failure(.unauthorized)
    case 404:
        return .failure(.notFound)
    default:
        return .failure(.unavailable)
    }
    switch operation {
    case .capabilities:
        guard let value = tellomiDiscoverParseCapabilities(result.body) else {
            return .failure(.unreadable)
        }
        return .success(.capabilities(value))
    case .status:
        guard let visible = tellomiDiscoverParseStatus(result.body) else {
            return .failure(.unreadable)
        }
        return .success(.status(visible))
    case .engineConfig:
        guard let value = tellomiDiscoverParseEngineConfig(result.body) else {
            return .failure(.unreadable)
        }
        return .success(.engineConfig(value))
    case .feed:
        guard let page = tellomiDiscoverParseFeedPage(result.body) else {
            return .failure(.unreadable)
        }
        return .success(.feed(page))
    case .cards:
        guard let cards = tellomiDiscoverParseCards(result.body) else {
            return .failure(.unreadable)
        }
        return .success(.cards(cards))
    case .publish:
        guard let created = tellomiDiscoverParseCreatedPost(result.body) else {
            return .failure(.unreadable)
        }
        return .success(.created(created))
    }
}

public struct TellomiDiscoverCopy: Equatable {
    public var recommend: String
    public var following: String
    public var nearby: String
    public var compose: String
    public var emptyTitle: String
    public var emptyText: String
    public var unavailable: String
    public var failed: String
    public var cityPrompt: String
    public var cityPlaceholder: String
    public var useLocation: String
    public var confirmCity: String
    public var cityDenied: String
    public var visibility: String
    public var everyone: String
    public var contacts: String
    public var closeFriends: String
    public var selected: String
    public var exclude: String
    public var audienceInvalid: String
    public var userInvalid: String
    public var userBlocked: String
    public var discoverDisabled: String
    public var nearbyEmpty: String
    public var aiGenerated: String
    public var quoteDeleted: String
    public var publish: String

    public static func resolve(languageCode: String) -> TellomiDiscoverCopy {
        if tellomiDiscoverLanguageIsChinese(languageCode) {
            return TellomiDiscoverCopy(
                recommend: "推荐",
                following: "关注",
                nearby: "同城",
                compose: "发布",
                emptyTitle: "还没有帖子",
                emptyText: "关注的人和推荐会显示在这里。",
                unavailable: "这条动态已不可见",
                failed: "暂时打不开，下拉再试一次。",
                cityPrompt: "同城只按城市显示",
                cityPlaceholder: "输入城市",
                useLocation: "使用当前位置",
                confirmCity: "确定",
                cityDenied: "没有定位时可以自己填城市。位置不会精确到街道。",
                visibility: "谁可以看",
                everyone: "所有人",
                contacts: "我的联系人",
                closeFriends: "密友",
                selected: "选定的用户",
                exclude: "不给谁看",
                audienceInvalid: "名单无效，请重新选择。",
                userInvalid: "名单里有人无法使用。",
                userBlocked: "名单里有人已互相拉黑。",
                discoverDisabled: "发现暂时不可用。",
                nearbyEmpty: "同城动态稍后会显示在这里。",
                aiGenerated: "AI 生成",
                quoteDeleted: "原动态已被作者删除",
                publish: "发布"
            )
        }
        return TellomiDiscoverCopy(
            recommend: "For You",
            following: "Following",
            nearby: "Nearby",
            compose: "Post",
            emptyTitle: "No posts yet",
            emptyText: "Posts from people you follow, and recommendations, show up here.",
            unavailable: "This post isn't available",
            failed: "Couldn't load this. Pull to try again.",
            cityPrompt: "Nearby uses a city, nothing finer",
            cityPlaceholder: "City",
            useLocation: "Use current location",
            confirmCity: "Done",
            cityDenied: "You can type a city. The street is not kept.",
            visibility: "Who can see this",
            everyone: "Everyone",
            contacts: "My Contacts",
            closeFriends: "Close Friends",
            selected: "Selected People",
            exclude: "Exclude",
            audienceInvalid: "That list can't be used. Choose again.",
            userInvalid: "Someone on the list can't be added.",
            userBlocked: "Someone on the list is blocked.",
            discoverDisabled: "Discover isn't available right now.",
            nearbyEmpty: "Nearby posts will show up here.",
            aiGenerated: "AI generated",
            quoteDeleted: "The original post was deleted by its author",
            publish: "Post"
        )
    }

    public func visibilityTitle(_ visibility: TellomiDiscoverVisibility) -> String {
        switch visibility {
        case .everyone:
            return self.everyone
        case .contacts:
            return self.contacts
        case .closeFriends:
            return self.closeFriends
        case .include:
            return self.selected
        case .exclude:
            return self.exclude
        }
    }

    public func reasonText(_ reason: String?) -> String? {
        switch reason {
        case "audience_invalid":
            return self.audienceInvalid
        default:
            return nil
        }
    }

    public func failureText(_ error: TellomiDiscoverClientError) -> String? {
        switch error {
        case .audienceInvalid:
            return self.audienceInvalid
        case .userInvalid:
            return self.userInvalid
        case .userBlocked:
            return self.userBlocked
        case .disabled:
            return self.discoverDisabled
        case .signedOut, .notPublishable, .hidden, .unavailable, .unauthorized, .notFound, .unreadable:
            return self.failed
        }
    }
}

private func tellomiDiscoverLanguageIsChinese(_ code: String) -> Bool {
    let value = code.lowercased()
    return value == "zh" || value.hasPrefix("zh-")
}

public struct TellomiDiscoverPostSummary: Equatable {
    public var title: String
    public var body: String
    public var meta: String

    public init(title: String, body: String, meta: String) {
        self.title = title
        self.body = body
        self.meta = meta
    }
}

public func tellomiDiscoverPostSummary(post: TellomiDiscoverPost, copy: TellomiDiscoverCopy, list: Bool) -> TellomiDiscoverPostSummary {
    var title = post.authorName
    if let handle = post.authorHandle, !handle.isEmpty {
        if title.isEmpty {
            title = "@" + handle
        } else {
            title += " @" + handle
        }
    } else if let number = post.tellomiNumber, !number.isEmpty {
        let label = copy.recommend == "推荐" ? "Tellomi 号：\(number)" : "Tellomi ID: \(number)"
        if title.isEmpty {
            title = label
        } else {
            title += " · " + label
        }
    }
    var body: String
    if post.unavailable {
        body = copy.unavailable
    } else {
        body = post.text
        if list, body.count > 280 {
            body = String(body.prefix(280))
        }
        if post.quoteState == "deleted" {
            if !body.isEmpty {
                body += "\n"
            }
            body += copy.quoteDeleted
        } else if post.quoteState == "unavailable" {
            if !body.isEmpty {
                body += "\n"
            }
            body += copy.unavailable
        } else if let quoteText = post.quoteText, !quoteText.isEmpty {
            body += "\n" + quoteText
        }
    }
    let chinese = copy.recommend == "推荐"
    var meta: [String] = []
    if let region = post.ipRegionLabel, !region.isEmpty {
        meta.append(region)
    }
    if post.likeCount > 0 {
        meta.append(chinese ? "\(post.likeCount) 赞" : "\(post.likeCount) likes")
    }
    if post.commentCount > 0 {
        meta.append(chinese ? "\(post.commentCount) 评论" : "\(post.commentCount) comments")
    }
    if post.imageCount > 0 {
        meta.append(chinese ? "\(post.imageCount) 张图片" : "\(post.imageCount) photos")
    }
    if let badge = tellomiDiscoverVisibleBadge(post.badge, aiGenerated: post.aiGenerated, copy: copy) {
        meta.append(badge)
    }
    return TellomiDiscoverPostSummary(title: title, body: body, meta: meta.joined(separator: " · "))
}

public func tellomiDiscoverVisibleBadge(_ badge: String?, aiGenerated: Bool, copy: TellomiDiscoverCopy) -> String? {
    if let badge {
        let trimmed = badge.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = trimmed.lowercased()
        let hidden = trimmed.contains("审核") || folded.contains("review") || folded.contains("pending") || folded.contains("moderation")
        if !trimmed.isEmpty, !hidden {
            if aiGenerated {
                return trimmed + " · " + copy.aiGenerated
            }
            return trimmed
        }
    }
    if aiGenerated {
        return copy.aiGenerated
    }
    return nil
}
