import XCTest

final class TellomiDiscoverFeedTests: XCTestCase {
    func testFeatureFlagDefaultsOff() {
        XCTAssertFalse(tellomiDiscoverEnabled(.missing))
        XCTAssertFalse(tellomiDiscoverEnabled(.bool(false)))
        XCTAssertFalse(tellomiDiscoverEnabled(.number(0)))
        XCTAssertFalse(tellomiDiscoverEnabled(.string("no")))
        XCTAssertFalse(tellomiDiscoverEnabled(.string("maybe")))
        XCTAssertTrue(tellomiDiscoverEnabled(.bool(true)))
        XCTAssertTrue(tellomiDiscoverEnabled(.number(1)))
        XCTAssertTrue(tellomiDiscoverEnabled(.string("enabled")))
    }

    func testConfigurationStaysOffWithoutAFlag() {
        let off = TellomiDiscoverConfiguration.resolve(enabledField: .missing, baseURLField: .string("https://feed.tellomi.cn"))
        XCTAssertFalse(off.enabled)
        XCTAssertNil(off.baseURL)

        let http = TellomiDiscoverConfiguration.resolve(enabledField: .bool(true), baseURLField: .string("http://feed.tellomi.cn"))
        XCTAssertFalse(http.enabled)

        let withUser = TellomiDiscoverConfiguration.resolve(enabledField: .bool(true), baseURLField: .string("https://user:secret@feed.tellomi.cn"))
        XCTAssertFalse(withUser.enabled)

        let on = TellomiDiscoverConfiguration.resolve(enabledField: .bool(true), baseURLField: .missing)
        XCTAssertEqual(on.baseURL?.absoluteString, "https://feed.tellomi.cn")
    }

    func testSignedOutNeverBuildsARequest() {
        let configuration = TellomiDiscoverConfiguration.resolve(enabledField: .bool(true), baseURLField: .missing)
        for operation in sampleOperations() {
            let chrome = tellomiDiscoverChrome(loggedIn: false, enabled: true, kind: .recommend, city: "成都", openedPostId: "post-9", failed: false)
            XCTAssertFalse(chrome.issuesNetwork)
            XCTAssertFalse(chrome.loadsFeed)
            XCTAssertFalse(chrome.loadsPost)
            XCTAssertEqual(chrome.surface, .legacyEmpty(postUnavailable: true))
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
            XCTAssertEqual(loader.calls, [])
        }
    }

