import Foundation

public enum TellomiDiscoverClientError: Equatable, Error {
    case signedOut
    case disabled
    case audienceInvalid
    case userInvalid
    case userBlocked
    case invalidCity
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
    case reported
    case acknowledged
    case voted(TellomiDiscoverVoteTally)
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
    case let .nearby(city, _):
        return tellomiDiscoverKnownCityCode(city) == nil ? .invalidCity : nil
    case let .cards(identifiers):
        return tellomiDiscoverCardsBody(identifiers) == nil ? .notFound : nil
    case let .publish(text, visibility, audienceToken, clientNonce, textLimit, city, quoteOf, pollOptions):
        if let city, !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, tellomiDiscoverKnownCityCode(city) == nil {
            return .invalidCity
        }
        if tellomiDiscoverPublishBody(text: text, visibility: visibility, audienceToken: audienceToken, clientNonce: clientNonce, textLimit: textLimit, city: city, quoteOf: quoteOf, pollOptions: pollOptions) == nil {
            return .notPublishable
        }
        return nil
    case let .repost(identifier), let .unrepost(identifier):
        return tellomiDiscoverPostId(identifier) == nil ? .notFound : nil
    case let .vote(identifier, option):
        if tellomiDiscoverPostId(identifier) == nil || tellomiDiscoverVoteBody(option: option) == nil {
            return .notPublishable
        }
        return nil
    case let .report(target, option, detail):
        return tellomiDiscoverReportBody(target: target, option: option, detail: detail) == nil ? .unavailable : nil
    }
}

public func tellomiDiscoverDecodeHTTP(operation: TellomiDiscoverOperation, result: TellomiDiscoverHTTPResult) -> Result<TellomiDiscoverDecoded, TellomiDiscoverClientError> {
    if result.status == 404, tellomiDiscoverErrorCode(result.body) == "feed_hidden" {
        return .failure(.hidden)
    }
    if result.status == 400, tellomiDiscoverErrorCode(result.body) == "invalid_city" {
        return .failure(.invalidCity)
    }
    switch result.status {
    case 200, 201:
        break
    case 204:
        switch operation {
        case .repost, .unrepost:
            return .success(.acknowledged)
        default:
            return .failure(.unavailable)
        }
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
    case .feed, .nearby:
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
    case .report:
        return .success(.reported)
    case .repost, .unrepost:
        return .success(.acknowledged)
    case .vote:
        guard let tally = tellomiDiscoverParseVote(result.body) else {
            return .failure(.unreadable)
        }
        return .success(.voted(tally))
    }
}

public struct TellomiDiscoverCopy: Equatable {
    public var languageCode: String
    public var pack: [String: String]
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
    public var invalidCity: String
    public var aiGenerated: String
    public var quoteDeleted: String
    public var publish: String
    public var tellomiId: String
    public var likes: String
    public var comments: String
    public var photos: String
    public var reposts: String
    public var repost: String
    public var unrepost: String
    public var quote: String
    public var shareChat: String
    public var shareExternal: String
    public var poll: String
    public var pollAdd: String
    public var pollOption: String
    public var pollHint: String
    public var votes: String
    public var notifications: String
    public var notificationsInfo: String

