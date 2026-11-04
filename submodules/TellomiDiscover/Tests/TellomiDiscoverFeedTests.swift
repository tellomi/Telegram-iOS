import XCTest

final class TellomiDiscoverFeedTests: XCTestCase {
    private let nonce = "11111111-1111-4111-8111-111111111111"

    func testFeatureFlagDefaultsOff() {
        XCTAssertFalse(tellomiDiscoverEnabled(.missing))
        XCTAssertFalse(tellomiDiscoverEnabled(.bool(false)))
        XCTAssertTrue(tellomiDiscoverEnabled(.string("enabled")))
    }

    func testConfigurationStaysOffWithoutAFlag() {
        let off = TellomiDiscoverConfiguration.resolve(enabledField: .missing, baseURLField: .string("https://feed.tellomi.cn"))
        XCTAssertFalse(off.enabled)
        XCTAssertNil(off.baseURL)
        let http = TellomiDiscoverConfiguration.resolve(enabledField: .bool(true), baseURLField: .string("http://feed.tellomi.cn"))
        XCTAssertFalse(http.enabled)
        let on = TellomiDiscoverConfiguration.resolve(enabledField: .bool(true), baseURLField: .missing)
        XCTAssertEqual(on.baseURL?.absoluteString, "https://feed.tellomi.cn")
    }

    func testSignedOutNeverBuildsARequest() {
        let configuration = TellomiDiscoverConfiguration.resolve(enabledField: .bool(true), baseURLField: .missing)
        let operations: [TellomiDiscoverOperation] = [
            .capabilities,
            .status,
            .feed(.recommend, cursor: nil, personalized: true),
            .cards(["post-9"]),
            .publish(text: "hi", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500)
        ]
        for operation in operations {
            let loader = RecordingLoader()
            let finished = expectation(description: "signed out")
            loader.loader.run(loggedIn: false, configuration: configuration, operation: operation) { result in
                guard case .failure(.signedOut) = result else {
                    XCTFail("expected signedOut")
                    return
                }
                finished.fulfill()
            }
            wait(for: [finished], timeout: 1)
            XCTAssertEqual(loader.credentialFetches, 0)
            XCTAssertTrue(loader.calls.isEmpty)
        }
        let chrome = tellomiDiscoverChrome(loggedIn: false, enabled: true, openedPostId: "post-9", failed: false)
        XCTAssertFalse(chrome.issuesNetwork)
        XCTAssertEqual(chrome.surface, .legacyEmpty(postUnavailable: true))
    }