    func testDisabledFlagNeverBuildsARequest() {
        let configuration = TellomiDiscoverConfiguration.resolve(enabledField: .missing, baseURLField: .missing)
        let chrome = tellomiDiscoverChrome(loggedIn: true, enabled: false, kind: .following, city: nil, openedPostId: nil, failed: false)
        XCTAssertEqual(chrome.surface, .legacyEmpty(postUnavailable: false))
        XCTAssertFalse(chrome.issuesNetwork)
        XCTAssertFalse(chrome.showsCompose)
        let loader = RecordingLoader()
        let finished = expectation(description: "disabled")
        loader.loader.run(loggedIn: true, configuration: configuration, operation: .feed(.recommend, cursor: nil, city: nil)) { result in
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

    func testFeedAndPostUseTheCredentialThenTheEngine() {
        let configuration = TellomiDiscoverConfiguration.resolve(enabledField: .string("true"), baseURLField: .string("https://feed.example/"))
        let loader = RecordingLoader()
        loader.credential = TellomiDiscoverCredential(token: "jwt-1", expires: 10_000, region: "cn")
        loader.pageBody = pageJSON
        let finished = expectation(description: "feed")
        loader.loader.run(loggedIn: true, configuration: configuration, operation: .feed(.recommend, cursor: "c1", city: nil)) { result in
            guard case let .success(.page(page)) = result else {
                XCTFail("expected a page")
                return
            }
            XCTAssertEqual(page.posts.map(\.id), ["post-9"])
            XCTAssertEqual(page.nextCursor, "n1")
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(loader.credentialFetches, 1)
        XCTAssertEqual(loader.calls.count, 1)
        XCTAssertEqual(loader.calls[0].method, "GET")
        XCTAssertEqual(loader.calls[0].token, "jwt-1")
        XCTAssertEqual(loader.calls[0].url.path, "/v1/feed/recommend")
        XCTAssertTrue(loader.calls[0].url.query?.contains("cursor=c1") == true)
        XCTAssertFalse(loader.calls[0].url.absoluteString.contains("jwt-1"))

        let detail = expectation(description: "detail")
        loader.loader.run(loggedIn: true, configuration: configuration, operation: .post("post-9")) { result in
            guard case let .success(.post(post)) = result else {
                XCTFail("expected a post")
                return
            }
            XCTAssertEqual(post.text, "好看")
            XCTAssertEqual(post.city, "成都")
            XCTAssertEqual(post.authorUserId, 42)
            detail.fulfill()
        }
        wait(for: [detail], timeout: 1)
        XCTAssertEqual(loader.calls.last?.url.path, "/v1/feed/posts/post-9")
    }

    func testExpiredCredentialIsRefreshedBeforeTheFeedRequest() {
        let configuration = TellomiDiscoverConfiguration(enabled: true, baseURL: URL(string: "https://feed.example")!)
        let loader = RecordingLoader(cached: TellomiDiscoverCredential(token: "old", expires: 5_000, region: "global"))
        loader.nowValue = 5_000
        loader.credential = TellomiDiscoverCredential(token: "new", expires: 9_000, region: "global")
        loader.pageBody = #"{"posts":[]}"#.data(using: .utf8)!
        let finished = expectation(description: "refresh")
        loader.loader.run(loggedIn: true, configuration: configuration, operation: .feed(.following, cursor: nil, city: nil)) { result in
            guard case .success = result else {
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
        loader.pageBody = #"{"posts":[]}"#.data(using: .utf8)!
        let finished = expectation(description: "retry")
        loader.loader.run(loggedIn: true, configuration: configuration, operation: .feed(.recommend, cursor: nil, city: nil)) { result in
            guard case .success = result else {
                XCTFail("expected success after one retry")
                return
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(loader.credentialFetches, 1)
        XCTAssertEqual(loader.calls.map(\.token), ["old", "new"])
    }

    func testNearbySendsTheCityAndNothingFiner() {
        let base = URL(string: "https://feed.example")!
        XCTAssertNil(tellomiDiscoverFeedURL(base: base, kind: .nearby, cursor: nil, city: nil))
        XCTAssertNil(tellomiDiscoverFeedURL(base: base, kind: .nearby, cursor: nil, city: "30.67,104.06"))
        XCTAssertNil(tellomiDiscoverHTTPCall(base: base, operation: .feed(.nearby, cursor: nil, city: nil), token: "jwt"))
        let url = tellomiDiscoverFeedURL(base: base, kind: .nearby, cursor: nil, city: "成都, 武侯区")
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.map(\.name).sorted(), ["city", "limit"])
        XCTAssertEqual(items.first(where: { $0.name == "city" })?.value, "成都")
        let absolute = url!.absoluteString
        XCTAssertFalse(absolute.contains("武侯"))
        XCTAssertFalse(absolute.contains("latitude"))
        XCTAssertFalse(absolute.contains("longitude"))
        XCTAssertFalse(absolute.contains("人民路"))

        let chrome = tellomiDiscoverChrome(loggedIn: true, enabled: true, kind: .nearby, city: nil, openedPostId: nil, failed: false)
        XCTAssertEqual(chrome.surface, .cityPrompt)
        XCTAssertFalse(chrome.loadsFeed)
        let ready = tellomiDiscoverChrome(loggedIn: true, enabled: true, kind: .nearby, city: " 成都市 ", openedPostId: nil, failed: false)
        XCTAssertEqual(ready.surface, .feed)
        XCTAssertTrue(ready.loadsFeed)
        XCTAssertTrue(ready.showsCompose)
    }

    func testCityDropsStreetAndCoordinates() {
        XCTAssertEqual(tellomiDiscoverCity(street: "人民路 1 号", city: "成都", state: "四川"), "成都")
        XCTAssertNil(tellomiDiscoverCity(street: "人民路", city: nil, state: "四川"))
        XCTAssertNil(tellomiDiscoverNormalizedCity("30.5728"))
        XCTAssertNil(tellomiDiscoverNormalizedCity("104.0668"))
        XCTAssertEqual(tellomiDiscoverNormalizedCity("New York"), "New York")
    }

    func testStoriesVisibility() {
        XCTAssertEqual(tellomiDiscoverAudience(base: .everyone, includePeerIds: [])?.visibility, .everyone)
        XCTAssertEqual(tellomiDiscoverAudience(base: .everyone, includePeerIds: [])?.publishable, true)
        XCTAssertEqual(tellomiDiscoverAudience(base: .contacts, includePeerIds: [])?.visibility, .contacts)
        XCTAssertEqual(tellomiDiscoverAudience(base: .closeFriends, includePeerIds: [7])?.visibility, .closeFriends)
        XCTAssertEqual(tellomiDiscoverAudience(base: .closeFriends, includePeerIds: [7])?.publishable, true)
        XCTAssertEqual(tellomiDiscoverAudience(base: .nobody, includePeerIds: [7])?.visibility, .selected)
        XCTAssertEqual(tellomiDiscoverAudience(base: .nobody, includePeerIds: [7])?.publishable, false)
        XCTAssertEqual(tellomiDiscoverAudience(base: .nobody, includePeerIds: [7])?.reason, "needs_audience_token")
        XCTAssertNil(tellomiDiscoverAudience(base: .nobody, includePeerIds: []))
        XCTAssertEqual(tellomiDiscoverAudience(base: .everyone, includePeerIds: [3])?.reason, "excluded_peers")
        XCTAssertNil(tellomiDiscoverPublishBody(text: "hi", visibility: .selected))
        let body = tellomiDiscoverPublishBody(text: " 你好 ", visibility: .contacts)
        let object = try! JSONSerialization.jsonObject(with: body!) as! [String: String]
        XCTAssertEqual(object["text"], "你好")
        XCTAssertEqual(object["visibility"], "contacts")
        XCTAssertEqual(Set(object.keys), Set(["text", "visibility"]))
    }

    func testPostLinkDoesNotRequestWhenTheFeedIsOff() {
        let off = tellomiDiscoverChrome(loggedIn: true, enabled: false, kind: .recommend, city: nil, openedPostId: "post-9", failed: false)
        XCTAssertEqual(off.surface, .legacyEmpty(postUnavailable: true))
        XCTAssertFalse(off.loadsPost)
        let on = tellomiDiscoverChrome(loggedIn: true, enabled: true, kind: .nearby, city: nil, openedPostId: "post-9", failed: false)
        XCTAssertEqual(on.surface, .detail("post-9"))
        XCTAssertTrue(on.loadsPost)
        XCTAssertFalse(on.loadsFeed)
        XCTAssertNil(tellomiDiscoverPostURL(base: URL(string: "https://feed.example")!, id: "../admin"))
        XCTAssertNil(tellomiDiscoverPostURL(base: URL(string: "https://feed.example")!, id: ".."))
        XCTAssertNil(tellomiDiscoverPostURL(base: URL(string: "https://feed.example")!, id: "a/b"))
    }

    func testCredentialRoundTrip() {
        XCTAssertEqual(Array(TellomiDiscoverTL.encodeRequest()), [0x76, 0x7F, 0x0A, 0xA8])
        var body = Data()
        body.append(contentsOf: [0xAA, 0xCC, 0x78, 0x05])
        body.append(contentsOf: encodeString("jwt.token"))
        body.append(contentsOf: [0x39, 0x30, 0x00, 0x00])
        body.append(contentsOf: encodeString("cn"))
        let credential = TellomiDiscoverTL.decodeCredential(body)
        XCTAssertEqual(credential, TellomiDiscoverCredential(token: "jwt.token", expires: 12345, region: "cn"))
        XCTAssertNil(TellomiDiscoverTL.decodeCredential(Data([0x00])))
        XCTAssertTrue(tellomiDiscoverCredentialNeedsRefresh(expires: 1_000, now: 880))
        XCTAssertFalse(tellomiDiscoverCredentialNeedsRefresh(expires: 1_000, now: 879))
        var long = Data()
        long.append(contentsOf: [0xAA, 0xCC, 0x78, 0x05])
        long.append(contentsOf: encodeString(String(repeating: "测", count: 90)))
        long.append(contentsOf: [0x01, 0x00, 0x00, 0x00])
        long.append(contentsOf: encodeString("global"))
        XCTAssertEqual(TellomiDiscoverTL.decodeCredential(long)?.region, "global")
    }

    func testPageParsesTheDocumentedCardAndDropsAStreet() {
        let page = tellomiDiscoverParsePage(pageJSON)
        let post = page?.posts.first
        XCTAssertEqual(post?.text, "好看")
        XCTAssertEqual(post?.authorName, "林")
        XCTAssertEqual(post?.authorUsername, "lin")
        XCTAssertEqual(post?.authorUserId, 42)
        XCTAssertEqual(post?.city, "成都")
        XCTAssertEqual(post?.imageCount, 1)
        XCTAssertEqual(post?.likeCount, 3)
        XCTAssertEqual(post?.aiGenerated, true)
        XCTAssertEqual(page?.nextCursor, "n1")
        let located = #"{"id":"post-1","text":"x","location":{"street":"人民路","city":"成都","latitude":30.6,"longitude":104.0}}"#.data(using: .utf8)!
        XCTAssertEqual(tellomiDiscoverParsePost(located)?.city, "成都")
        let review = tellomiDiscoverVisibleBadge("审核中", aiGenerated: false, copy: .resolve(languageCode: "zh"))
        XCTAssertNil(review)
        let summary = tellomiDiscoverPostSummary(post: post!, copy: .resolve(languageCode: "zh-Hans"), list: true)
        XCTAssertEqual(summary.title, "林 @lin")
        XCTAssertTrue(summary.meta.contains("成都"))
        XCTAssertTrue(summary.meta.contains("AI 生成"))
        XCTAssertFalse(summary.body.contains("审核"))
    }

    func testDeletedQuoteAndEnglishCopy() {
        let data = #"{"id":"post-2","text":"引用","quote_of":{"deleted":true}}"#.data(using: .utf8)!
        let post = tellomiDiscoverParsePost(data)
        XCTAssertEqual(post?.quoteDeleted, true)
        let summary = tellomiDiscoverPostSummary(post: post!, copy: .resolve(languageCode: "en"), list: false)
        XCTAssertTrue(summary.body.contains("The original post was deleted"))
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "de").recommend, "For You")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "zh").nearby, "同城")
    }

    func testTabsWhenTheFeedIsOn() {
        let chrome = tellomiDiscoverChrome(loggedIn: true, enabled: true, kind: .following, city: nil, openedPostId: nil, failed: true)
        XCTAssertEqual(chrome.surface, .feed)
        XCTAssertTrue(chrome.showsCompose)
        XCTAssertTrue(chrome.loadsFeed)
        XCTAssertTrue(chrome.failure)
    }

    func testUIFeedStaysOnTheEmptyPageUntilTheFlagIsOn() {
        let signedOut = tellomiDiscoverChrome(loggedIn: false, enabled: true, kind: .recommend, city: "成都", openedPostId: "post-9", failed: false)
        XCTAssertEqual(signedOut.surface, .legacyEmpty(postUnavailable: true))
        XCTAssertFalse(signedOut.issuesNetwork)
        XCTAssertFalse(signedOut.showsCompose)

        let nearby = tellomiDiscoverChrome(loggedIn: true, enabled: true, kind: .nearby, city: "30.5728", openedPostId: nil, failed: false)
        XCTAssertEqual(nearby.surface, .cityPrompt)
        XCTAssertFalse(nearby.loadsFeed)

        let tabs = tellomiDiscoverChrome(loggedIn: true, enabled: true, kind: .recommend, city: nil, openedPostId: nil, failed: false)
        XCTAssertEqual(tabs.surface, .feed)
        XCTAssertTrue(tabs.showsCompose)
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "zh-Hans").recommend, "推荐")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "en").following, "Following")
    }

    private func sampleOperations() -> [TellomiDiscoverOperation] {
        return [
            .feed(.recommend, cursor: nil, city: nil),
            .feed(.nearby, cursor: nil, city: "成都"),
            .post("post-9"),
            .publish(text: "hi", visibility: .everyone)
        ]
    }
}

