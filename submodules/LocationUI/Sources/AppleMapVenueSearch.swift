import Foundation
import CoreLocation
import MapKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext

/// Nearby places and venue text search when `venue_search_username` cannot be resolved
/// or returns no venues. The bot request still runs, in parallel, and is given
/// `appleMapVenueBotTimeout`. MapKit is `MKLocalPointsOfInterestRequest` (~2.5 km),
/// then one `MKLocalSearch` if that list is empty, and `MKLocalSearch` within ~100 km
/// for a text query. Rows are ordinary `TelegramMediaMap` venues (`provider` `apple`),
/// so the picker and `inputMediaVenue` stay the existing send path.
///
/// Disposal cancels the in-flight `MKLocalSearch`. A new coordinate replaces the
/// previous signal (`mapToSignal`), so a pan or a new query does not leave the old
/// request running. Starts are at least `appleMapVenueMinimumInterval` apart, and
/// `MKError.loadingThrottled` opens a cooldown instead of a second request.
/// The same query within `appleMapVenueCacheDistance` is served from memory.
/// Nothing here is written to disk, and nothing is requested except Apple and the
/// existing bot RPC.
func appleMapNearbyVenueSignal(context: AccountContext, story: Bool, latitude: Double, longitude: Double, query: String?) -> Signal<ChatContextResultCollection?, NoError> {
    let strings = context.sharedContext.currentPresentationData.with { $0 }.strings
    let primary = strings.primaryComponent.languageCode
    let languageCode = primary.isEmpty ? strings.baseLanguageCode : primary
    let apple = appleMapVenueDraftSignal(latitude: latitude, longitude: longitude, query: query, languageCode: languageCode)
    let bot = appleMapVenueBotSignal(context: context, story: story, latitude: latitude, longitude: longitude, query: query)
    |> timeout(appleMapVenueBotTimeout, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))
    return appleMapMergedVenueSignal(bot: bot, apple: apple, peerId: context.account.peerId, query: query ?? "", latitude: latitude, longitude: longitude)
}

private final class AppleMapVenueGate {
    static let shared = AppleMapVenueGate()

    private let lock = NSLock()
    private var state = AppleMapVenueGateState()

    func lookup(now: Double, latitude: Double, longitude: Double, query: String) -> AppleMapVenueLookup {
        self.lock.lock()
        let result = self.state.lookup(now: now, latitude: latitude, longitude: longitude, query: query)
        self.lock.unlock()
        return result
    }

    func store(now: Double, latitude: Double, longitude: Double, query: String, venues: [AppleMapVenueDraft]) {
        self.lock.lock()
        self.state.store(now: now, latitude: latitude, longitude: longitude, query: query, venues: venues)
        self.lock.unlock()
    }

    func noteThrottled(now: Double) {
        self.lock.lock()
        self.state.noteThrottled(now: now)
        self.lock.unlock()
    }

    func reserveExtraDelay(now: Double) -> Double {
        self.lock.lock()
        let delay = self.state.reserveStart(now: now)
        self.lock.unlock()
        return delay
    }
}

private struct AppleMapSearchPayload {
    var items: [MKMapItem]
    var throttled: Bool
    var failed: Bool
}

private struct AppleMapFetchedPlaces {
    var fields: [AppleMapPlacemarkFields]
    var throttled: Bool
    var failed: Bool
}

private final class AppleMapSearchRun {
    private let lock = NSLock()
    private var cancelled = false
    private var search: MKLocalSearch?

    func isCancelled() -> Bool {
        self.lock.lock()
        let value = self.cancelled
        self.lock.unlock()
        return value
    }

    func begin(_ search: MKLocalSearch) -> Bool {
        self.lock.lock()
        if self.cancelled {
            self.lock.unlock()
            search.cancel()
            return false
        }
        self.search = search
        self.lock.unlock()
        return true
    }

    func finish() {
        self.lock.lock()
        self.search = nil
        self.lock.unlock()
    }

