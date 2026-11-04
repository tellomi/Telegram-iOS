import Foundation

public enum TellomiDiscoverClientError: Equatable, Error {
    case signedOut
    case disabled
    case needsCity
    case notPublishable
    case unavailable
    case unauthorized
    case notFound
    case unreadable
}

public enum TellomiDiscoverDecoded: Equatable {
    case page(TellomiDiscoverPage)
    case post(TellomiDiscoverPost)
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
        guard ticket == self.generation, let token = self.credential?.token else {
            return
        }
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
                if response.status == 401 || response.status == 403 {
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
    case let .feed(kind, _, city):
        if kind == .nearby, tellomiDiscoverNormalizedCity(city ?? "") == nil {
            return .needsCity
        }
        return nil
    case let .post(identifier):
        return tellomiDiscoverPostId(identifier) == nil ? .notFound : nil
    case let .publish(text, visibility):
        if visibility == .selected {
            return .notPublishable
        }
        if tellomiDiscoverPublishBody(text: text, visibility: visibility) == nil {
            return .notPublishable
        }
        return nil
    }
}

public func tellomiDiscoverDecodeHTTP(operation: TellomiDiscoverOperation, result: TellomiDiscoverHTTPResult) -> Result<TellomiDiscoverDecoded, TellomiDiscoverClientError> {
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
    case .feed:
        guard let page = tellomiDiscoverParsePage(result.body) else {
            return .failure(.unreadable)
        }
        return .success(.page(page))
    case .post, .publish:
        guard let post = tellomiDiscoverParsePost(result.body) else {
            return .failure(.unreadable)
        }
        return .success(.post(post))
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
    public var needsAudienceToken: String
    public var excludedPeers: String
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
                unavailable: "这条帖子暂时无法打开。",
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
                needsAudienceToken: "选定的用户还不能发布。",
                excludedPeers: "排除部分人还不能发布。",
                aiGenerated: "AI 生成",
                quoteDeleted: "原帖子已被作者删除",
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
            unavailable: "This post can't be opened yet.",
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
            needsAudienceToken: "Selected people can't be published yet.",
            excludedPeers: "Excluding people can't be published yet.",
            aiGenerated: "AI generated",
            quoteDeleted: "The original post was deleted",
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
        case .selected:
            return self.selected
        }
    }

    public func reasonText(_ reason: String?) -> String? {
        switch reason {
        case "needs_audience_token":
            return self.needsAudienceToken
        case "excluded_peers":
            return self.excludedPeers
        default:
            return nil
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
    if let username = post.authorUsername, !username.isEmpty {
        if title.isEmpty {
            title = "@" + username
        } else {
            title += " @" + username
        }
    }
    var body = post.text
    if list, body.count > 280 {
        body = String(body.prefix(280))
    }
    if post.quoteDeleted {
        if !body.isEmpty {
            body += "\n"
        }
        body += copy.quoteDeleted
    } else if let quoteText = post.quoteText, !quoteText.isEmpty {
        body += "\n" + quoteText
    }
    let chinese = copy.recommend == "推荐"
    var meta: [String] = []
    if let city = post.city, !city.isEmpty {
        meta.append(city)
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
