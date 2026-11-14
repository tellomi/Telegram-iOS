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
            .publish(text: "hi", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, city: nil, quoteOf: nil, pollOptions: nil, linkPreview: nil, mediaKeys: nil),
            .nearby(city: "cn:chengdu", cursor: nil),
            .report(target: .post("post-9"), option: "spam", detail: "nope")
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
        let chrome = tellomiDiscoverChrome(loggedIn: false, enabled: true, kind: .recommend, openedPostId: "post-9", failed: false)
        XCTAssertFalse(chrome.issuesNetwork)
        XCTAssertEqual(chrome.surface, .legacyEmpty(postUnavailable: true))
    }

    func testDisabledFlagNeverBuildsARequest() {
        let configuration = TellomiDiscoverConfiguration.resolve(enabledField: .missing, baseURLField: .missing)
        let chrome = tellomiDiscoverChrome(loggedIn: true, enabled: false, kind: .recommend, openedPostId: nil, failed: false)
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

    func testRecommendPersonalizationTurnsOffAndRestores() {
        let base = URL(string: "https://feed.example")!
        let on = tellomiDiscoverHTTPCall(base: base, operation: .feed(.recommend, cursor: nil, personalized: true), token: "jwt")
        XCTAssertEqual(on?.method, "GET")
        XCTAssertEqual(on?.url.path, "/v1/feed/recommend")
        XCTAssertNil(on?.url.query)
        XCTAssertTrue(tellomiDiscoverRecommendPersonalizationQuery(personalized: true).isEmpty)

        let off = tellomiDiscoverHTTPCall(base: base, operation: .feed(.recommend, cursor: "stale", personalized: false), token: "jwt")
        XCTAssertEqual(off?.url.path, "/v1/feed/recommend")
        XCTAssertEqual(URLComponents(url: off!.url, resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "personalized", value: "false")])

        let restored = tellomiDiscoverHTTPCall(base: base, operation: .feed(.recommend, cursor: nil, personalized: true), token: "jwt")
        XCTAssertNil(restored?.url.query)

        let following = tellomiDiscoverHTTPCall(base: base, operation: .feed(.following, cursor: nil, personalized: tellomiDiscoverFeedRequestPersonalized(kind: .following, switchOn: false)), token: "jwt")
        XCTAssertEqual(following?.url.path, "/v1/feed/following")
        XCTAssertNil(following?.url.query)
        XCTAssertFalse(following!.url.absoluteString.contains("personalized"))

        XCTAssertTrue(tellomiDiscoverFeedRequestPersonalized(kind: .recommend, switchOn: true))
        XCTAssertFalse(tellomiDiscoverFeedRequestPersonalized(kind: .recommend, switchOn: false))
        XCTAssertTrue(tellomiDiscoverFeedRequestPersonalized(kind: .following, switchOn: false))
        XCTAssertTrue(tellomiDiscoverFeedRequestPersonalized(kind: .nearby, switchOn: false))
        let nearby = tellomiDiscoverHTTPCall(base: base, operation: .nearby(city: "cn:chengdu", cursor: nil), token: "jwt")
        XCTAssertEqual(nearby?.url.path, "/v1/feed/nearby")
        XCTAssertFalse(nearby!.url.absoluteString.contains("personalized"))
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

    func testAudienceTokenRequestAndErrors() {
        XCTAssertEqual(TellomiDiscoverAudienceList.tokenType, "tellomi-feed-audience")
        XCTAssertEqual(TellomiDiscoverAudienceList.memberLimit, 500)
        XCTAssertEqual(TellomiDiscoverAudienceList.lifetime, 10 * 60)
        XCTAssertEqual(tellomiDiscoverAudienceList(kind: "include", members: ["abc"])?.members, ["abc"])
        XCTAssertNil(tellomiDiscoverAudienceList(kind: "include", members: []))
        XCTAssertNil(tellomiDiscoverAudienceList(kind: "include", members: Array(repeating: "abc", count: 501)))
        XCTAssertNil(tellomiDiscoverAudienceList(kind: "public", members: ["abc"]))
        XCTAssertTrue(tellomiDiscoverAudienceExpiryIsValid(expires: 600, now: 0))
        XCTAssertFalse(tellomiDiscoverAudienceExpiryIsValid(expires: 601, now: 0))
        XCTAssertFalse(tellomiDiscoverAudienceTokenNeedsRefresh(expires: 1_000, now: 939))
        XCTAssertTrue(tellomiDiscoverAudienceTokenNeedsRefresh(expires: 1_000, now: 940))
        XCTAssertEqual(tellomiDiscoverAudience(base: .everyone, includePeerIds: [], selfUserId: 1)?.visibility.rawValue, "public")
        XCTAssertEqual(tellomiDiscoverAudience(base: .nobody, includePeerIds: [7], selfUserId: 1)?.visibility, .include)
        XCTAssertEqual(tellomiDiscoverAudience(base: .nobody, includePeerIds: [7], selfUserId: 1)?.publishable, true)
        XCTAssertEqual(tellomiDiscoverAudience(base: .nobody, includePeerIds: [7], selfUserId: 1)?.userIds, [7])
        XCTAssertEqual(tellomiDiscoverAudience(base: .nobody, includePeerIds: [1], selfUserId: 1)?.publishable, false)
        XCTAssertEqual(tellomiDiscoverAudience(base: .everyone, includePeerIds: [3], selfUserId: 1)?.visibility, .exclude)
        XCTAssertEqual(tellomiDiscoverAudience(base: .everyone, includePeerIds: [3], selfUserId: 1)?.publishable, true)
        XCTAssertEqual(tellomiDiscoverAudience(base: .closeFriends, includePeerIds: [7], selfUserId: 1)?.visibility.rawValue, "close_friends")
        XCTAssertNil(tellomiDiscoverAudience(base: .nobody, includePeerIds: [], selfUserId: 1))
        XCTAssertNil(tellomiDiscoverAudienceUserIds(kind: "include", userIds: [2, 2], selfUserId: 1))
        XCTAssertNil(tellomiDiscoverAudienceUserIds(kind: "include", userIds: [], selfUserId: 1))
        XCTAssertNil(tellomiDiscoverAudienceUserIds(kind: "include", userIds: [0], selfUserId: 1))
        let step = tellomiDiscoverPublishStep(text: "hi", visibility: .include, userIds: [7], selfUserId: 1, clientNonce: self.nonce, textLimit: 500, token: nil, now: 0)
        guard case let .needsAudienceToken(kind, ids) = step else {
            XCTFail("expected a token request")
            return
        }
        XCTAssertEqual(kind, "include")
        XCTAssertEqual(ids, [7])
        let ready = tellomiDiscoverPublishStep(text: "hi", visibility: .include, userIds: [7], selfUserId: 1, clientNonce: self.nonce, textLimit: 500, token: TellomiDiscoverAudienceToken(token: "signed-jwt", expires: 600), now: 0)
        guard case let .ready(data) = ready else {
            XCTFail("expected a post body")
            return
        }
        let posted = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(posted["visibility"] as? String, "include")
        XCTAssertEqual((posted["audience"] as? [String: String])?["audience_token"], "signed-jwt")
        let stale = tellomiDiscoverPublishStep(text: "hi", visibility: .exclude, userIds: [7], selfUserId: 1, clientNonce: self.nonce, textLimit: 500, token: TellomiDiscoverAudienceToken(token: "old", expires: 100), now: 40)
        guard case .needsAudienceToken = stale else {
            XCTFail("expected a refresh")
            return
        }
        let rejected = tellomiDiscoverPublishStep(text: "hi", visibility: .include, userIds: [1, 7], selfUserId: 1, clientNonce: self.nonce, textLimit: 500, token: nil, now: 0)
        guard case .rejected(.audienceInvalid) = rejected else {
            XCTFail("expected the caller's id to reject the list")
            return
        }
        XCTAssertEqual(tellomiDiscoverClientError(description: "DISCOVER_DISABLED", code: 400), .disabled)
        XCTAssertEqual(tellomiDiscoverClientError(description: "AUDIENCE_INVALID", code: 400), .audienceInvalid)
        XCTAssertEqual(tellomiDiscoverClientError(description: "USER_ID_INVALID", code: 400), .userInvalid)
        XCTAssertEqual(tellomiDiscoverClientError(description: "USER_IS_BLOCKED", code: 400), .userBlocked)
        XCTAssertEqual(tellomiDiscoverClientError(description: "AUTH_KEY_UNREGISTERED", code: 401), .signedOut)
        let copy = TellomiDiscoverCopy.resolve(languageCode: "zh")
        XCTAssertEqual(copy.failureText(.disabled), "发现暂时不可用。")
        XCTAssertEqual(copy.failureText(.audienceInvalid), "名单无效，请重新选择。")
        XCTAssertEqual(copy.failureText(.userInvalid), "名单里有人无法使用。")
        XCTAssertEqual(copy.failureText(.userBlocked), "名单里有人已互相拉黑。")
        let bytes = TellomiDiscoverTL.encodeAudienceRequest(kind: "include", userIds: [42, 43])
        XCTAssertEqual(Array(bytes), [
            0xC2, 0x13, 0x52, 0xDC,
            0x07, 0x69, 0x6E, 0x63, 0x6C, 0x75, 0x64, 0x65,
            0x15, 0xC4, 0xB5, 0x1C,
            0x02, 0x00, 0x00, 0x00,
            0x2A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x2B, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ])
        var response = Data([0x81, 0x71, 0x17, 0xDA])
        response.append(contentsOf: encodeString("signed-jwt"))
        response.append(contentsOf: [0x58, 0x02, 0x00, 0x00])
        XCTAssertEqual(TellomiDiscoverTL.decodeAudienceToken(response), TellomiDiscoverAudienceToken(token: "signed-jwt", expires: 600))
        let loggedOut = RecordingLoader()
        let finished = expectation(description: "no audience request")
        loggedOut.loader.run(loggedIn: false, configuration: TellomiDiscoverConfiguration(enabled: true, baseURL: URL(string: "https://feed.example")!), operation: .publish(text: "hi", visibility: .include, audienceToken: "signed-jwt", clientNonce: self.nonce, textLimit: 500, city: "cn:chengdu", quoteOf: nil, pollOptions: nil, linkPreview: nil, mediaKeys: nil)) { result in
            guard case .failure(.signedOut) = result else {
                XCTFail("expected signed out")
                return
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1)
        XCTAssertTrue(loggedOut.calls.isEmpty)
        XCTAssertNil(tellomiDiscoverFeedURL(base: URL(string: "https://feed.example")!, kind: .nearby, cursor: "chengdu", personalized: true))
        let nearby = RecordingLoader()
        let nearbyDone = expectation(description: "no nearby request")
        nearby.loader.run(loggedIn: true, configuration: TellomiDiscoverConfiguration(enabled: true, baseURL: URL(string: "https://feed.example")!), operation: .feed(.nearby, cursor: "chengdu", personalized: true)) { result in
            guard case .failure(.unavailable) = result else {
                XCTFail("expected nearby to stay local")
                return
            }
            nearbyDone.fulfill()
        }
        wait(for: [nearbyDone], timeout: 1)
        XCTAssertTrue(nearby.calls.isEmpty)
        XCTAssertEqual(nearby.credentialFetches, 0)
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
        XCTAssertTrue(summary.meta.contains("成都"))
        XCTAssertEqual(card?.city, "cn:chengdu")
        XCTAssertFalse(summary.body.contains("人民路"))
        let unavailable = tellomiDiscoverParseCards(#"{"cards":[{"id":"post-1","state":"unavailable"}]}"#.data(using: .utf8)!)
        XCTAssertEqual(tellomiDiscoverDisplayPost(unavailable!.first!).unavailable, true)
        XCTAssertEqual(tellomiDiscoverPostSummary(post: tellomiDiscoverDisplayPost(unavailable!.first!), copy: .resolve(languageCode: "zh"), list: false).body, "这条动态已不可见")
        let street = #"{"cards":[{"id":"post-2","state":"ok","card":{"text":"x","city":"人民南路 1 号"}}]}"#.data(using: .utf8)!
        XCTAssertNil(tellomiDiscoverParseCards(street)?.first?.city)
    }

    func testNearbyCityCodeAndFeed() {
        XCTAssertEqual(tellomiDiscoverKnownCityCode("cn:chengdu"), "cn:chengdu")
        XCTAssertEqual(tellomiDiscoverKnownCityCode("CN:Chengdu"), "cn:chengdu")
        XCTAssertNil(tellomiDiscoverCityCode("hk:hong-kong"))
        XCTAssertNil(tellomiDiscoverCityCode("tw:taipei"))
        XCTAssertNil(tellomiDiscoverCityCode("mo:macau"))
        XCTAssertNil(tellomiDiscoverKnownCityCode("cn:not-a-city"))
        XCTAssertNil(tellomiDiscoverKnownCityCode("30.57,104.07"))
        XCTAssertEqual(tellomiDiscoverCityCode(locality: "成都市", isoCountryCode: "CN"), "cn:chengdu")
        XCTAssertEqual(tellomiDiscoverCityCode(locality: "台北市", isoCountryCode: "TW"), "cn:taipei")
        XCTAssertEqual(tellomiDiscoverCityCode(locality: "臺北市", isoCountryCode: "TW"), "cn:taipei")
        XCTAssertEqual(tellomiDiscoverCityCode(locality: "Hong Kong", isoCountryCode: "HK"), "cn:hong-kong")
        XCTAssertEqual(tellomiDiscoverCityCode(locality: "澳门", isoCountryCode: "MO"), "cn:macau")
        XCTAssertNil(tellomiDiscoverCityCode(locality: "人民南路", isoCountryCode: "CN"))
        XCTAssertNil(tellomiDiscoverCity(street: "春熙路", city: nil, state: "四川省"))
        XCTAssertEqual(tellomiDiscoverCity(street: "春熙路", city: "成都市", state: "四川省"), "cn:chengdu")
        XCTAssertEqual(tellomiDiscoverCityName(code: "cn:chengdu", languageCode: "zh"), "成都")
        XCTAssertEqual(tellomiDiscoverNearbyGate(city: nil, location: .notDetermined, asked: false), .choose(requestLocation: true))
        XCTAssertEqual(tellomiDiscoverNearbyGate(city: nil, location: .notDetermined, asked: true), .choose(requestLocation: false))
        XCTAssertEqual(tellomiDiscoverNearbyGate(city: nil, location: .denied, asked: false), .choose(requestLocation: false))
        XCTAssertEqual(tellomiDiscoverNearbyGate(city: "cn:chengdu", location: .notDetermined, asked: false), .feed("cn:chengdu"))
        let base = URL(string: "https://feed.example")!
        let url = tellomiDiscoverNearbyURL(base: base, city: "cn:chengdu", cursor: "page-2")
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(url?.path, "/v1/feed/nearby")
        XCTAssertEqual(items, [URLQueryItem(name: "city", value: "cn:chengdu"), URLQueryItem(name: "cursor", value: "page-2")])
        XCTAssertNil(tellomiDiscoverNearbyURL(base: base, city: "chengdu", cursor: nil))
        let body = tellomiDiscoverPublishBody(text: "hi", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, city: "cn:chengdu")
        let posted = try! JSONSerialization.jsonObject(with: body!) as! [String: Any]
        XCTAssertEqual(posted["city"] as? String, "cn:chengdu")
        XCTAssertNil(tellomiDiscoverPublishBody(text: "hi", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, city: "人民南路"))
        let omitted = tellomiDiscoverPublishBody(text: "hi", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, city: nil)
        XCTAssertNil((try! JSONSerialization.jsonObject(with: omitted!) as! [String: Any])["city"])
        let rejected = tellomiDiscoverDecodeHTTP(operation: .publish(text: "hi", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, city: "cn:chengdu", quoteOf: nil, pollOptions: nil, linkPreview: nil, mediaKeys: nil), result: TellomiDiscoverHTTPResult(status: 400, body: #"{"error":"invalid_city"}"#.data(using: .utf8)!))
        guard case .failure(.invalidCity) = rejected else {
            XCTFail("expected invalid_city")
            return
        }
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "zh").failureText(.invalidCity), "这个城市不能用，请重新选择。")
        let page = #"{"items":[{"id":"post-9","reason":"nearby"}],"cursor":"next"}"#.data(using: .utf8)!
        let decoded = tellomiDiscoverDecodeHTTP(operation: .nearby(city: "cn:chengdu", cursor: nil), result: TellomiDiscoverHTTPResult(status: 200, body: page))
        guard case let .success(.feed(feed)) = decoded else {
            XCTFail("expected a nearby page")
            return
        }
        XCTAssertEqual(feed.items.map(\.reason), ["nearby"])
        XCTAssertEqual(feed.cursor, "next")
        let loader = RecordingLoader()
        let finished = expectation(description: "nearby page")
        loader.loader.run(loggedIn: true, configuration: TellomiDiscoverConfiguration(enabled: true, baseURL: base), operation: .nearby(city: "cn:chengdu", cursor: nil)) { result in
            guard case .success(.feed) = result else {
                XCTFail("expected nearby items")
                return
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(loader.calls.count, 1)
        XCTAssertEqual(loader.calls[0].url.path, "/v1/feed/nearby")
        XCTAssertEqual(URLComponents(url: loader.calls[0].url, resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "city", value: "cn:chengdu")])
        let bad = RecordingLoader()
        let rejectedLocally = expectation(description: "bad city")
        bad.loader.run(loggedIn: true, configuration: TellomiDiscoverConfiguration(enabled: true, baseURL: base), operation: .nearby(city: "not-a-code", cursor: "chengdu")) { result in
            guard case .failure(.invalidCity) = result else {
                XCTFail("expected invalid city")
                return
            }
            rejectedLocally.fulfill()
        }
        wait(for: [rejectedLocally], timeout: 1)
        XCTAssertTrue(bad.calls.isEmpty)
        XCTAssertEqual(bad.credentialFetches, 0)
    }

    func testEngineConfigTabsAndTextLimit() {
        let data = #"{"enabled":true,"region":"cn","tabs":["recommend","hot","nearby"],"recommend_mode":"editorial_chronological","personalization_toggle_visible":false,"limits":{"post_text_chars":500}}"#.data(using: .utf8)!
        let config = tellomiDiscoverParseEngineConfig(data)
        XCTAssertEqual(config?.tabs, [.recommend, .nearby])
        let official = #"{"enabled":true,"region":"cn","tabs":["recommend","following","nearby"],"limits":{"post_text_chars":500}}"#.data(using: .utf8)!
        XCTAssertEqual(tellomiDiscoverParseEngineConfig(official)?.tabs, [.recommend, .following, .nearby])
        XCTAssertEqual(config?.postTextChars, 500)
        XCTAssertEqual(config?.recommendMode, "editorial_chronological")
        XCTAssertEqual(config?.personalizationToggleVisible, false)
        XCTAssertEqual(tellomiDiscoverParseEngineConfig(official)?.personalizationToggleVisible, false)
        XCTAssertNil(tellomiDiscoverFeedURL(base: URL(string: "https://feed.example")!, kind: .recommend, cursor: nil, personalized: tellomiDiscoverFeedRequestPersonalized(kind: .recommend, switchOn: true))?.query)
    }

    func testCreatedPostAndUIChrome() {
        let created = tellomiDiscoverParseCreatedPost(#"{"id":"post-9","state":"pending","version":1}"#.data(using: .utf8)!)
        XCTAssertEqual(created, TellomiDiscoverCreatedPost(id: "post-9", state: "pending", version: 1))
        let on = tellomiDiscoverChrome(loggedIn: true, enabled: true, kind: .recommend, openedPostId: "post-9", failed: false)
        XCTAssertEqual(on.surface, .detail("post-9"))
        XCTAssertTrue(on.loadsPost)
        XCTAssertFalse(on.loadsFeed)
        let tabs = tellomiDiscoverChrome(loggedIn: true, enabled: true, kind: .recommend, openedPostId: nil, failed: false)
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
        let signedOut = tellomiDiscoverChrome(loggedIn: false, enabled: true, kind: .recommend, openedPostId: "post-9", failed: false)
        XCTAssertEqual(signedOut.surface, .legacyEmpty(postUnavailable: true))
        XCTAssertFalse(signedOut.issuesNetwork)
        XCTAssertFalse(signedOut.showsCompose)
        let tabs = tellomiDiscoverChrome(loggedIn: true, enabled: true, kind: .recommend, openedPostId: nil, failed: false)
        XCTAssertEqual(tabs.surface, .feed)
        let nearby = tellomiDiscoverChrome(loggedIn: true, enabled: true, kind: .nearby, openedPostId: nil, failed: false)
        XCTAssertEqual(nearby.surface, .chooseCity)
        XCTAssertFalse(nearby.loadsFeed)
        XCTAssertFalse(nearby.issuesNetwork)
        let chosen = tellomiDiscoverChrome(loggedIn: true, enabled: true, kind: .nearby, openedPostId: nil, failed: false, city: "cn:chengdu")
        XCTAssertEqual(chosen.surface, .feed)
        XCTAssertTrue(chosen.loadsFeed)
        XCTAssertTrue(chosen.issuesNetwork)
    }
}

private let cardsJSON = """
{"cards":[{"id":"post-9","state":"ok","version":1,"card":{"kind":"post","display_mode":"post","source_url":"","ai_generated":true,"edited":false,"text":"好看","author":{"id":"profile-1","display_name":"林","handle":"lin","native":true},"media":[{"type":"image","key":"m/a"}],"ip_region_label":"四川","city":"cn:chengdu"},"stats":{"likes":3,"comments":1,"reposts":0},"me":{"liked":false},"shareable":true,"quoted":{"id":"post-1","state":"deleted"}}]}
""".data(using: .utf8)!

final class TellomiDiscoverLocalizationAndReportTests: XCTestCase {
    func testLanguagePackReplacesHardcodedCopy() {
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "zh-Hans").recommend, "推荐")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "zh-Hant").recommend, "推薦")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "ja").recommend, "おすすめ")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "de").invalidCity, "Diese Stadt kann nicht verwendet werden. Wähle eine andere.")
        let japanese = [
            "Tellomi.Discover.Recommend": "おすすめ",
            "Tellomi.Discover.Likes": "%d いいね",
            "Tellomi.Discover.City.cn_chengdu": "成都"
        ]
        let copy = TellomiDiscoverCopy.resolve(languageCode: "ja", pack: japanese)
        XCTAssertEqual(copy.recommend, "おすすめ")
        XCTAssertEqual(copy.following, "フォロー中")
        XCTAssertEqual(tellomiDiscoverCityName(code: "cn:chengdu", languageCode: "ja", pack: japanese), "成都")
        XCTAssertEqual(tellomiDiscoverCityName(code: "cn:chengdu", languageCode: "ja"), "成都")
        XCTAssertEqual(tellomiDiscoverCityName(code: "cn:chengdu", languageCode: "zh-Hant"), "成都")
        XCTAssertEqual(tellomiDiscoverCityName(code: "cn:chongqing", languageCode: "zh-HK"), "重慶")
        XCTAssertEqual(tellomiDiscoverCityStringKey("cn:hong-kong"), "Tellomi.Discover.City.cn_hong_kong")
        XCTAssertEqual(tellomiDiscoverCityStringKey("us:new-york"), "Tellomi.Discover.City.us_new_york")
        XCTAssertEqual(tellomiDiscoverCityStringKey("us:los-angeles"), "Tellomi.Discover.City.us_los_angeles")
        XCTAssertEqual(tellomiDiscoverCityStringKey("us:san-francisco"), "Tellomi.Discover.City.us_san_francisco")
        for city in tellomiDiscoverCities(languageCode: "en") {
            let ident = tellomiDiscoverCityStringKey(city.code).replacingOccurrences(of: ".", with: "_")
            XCTAssertNotNil(ident.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression), ident)
        }
        let post = TellomiDiscoverPost(id: "post-9", text: "hi", authorName: "", authorHandle: nil, tellomiNumber: "100", unavailable: false, aiGenerated: false, badge: nil, likeCount: 2, commentCount: 0, repostCount: 0, imageCount: 0, quoteState: nil, quoteText: nil, ipRegionLabel: nil, city: "cn:chengdu")
        let summary = tellomiDiscoverPostSummary(post: post, copy: copy, list: false)
        XCTAssertEqual(summary.title, "Tellomi ID: 100")
        XCTAssertTrue(summary.meta.contains("2 いいね"))
        XCTAssertTrue(summary.meta.contains("成都"))
    }

    func testReportPostsToTheFeedEndpoint() {
        let base = URL(string: "https://feed.example")!
        XCTAssertNil(tellomiDiscoverReportCall(loggedIn: false, base: base, token: "jwt", target: .post("post-9"), option: "spam", detail: "x"))
        XCTAssertNil(tellomiDiscoverReportBody(target: .post("post-9"), option: "not-a-reason", detail: ""))
        XCTAssertNil(tellomiDiscoverReportBody(target: .post("../x"), option: "spam", detail: ""))

        let postBody = tellomiDiscoverReportBody(target: .post("post-9"), option: "childAbuse", detail: "details")
        let postJSON = try! JSONSerialization.jsonObject(with: postBody!) as! [String: Any]
        XCTAssertEqual(postJSON["target_type"] as? String, "content")
        XCTAssertEqual(postJSON["post_id"] as? String, "post-9")
        XCTAssertEqual(postJSON["option"] as? String, "child")
        XCTAssertEqual(postJSON["reason"] as? String, "child")
        XCTAssertEqual(postJSON["detail"] as? String, "details")
        XCTAssertNil(postJSON["comment_id"])

        let commentBody = tellomiDiscoverReportBody(target: .comment(postId: "post-9", commentId: "cmt-1"), option: "other", detail: "more")
        let commentJSON = try! JSONSerialization.jsonObject(with: commentBody!) as! [String: Any]
        XCTAssertEqual(commentJSON["option"] as? String, "other")
        XCTAssertEqual(commentJSON["comment_id"] as? String, "cmt-1")
        XCTAssertEqual(commentJSON["detail"] as? String, "more")

        let call = tellomiDiscoverReportCall(loggedIn: true, base: base, token: "jwt", target: .post("post-9"), option: "violence", detail: "")
        XCTAssertEqual(call?.method, "POST")
        XCTAssertEqual(call?.url.path, "/v1/feed/reports")
        XCTAssertEqual(call?.authorizes, true)

        let loader = RecordingLoader()
        let finished = expectation(description: "reported")
        loader.loader.run(loggedIn: true, configuration: TellomiDiscoverConfiguration(enabled: true, baseURL: base), operation: .report(target: .comment(postId: "post-9", commentId: "cmt-1"), option: "spam", detail: "")) { result in
            guard case .success(.reported) = result else {
                XCTFail("expected a stored report")
                return
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(loader.calls.count, 1)
        XCTAssertEqual(loader.calls[0].url.path, "/v1/feed/reports")

        let signedOut = RecordingLoader()
        let blocked = expectation(description: "signed out report")
        signedOut.loader.run(loggedIn: false, configuration: TellomiDiscoverConfiguration(enabled: true, baseURL: base), operation: .report(target: .post("post-9"), option: "spam", detail: "")) { result in
            guard case .failure(.signedOut) = result else {
                XCTFail("expected signedOut")
                return
            }
            blocked.fulfill()
        }
        wait(for: [blocked], timeout: 1)
        XCTAssertTrue(signedOut.calls.isEmpty)

        let cards = #"{"cards":[{"id":"post-9","state":"ok","comments":[{"id":"cmt-1","text":"no","author":{"display_name":"A"}}]}]}"#.data(using: .utf8)!
        XCTAssertEqual(tellomiDiscoverParseCards(cards)?.first?.comments, [TellomiDiscoverComment(id: "cmt-1", text: "no", authorName: "A")])
    }
}

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