    func cancel() {
        self.lock.lock()
        self.cancelled = true
        let search = self.search
        self.search = nil
        self.lock.unlock()
        search?.cancel()
    }
}

private final class AppleMapResolveState {
    var sawResult = false
}

private final class AppleMapVenueMerge {
    var bot: ChatContextResultCollection?
    var botReady = false
    var apple: [AppleMapVenueDraft] = []
    var appleReady = false
    var finished = false
    let lock = NSLock()
}

private func appleMapVenueDraftSignal(latitude: Double, longitude: Double, query: String?, languageCode: String) -> Signal<[AppleMapVenueDraft], NoError> {
    return Signal { subscriber in
        guard appleMapCoordinateIsUsable(latitude: latitude, longitude: longitude) else {
            subscriber.putNext([])
            subscriber.putCompletion()
            return EmptyDisposable
        }
        let trimmed = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let queryKey = appleMapVenueQueryKey(trimmed)
        let now = CFAbsoluteTimeGetCurrent()
        switch AppleMapVenueGate.shared.lookup(now: now, latitude: latitude, longitude: longitude, query: queryKey) {
        case let .cached(venues):
            subscriber.putNext(venues)
            subscriber.putCompletion()
            return EmptyDisposable
        case .coolingDown:
            subscriber.putNext([])
            subscriber.putCompletion()
            return EmptyDisposable
        case let .fetch(delay):
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            return appleMapFetchItems(coordinate: coordinate, query: trimmed, languageCode: languageCode, delay: delay).start(next: { places in
                let drafts = appleMapVenueDrafts(from: places.fields, latitude: latitude, longitude: longitude, limit: appleMapVenueLimit)
                if !places.throttled && !places.failed {
                    AppleMapVenueGate.shared.store(now: CFAbsoluteTimeGetCurrent(), latitude: latitude, longitude: longitude, query: queryKey, venues: drafts)
                }
                subscriber.putNext(drafts)
            }, completed: {
                subscriber.putCompletion()
            })
        }
    }
}

private func appleMapFetchItems(coordinate: CLLocationCoordinate2D, query: String, languageCode: String, delay: Double) -> Signal<AppleMapFetchedPlaces, NoError> {
    let payload: Signal<AppleMapSearchPayload, NoError>
    if query.isEmpty {
        payload = appleMapNearbyItems(coordinate: coordinate, languageCode: languageCode, delay: delay)
    } else {
        payload = appleMapPerformSearch(delay: delay, makeSearch: {
            return appleMapTextSearch(query: query, coordinate: coordinate)
        })
    }
    return payload
    |> map { result in
        return appleMapFetchedPlaces(from: result)
    }
}

private func appleMapNearbyItems(coordinate: CLLocationCoordinate2D, languageCode: String, delay: Double) -> Signal<AppleMapSearchPayload, NoError> {
    return appleMapPerformSearch(delay: delay, makeSearch: {
        return appleMapNearbySearch(coordinate: coordinate)
    })
    |> mapToSignal { payload in
        if !appleMapShouldRunNearbyFallback(itemCount: payload.items.count, throttled: payload.throttled) {
            return .single(payload)
        }
        let spacing = AppleMapVenueGate.shared.reserveExtraDelay(now: CFAbsoluteTimeGetCurrent())
        return appleMapPerformSearch(delay: spacing, makeSearch: {
            return appleMapFallbackSearch(coordinate: coordinate, languageCode: languageCode)
        })
    }
}

