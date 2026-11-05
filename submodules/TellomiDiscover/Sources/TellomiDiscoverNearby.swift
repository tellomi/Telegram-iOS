import Foundation

/// Nearby tab (D-11 / D-12). The bar is always 推荐 / 关注 / 同城.
/// A post stores a catalog city code in the existing `city` field.
/// A coordinate never becomes that code.
public func tellomiDiscoverHomeTabs() -> [TellomiDiscoverFeedKind] {
    return [.recommend, .following, .nearby]
}

/// True when `GET /v1/feed/config` did not name the nearby tab. The bar still shows it.
public func tellomiDiscoverEngineOmitsNearby(_ engineTabs: [TellomiDiscoverFeedKind]) -> Bool {
    return !engineTabs.contains(.nearby)
}

/// Catalog code for `city` on publish and on `GET /v1/feed/nearby`.
public func tellomiDiscoverPublishCity(_ raw: String?) -> String? {
    return tellomiDiscoverKnownCityCode(raw)
}

public func tellomiDiscoverNearbyDisplayName(_ raw: String?, languageCode: String, pack: [String: String] = [:]) -> String? {
    guard let code = tellomiDiscoverPublishCity(raw) else {
        return nil
    }
    return tellomiDiscoverCityName(code: code, languageCode: languageCode, pack: pack)
}

/// City-level line shown above the feed. A missing code uses the "no city" sentence.
/// A pack that still says `%s` (the Android format) is read as `%@`.
public func tellomiDiscoverComposeCityLine(_ raw: String?, languageCode: String, pack: [String: String] = [:]) -> String {
    let copy = TellomiDiscoverCopy.resolve(languageCode: languageCode, pack: pack)
    guard let name = tellomiDiscoverNearbyDisplayName(raw, languageCode: languageCode, pack: pack) else {
        return copy.composeCityNone
    }
    let pattern = copy.composeCity.replacingOccurrences(of: "%s", with: "%@")
    return tellomiFormatString(pattern, name)
}

/// The nearby route itself is absent. An empty 200 is a normal feed, not this.
public func tellomiDiscoverNearbyMissingEndpoint(_ status: Int) -> Bool {
    return status == 404 || status == 405 || status == 501
}

/// Names allowed on `GET /v1/feed/nearby`. Latitude is not one of them.
public func tellomiDiscoverNearbyQueryName(_ name: String) -> Bool {
    return name == "city" || name == "cursor"
}
