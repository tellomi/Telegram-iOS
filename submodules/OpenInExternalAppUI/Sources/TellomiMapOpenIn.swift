import Foundation
import UrlEscaping

// Chinese map apps on a shared location or venue.
// Telegram stores WGS-84. 高德 and 腾讯 draw GCJ-02; 百度 draws BD-09.
// Apple Maps in China already offsets a WGS-84 coordinate, so that path stays unconverted.

let tellomiOpenInSystemLangPackDefaultsKey = "TellomiDidApplySystemLangPack"

let tellomiAppleMapsOpenInIdentifier = "appleMaps"
let tellomiAmapOpenInIdentifier = "amap"
let tellomiBaiduMapsOpenInIdentifier = "baiduMaps"
let tellomiTencentMapsOpenInIdentifier = "tencentMaps"

let tellomiAmapURLScheme = "iosamap"
let tellomiBaiduMapURLScheme = "baidumap"
let tellomiTencentMapURLScheme = "qqmap"

let tellomiAmapAppStoreIdentifier: Int64 = 461703208
let tellomiBaiduMapsAppStoreIdentifier: Int64 = 452186370
let tellomiTencentMapsAppStoreIdentifier: Int64 = 481623196

let tellomiMapOpenInSourceName = "Tellomi"
let tellomiBaiduMapOpenInSource = "ios.tellomi.chat"

enum TellomiOpenInMapApp {
    case apple
    case amap
    case baidu
    case tencent
    case google
}

enum TellomiMapTravelMode {
    case driving
    case walking
    case transit
}

func tellomiLocationOpenInSortRank(_ identifier: String) -> Int {
    switch identifier {
    case tellomiAppleMapsOpenInIdentifier:
        return 0
    case tellomiAmapOpenInIdentifier:
        return 1
    case tellomiBaiduMapsOpenInIdentifier:
        return 2
    case tellomiTencentMapsOpenInIdentifier:
        return 3
    default:
        return 100
    }
}

func tellomiOrderedLocationOpenInIdentifiers(_ identifiers: [String]) -> [String] {
    return identifiers.enumerated().sorted { lhs, rhs in
        let leftRank = tellomiLocationOpenInSortRank(lhs.element)
        let rightRank = tellomiLocationOpenInSortRank(rhs.element)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
}

/// Simplified Chinese for zh-Hans (and the other mainland `zh*` codes). English otherwise.
/// Traditional codes stay on the English names. The bundled pack is English, and the
/// server langpack has no keys for these apps, so the label is chosen here.
func tellomiOpenInMapLabelsUseChinese(_ languageCode: String) -> Bool {
    let language = languageCode.lowercased()
    if language.hasPrefix("zh-hant") || language.hasPrefix("zh-tw") || language.hasPrefix("zh-hk") || language.hasPrefix("zh-mo") {
        return false
    }
    if language == "zh" || language.hasPrefix("zh-hans") || language.hasPrefix("zh-cn") || language.hasPrefix("zh-") {
        return true
    }
    return false
}

func tellomiOpenInMapAppTitle(_ app: TellomiOpenInMapApp, languageCode: String) -> String {
    let chinese = tellomiOpenInMapLabelsUseChinese(languageCode)
    switch app {
    case .apple:
        return chinese ? "地图" : "Maps"
    case .amap:
        return chinese ? "高德地图" : "Amap"
    case .baidu:
        return chinese ? "百度地图" : "Baidu Maps"
    case .tencent:
        return chinese ? "腾讯地图" : "Tencent Maps"
    case .google:
        return chinese ? "谷歌地图" : "Google Maps"
    }
}

/// Same choice as the login chrome: the saved pack wins once it has been applied.
/// Until then a Chinese system language is used, because the bundle only ships `en`.
func tellomiOpenInLanguageCode(savedLanguageCode: String, systemLanguages: [String], systemLangPackApplied: Bool) -> String {
    if systemLangPackApplied {
        return savedLanguageCode
    }
    let saved = savedLanguageCode.lowercased()
    if saved == "zh" || saved.hasPrefix("zh-") {
        return savedLanguageCode
    }
    if let first = systemLanguages.first?.lowercased(), first == "zh" || first.hasPrefix("zh-") {
        return systemLanguages[0]
    }
    return savedLanguageCode
}

func tellomiMapCoordinateText(_ value: Double) -> String {
    return String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), arguments: [value])
}