private func appleMapPerformSearch(delay: Double, makeSearch: @escaping () -> MKLocalSearch) -> Signal<AppleMapSearchPayload, NoError> {
    return Signal { subscriber in
        let run = AppleMapSearchRun()
        let start = {
            if run.isCancelled() {
                return
            }
            let search = makeSearch()
            guard run.begin(search) else {
                return
            }
            search.start { response, error in
                if run.isCancelled() {
                    return
                }
                run.finish()
                let throttled = appleMapSearchIsThrottled(error)
                if throttled {
                    AppleMapVenueGate.shared.noteThrottled(now: CFAbsoluteTimeGetCurrent())
                }
                let failed = error != nil && !throttled
                let items = (throttled || failed) ? [] : (response?.mapItems ?? [])
                subscriber.putNext(AppleMapSearchPayload(items: items, throttled: throttled, failed: failed))
                subscriber.putCompletion()
            }
        }
        let timerDisposable = MetaDisposable()
        if delay <= 0.0 && Queue.mainQueue().isCurrent() {
            start()
        } else if delay <= 0.0 {
            Queue.mainQueue().async {
                start()
            }
        } else {
            let timer = Timer(timeout: delay, repeat: false, completion: {
                start()
            }, queue: .mainQueue())
            timerDisposable.set(ActionDisposable {
                timer.invalidate()
            })
            timer.start()
        }
        return ActionDisposable {
            run.cancel()
            timerDisposable.dispose()
        }
    }
}

private func appleMapNearbySearch(coordinate: CLLocationCoordinate2D) -> MKLocalSearch {
    let radius = min(appleMapNearbyRadiusMeters, MKLocalPointsOfInterestRequest.maxRadius)
    let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radius)
    request.pointOfInterestFilter = .includingAll
    return MKLocalSearch(request: request)
}

private func appleMapFallbackSearch(coordinate: CLLocationCoordinate2D, languageCode: String) -> MKLocalSearch {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = appleMapNearbyFallbackQuery(languageCode: languageCode)
    let span = appleMapNearbyRadiusMeters * 2.0
    request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: span, longitudinalMeters: span)
    request.resultTypes = .pointOfInterest
    return MKLocalSearch(request: request)
}

private func appleMapTextSearch(query: String, coordinate: CLLocationCoordinate2D) -> MKLocalSearch {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: appleMapTextSearchSpanMeters, longitudinalMeters: appleMapTextSearchSpanMeters)
    request.resultTypes = [.pointOfInterest, .address]
    return MKLocalSearch(request: request)
}

private func appleMapSearchIsThrottled(_ error: Error?) -> Bool {
    guard let error = error as NSError? else {
        return false
    }
    return error.domain == MKErrorDomain && error.code == MKError.Code.loadingThrottled.rawValue
}

private func appleMapFetchedPlaces(from payload: AppleMapSearchPayload) -> AppleMapFetchedPlaces {
    if payload.throttled || payload.failed {
        return AppleMapFetchedPlaces(fields: [], throttled: payload.throttled, failed: true)
    }
    return AppleMapFetchedPlaces(fields: payload.items.compactMap(appleMapPlacemarkFields), throttled: false, failed: false)
}

/// MapKit's public coordinates are WGS-84, including in mainland China. The GCJ-02
/// offset is applied by the map renderer. A shared location from `CLLocation` and
/// the Apple Maps URL in `TellomiMapOpenIn` use that same value. Converting a search
/// result here would move the pin off the building on iOS and shift it a second time
/// for 高德 (`dev=1`), 百度 (`coord_type=wgs84`), and 腾讯. The stored point is the
/// coordinate MapKit returned, so an Android receiver plots the same building.
private func appleMapPlacemarkFields(from item: MKMapItem) -> AppleMapPlacemarkFields? {
    if item.isCurrentLocation {
        return nil
    }
    let placemark = item.placemark
    let coordinate = placemark.coordinate
    return AppleMapPlacemarkFields(
        latitude: coordinate.latitude,
        longitude: coordinate.longitude,
        name: item.name ?? placemark.name ?? "",
        thoroughfare: placemark.thoroughfare,
        subThoroughfare: placemark.subThoroughfare,
        subLocality: placemark.subLocality,
        locality: placemark.locality,
        administrativeArea: placemark.administrativeArea,
        category: appleMapVenueCategoryToken(item.pointOfInterestCategory)
    )
}

