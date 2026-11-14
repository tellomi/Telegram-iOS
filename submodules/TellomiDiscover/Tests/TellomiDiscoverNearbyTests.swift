import XCTest

/// City normalize, the three-tab bar, and the nearby request shape.
/// Mirrors Android `TellomiDiscoverNearbyTest` (tellomi/Telegram#78).
final class TellomiDiscoverNearbyTests: XCTestCase {
    private let nonce = "11111111-1111-4111-8111-111111111111"

    func testCityNormalizeDropsStreetProvinceAndCoordinates() {
        XCTAssertEqual(tellomiDiscoverCityCode(locality: "成都市", isoCountryCode: "CN"), "cn:chengdu")
        XCTAssertEqual(tellomiDiscoverCityCode(locality: "成都", isoCountryCode: nil), "cn:chengdu")
        XCTAssertEqual(tellomiDiscoverCityCode(locality: "台北市", isoCountryCode: "TW"), "cn:taipei")
        XCTAssertEqual(tellomiDiscoverCityCode(locality: "臺北市", isoCountryCode: "TW"), "cn:taipei")
        XCTAssertEqual(tellomiDiscoverCityCode(locality: "Hong Kong", isoCountryCode: "HK"), "cn:hong-kong")
        XCTAssertEqual(tellomiDiscoverCityCode(locality: "澳门", isoCountryCode: "MO"), "cn:macau")
        XCTAssertEqual(tellomiDiscoverCity(street: "春熙路 1 号", city: "成都市", state: "四川省"), "cn:chengdu")
        XCTAssertNil(tellomiDiscoverCity(street: "春熙路 1 号", city: nil, state: "四川省"))
        XCTAssertNil(tellomiDiscoverCity(street: "人民南路", city: "30.67", state: "104.06"))
        XCTAssertNil(tellomiDiscoverCityCode(locality: "30.5728", isoCountryCode: "CN"))
        XCTAssertNil(tellomiDiscoverCityCode(locality: "人民南路", isoCountryCode: "CN"))
        XCTAssertNil(tellomiDiscoverCityCode("hk:hong-kong"))
        XCTAssertNil(tellomiDiscoverCityCode("tw:taipei"))
        XCTAssertNil(tellomiDiscoverPublishCity("cn:not-a-city"))
        XCTAssertEqual(tellomiDiscoverPublishCity("CN:Chengdu"), "cn:chengdu")
        XCTAssertNil(tellomiDiscoverPublishCity("成都市"))
        XCTAssertNil(tellomiDiscoverPublishCity("30.5728,104.0668"))
        XCTAssertEqual(tellomiDiscoverNearbyDisplayName("cn:chengdu", languageCode: "zh-Hant"), "成都")
        XCTAssertEqual(tellomiDiscoverNearbyDisplayName("cn:chengdu", languageCode: "en"), "Chengdu")
        XCTAssertNil(tellomiDiscoverNearbyDisplayName("人民南路", languageCode: "zh"))
    }