func tellomiMapQueryValue(_ value: String) -> String {
    var allowed = CharacterSet.urlQueryValueAllowed
    allowed.remove(charactersIn: " |/?\\")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
}

/// Published vector from the coordtransform WGS-84 → GCJ-02 transform:
/// (longitude 116.404, latitude 39.915) → (116.41024449916938, 39.91640428150164).
/// Outside the China box the input is returned unchanged.
func tellomiWgs84ToGcj02(latitude: Double, longitude: Double) -> (latitude: Double, longitude: Double) {
    if tellomiGcjOutOfChina(latitude: latitude, longitude: longitude) {
        return (latitude, longitude)
    }
    let pi = 3.1415926535897932384626
    let a = 6378245.0
    let ee = 0.00669342162296594323
    var dLat = tellomiGcjTransformLatitude(longitude - 105.0, latitude - 35.0)
    var dLon = tellomiGcjTransformLongitude(longitude - 105.0, latitude - 35.0)
    let radLat = latitude / 180.0 * pi
    var magic = sin(radLat)
    magic = 1 - ee * magic * magic
    let sqrtMagic = sqrt(magic)
    dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * pi)
    dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * pi)
    return (latitude + dLat, longitude + dLon)
}

/// Show a point (`viewMap`) or directions from the current location (`path`).
/// `dev=1` tells 高德 the coordinates are WGS-84 and it should apply the GCJ-02 offset.
func tellomiAmapURL(latitude: Double, longitude: Double, name: String, mode: TellomiMapTravelMode?) -> String {
    let lat = tellomiMapCoordinateText(latitude)
    let lon = tellomiMapCoordinateText(longitude)
    if let mode = mode {
        var items = [
            "sourceApplication=\(tellomiMapOpenInSourceName)",
            "dlat=\(lat)",
            "dlon=\(lon)"
        ]
        if !name.isEmpty {
            items.append("dname=\(tellomiMapQueryValue(name))")
        }
        items.append("dev=1")
        items.append("t=\(tellomiAmapTravelCode(mode))")
        return "iosamap://path?\(items.joined(separator: "&"))"
    }
    var items = ["sourceApplication=\(tellomiMapOpenInSourceName)"]
    if !name.isEmpty {
        items.append("poiname=\(tellomiMapQueryValue(name))")
    }
    items.append("lat=\(lat)")
    items.append("lon=\(lon)")
    items.append("dev=1")
    return "iosamap://viewMap?\(items.joined(separator: "&"))"
}

/// `coord_type=wgs84` keeps the Telegram coordinate. Baidu converts it.
/// Directions start at 我的位置, which the app treats as the device location.
func tellomiBaiduMapURL(latitude: Double, longitude: Double, name: String, address: String, mode: TellomiMapTravelMode?) -> String {
    let lat = tellomiMapCoordinateText(latitude)
    let lon = tellomiMapCoordinateText(longitude)
    if let mode = mode {
        let destination: String
        if name.isEmpty {
            destination = "\(lat),\(lon)"
        } else {
            destination = "latlng:\(lat),\(lon)%7Cname:\(tellomiMapQueryValue(name))"
        }
        let items = [
            "origin=\(tellomiMapQueryValue("我的位置"))",
            "destination=\(destination)",
            "mode=\(tellomiBaiduTravelMode(mode))",
            "coord_type=wgs84",
            "src=\(tellomiBaiduMapOpenInSource)"
        ]
        return "baidumap://map/direction?\(items.joined(separator: "&"))"
    }
    let title = name.isEmpty ? "\(lat),\(lon)" : name
    let content = address.isEmpty ? title : address
    let items = [
        "location=\(lat),\(lon)",
        "title=\(tellomiMapQueryValue(title))",
        "content=\(tellomiMapQueryValue(content))",
        "coord_type=wgs84",
        "src=\(tellomiBaiduMapOpenInSource)"
    ]
    return "baidumap://map/marker?\(items.joined(separator: "&"))"
}

