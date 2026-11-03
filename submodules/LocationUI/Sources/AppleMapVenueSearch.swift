import Foundation
import CoreLocation
import MapKit
import SwiftSignalKit
import TelegramCore

/// Places around a coordinate when the venue bot cannot be resolved or returns no venues.
/// Nearby uses `MKLocalPointsOfInterestRequest`. A text query uses `MKLocalSearch` biased to
/// that coordinate. Results are ordinary `TelegramMediaMap` venues (`provider` `apple`), so
/// the picker rows, category colors, and the send path stay the bot's.
/// MapKit's search requests have no preferred locale. Place names are Apple's local names
/// (a Chongqing restaurant stays Chinese). The empty nearby fallback query follows
/// `languageCode`, which is the UI language from `localeIdentifierLanguageCode`.
func appleMapVenueResults(peerId: EnginePeer.Id, latitude: Double, longitude: Double, query: String?, languageCode: String) -> Signal<ChatContextResultCollection?, NoError> {
    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let items: Signal<[MKMapItem], NoError>
    if !CLLocationCoordinate2DIsValid(coordinate) {
        items = .single([])
    } else if trimmed.isEmpty {
        items = appleNearbyMapItems(coordinate: coordinate, languageCode: languageCode)
    } else {
        items = appleTextMapItems(query: trimmed, coordinate: coordinate)
    }
    return items
    |> map { mapItems -> ChatContextResultCollection? in
        let venues = appleVenues(from: mapItems, around: coordinate, sortByDistance: trimmed.isEmpty)
        return appleVenueCollection(peerId: peerId, query: trimmed, latitude: latitude, longitude: longitude, venues: venues)
    }
}

private let appleNearbyRadius: CLLocationDistance = 2500
private let appleSearchSpan: CLLocationDistance = 100_000
private let appleVenueLimit = 20

private func appleNearbyMapItems(coordinate: CLLocationCoordinate2D, languageCode: String) -> Signal<[MKMapItem], NoError> {
    let pointsOfInterest = appleMapItems {
        let radius = min(appleNearbyRadius, MKLocalPointsOfInterestRequest.maxRadius)
        let request = MKLocalPointsOfInterestRequest(centerCoordinate: coordinate, radius: radius)
        request.pointOfInterestFilter = .includingAll
        return MKLocalSearch(request: request)
    }
    return pointsOfInterest
    |> mapToSignal { items -> Signal<[MKMapItem], NoError> in
        if !items.isEmpty {
            return .single(items)
        }
        let fallbackQuery = appleNearbyFallbackQuery(languageCode: languageCode)
        return appleMapItems {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = fallbackQuery
            request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: appleNearbyRadius * 2, longitudinalMeters: appleNearbyRadius * 2)
            request.resultTypes = .pointOfInterest
            return MKLocalSearch(request: request)
        }
    }
}

private func appleTextMapItems(query: String, coordinate: CLLocationCoordinate2D) -> Signal<[MKMapItem], NoError> {
    return appleMapItems {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: appleSearchSpan, longitudinalMeters: appleSearchSpan)
        request.resultTypes = [.pointOfInterest, .address]
        return MKLocalSearch(request: request)
    }
}

private func appleMapItems(makeSearch: @escaping () -> MKLocalSearch) -> Signal<[MKMapItem], NoError> {
    return Signal { subscriber in
        let search = makeSearch()
        search.start { response, _ in
            subscriber.putNext(response?.mapItems ?? [])
            subscriber.putCompletion()
        }
        return ActionDisposable {
            search.cancel()
        }
    }
}

private func appleNearbyFallbackQuery(languageCode: String) -> String {
    let code = languageCode.lowercased().replacingOccurrences(of: "_", with: "-")
    if code.hasPrefix("zh-hant") || code.hasPrefix("zh-tw") || code.hasPrefix("zh-hk") || code.hasPrefix("zh-mo") {
        return "餐飲"
    }
    if code == "zh" || code.hasPrefix("zh-") {
        return "餐饮"
    }
    return "restaurant"
}

private func appleVenues(from items: [MKMapItem], around coordinate: CLLocationCoordinate2D, sortByDistance: Bool) -> [TelegramMediaMap] {
    var seen = Set<String>()
    var venues: [TelegramMediaMap] = []
    for item in items {
        guard let venue = appleVenue(from: item), let id = venue.venue?.id, seen.insert(id).inserted else {
            continue
        }
        venues.append(venue)
    }
    if sortByDistance {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        venues.sort { lhs, rhs in
            let left = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude).distance(from: origin)
            let right = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude).distance(from: origin)
            if left == right {
                return (lhs.venue?.title ?? "") < (rhs.venue?.title ?? "")
            }
            return left < right
        }
    }
    if venues.count > appleVenueLimit {
        venues = Array(venues.prefix(appleVenueLimit))
    }
    return venues
}

