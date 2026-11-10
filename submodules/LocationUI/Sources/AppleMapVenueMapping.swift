import Foundation

/// Pure venue-list rules for the on-device MapKit fallback.
/// MapKit, signals, and `TelegramMediaMap` stay in `AppleMapVenueSearch`.
/// These functions are what the unit test compiles on its own.

let appleMapVenueProvider = "apple"
let appleMapVenueLimit = 20
let appleMapVenueBotTimeout: Double = 1.5
let appleMapVenueMinimumInterval: Double = 0.4
let appleMapVenueSuccessCacheLifetime: Double = 180
let appleMapVenueEmptyCacheLifetime: Double = 20
let appleMapVenueThrottleCooldown: Double = 8
let appleMapVenueCacheDistance: Double = 200
let appleMapNearbyRadiusMeters: Double = 2500
let appleMapTextSearchSpanMeters: Double = 100_000

struct AppleMapPlacemarkFields {
    var latitude: Double
    var longitude: Double
    var name: String
    var thoroughfare: String?
    var subThoroughfare: String?
    var subLocality: String?
    var locality: String?
    var administrativeArea: String?
    var category: String?
}

struct AppleMapAddressParts {
    var thoroughfare: String?
    var subThoroughfare: String?
    var subLocality: String?
    var locality: String?
    var administrativeArea: String?
}

struct AppleMapVenueDraft: Equatable {
    var latitude: Double
    var longitude: Double
    var title: String
    var address: String?
    var provider: String
    var id: String
    var type: String
}

enum AppleMapVenueLookup {
    case cached([AppleMapVenueDraft])
    case coolingDown
    case fetch(delay: Double)
}

struct AppleMapVenueGateState {
    private struct Entry {
        var time: Double
        var latitude: Double
        var longitude: Double
        var query: String
        var venues: [AppleMapVenueDraft]
    }

    private var entries: [Entry] = []
    private var lastStart: Double?
    private var throttleUntil: Double?

    mutating func lookup(now: Double, latitude: Double, longitude: Double, query: String) -> AppleMapVenueLookup {
        if let venues = self.freshVenues(now: now, latitude: latitude, longitude: longitude, query: query) {
            return .cached(venues)
        }
        if let until = self.throttleUntil, now < until {
            return .coolingDown
        }
        return .fetch(delay: self.reserveStart(now: now))
    }

    mutating func reserveStart(now: Double) -> Double {
        let earliest: Double
        if let lastStart = self.lastStart {
            earliest = lastStart + appleMapVenueMinimumInterval
        } else {
            earliest = now
        }
        let start = max(now, earliest)
        self.lastStart = start
        return start - now
    }

    mutating func noteThrottled(now: Double) {
        let until = now + appleMapVenueThrottleCooldown
        if let current = self.throttleUntil {
            self.throttleUntil = max(current, until)
        } else {
            self.throttleUntil = until
        }
    }

    mutating func store(now: Double, latitude: Double, longitude: Double, query: String, venues: [AppleMapVenueDraft]) {
        let entry = Entry(time: now, latitude: latitude, longitude: longitude, query: query, venues: venues)
        if let index = self.entries.firstIndex(where: { existing in
            existing.query == query && appleMapDistanceMeters(fromLatitude: existing.latitude, fromLongitude: existing.longitude, toLatitude: latitude, toLongitude: longitude) <= appleMapVenueCacheDistance
        }) {
            self.entries[index] = entry
            return
        }
        self.entries.append(entry)
        if self.entries.count > 32 {
            self.entries.removeFirst(self.entries.count - 32)
        }
    }

    private func freshVenues(now: Double, latitude: Double, longitude: Double, query: String) -> [AppleMapVenueDraft]? {
        var bestDistance = Double.greatestFiniteMagnitude
        var best: [AppleMapVenueDraft]?
        for entry in self.entries where entry.query == query {
            let lifetime = entry.venues.isEmpty ? appleMapVenueEmptyCacheLifetime : appleMapVenueSuccessCacheLifetime
            if now - entry.time >= lifetime {
                continue
            }
            let distance = appleMapDistanceMeters(fromLatitude: entry.latitude, fromLongitude: entry.longitude, toLatitude: latitude, toLongitude: longitude)
            if distance <= appleMapVenueCacheDistance && distance < bestDistance {
                bestDistance = distance
                best = entry.venues
            }
        }
        return best
    }
}

func appleMapNearbyFallbackQuery(languageCode: String) -> String {
    let code = languageCode.lowercased(with: Locale(identifier: "en_US_POSIX")).replacingOccurrences(of: "_", with: "-")
    if code.hasPrefix("zh-hant") || code.hasPrefix("zh-tw") || code.hasPrefix("zh-hk") || code.hasPrefix("zh-mo") {
        return "餐飲"
    }
    if code == "zh" || code.hasPrefix("zh-") {
        return "餐饮"
    }
    return "restaurant"
}