    func testDisabledFlagNeverBuildsARequest() {
        let configuration = TellomiDiscoverConfiguration.resolve(enabledField: .missing, baseURLField: .missing)
        let chrome = tellomiDiscoverChrome(loggedIn: true, enabled: false, openedPostId: nil, failed: false)
        XCTAssertEqual(chrome.surface, .legacyEmpty(postUnavailable: false))
        XCTAssertFalse(chrome.issuesNetwork)
        let loader = RecordingLoader()
        let finished = expectation(description: "disabled")
        loader.loader.run(loggedIn: true, configuration: configuration, operation: .feed(.recommend, cursor: nil, personalized: true)) { result in
            guard case .failure(.disabled) = result else {
                XCTFail("expected disabled")
                return
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(loader.credentialFetches, 0)
        XCTAssertTrue(loader.calls.isEmpty)
    }

    func testCapabilitiesDoNotSendACredential() {
        let configuration = TellomiDiscoverConfiguration(enabled: true, baseURL: URL(string: "https://feed.example")!)
        let loader = RecordingLoader()
        let finished = expectation(description: "capabilities")
        loader.loader.run(loggedIn: true, configuration: configuration, operation: .capabilities) { result in
            guard case let .success(.capabilities(value)) = result else {
                XCTFail("expected capabilities")
                return
            }
            XCTAssertEqual(value.version, 1)
            XCTAssertTrue(value.features.contains("feed"))
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(loader.credentialFetches, 0)
        XCTAssertEqual(loader.calls.count, 1)
        XCTAssertFalse(loader.calls[0].authorizes)
        XCTAssertEqual(loader.calls[0].token, "")
        XCTAssertEqual(loader.calls[0].url.path, "/v1/capabilities")
    }

    func testFeedThenCardsUseTheDocumentedPaths() {
        let configuration = TellomiDiscoverConfiguration.resolve(enabledField: .string("true"), baseURLField: .string("https://feed.example/"))
        let loader = RecordingLoader()
        loader.credential = TellomiDiscoverCredential(token: "jwt-1", expires: 10_000, region: "cn")
        let finished = expectation(description: "feed")
        loader.loader.run(loggedIn: true, configuration: configuration, operation: .feed(.recommend, cursor: nil, personalized: true)) { result in
            guard case let .success(.feed(page)) = result else {
                XCTFail("expected a feed page")
                return
            }
            XCTAssertEqual(page.items.map(\.id), ["post-9"])
            XCTAssertEqual(page.items.first?.reason, "editorial")
            XCTAssertNil(page.cursor)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(loader.credentialFetches, 1)
        XCTAssertEqual(loader.calls[0].method, "GET")
        XCTAssertEqual(loader.calls[0].url.path, "/v1/feed/recommend")
        XCTAssertNil(loader.calls[0].url.query)
        XCTAssertFalse(loader.calls[0].url.absoluteString.contains("limit="))
        XCTAssertFalse(loader.calls[0].url.absoluteString.contains("jwt-1"))

        let cards = expectation(description: "cards")
        loader.loader.run(loggedIn: true, configuration: configuration, operation: .cards(["post-9"])) { result in
            guard case let .success(.cards(value)) = result else {
                XCTFail("expected cards")
                return
            }
            XCTAssertEqual(value.first?.text, "好看")
            XCTAssertEqual(value.first?.authorName, "林")
            XCTAssertEqual(value.first?.authorHandle, "lin")
            XCTAssertEqual(value.first?.likeCount, 3)
            XCTAssertTrue(value.first?.shareable == true)
            cards.fulfill()
        }
        wait(for: [cards], timeout: 1)
        XCTAssertEqual(loader.calls.last?.method, "POST")
        XCTAssertEqual(loader.calls.last?.url.path, "/v1/feed/cards")
        let body = try! JSONSerialization.jsonObject(with: loader.calls.last!.body!) as! [String: [String]]
        XCTAssertEqual(body["ids"], ["post-9"])
    }

    func testFollowingCursorAndUnpersonalizedRecommend() {
        let base = URL(string: "https://feed.example")!
        let following = tellomiDiscoverFeedURL(base: base, kind: .following, cursor: "c1", personalized: true)
        XCTAssertEqual(following?.path, "/v1/feed/following")
        XCTAssertEqual(URLComponents(url: following!, resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "cursor", value: "c1")])
        let recommend = tellomiDiscoverFeedURL(base: base, kind: .recommend, cursor: "ignored", personalized: false)
        XCTAssertEqual(recommend?.path, "/v1/feed/recommend")
        XCTAssertEqual(URLComponents(url: recommend!, resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "personalized", value: "false")])
        XCTAssertNil(tellomiDiscoverFeedURL(base: base, kind: .recommend, cursor: nil, personalized: true)?.query)
    }

    func testPublishBodyMatchesTheEngine() {
        let body = tellomiDiscoverPublishBody(text: " 你好 ", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500)
        let object = try! JSONSerialization.jsonObject(with: body!) as! [String: Any]
        XCTAssertEqual(object["kind"] as? String, "post")
        XCTAssertEqual(object["text"] as? String, "你好")
        XCTAssertEqual(object["visibility"] as? String, "public")
        XCTAssertEqual(object["client_nonce"] as? String, self.nonce)
        XCTAssertNil(object["audience"])
        XCTAssertEqual(Set(object.keys), Set(["kind", "text", "visibility", "client_nonce"]))
        XCTAssertNil(tellomiDiscoverPublishBody(text: "hi", visibility: .include, audienceToken: nil, clientNonce: self.nonce, textLimit: 500))
        XCTAssertNil(tellomiDiscoverPublishBody(text: "hi", visibility: .exclude, audienceToken: " ", clientNonce: self.nonce, textLimit: 500))
        let selected = tellomiDiscoverPublishBody(text: "hi", visibility: .include, audienceToken: "signed-jwt", clientNonce: self.nonce, textLimit: 500)
        let selectedObject = try! JSONSerialization.jsonObject(with: selected!) as! [String: Any]
        XCTAssertEqual(selectedObject["visibility"] as? String, "include")
        XCTAssertEqual((selectedObject["audience"] as? [String: String])?["audience_token"], "signed-jwt")
        let contacts = tellomiDiscoverPublishBody(text: "hi", visibility: .contacts, audienceToken: nil, clientNonce: self.nonce, textLimit: 500)
        XCTAssertEqual((try! JSONSerialization.jsonObject(with: contacts!) as! [String: Any])["visibility"] as? String, "contacts")
    }

    func testAudienceListStaysLocalUntilATokenExists() {
        XCTAssertEqual(TellomiDiscoverAudienceList.tokenType, "tellomi-feed-audience")
        XCTAssertEqual(TellomiDiscoverAudienceList.memberLimit, 500)
        XCTAssertEqual(TellomiDiscoverAudienceList.maximumLifetime, 15 * 60)
        XCTAssertEqual(tellomiDiscoverAudienceList(kind: "include", members: ["abc"])?.members, ["abc"])
        XCTAssertNil(tellomiDiscoverAudienceList(kind: "include", members: []))
        XCTAssertNil(tellomiDiscoverAudienceList(kind: "include", members: Array(repeating: "abc", count: 501)))
        XCTAssertNil(tellomiDiscoverAudienceList(kind: "public", members: ["abc"]))
        XCTAssertTrue(tellomiDiscoverAudienceExpiryIsValid(expires: 1_000, now: 200))
        XCTAssertFalse(tellomiDiscoverAudienceExpiryIsValid(expires: 1_000, now: 0))
        XCTAssertEqual(tellomiDiscoverAudience(base: .everyone, includePeerIds: [])?.visibility.rawValue, "public")
        XCTAssertEqual(tellomiDiscoverAudience(base: .nobody, includePeerIds: [7])?.visibility, .include)
        XCTAssertEqual(tellomiDiscoverAudience(base: .nobody, includePeerIds: [7])?.publishable, false)
        XCTAssertEqual(tellomiDiscoverAudience(base: .everyone, includePeerIds: [3])?.visibility, .exclude)
        XCTAssertEqual(tellomiDiscoverAudience(base: .everyone, includePeerIds: [3])?.publishable, false)
        XCTAssertEqual(tellomiDiscoverAudience(base: .closeFriends, includePeerIds: [7])?.visibility.rawValue, "close_friends")
        XCTAssertNil(tellomiDiscoverAudience(base: .nobody, includePeerIds: []))
    }

    func testCredentialRoundTripAndRefresh() {
        XCTAssertEqual(Array(TellomiDiscoverTL.encodeRequest()), [0x76, 0x7F, 0x0A, 0xA8])
        var body = Data()
        body.append(contentsOf: [0xAA, 0xCC, 0x78, 0x05])
        body.append(contentsOf: encodeString("jwt.token"))
        body.append(contentsOf: [0x39, 0x30, 0x00, 0x00])
        body.append(contentsOf: encodeString("cn"))
        XCTAssertEqual(TellomiDiscoverTL.decodeCredential(body), TellomiDiscoverCredential(token: "jwt.token", expires: 12345, region: "cn"))
        XCTAssertTrue(tellomiDiscoverCredentialNeedsRefresh(expires: 1_000, now: 880))
        XCTAssertFalse(tellomiDiscoverCredentialNeedsRefresh(expires: 1_000, now: 879))
    }

    func testHiddenFeedIsNotAnEmptyList() {
        let hidden = #"{"error":"feed_hidden"}"#.data(using: .utf8)!
        let result = tellomiDiscoverDecodeHTTP(operation: .feed(.recommend, cursor: nil, personalized: true), result: TellomiDiscoverHTTPResult(status: 404, body: hidden))
        guard case .failure(.hidden) = result else {
            XCTFail("expected hidden")
            return
        }
        let status = tellomiDiscoverParseStatus(#"{"visible":false}"#.data(using: .utf8)!)
        XCTAssertEqual(status, false)
    }

    func testCardParsesAuthorQuoteAndDropsStreet() {
        let cards = tellomiDiscoverParseCards(cardsJSON)
        let card = cards?.first
        XCTAssertEqual(card?.text, "好看")
        XCTAssertEqual(card?.authorHandle, "lin")
        XCTAssertEqual(card?.likeCount, 3)
        XCTAssertEqual(card?.imageCount, 1)
        XCTAssertEqual(card?.aiGenerated, true)
        XCTAssertEqual(card?.ipRegionLabel, "四川")
        XCTAssertEqual(card?.quoteState, "deleted")
        let post = tellomiDiscoverDisplayPost(card!)
        let summary = tellomiDiscoverPostSummary(post: post, copy: .resolve(languageCode: "zh-Hans"), list: true)
        XCTAssertEqual(summary.title, "林 @lin")
        XCTAssertTrue(summary.body.contains("原动态已被作者删除"))
        XCTAssertTrue(summary.meta.contains("AI 生成"))
        XCTAssertTrue(summary.meta.contains("四川"))
        XCTAssertFalse(summary.body.contains("人民路"))
        let unavailable = tellomiDiscoverParseCards(#"{"cards":[{"id":"post-1","state":"unavailable"}]}"#.data(using: .utf8)!)
        XCTAssertEqual(tellomiDiscoverDisplayPost(unavailable!.first!).unavailable, true)
        XCTAssertEqual(tellomiDiscoverPostSummary(post: tellomiDiscoverDisplayPost(unavailable!.first!), copy: .resolve(languageCode: "zh"), list: false).body, "这条动态已不可见")
    }

    func testEngineConfigTabsAndTextLimit() {
        let data = #"{"enabled":true,"region":"cn","tabs":["recommend","following","nearby"],"recommend_mode":"editorial_chronological","personalization_toggle_visible":false,"limits":{"post_text_chars":500}}"#.data(using: .utf8)!
        let config = tellomiDiscoverParseEngineConfig(data)
        XCTAssertEqual(config?.tabs, [.recommend, .following])
        XCTAssertEqual(config?.postTextChars, 500)
        XCTAssertEqual(config?.recommendMode, "editorial_chronological")
    }

    func testCreatedPostAndUIChrome() {
        let created = tellomiDiscoverParseCreatedPost(#"{"id":"post-9","state":"pending","version":1}"#.data(using: .utf8)!)
        XCTAssertEqual(created, TellomiDiscoverCreatedPost(id: "post-9", state: "pending", version: 1))
        let on = tellomiDiscoverChrome(loggedIn: true, enabled: true, openedPostId: "post-9", failed: false)
        XCTAssertEqual(on.surface, .detail("post-9"))
        XCTAssertTrue(on.loadsPost)
        XCTAssertFalse(on.loadsFeed)
        let tabs = tellomiDiscoverChrome(loggedIn: true, enabled: true, openedPostId: nil, failed: false)
        XCTAssertEqual(tabs.surface, .feed)
        XCTAssertTrue(tabs.showsCompose)
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "zh-Hans").recommend, "推荐")
    }

    func testExpiredCredentialIsRefreshedBeforeTheFeedRequest() {
        let configuration = TellomiDiscoverConfiguration(enabled: true, baseURL: URL(string: "https://feed.example")!)
        let loader = RecordingLoader(cached: TellomiDiscoverCredential(token: "old", expires: 5_000, region: "global"))
        loader.nowValue = 5_000
        loader.credential = TellomiDiscoverCredential(token: "new", expires: 9_000, region: "global")
        let finished = expectation(description: "refresh")
        loader.loader.run(loggedIn: true, configuration: configuration, operation: .feed(.following, cursor: nil, personalized: true)) { result in
            guard case .success(.feed) = result else {
                XCTFail("expected success")
                return
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(loader.credentialFetches, 1)
        XCTAssertEqual(loader.calls.map(\.token), ["new"])
        XCTAssertEqual(loader.calls[0].url.path, "/v1/feed/following")
    }

    func testUnauthorizedResponseFetchesOneNewCredential() {
        let configuration = TellomiDiscoverConfiguration(enabled: true, baseURL: URL(string: "https://feed.example")!)
        let loader = RecordingLoader(cached: TellomiDiscoverCredential(token: "old", expires: 9_000, region: "cn"))
        loader.credential = TellomiDiscoverCredential(token: "new", expires: 9_000, region: "cn")
        loader.statuses = [401, 200]
        let finished = expectation(description: "retry")
        loader.loader.run(loggedIn: true, configuration: configuration, operation: .status) { result in
            guard case .success(.status(true)) = result else {
                XCTFail("expected status after one retry")
                return
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(loader.credentialFetches, 1)
        XCTAssertEqual(loader.calls.map(\.token), ["old", "new"])
    }
}

final class TellomiDiscoverFeedUITests: XCTestCase {
    func testUIFeedStaysOnTheEmptyPageUntilTheFlagIsOn() {
        let signedOut = tellomiDiscoverChrome(loggedIn: false, enabled: true, openedPostId: "post-9", failed: false)
        XCTAssertEqual(signedOut.surface, .legacyEmpty(postUnavailable: true))
        XCTAssertFalse(signedOut.issuesNetwork)
        XCTAssertFalse(signedOut.showsCompose)
        let tabs = tellomiDiscoverChrome(loggedIn: true, enabled: true, openedPostId: nil, failed: false)
        XCTAssertEqual(tabs.surface, .feed)
        XCTAssertTrue(tabs.showsCompose)
        XCTAssertTrue(tabs.loadsFeed)
    }
}

private let cardsJSON = """
{"cards":[{"id":"post-9","state":"ok","version":1,"card":{"kind":"post","display_mode":"post","source_url":"","ai_generated":true,"edited":false,"text":"好看","author":{"id":"profile-1","display_name":"林","handle":"lin","native":true},"media":[{"type":"image","key":"m/a"}],"ip_region_label":"四川"},"stats":{"likes":3,"comments":1,"reposts":0},"me":{"liked":false},"shareable":true,"quoted":{"id":"post-1","state":"deleted"}}]}
""".data(using: .utf8)!

private final class RecordingLoader {
    var nowValue: Int64 = 1_000
    var credential = TellomiDiscoverCredential(token: "jwt", expires: 9_000, region: "cn")
    var statuses: [Int] = []
    var credentialFetches = 0
    var calls: [TellomiDiscoverHTTPCall] = []
    let loader: TellomiDiscoverLoader

    init(cached: TellomiDiscoverCredential? = nil) {
        let box = LoaderBox()
        self.loader = TellomiDiscoverLoader(now: { box.owner?.nowValue ?? 0 }, credential: cached, fetchCredential: { completion in
            box.owner?.credentialFetches += 1
            if let credential = box.owner?.credential {
                completion(.success(credential))
            } else {
                completion(.failure(.unavailable))
            }
        }, http: { call, completion in
            guard let owner = box.owner else {
                return
            }
            owner.calls.append(call)
            let status = owner.statuses.isEmpty ? 200 : owner.statuses.removeFirst()
            let body = status == 200 ? owner.body(for: call) : Data()
            completion(.success(TellomiDiscoverHTTPResult(status: status, body: body)))
        })
        box.owner = self
    }

    private func body(for call: TellomiDiscoverHTTPCall) -> Data {
        switch call.url.path {
        case "/v1/capabilities":
            return #"{"version":1,"features":["feed","posting"]}"#.data(using: .utf8)!
        case "/v1/feed/status":
            return #"{"visible":true}"#.data(using: .utf8)!
        case "/v1/feed/cards":
            return cardsJSON
        case "/v1/feed/posts":
            return #"{"id":"post-9","state":"pending","version":1}"#.data(using: .utf8)!
        default:
            return #"{"items":[{"id":"post-9","reason":"editorial"}]}"#.data(using: .utf8)!
        }
    }
}

private final class LoaderBox {
    weak var owner: RecordingLoader?
}

private func encodeString(_ value: String) -> [UInt8] {
    let bytes = Array(value.utf8)
    let length = bytes.count
    var out: [UInt8] = []
    out.append(UInt8(length))
    out.append(contentsOf: bytes)
    let padded = length + 1
    let padding = (4 - (padded % 4)) % 4
    out.append(contentsOf: Array(repeating: 0, count: padding))
    return out
}
