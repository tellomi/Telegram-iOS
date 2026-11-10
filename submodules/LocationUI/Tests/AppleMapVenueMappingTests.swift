import XCTest

final class AppleMapVenueMappingTests: XCTestCase {
    private let latitude = 29.563
    private let longitude = 106.551

    func testFallbackQueryFollowsTheUiLanguage() {
        XCTAssertEqual(appleMapNearbyFallbackQuery(languageCode: "zh"), "餐饮")
        XCTAssertEqual(appleMapNearbyFallbackQuery(languageCode: "zh-Hans"), "餐饮")
        XCTAssertEqual(appleMapNearbyFallbackQuery(languageCode: "zh_CN"), "餐饮")
        XCTAssertEqual(appleMapNearbyFallbackQuery(languageCode: "zh-hant"), "餐飲")
        XCTAssertEqual(appleMapNearbyFallbackQuery(languageCode: "zh-TW"), "餐飲")
        XCTAssertEqual(appleMapNearbyFallbackQuery(languageCode: "zh-HK"), "餐飲")
        XCTAssertEqual(appleMapNearbyFallbackQuery(languageCode: "zh-MO"), "餐飲")
        XCTAssertEqual(appleMapNearbyFallbackQuery(languageCode: "en"), "restaurant")
        XCTAssertEqual(appleMapNearbyFallbackQuery(languageCode: ""), "restaurant")
    }

    func testQueryKeyTrimsAndIgnoresCase() {
        XCTAssertEqual(appleMapVenueQueryKey("  Cafe "), "cafe")
        XCTAssertEqual(appleMapVenueQueryKey("火锅"), "火锅")
        XCTAssertEqual(appleMapVenueQueryKey(nil), "")
        XCTAssertEqual(appleMapVenueQueryKey("   "), "")
    }

    func testThrottleDoesNotStartTheFallbackSearch() {
        XCTAssertTrue(appleMapShouldRunNearbyFallback(itemCount: 0, throttled: false))
        XCTAssertFalse(appleMapShouldRunNearbyFallback(itemCount: 0, throttled: true))
        XCTAssertFalse(appleMapShouldRunNearbyFallback(itemCount: 4, throttled: false))
    }

    func testVenueFieldsKeepWgs84AndAStableAppleId() {
        let draft = appleMapVenueDraft(from: self.place(
            name: "天安门",
            latitude: 39.908692,
            longitude: 116.397477,
            thoroughfare: "长安街",
            subLocality: "东城区",
            locality: "北京市",
            category: "cafe"
        ))
        XCTAssertEqual(draft?.latitude, 39.908692)
        XCTAssertEqual(draft?.longitude, 116.397477)
        XCTAssertEqual(draft?.provider, "apple")
        XCTAssertEqual(draft?.type, "food/cafe")
        XCTAssertEqual(draft?.title, "天安门")
        XCTAssertEqual(draft?.address, "东城区长安街")
        XCTAssertEqual(draft?.id, appleMapVenueIdentifier(latitude: 39.908692, longitude: 116.397477, title: "天安门"))
        XCTAssertEqual(appleMapVenueIdentifier(latitude: 39.5, longitude: 116.25, title: "Cafe"), "apple:39.500000:116.250000:cafe")
    }

    func testTitleCollapsesNewlinesAndDropsAnEmptyName() {
        let draft = appleMapVenueDraft(from: self.place(name: "Hot\nPot  ", category: "restaurant"))
        XCTAssertEqual(draft?.title, "Hot Pot")
        XCTAssertEqual(draft?.type, "food")
        XCTAssertNil(appleMapVenueDraft(from: self.place(name: " \n ")))
        XCTAssertNil(appleMapVenueDraft(from: self.place(name: "Null Island", latitude: 0, longitude: 0)))
        XCTAssertNil(appleMapVenueDraft(from: self.place(name: "Off World", latitude: 91, longitude: 10)))
    }

    func testChineseAddressJoinsWithoutRepeatingTheStreetNumber() {
        let address = appleMapVenueAddress(title: "火锅", parts: AppleMapAddressParts(
            thoroughfare: "民族路88号",
            subThoroughfare: "88号",
            subLocality: "渝中区",
            locality: "重庆市",
            administrativeArea: "重庆市"
        ))
        XCTAssertEqual(address, "渝中区民族路88号")
    }

    func testEnglishAddressUsesNumberThenStreet() {
        let address = appleMapVenueAddress(title: "Museum", parts: AppleMapAddressParts(
            thoroughfare: "Baker Street",
            subThoroughfare: "221B",
            subLocality: "Marylebone",
            locality: "London",
            administrativeArea: "England"
        ))
        XCTAssertEqual(address, "221B Baker Street, Marylebone, London, England")
    }