    public static func resolve(languageCode: String, pack: [String: String] = [:]) -> TellomiDiscoverCopy {
        func text(_ key: String, _ english: String, _ simplified: String, _ traditional: String) -> String {
            return tellomiLocalizedPackString(languageCode: languageCode, pack: pack, key: key, english: english, simplified: simplified, traditional: traditional)
        }
        return TellomiDiscoverCopy(
            languageCode: languageCode,
            pack: pack,
            recommend: text("Tellomi.Discover.Recommend", "For You", "推荐", "推薦"),
            following: text("Tellomi.Discover.Following", "Following", "关注", "追蹤"),
            nearby: text("Tellomi.Discover.Nearby", "Nearby", "同城", "同城"),
            compose: text("Tellomi.Discover.Compose", "Post", "发布", "發布"),
            emptyTitle: text("Tellomi.Discover.EmptyTitle", "No posts yet", "还没有帖子", "還沒有貼文"),
            emptyText: text("Tellomi.Discover.EmptyText", "Posts from people you follow, and recommendations, show up here.", "关注的人和推荐会显示在这里。", "追蹤的人和推薦會顯示在這裡。"),
            unavailable: text("Tellomi.Discover.Unavailable", "This post isn't available", "这条动态已不可见", "這則動態已不可見"),
            failed: text("Tellomi.Discover.Failed", "Couldn't load this. Pull to try again.", "暂时打不开，下拉再试一次。", "暫時打不開，下拉再試一次。"),
            cityPrompt: text("Tellomi.Discover.CityPrompt", "Choose a city", "选择城市", "選擇城市"),
            cityPlaceholder: text("Tellomi.Discover.CityPlaceholder", "City", "输入城市", "輸入城市"),
            useLocation: text("Tellomi.Discover.UseLocation", "Use current location", "使用当前位置", "使用目前位置"),
            confirmCity: text("Tellomi.Discover.ConfirmCity", "Done", "确定", "確定"),
            cityDenied: text("Tellomi.Discover.CityDenied", "You can pick a city without location. Only the city is kept.", "可以不定位，直接从列表里选。只保存城市，不保存坐标。", "可以不定位，直接從列表裡選。只保存城市，不保存座標。"),
            visibility: text("Tellomi.Discover.Visibility", "Who can see this", "谁可以看", "誰可以看"),
            everyone: text("Tellomi.Discover.Everyone", "Everyone", "所有人", "所有人"),
            contacts: text("Tellomi.Discover.Contacts", "My Contacts", "我的联系人", "我的聯絡人"),
            closeFriends: text("Tellomi.Discover.CloseFriends", "Close Friends", "密友", "密友"),
            selected: text("Tellomi.Discover.Selected", "Selected People", "选定的用户", "指定的使用者"),
            exclude: text("Tellomi.Discover.Exclude", "Exclude", "不给谁看", "不給誰看"),
            audienceInvalid: text("Tellomi.Discover.AudienceInvalid", "That list can't be used. Choose again.", "名单无效，请重新选择。", "名單無效，請重新選擇。"),
            userInvalid: text("Tellomi.Discover.UserInvalid", "Someone on the list can't be added.", "名单里有人无法使用。", "名單裡有人無法使用。"),
            userBlocked: text("Tellomi.Discover.UserBlocked", "Someone on the list is blocked.", "名单里有人已互相拉黑。", "名單裡有人已互相封鎖。"),
            discoverDisabled: text("Tellomi.Discover.Disabled", "Discover isn't available right now.", "发现暂时不可用。", "發現暫時無法使用。"),
            nearbyEmpty: text("Tellomi.Discover.NearbyEmpty", "No posts in this city yet.", "这个城市还没有帖子。", "這個城市還沒有貼文。"),
            invalidCity: text("Tellomi.Discover.InvalidCity", "That city can't be used. Choose another.", "这个城市不能用，请重新选择。", "這個城市不能用，請重新選擇。"),
            aiGenerated: text("Tellomi.Discover.AiGenerated", "AI generated", "AI 生成", "AI 生成"),
            quoteDeleted: text("Tellomi.Discover.QuoteDeleted", "The original post was deleted by its author", "原动态已被作者删除", "原動態已被作者刪除"),
            publish: text("Tellomi.Discover.Publish", "Post", "发布", "發布"),
            tellomiId: text("Tellomi.Discover.TellomiId", "Tellomi ID: %@", "Tellomi 号：%@", "Tellomi 號：%@"),
            likes: text("Tellomi.Discover.Likes", "%d likes", "%d 赞", "%d 讚"),
            comments: text("Tellomi.Discover.Comments", "%d comments", "%d 评论", "%d 則留言"),
            photos: text("Tellomi.Discover.Photos", "%d photos", "%d 张图片", "%d 張圖片"),
            reposts: text("Tellomi.Discover.Reposts", "%d reposts", "%d 转发", "%d 轉發"),
            repost: text("Tellomi.Discover.Repost", "Repost", "直接转发", "直接轉發"),
            unrepost: text("Tellomi.Discover.Unrepost", "Undo repost", "取消转发", "取消轉發"),
            quote: text("Tellomi.Discover.Quote", "Quote", "引用转发", "引用轉發"),
            shareChat: text("Tellomi.Discover.ShareChat", "Share to a tellomi chat", "分享到 tellomi 聊天", "分享到 tellomi 聊天"),
            shareExternal: text("Tellomi.Discover.ShareExternal", "Share to another app", "分享到外部 App", "分享到外部 App"),
            poll: text("Tellomi.Discover.Poll", "Poll", "投票", "投票"),
            pollAdd: text("Tellomi.Discover.PollAdd", "Add an option", "添加选项", "新增選項"),
            pollOption: text("Tellomi.Discover.PollOption", "Option", "选项", "選項"),
            pollHint: text("Tellomi.Discover.PollHint", "Add at least two options.", "至少两个选项。", "至少兩個選項。"),
            votes: text("Tellomi.Discover.Votes", "%d votes", "%d 票", "%d 票"),
            notifications: text("Tellomi.Discover.Notifications", "Discover activity", "发现的互动", "發現的互動"),
            notificationsInfo: text("Tellomi.Discover.NotificationsInfo", "Likes, comments, and reposts. Off stops those pushes.", "点赞、评论和转发。关掉后不再收到这些推送。", "讚、留言和轉發。關掉後不再收到這些推播。")
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
        case .invalidCity:
            return self.invalidCity
        case .signedOut, .notPublishable, .hidden, .unavailable, .unauthorized, .notFound, .unreadable:
            return self.failed
        }
    }
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

public func tellomiDiscoverPostSummary(post: TellomiDiscoverPost, copy: TellomiDiscoverCopy, list: Bool, includePoll: Bool = true) -> TellomiDiscoverPostSummary {
    var title = post.authorName
    if let handle = post.authorHandle, !handle.isEmpty {
        if title.isEmpty {
            title = "@" + handle
        } else {
            title += " @" + handle
        }
    } else if let number = post.tellomiNumber, !number.isEmpty {
        let label = tellomiFormatString(copy.tellomiId, number)
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
        if includePoll, let poll = post.poll {
            for option in poll.options {
                body += "\n" + option.text
                if !poll.voted.isEmpty || option.votes > 0 {
                    body += " · " + tellomiFormatInteger(copy.votes, option.votes)
                }
            }
        }
    }
    var meta: [String] = []
    if let city = post.city, let name = tellomiDiscoverCityName(code: city, languageCode: copy.languageCode, pack: copy.pack) {
        meta.append(name)
    }
    if let region = post.ipRegionLabel, !region.isEmpty {
        meta.append(region)
    }
    if post.likeCount > 0 {
        meta.append(tellomiFormatInteger(copy.likes, post.likeCount))
    }
    if post.commentCount > 0 {
        meta.append(tellomiFormatInteger(copy.comments, post.commentCount))
    }
    if post.repostCount > 0 {
        meta.append(tellomiFormatInteger(copy.reposts, post.repostCount))
    }
    if post.imageCount > 0 {
        meta.append(tellomiFormatInteger(copy.photos, post.imageCount))
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