/// The mobile `qqmap://` marker and routeplan calls are GCJ-02 and have no coordinate-type
/// parameter (that parameter is on the web URI). The point is converted here.
/// `referer` is the app name. The mobile guide asks for a developer key; we do not have one.
func tellomiTencentMapURL(latitude: Double, longitude: Double, name: String, address: String, mode: TellomiMapTravelMode?) -> String {
    let gcj = tellomiWgs84ToGcj02(latitude: latitude, longitude: longitude)
    let lat = tellomiMapCoordinateText(gcj.latitude)
    let lon = tellomiMapCoordinateText(gcj.longitude)
    if let mode = mode {
        var items = [
            "type=\(tellomiTencentTravelType(mode))",
            "fromcoord=CurrentLocation"
        ]
        if !name.isEmpty {
            items.append("to=\(tellomiMapQueryValue(name))")
        }
        items.append("tocoord=\(lat),\(lon)")
        items.append("referer=\(tellomiMapOpenInSourceName)")
        return "qqmap://map/routeplan?\(items.joined(separator: "&"))"
    }
    if name.isEmpty {
        return "qqmap://map/geocoder?coord=\(lat),\(lon)&referer=\(tellomiMapOpenInSourceName)"
    }
    var marker = "coord:\(lat),\(lon);title:\(tellomiMapQueryValue(name))"
    if !address.isEmpty {
        marker += ";addr:\(tellomiMapQueryValue(address))"
    }
    return "qqmap://map/marker?marker=\(marker)&referer=\(tellomiMapOpenInSourceName)"
}

private func tellomiAmapTravelCode(_ mode: TellomiMapTravelMode) -> String {
    switch mode {
    case .driving:
        return "0"
    case .transit:
        return "1"
    case .walking:
        return "2"
    }
}

private func tellomiBaiduTravelMode(_ mode: TellomiMapTravelMode) -> String {
    switch mode {
    case .driving:
        return "driving"
    case .transit:
        return "transit"
    case .walking:
        return "walking"
    }
}

private func tellomiTencentTravelType(_ mode: TellomiMapTravelMode) -> String {
    switch mode {
    case .driving:
        return "drive"
    case .transit:
        return "bus"
    case .walking:
        return "walk"
    }
}

private func tellomiGcjOutOfChina(latitude: Double, longitude: Double) -> Bool {
    if longitude < 72.004 || longitude > 137.8347 {
        return true
    }
    if latitude < 0.8293 || latitude > 55.8271 {
        return true
    }
    return false
}

private func tellomiGcjTransformLatitude(_ longitude: Double, _ latitude: Double) -> Double {
    let pi = 3.1415926535897932384626
    var ret = -100.0 + 2.0 * longitude + 3.0 * latitude + 0.2 * latitude * latitude + 0.1 * longitude * latitude + 0.2 * sqrt(abs(longitude))
    ret += (20.0 * sin(6.0 * longitude * pi) + 20.0 * sin(2.0 * longitude * pi)) * 2.0 / 3.0
    ret += (20.0 * sin(latitude * pi) + 40.0 * sin(latitude / 3.0 * pi)) * 2.0 / 3.0
    ret += (160.0 * sin(latitude / 12.0 * pi) + 320.0 * sin(latitude * pi / 30.0)) * 2.0 / 3.0
    return ret
}

private func tellomiGcjTransformLongitude(_ longitude: Double, _ latitude: Double) -> Double {
    let pi = 3.1415926535897932384626
    var ret = 300.0 + longitude + 2.0 * latitude + 0.1 * longitude * longitude + 0.1 * longitude * latitude + 0.1 * sqrt(abs(longitude))
    ret += (20.0 * sin(6.0 * longitude * pi) + 20.0 * sin(2.0 * longitude * pi)) * 2.0 / 3.0
    ret += (20.0 * sin(longitude * pi) + 40.0 * sin(longitude / 3.0 * pi)) * 2.0 / 3.0
    ret += (150.0 * sin(longitude / 12.0 * pi) + 300.0 * sin(longitude / 30.0 * pi)) * 2.0 / 3.0
    return ret
}