func appleMapVenueQueryKey(_ query: String?) -> String {
    return appleMapCollapsedText(query ?? "").lowercased(with: Locale(identifier: "en_US_POSIX"))
}

/// A points-of-interest response with no rows gets one text search.
/// `MKError.loadingThrottled` does not: a second request makes Apple's limit worse.
func appleMapShouldRunNearbyFallback(itemCount: Int, throttled: Bool) -> Bool {
    return itemCount == 0 && !throttled
}

func appleMapVenueType(category token: String?) -> String {
    switch token {
    case "cafe":
        return "food/cafe"
    case "restaurant", "bakery", "brewery", "winery", "foodMarket":
        return "food"
    case "hotel":
        return "travel/hotel"
    case "park", "nationalPark", "beach", "campground":
        return "parks_outdoors"
    case "nightlife":
        return "nightlife"
    case "hospital", "pharmacy":
        return "building/medical"
    case "fitnessCenter", "stadium":
        return "building/gym"
    case "school", "university", "library":
        return "education"
    case "museum", "movieTheater", "theater", "amusementPark", "aquarium", "zoo":
        return "arts_entertainment"
    case "store":
        return "shops"
    case "airport", "publicTransport", "marina", "carRental", "gasStation":
        return "travel"
    default:
        return "building/default"
    }
}

func appleMapVenueDraft(from fields: AppleMapPlacemarkFields) -> AppleMapVenueDraft? {
    guard appleMapCoordinateIsUsable(latitude: fields.latitude, longitude: fields.longitude) else {
        return nil
    }
    guard let title = appleMapVenueTitle(fields.name) else {
        return nil
    }
    let address = appleMapVenueAddress(title: title, parts: AppleMapAddressParts(
        thoroughfare: fields.thoroughfare,
        subThoroughfare: fields.subThoroughfare,
        subLocality: fields.subLocality,
        locality: fields.locality,
        administrativeArea: fields.administrativeArea
    ))
    return AppleMapVenueDraft(
        latitude: fields.latitude,
        longitude: fields.longitude,
        title: title,
        address: address,
        provider: appleMapVenueProvider,
        id: appleMapVenueIdentifier(latitude: fields.latitude, longitude: fields.longitude, title: title),
        type: appleMapVenueType(category: fields.category)
    )
}

func appleMapVenueDrafts(from fields: [AppleMapPlacemarkFields], latitude: Double, longitude: Double, limit: Int) -> [AppleMapVenueDraft] {
    var drafts: [AppleMapVenueDraft] = []
    for field in fields {
        guard let draft = appleMapVenueDraft(from: field) else {
            continue
        }
        if drafts.contains(where: { appleMapVenuesAreSamePlace($0, draft) }) {
            continue
        }
        drafts.append(draft)
    }
    return appleMapVenuesSortedByDistance(drafts, latitude: latitude, longitude: longitude, limit: limit)
}

func appleMapMergeVenues(bot: [AppleMapVenueDraft], apple: [AppleMapVenueDraft], latitude: Double, longitude: Double, limit: Int) -> [AppleMapVenueDraft] {
    var chosen: [AppleMapVenueDraft] = []
    for draft in bot + apple {
        if chosen.contains(where: { appleMapVenuesAreSamePlace($0, draft) }) {
            continue
        }
        chosen.append(draft)
    }
    return appleMapVenuesSortedByDistance(chosen, latitude: latitude, longitude: longitude, limit: limit)
}

func appleMapVenuesAreSamePlace(_ lhs: AppleMapVenueDraft, _ rhs: AppleMapVenueDraft) -> Bool {
    if !lhs.id.isEmpty && lhs.id == rhs.id {
        return true
    }
    let distance = appleMapDistanceMeters(fromLatitude: lhs.latitude, fromLongitude: lhs.longitude, toLatitude: rhs.latitude, toLongitude: rhs.longitude)
    if distance < 15.0 {
        return true
    }
    if distance < 50.0 && appleMapVenueTitleKey(lhs.title) == appleMapVenueTitleKey(rhs.title) {
        return true
    }
    return false
}

func appleMapVenueIdentifier(latitude: Double, longitude: Double, title: String) -> String {
    let latitudeText = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), latitude)
    let longitudeText = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), longitude)
    let slug = String(appleMapVenueTitleKey(title).prefix(40))
    return "apple:\(latitudeText):\(longitudeText):\(slug)"
}