private func appleMapVenueCategoryToken(_ category: MKPointOfInterestCategory?) -> String? {
    guard let category else {
        return nil
    }
    if category == .cafe {
        return "cafe"
    }
    if category == .restaurant {
        return "restaurant"
    }
    if category == .bakery {
        return "bakery"
    }
    if category == .brewery {
        return "brewery"
    }
    if category == .winery {
        return "winery"
    }
    if category == .foodMarket {
        return "foodMarket"
    }
    if category == .hotel {
        return "hotel"
    }
    if category == .park {
        return "park"
    }
    if category == .nationalPark {
        return "nationalPark"
    }
    if category == .beach {
        return "beach"
    }
    if category == .campground {
        return "campground"
    }
    if category == .nightlife {
        return "nightlife"
    }
    if category == .hospital {
        return "hospital"
    }
    if category == .pharmacy {
        return "pharmacy"
    }
    if category == .fitnessCenter {
        return "fitnessCenter"
    }
    if category == .stadium {
        return "stadium"
    }
    if category == .school {
        return "school"
    }
    if category == .university {
        return "university"
    }
    if category == .library {
        return "library"
    }
    if category == .museum {
        return "museum"
    }
    if category == .movieTheater {
        return "movieTheater"
    }
    if category == .theater {
        return "theater"
    }
    if category == .amusementPark {
        return "amusementPark"
    }
    if category == .aquarium {
        return "aquarium"
    }
    if category == .zoo {
        return "zoo"
    }
    if category == .store {
        return "store"
    }
    if category == .airport {
        return "airport"
    }
    if category == .publicTransport {
        return "publicTransport"
    }
    if category == .marina {
        return "marina"
    }
    if category == .carRental {
        return "carRental"
    }
    if category == .gasStation {
        return "gasStation"
    }
    return nil
}

private func appleMapVenueBotSignal(context: AccountContext, story: Bool, latitude: Double, longitude: Double, query: String?) -> Signal<ChatContextResultCollection?, NoError> {
    let botUsername: Signal<String, NoError>
    if story {
        botUsername = context.engine.data.get(TelegramEngine.EngineData.Item.Configuration.App())
        |> map { appConfiguration in
            let storiesConfiguration = StoriesConfiguration.with(appConfiguration: appConfiguration)
            return storiesConfiguration.venueSearchBot
        }
    } else {
        botUsername = context.engine.data.get(TelegramEngine.EngineData.Item.Configuration.SearchBots())
        |> map { searchBotsConfiguration -> String in
            return searchBotsConfiguration.venueBotUsername ?? "foursquare"
        }
    }
    return botUsername
    |> mapToSignal { name in
        return appleMapResolvedPeer(context: context, name: name)
        |> mapToSignal { peer -> Signal<ChatContextResultCollection?, NoError> in
            guard let peer else {
                return .single(nil)
            }
            return context.engine.messages.requestChatContextResults(botId: peer.id, peerId: context.account.peerId, query: query ?? "", location: .single((latitude, longitude)), offset: "")
            |> map { results -> ChatContextResultCollection? in
                return results?.results
            }
            |> `catch` { _ -> Signal<ChatContextResultCollection?, NoError> in
                return .single(nil)
            }
        }
    }
}

private func appleMapResolvedPeer(context: AccountContext, name: String) -> Signal<EnginePeer?, NoError> {
    return Signal { subscriber in
        let state = AppleMapResolveState()
        return context.engine.peers.resolvePeerByName(name: name, referrer: nil).start(next: { result in
            guard case let .result(peer) = result else {
                return
            }
            state.sawResult = true
            subscriber.putNext(peer)
        }, completed: {
            if !state.sawResult {
                subscriber.putNext(nil)
            }
            subscriber.putCompletion()
        })
    }
}