    func testCategoryTypesMatchTheExistingVenueColors() {
        XCTAssertEqual(appleMapVenueType(category: "hotel"), "travel/hotel")
        XCTAssertEqual(appleMapVenueType(category: "park"), "parks_outdoors")
        XCTAssertEqual(appleMapVenueType(category: "hospital"), "building/medical")
        XCTAssertEqual(appleMapVenueType(category: "store"), "shops")
        XCTAssertEqual(appleMapVenueType(category: "airport"), "travel")
        XCTAssertEqual(appleMapVenueType(category: "school"), "education")
        XCTAssertEqual(appleMapVenueType(category: nil), "building/default")
        XCTAssertEqual(appleMapVenueType(category: "atm"), "building/default")
    }

    func testNearbyListDedupsSortsByDistanceAndCapsAtTwenty() {
        var fields: [AppleMapPlacemarkFields] = []
        fields.append(self.place(name: "Far", latitude: self.north(meters: 2000)))
        fields.append(self.place(name: "Near", latitude: self.north(meters: 100)))
        fields.append(self.place(name: "Near", latitude: self.north(meters: 130)))
        for index in 0 ..< 24 {
            fields.append(self.place(name: "Row \(index)", latitude: self.north(meters: Double(300 + index * 20))))
        }
        let drafts = appleMapVenueDrafts(from: fields, latitude: self.latitude, longitude: self.longitude, limit: appleMapVenueLimit)
        XCTAssertEqual(drafts.count, appleMapVenueLimit)
        XCTAssertEqual(drafts.first?.title, "Near")
        XCTAssertEqual(drafts.filter { $0.title == "Near" }.count, 1)
        let first = appleMapDistanceMeters(fromLatitude: self.latitude, fromLongitude: self.longitude, toLatitude: drafts[0].latitude, toLongitude: drafts[0].longitude)
        let last = appleMapDistanceMeters(fromLatitude: self.latitude, fromLongitude: self.longitude, toLatitude: drafts[19].latitude, toLongitude: drafts[19].longitude)
        XCTAssertLessThan(first, last)
    }

    func testMergeKeepsTheBotRowAndOrdersByDistance() {
        let bot = AppleMapVenueDraft(
            latitude: self.north(meters: 40),
            longitude: self.longitude,
            title: "火锅",
            address: "渝中区",
            provider: "foursquare",
            id: "fsq-1",
            type: "food"
        )
        let appleSame = AppleMapVenueDraft(
            latitude: self.north(meters: 80),
            longitude: self.longitude,
            title: "火锅",
            address: "渝中区民族路",
            provider: "apple",
            id: "apple:same",
            type: "food"
        )
        let appleNear = AppleMapVenueDraft(
            latitude: self.north(meters: 200),
            longitude: self.longitude,
            title: "Cafe",
            address: "1 Road",
            provider: "apple",
            id: "apple:cafe",
            type: "food/cafe"
        )
        let botFar = AppleMapVenueDraft(
            latitude: self.north(meters: 900),
            longitude: self.longitude,
            title: "Park",
            address: nil,
            provider: "foursquare",
            id: "fsq-2",
            type: "parks_outdoors"
        )
        let merged = appleMapMergeVenues(bot: [botFar, bot], apple: [appleSame, appleNear], latitude: self.latitude, longitude: self.longitude, limit: 20)
        XCTAssertEqual(merged.map { $0.id }, ["fsq-1", "apple:cafe", "fsq-2"])
        XCTAssertEqual(merged[0].provider, "foursquare")
        XCTAssertEqual(merged[0].address, "渝中区")
    }

    func testPlacesWithinFifteenMetersCollapseEvenWhenTheNamesDiffer() {
        let door = self.place(name: "North Door", latitude: self.north(meters: 10))
        let lobby = self.place(name: "Lobby", latitude: self.north(meters: 18))
        let other = self.place(name: "Other Shop", latitude: self.north(meters: 40))
        let drafts = appleMapVenueDrafts(from: [door, lobby, other], latitude: self.latitude, longitude: self.longitude, limit: 20)
        XCTAssertEqual(drafts.map { $0.title }, ["North Door", "Other Shop"])
    }

    func testCacheReusesTheSameQueryInsideTwoHundredMeters() {
        var state = AppleMapVenueGateState()
        let venue = self.draft(name: "Cafe", meters: 20)
        state.store(now: 1_000, latitude: self.latitude, longitude: self.longitude, query: "cafe", venues: [venue])
        guard case let .cached(hit) = state.lookup(now: 1_010, latitude: self.north(meters: 100), longitude: self.longitude, query: "cafe") else {
            return XCTFail("expected a cache hit")
        }
        XCTAssertEqual(hit, [venue])

        guard case let .fetch(delay) = state.lookup(now: 1_010, latitude: self.north(meters: 1_000), longitude: self.longitude, query: "cafe") else {
            return XCTFail("expected a fetch past 200 meters")
        }
        XCTAssertEqual(delay, 0, accuracy: 0.000_1)

        guard case .fetch = state.lookup(now: 1_010, latitude: self.latitude, longitude: self.longitude, query: "hotel") else {
            return XCTFail("expected a fetch for a different query")
        }
    }