func appleMapVenueAddress(title: String, parts: AppleMapAddressParts) -> String? {
    let street = appleMapStreetLine(thoroughfare: parts.thoroughfare, subThoroughfare: parts.subThoroughfare)
    let chinese = appleMapContainsCJK(title) || appleMapContainsCJK(street ?? "") || appleMapContainsCJK(parts.subLocality ?? "") || appleMapContainsCJK(parts.locality ?? "")
    var pieces: [String] = []
    func append(_ value: String?) {
        guard let cleaned = appleMapOptionalText(value), cleaned != title, !pieces.contains(cleaned) else {
            return
        }
        pieces.append(cleaned)
    }
    if chinese {
        append(parts.subLocality)
        append(street)
        if pieces.isEmpty {
            append(parts.locality)
        }
        if pieces.isEmpty {
            append(parts.administrativeArea)
        }
    } else {
        append(street)
        append(parts.subLocality)
        append(parts.locality)
        append(parts.administrativeArea)
    }
    let joined = chinese ? pieces.joined() : pieces.joined(separator: ", ")
    if joined.isEmpty {
        return nil
    }
    if joined.count > 180 {
        return String(joined.prefix(180))
    }
    return joined
}

func appleMapStreetLine(thoroughfare: String?, subThoroughfare: String?) -> String? {
    let street = appleMapOptionalText(thoroughfare)
    let number = appleMapOptionalText(subThoroughfare)
    switch (street, number) {
    case let (street?, number?):
        if appleMapContainsCJK(street) || appleMapContainsCJK(number) {
            if street.contains(number) {
                return street
            }
            return street + number
        }
        if number.count >= 2 && street.contains(number) {
            return street
        }
        return number + " " + street
    case let (street?, nil):
        return street
    case let (nil, number?):
        return number
    default:
        return nil
    }
}

func appleMapCoordinateIsUsable(latitude: Double, longitude: Double) -> Bool {
    if !latitude.isFinite || !longitude.isFinite {
        return false
    }
    if latitude < -90.0 || latitude > 90.0 || longitude < -180.0 || longitude > 180.0 {
        return false
    }
    if latitude == 0.0 && longitude == 0.0 {
        return false
    }
    return true
}

func appleMapDistanceMeters(fromLatitude: Double, fromLongitude: Double, toLatitude: Double, toLongitude: Double) -> Double {
    let earth = 6_371_000.0
    let lat1 = fromLatitude * Double.pi / 180.0
    let lat2 = toLatitude * Double.pi / 180.0
    let dLat = (toLatitude - fromLatitude) * Double.pi / 180.0
    let dLon = (toLongitude - fromLongitude) * Double.pi / 180.0
    let a = sin(dLat / 2.0) * sin(dLat / 2.0) + cos(lat1) * cos(lat2) * sin(dLon / 2.0) * sin(dLon / 2.0)
    let c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
    return earth * c
}

func appleMapVenueTitle(_ raw: String) -> String? {
    let text = appleMapCollapsedText(raw)
    if text.isEmpty {
        return nil
    }
    return text
}

func appleMapVenueTitleKey(_ title: String) -> String {
    return appleMapCollapsedText(title).lowercased(with: Locale(identifier: "en_US_POSIX"))
}

func appleMapContainsCJK(_ text: String) -> Bool {
    for scalar in text.unicodeScalars {
        let value = scalar.value
        if (0x3400...0x4DBF).contains(value) || (0x4E00...0x9FFF).contains(value) || (0xF900...0xFAFF).contains(value) {
            return true
        }
    }
    return false
}

private func appleMapVenuesSortedByDistance(_ drafts: [AppleMapVenueDraft], latitude: Double, longitude: Double, limit: Int) -> [AppleMapVenueDraft] {
    let sorted = drafts.sorted { lhs, rhs in
        let left = appleMapDistanceMeters(fromLatitude: latitude, fromLongitude: longitude, toLatitude: lhs.latitude, toLongitude: lhs.longitude)
        let right = appleMapDistanceMeters(fromLatitude: latitude, fromLongitude: longitude, toLatitude: rhs.latitude, toLongitude: rhs.longitude)
        if abs(left - right) > 1.0 {
            return left < right
        }
        if lhs.title != rhs.title {
            return lhs.title < rhs.title
        }
        return lhs.id < rhs.id
    }
    if limit >= 0 && sorted.count > limit {
        return Array(sorted.prefix(limit))
    }
    return sorted
}

private func appleMapOptionalText(_ raw: String?) -> String? {
    guard let raw else {
        return nil
    }
    let text = appleMapCollapsedText(raw)
    if text.isEmpty {
        return nil
    }
    return text
}

private func appleMapCollapsedText(_ raw: String) -> String {
    return raw.split(whereSeparator: { $0.isWhitespace }).map(String.init).joined(separator: " ")
}