private func appleMapMergedVenueSignal(bot: Signal<ChatContextResultCollection?, NoError>, apple: Signal<[AppleMapVenueDraft], NoError>, peerId: EnginePeer.Id, query: String, latitude: Double, longitude: Double) -> Signal<ChatContextResultCollection?, NoError> {
    return Signal { subscriber in
        let merge = AppleMapVenueMerge()
        let publish = {
            let snapshot: (ChatContextResultCollection, Bool)? = {
                merge.lock.lock()
                defer {
                    merge.lock.unlock()
                }
                if merge.finished {
                    return nil
                }
                let botDrafts = appleMapDrafts(from: merge.bot)
                let appleHasVenues = merge.appleReady && !merge.apple.isEmpty
                let botHasVenues = merge.botReady && !botDrafts.isEmpty
                let bothReady = merge.appleReady && merge.botReady
                if !appleHasVenues && !botHasVenues && !bothReady {
                    return nil
                }
                if bothReady {
                    merge.finished = true
                }
                let drafts = appleMapMergeVenues(bot: botDrafts, apple: merge.apple, latitude: latitude, longitude: longitude, limit: appleMapVenueLimit)
                let collection = appleMapVenueCollection(peerId: peerId, query: query, latitude: latitude, longitude: longitude, drafts: drafts)
                return (collection, bothReady)
            }()
            guard let snapshot else {
                return
            }
            subscriber.putNext(snapshot.0)
            if snapshot.1 {
                subscriber.putCompletion()
            }
        }
        let disposable = DisposableSet()
        disposable.add(bot.start(next: { value in
            merge.lock.lock()
            merge.bot = value
            merge.botReady = true
            merge.lock.unlock()
            publish()
        }, completed: {
            merge.lock.lock()
            let already = merge.botReady
            merge.botReady = true
            merge.lock.unlock()
            if !already {
                publish()
            }
        }))
        disposable.add(apple.start(next: { value in
            merge.lock.lock()
            merge.apple = value
            merge.appleReady = true
            merge.lock.unlock()
            publish()
        }, completed: {
            merge.lock.lock()
            let already = merge.appleReady
            merge.appleReady = true
            merge.lock.unlock()
            if !already {
                publish()
            }
        }))
        return disposable
    }
}

private func appleMapDrafts(from collection: ChatContextResultCollection?) -> [AppleMapVenueDraft] {
    guard let collection else {
        return []
    }
    var drafts: [AppleMapVenueDraft] = []
    for result in collection.results {
        guard case let .mapLocation(media, _) = result.message, let venue = media.venue else {
            continue
        }
        guard let title = appleMapVenueTitle(venue.title) else {
            continue
        }
        guard appleMapCoordinateIsUsable(latitude: media.latitude, longitude: media.longitude) else {
            continue
        }
        let identifier = venue.id ?? result.id
        drafts.append(AppleMapVenueDraft(
            latitude: media.latitude,
            longitude: media.longitude,
            title: title,
            address: venue.address,
            provider: venue.provider ?? "",
            id: identifier,
            type: venue.type ?? ""
        ))
    }
    return drafts
}

private func appleMapVenueCollection(peerId: EnginePeer.Id, query: String, latitude: Double, longitude: Double, drafts: [AppleMapVenueDraft]) -> ChatContextResultCollection {
    let results: [ChatContextResult] = drafts.map { draft in
        let identifier = draft.id.isEmpty ? "venue:\(draft.latitude):\(draft.longitude)" : draft.id
        let media = TelegramMediaMap(
            latitude: draft.latitude,
            longitude: draft.longitude,
            heading: nil,
            accuracyRadius: nil,
            venue: MapVenue(
                title: draft.title,
                address: draft.address,
                provider: draft.provider.isEmpty ? nil : draft.provider,
                id: identifier,
                type: draft.type.isEmpty ? nil : draft.type
            ),
            liveBroadcastingTimeout: nil,
            liveProximityNotificationRadius: nil
        )
        return .internalReference(ChatContextResult.InternalReference(
            queryId: 0,
            id: identifier,
            type: "venue",
            title: draft.title,
            description: draft.address,
            image: nil,
            file: nil,
            message: .mapLocation(media: media, replyMarkup: nil)
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