private func appleVenue(from item: MKMapItem) -> TelegramMediaMap? {
    if item.isCurrentLocation {
        return nil
    }
    let placemark = item.placemark
    let coordinate = placemark.coordinate
    guard CLLocationCoordinate2DIsValid(coordinate), coordinate.latitude != 0 || coordinate.longitude != 0 else {
        return nil
    }
    let title = (item.name ?? placemark.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
    guard !title.isEmpty else {
        return nil
    }
    let address = venueAddress(from: placemark, title: title)
    let latitudeText = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), coordinate.latitude)
    let longitudeText = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), coordinate.longitude)
    let id = "apple:\(latitudeText):\(longitudeText):\(String(title.prefix(80)))"
    return TelegramMediaMap(
        latitude: coordinate.latitude,
        longitude: coordinate.longitude,
        heading: nil,
        accuracyRadius: nil,
        venue: MapVenue(title: title, address: address.isEmpty ? nil : address, provider: "apple", id: id, type: appleVenueType(for: item.pointOfInterestCategory)),
        liveBroadcastingTimeout: nil,
        liveProximityNotificationRadius: nil
    )
}

private func appleVenueCollection(peerId: EnginePeer.Id, query: String, latitude: Double, longitude: Double, venues: [TelegramMediaMap]) -> ChatContextResultCollection {
    let results: [ChatContextResult] = venues.map { venue in
        let id = venue.venue?.id ?? ""
        return .internalReference(ChatContextResult.InternalReference(
            queryId: 0,
            id: id,
            type: "venue",
            title: venue.venue?.title,
            description: venue.venue?.address,
            image: nil,
            file: nil,
            message: .mapLocation(media: venue, replyMarkup: nil)
        ))
    }
    return ChatContextResultCollection(
        botId: peerId,
        peerId: peerId,
        query: query,
        geoPoint: ChatContextResultCollection.GeoPoint(latitude: latitude, longitude: longitude),
        queryId: 0,
        nextOffset: nil,
        presentation: .list,
        switchPeer: nil,
        webView: nil,
        results: results,
        cacheTimeout: 0
    )
}

private func appleVenueType(for category: MKPointOfInterestCategory?) -> String {
    guard let category else {
        return "building/default"
    }
    if category == .cafe {
        return "food/cafe"
    }
    if [.restaurant, .bakery, .brewery, .winery, .foodMarket].contains(category) {
        return "food"
    }
    if category == .hotel {
        return "travel/hotel"
    }
    if [.park, .nationalPark, .beach, .campground].contains(category) {
        return "parks_outdoors"
    }
    if category == .nightlife {
        return "nightlife"
    }
    if [.hospital, .pharmacy].contains(category) {
        return "building/medical"
    }
    if [.fitnessCenter, .stadium].contains(category) {
        return "building/gym"
    }
    if [.school, .university, .library].contains(category) {
        return "education"
    }
    if [.museum, .movieTheater, .theater, .amusementPark, .aquarium, .zoo].contains(category) {
        return "arts_entertainment"
    }
    if category == .store {
        return "shops"
    }
    if [.airport, .publicTransport, .marina, .carRental, .gasStation].contains(category) {
        return "travel"
    }
    return "building/default"
}

private func venueAddress(from placemark: MKPlacemark, title: String) -> String {
    let street = streetLine(from: placemark)
    let chinese = containsCJK(title) || containsCJK(street ?? "") || containsCJK(placemark.subLocality ?? "") || containsCJK(placemark.locality ?? "")
    var parts: [String] = []
    func append(_ value: String?) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, value != title, !parts.contains(value) else {
            return
        }
        parts.append(value)
    }
    if chinese {
        append(placemark.subLocality)
        append(street)
        if parts.isEmpty {
            append(placemark.locality)
        }
        return parts.joined()
    }
    append(street)
    append(placemark.subLocality)
    append(placemark.locality)
    return parts.joined(separator: ", ")
}

private func streetLine(from placemark: MKPlacemark) -> String? {
    let street = trimmed(placemark.thoroughfare)
    let number = trimmed(placemark.subThoroughfare)
    switch (street, number) {
    case let (street?, number?):
        if containsCJK(street) || containsCJK(number) {
            return street + number
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

private func trimmed(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return value
}

private func containsCJK(_ text: String) -> Bool {
    for scalar in text.unicodeScalars {
        if (0x3400...0x4DBF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value) {
            return true
        }
    }
    return false
}