    func testHomeTabsStayRecommendFollowingNearby() {
        XCTAssertEqual(tellomiDiscoverHomeTabs(), [.recommend, .following, .nearby])
        let omitted: [TellomiDiscoverFeedKind] = [.recommend, .following]
        XCTAssertTrue(tellomiDiscoverEngineOmitsNearby(omitted))
        XCTAssertEqual(tellomiDiscoverHomeTabs(), [.recommend, .following, .nearby])
        let reversed: [TellomiDiscoverFeedKind] = [.nearby, .recommend]
        XCTAssertFalse(tellomiDiscoverEngineOmitsNearby(reversed))
        XCTAssertEqual(tellomiDiscoverHomeTabs(), [.recommend, .following, .nearby])
        XCTAssertEqual(tellomiDiscoverHomeTabs().firstIndex(of: .nearby), 2)
        let parsed = tellomiDiscoverParseEngineConfig(#"{"enabled":true,"region":"cn","tabs":["recommend","following"],"limits":{"post_text_chars":500}}"#.data(using: .utf8)!)
        XCTAssertEqual(parsed?.tabs, [.recommend, .following])
        XCTAssertTrue(tellomiDiscoverEngineOmitsNearby(parsed?.tabs ?? []))
        XCTAssertEqual(tellomiDiscoverHomeTabs(), [.recommend, .following, .nearby])
    }

    func testNearbyRequestAndPublishUseCityOnly() {
        let call = tellomiDiscoverHTTPCall(base: URL(string: "https://feed.example")!, operation: .nearby(city: "cn:chengdu", cursor: "page-2"), token: "token")
        XCTAssertEqual(call?.method, "GET")
        XCTAssertEqual(call?.url.path, "/v1/feed/nearby")
        let query = URLComponents(url: call!.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query, [
            URLQueryItem(name: "city", value: "cn:chengdu"),
            URLQueryItem(name: "cursor", value: "page-2")
        ])
        for item in query {
            XCTAssertTrue(tellomiDiscoverNearbyQueryName(item.name))
            XCTAssertNotEqual(item.name, "lat")
            XCTAssertNotEqual(item.name, "lng")
            XCTAssertNotEqual(item.name, "latitude")
            XCTAssertNotEqual(item.name, "longitude")
            XCTAssertNotEqual(item.name, "location")
        }
        XCTAssertNil(tellomiDiscoverNearbyURL(base: URL(string: "https://feed.example")!, city: "人民南路", cursor: nil))
        XCTAssertNil(tellomiDiscoverHTTPCall(base: URL(string: "https://feed.example")!, operation: .nearby(city: "30.57", cursor: nil), token: "token"))

        let postedData = tellomiDiscoverPublishBody(text: "hi", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, city: tellomiDiscoverPublishCity("cn:chengdu"))
        let posted = try! JSONSerialization.jsonObject(with: postedData!) as! [String: Any]
        XCTAssertEqual(Set(posted.keys), Set(["kind", "text", "visibility", "client_nonce", "city"]))
        XCTAssertEqual(posted["city"] as? String, "cn:chengdu")
        XCTAssertNil(posted["latitude"])
        XCTAssertNil(posted["longitude"])
        XCTAssertNil(posted["location"])
        XCTAssertNil(posted["lat"])
        XCTAssertNil(posted["lng"])
        let omittedData = tellomiDiscoverPublishBody(text: "hi", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, city: tellomiDiscoverPublishCity(nil))
        let omitted = try! JSONSerialization.jsonObject(with: omittedData!) as! [String: Any]
        XCTAssertEqual(Set(omitted.keys), Set(["kind", "text", "visibility", "client_nonce"]))
        XCTAssertNil(omitted["city"])
        XCTAssertNil(tellomiDiscoverPublishBody(text: "hi", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, city: "人民南路"))
    }

    func testMissingNearbyRouteIsNotAnEmptyFeed() {
        XCTAssertTrue(tellomiDiscoverNearbyMissingEndpoint(404))
        XCTAssertTrue(tellomiDiscoverNearbyMissingEndpoint(405))
        XCTAssertTrue(tellomiDiscoverNearbyMissingEndpoint(501))
        XCTAssertFalse(tellomiDiscoverNearbyMissingEndpoint(200))
        XCTAssertFalse(tellomiDiscoverNearbyMissingEndpoint(400))
        XCTAssertFalse(tellomiDiscoverNearbyMissingEndpoint(500))
        let nearby = TellomiDiscoverOperation.nearby(city: "cn:chengdu", cursor: nil)
        guard case .failure(.nearbyUnavailable) = tellomiDiscoverDecodeHTTP(operation: nearby, result: TellomiDiscoverHTTPResult(status: 404, body: Data())) else {
            return XCTFail("expected a missing nearby route")
        }
        guard case .failure(.nearbyUnavailable) = tellomiDiscoverDecodeHTTP(operation: nearby, result: TellomiDiscoverHTTPResult(status: 405, body: Data(#"{"error":"method_not_allowed"}"#.utf8))) else {
            return XCTFail("expected method not allowed to stay a missing route")
        }
        guard case .failure(.nearbyUnavailable) = tellomiDiscoverDecodeHTTP(operation: nearby, result: TellomiDiscoverHTTPResult(status: 501, body: Data())) else {
            return XCTFail("expected 501 to stay a missing route")
        }
        guard case .failure(.hidden) = tellomiDiscoverDecodeHTTP(operation: nearby, result: TellomiDiscoverHTTPResult(status: 404, body: Data(#"{"error":"feed_hidden"}"#.utf8))) else {
            return XCTFail("expected feed_hidden to stay hidden")
        }
        let publish = TellomiDiscoverOperation.publish(text: "hi", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, city: "cn:chengdu", quoteOf: nil, pollOptions: nil, linkPreview: nil, mediaKeys: nil)
        guard case .failure(.invalidCity) = tellomiDiscoverDecodeHTTP(operation: publish, result: TellomiDiscoverHTTPResult(status: 400, body: Data(#"{"error":"invalid_city"}"#.utf8))) else {
            return XCTFail("expected invalid_city")
        }
        guard case .failure(.unavailable) = tellomiDiscoverDecodeHTTP(operation: nearby, result: TellomiDiscoverHTTPResult(status: 500, body: Data())) else {
            return XCTFail("expected a normal failure for 500")
        }
        guard case let .success(.feed(page)) = tellomiDiscoverDecodeHTTP(operation: nearby, result: TellomiDiscoverHTTPResult(status: 200, body: Data(#"{"items":[]}"#.utf8))) else {
            return XCTFail("expected an empty page")
        }
        XCTAssertTrue(page.items.isEmpty)
        XCTAssertEqual(tellomiDiscoverNearbyGate(city: nil, location: .notDetermined, asked: false), .choose(requestLocation: true))
        XCTAssertEqual(tellomiDiscoverNearbyGate(city: nil, location: .denied, asked: true), .choose(requestLocation: false))
        XCTAssertEqual(tellomiDiscoverNearbyGate(city: "cn:chengdu", location: .denied, asked: true), .feed("cn:chengdu"))
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "zh-Hans").failureText(.nearbyUnavailable), "同城暂时还不能刷新。")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "en").failureText(.unavailable), "Couldn't load this. Pull to try again.")
    }

    func testChineseCopyIsSharedByHansAndTraditional() {
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "zh-Hans").nearby, "同城")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "zh-Hant").nearby, "同城")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "zh-TW").nearby, "同城")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "zh-HK").nearby, "同城")
        XCTAssertEqual(tellomiDiscoverComposeCityLine("cn:chengdu", languageCode: "zh-Hans"), "发布到 成都")
        XCTAssertEqual(tellomiDiscoverComposeCityLine("cn:chengdu", languageCode: "zh-TW"), "發布到 成都")
        XCTAssertEqual(tellomiDiscoverComposeCityLine("cn:chengdu", languageCode: "zh-Hant"), "發布到 成都")
        XCTAssertEqual(tellomiDiscoverComposeCityLine("cn:chengdu", languageCode: "en"), "Posting in Chengdu")
        XCTAssertEqual(tellomiDiscoverComposeCityLine(nil, languageCode: "zh-TW"), "這條不標註城市")
        XCTAssertEqual(tellomiDiscoverComposeCityLine("人民南路", languageCode: "en"), "No city on this post")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "zh-Hant").nearbyUnavailable, "同城暫時還不能重新整理。")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "zh-Hans").nearbyUnavailableHint, "仍可以选城市。帖子只记录城市，不记录位置。")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "en").nearbyUnavailable, "City posts are not available yet.")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "zh-HK").changeCity, "更換城市")
        XCTAssertEqual(TellomiDiscoverCopy.resolve(languageCode: "en").composeCityNone, "No city on this post")
        let packed = tellomiDiscoverComposeCityLine("cn:chengdu", languageCode: "en", pack: ["Tellomi.Discover.ComposeCity": "Posting in %s"])
        XCTAssertEqual(packed, "Posting in Chengdu")
    }
}