private let pageJSON = """
{"posts":[{"id":"post-9","text":"好看","author_name":"林","author_username":"lin","user_id":42,"created_at":1762210000,"visibility":"everyone","city":"成都","shareable":true,"ai_generated":true,"badge":"","like_count":3,"comment_count":1,"repost_count":0,"media":[{"url":"https://cdn.example/a.jpg","kind":"image"}],"quote_of":null}],"next_cursor":"n1"}
""".data(using: .utf8)!

private final class RecordingLoader {
    var nowValue: Int64 = 1_000
    var credential = TellomiDiscoverCredential(token: "jwt", expires: 9_000, region: "cn")
    var pageBody = Data()
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
            if status == 200 {
                let body = call.method == "GET" && call.url.path.hasPrefix("/v1/feed/posts/") ? detailBody : owner.pageBody
                completion(.success(TellomiDiscoverHTTPResult(status: status, body: body)))
            } else {
                completion(.success(TellomiDiscoverHTTPResult(status: status, body: Data())))
            }
        })
        box.owner = self
    }
}

private final class LoaderBox {
    weak var owner: RecordingLoader?
}

private let detailBody = #"{"post":{"id":"post-9","text":"好看","author":{"name":"林","username":"lin","user_id":"42"},"city":"成都"}}"#.data(using: .utf8)!

private func encodeString(_ value: String) -> [UInt8] {
    let bytes = Array(value.utf8)
    let length = bytes.count
    var out: [UInt8] = []
    if length >= 254 {
        out.append(254)
        out.append(UInt8(length & 0xFF))
        out.append(UInt8((length >> 8) & 0xFF))
        out.append(UInt8((length >> 16) & 0xFF))
        out.append(contentsOf: bytes)
        let padding = (4 - (length % 4)) % 4
        out.append(contentsOf: Array(repeating: 0, count: padding))
    } else {
        out.append(UInt8(length))
        out.append(contentsOf: bytes)
        let padded = length + 1
        let padding = (4 - (padded % 4)) % 4
        out.append(contentsOf: Array(repeating: 0, count: padding))
    }
    return out
}