    func testCacheHitDoesNotWaitOutTheStartInterval() {
        var state = AppleMapVenueGateState()
        state.store(now: 50, latitude: self.latitude, longitude: self.longitude, query: "", venues: [self.draft(name: "A", meters: 10)])
        guard case .cached = state.lookup(now: 51, latitude: self.latitude, longitude: self.longitude, query: "") else {
            return XCTFail("expected a cache hit")
        }
        guard case let .fetch(delay) = state.lookup(now: 51, latitude: self.north(meters: 5_000), longitude: self.longitude, query: "") else {
            return XCTFail("expected a fetch")
        }
        XCTAssertEqual(delay, 0, accuracy: 0.000_1)
    }

    func testEmptyCacheExpiresSoonerThanAFilledOne() {
        var empty = AppleMapVenueGateState()
        empty.store(now: 0, latitude: self.latitude, longitude: self.longitude, query: "", venues: [])
        guard case .cached = empty.lookup(now: appleMapVenueEmptyCacheLifetime - 1, latitude: self.latitude, longitude: self.longitude, query: "") else {
            return XCTFail("empty cache should still be fresh")
        }
        guard case .fetch = empty.lookup(now: appleMapVenueEmptyCacheLifetime, latitude: self.latitude, longitude: self.longitude, query: "") else {
            return XCTFail("empty cache should expire")
        }

        var filled = AppleMapVenueGateState()
        filled.store(now: 0, latitude: self.latitude, longitude: self.longitude, query: "", venues: [self.draft(name: "A", meters: 10)])
        guard case .cached = filled.lookup(now: appleMapVenueSuccessCacheLifetime - 1, latitude: self.latitude, longitude: self.longitude, query: "") else {
            return XCTFail("filled cache should still be fresh")
        }
        guard case .fetch = filled.lookup(now: appleMapVenueSuccessCacheLifetime, latitude: self.latitude, longitude: self.longitude, query: "") else {
            return XCTFail("filled cache should expire")
        }
    }

    func testThrottleCooldownServesAFreshCacheAndOtherwiseSkipsTheNetwork() {
        var state = AppleMapVenueGateState()
        let venue = self.draft(name: "A", meters: 10)
        state.store(now: 0, latitude: self.latitude, longitude: self.longitude, query: "", venues: [venue])
        state.noteThrottled(now: 10)
        guard case let .cached(hit) = state.lookup(now: 12, latitude: self.latitude, longitude: self.longitude, query: "") else {
            return XCTFail("a fresh cache wins over the cooldown")
        }
        XCTAssertEqual(hit, [venue])

        guard case .coolingDown = state.lookup(now: 12, latitude: self.north(meters: 5_000), longitude: self.longitude, query: "") else {
            return XCTFail("cooldown should skip a new search")
        }
        guard case .fetch = state.lookup(now: 10 + appleMapVenueThrottleCooldown, latitude: self.north(meters: 5_000), longitude: self.longitude, query: "") else {
            return XCTFail("cooldown should end")
        }
    }

    func testStartsAreAtLeastTheMinimumIntervalApart() {
        var state = AppleMapVenueGateState()
        XCTAssertEqual(state.reserveStart(now: 100), 0, accuracy: 0.000_1)
        XCTAssertEqual(state.reserveStart(now: 100.1), 0.3, accuracy: 0.000_1)
        XCTAssertEqual(state.reserveStart(now: 101), 0, accuracy: 0.000_1)
    }

    private func place(name: String, latitude: Double? = nil, longitude: Double? = nil, thoroughfare: String? = nil, subThoroughfare: String? = nil, subLocality: String? = nil, locality: String? = nil, administrativeArea: String? = nil, category: String? = nil) -> AppleMapPlacemarkFields {
        return AppleMapPlacemarkFields(
            latitude: latitude ?? self.latitude,
            longitude: longitude ?? self.longitude,
            name: name,
            thoroughfare: thoroughfare,
            subThoroughfare: subThoroughfare,
            subLocality: subLocality,
            locality: locality,
            administrativeArea: administrativeArea,
            category: category
        )
    }

    private func draft(name: String, meters: Double) -> AppleMapVenueDraft {
        return AppleMapVenueDraft(
            latitude: self.north(meters: meters),
            longitude: self.longitude,
            title: name,
            address: nil,
            provider: "apple",
            id: name,
            type: "building/default"
        )
    }

    private func north(meters: Double) -> Double {
        return self.latitude + meters / 111_320.0
    }
}
