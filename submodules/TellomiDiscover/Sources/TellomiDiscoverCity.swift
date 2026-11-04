import Foundation

/// A city the nearby feed and the post body can name. `code` is
/// `<iso country>:<english slug>`, such as `cn:chengdu`. Hong Kong, Macau, and
/// Taiwan use the `cn:` prefix (`cn:hong-kong`, `cn:macau`, `cn:taipei`).
public struct TellomiDiscoverCity: Equatable {
    public var code: String
    public var name: String

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

public enum TellomiDiscoverLocationGate: Equatable {
    case notDetermined
    case allowed
    case denied
}

public enum TellomiDiscoverNearbyGate: Equatable {
    /// A city is already chosen. Load `GET /v1/feed/nearby` and do not ask again.
    case feed(String)
    /// No city yet. `requestLocation` is true only the first time this tab is opened.
    case choose(requestLocation: Bool)
}

/// First entry to the nearby tab is the only time location is requested.
/// A denial, or a decision not to locate, stays on the city list.
public func tellomiDiscoverNearbyGate(city: String?, location: TellomiDiscoverLocationGate, asked: Bool) -> TellomiDiscoverNearbyGate {
    if let code = tellomiDiscoverKnownCityCode(city) {
        return .feed(code)
    }
    switch location {
    case .denied:
        return .choose(requestLocation: false)
    case .notDetermined, .allowed:
        return .choose(requestLocation: !asked)
    }
}

/// Format check for a city code. `hk:`, `tw:`, and `mo:` are rejected; those
/// places are `cn:hong-kong`, `cn:taipei`, and `cn:macau`.
public func tellomiDiscoverCityCode(_ raw: String?) -> String? {
    guard let raw else {
        return nil
    }
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard value.range(of: #"^[a-z]{2}:[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil else {
        return nil
    }
    let country = value.prefix(2)
    if country == "hk" || country == "tw" || country == "mo" {
        return nil
    }
    return value
}

/// A code this client will put on a post or a nearby request. Anything else
/// stays off the wire, including a street or a coordinate.
public func tellomiDiscoverKnownCityCode(_ raw: String?) -> String? {
    guard let code = tellomiDiscoverCityCode(raw) else {
        return nil
    }
    return tellomiDiscoverCityCatalog.contains(where: { $0.code == code }) ? code : nil
}

/// `CLPlacemark.locality` plus the ISO country. Street, region, and the
/// coordinate are not read. Hong Kong, Macau, and Taiwan map onto `cn:`.
public func tellomiDiscoverCityCode(locality: String?, isoCountryCode: String?) -> String? {
    guard let key = tellomiDiscoverLocalityKey(locality) else {
        return nil
    }
    let country = tellomiDiscoverCanonicalCountry(isoCountryCode)
    let matches = tellomiDiscoverCityCatalog.filter { record in
        record.keys.contains(key) && (country == nil || record.code.hasPrefix(country! + ":"))
    }
    guard matches.count == 1 else {
        return nil
    }
    return matches[0].code
}

public func tellomiDiscoverCityName(code: String, languageCode: String) -> String? {
    guard let code = tellomiDiscoverCityCode(code) else {
        return nil
    }
    if let record = tellomiDiscoverCityCatalog.first(where: { $0.code == code }) {
        return tellomiDiscoverCityLanguageIsChinese(languageCode) ? record.zh : record.en
    }
    let slug = code.split(separator: ":").last.map(String.init) ?? code
    return slug.split(separator: "-").map { part in
        guard let first = part.first else {
            return ""
        }
        return first.uppercased() + part.dropFirst()
    }.joined(separator: " ")
}

public func tellomiDiscoverCities(languageCode: String) -> [TellomiDiscoverCity] {
    let chinese = tellomiDiscoverCityLanguageIsChinese(languageCode)
    return tellomiDiscoverCityCatalog.map { record in
        TellomiDiscoverCity(code: record.code, name: chinese ? record.zh : record.en)
    }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
}

private struct TellomiDiscoverCityRecord {
    var code: String
    var zh: String
    var en: String
    var keys: Set<String>
}

private func tellomiDiscoverCityRecord(_ code: String, _ zh: String, _ en: String, _ extra: [String] = []) -> TellomiDiscoverCityRecord {
    var keys: Set<String> = []
    let slug = code.split(separator: ":").last.map(String.init) ?? ""
    for value in [zh, en, slug] + extra {
        if let key = tellomiDiscoverLocalityKey(value) {
            keys.insert(key)
        }
    }
    return TellomiDiscoverCityRecord(code: code, zh: zh, en: en, keys: keys)
}

private func tellomiDiscoverCityLanguageIsChinese(_ code: String) -> Bool {
    let value = code.lowercased()
    return value == "zh" || value.hasPrefix("zh-")
}

private func tellomiDiscoverCityLooksLikeCoordinate(_ value: String) -> Bool {
    return value.range(of: #"^-?\d{1,3}(\.\d+)?$"#, options: .regularExpression) != nil
}

private func tellomiDiscoverCanonicalCountry(_ isoCountryCode: String?) -> String? {
    guard let isoCountryCode else {
        return nil
    }
    let value = isoCountryCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard value.count == 2, value.allSatisfy({ $0.isASCII && $0.isLetter }) else {
        return nil
    }
    switch value {
    case "hk", "tw", "mo":
        return "cn"
    default:
        return value
    }
}

private func tellomiDiscoverLocalityKey(_ raw: String?) -> String? {
    guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    if tellomiDiscoverCityLooksLikeCoordinate(value) {
        return nil
    }
    value = value.replacingOccurrences(of: "臺", with: "台")
    let suffixes = ["特别行政区", "特別行政區", "市"]
    for suffix in suffixes where value.hasSuffix(suffix) && value.count > suffix.count {
        value.removeLast(suffix.count)
        break
    }
    let key = value.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "·" }
    guard !key.isEmpty, key.count <= 40 else {
        return nil
    }
    return key
}

private let tellomiDiscoverCityCatalog: [TellomiDiscoverCityRecord] = [
    tellomiDiscoverCityRecord("cn:beijing", "北京", "Beijing"),
    tellomiDiscoverCityRecord("cn:shanghai", "上海", "Shanghai"),
    tellomiDiscoverCityRecord("cn:tianjin", "天津", "Tianjin"),
    tellomiDiscoverCityRecord("cn:chongqing", "重庆", "Chongqing"),
    tellomiDiscoverCityRecord("cn:chengdu", "成都", "Chengdu"),
    tellomiDiscoverCityRecord("cn:hangzhou", "杭州", "Hangzhou"),
    tellomiDiscoverCityRecord("cn:ningbo", "宁波", "Ningbo"),
    tellomiDiscoverCityRecord("cn:nanjing", "南京", "Nanjing"),
    tellomiDiscoverCityRecord("cn:suzhou", "苏州", "Suzhou"),
    tellomiDiscoverCityRecord("cn:wuxi", "无锡", "Wuxi"),
    tellomiDiscoverCityRecord("cn:wuhan", "武汉", "Wuhan"),
    tellomiDiscoverCityRecord("cn:xian", "西安", "Xi'an", ["Xian"]),
    tellomiDiscoverCityRecord("cn:guangzhou", "广州", "Guangzhou"),
    tellomiDiscoverCityRecord("cn:shenzhen", "深圳", "Shenzhen"),
    tellomiDiscoverCityRecord("cn:zhuhai", "珠海", "Zhuhai"),
    tellomiDiscoverCityRecord("cn:dongguan", "东莞", "Dongguan"),
    tellomiDiscoverCityRecord("cn:foshan", "佛山", "Foshan"),
    tellomiDiscoverCityRecord("cn:changsha", "长沙", "Changsha"),
    tellomiDiscoverCityRecord("cn:zhengzhou", "郑州", "Zhengzhou"),
    tellomiDiscoverCityRecord("cn:qingdao", "青岛", "Qingdao"),
    tellomiDiscoverCityRecord("cn:jinan", "济南", "Jinan"),
    tellomiDiscoverCityRecord("cn:hefei", "合肥", "Hefei"),
    tellomiDiscoverCityRecord("cn:fuzhou", "福州", "Fuzhou"),
    tellomiDiscoverCityRecord("cn:xiamen", "厦门", "Xiamen"),
    tellomiDiscoverCityRecord("cn:kunming", "昆明", "Kunming"),
    tellomiDiscoverCityRecord("cn:guiyang", "贵阳", "Guiyang"),
    tellomiDiscoverCityRecord("cn:nanning", "南宁", "Nanning"),
    tellomiDiscoverCityRecord("cn:haikou", "海口", "Haikou"),
    tellomiDiscoverCityRecord("cn:sanya", "三亚", "Sanya"),
    tellomiDiscoverCityRecord("cn:shenyang", "沈阳", "Shenyang"),
    tellomiDiscoverCityRecord("cn:dalian", "大连", "Dalian"),
    tellomiDiscoverCityRecord("cn:harbin", "哈尔滨", "Harbin"),
    tellomiDiscoverCityRecord("cn:changchun", "长春", "Changchun"),
    tellomiDiscoverCityRecord("cn:shijiazhuang", "石家庄", "Shijiazhuang"),
    tellomiDiscoverCityRecord("cn:taiyuan", "太原", "Taiyuan"),
    tellomiDiscoverCityRecord("cn:nanchang", "南昌", "Nanchang"),
    tellomiDiscoverCityRecord("cn:lanzhou", "兰州", "Lanzhou"),
    tellomiDiscoverCityRecord("cn:yinchuan", "银川", "Yinchuan"),
    tellomiDiscoverCityRecord("cn:xining", "西宁", "Xining"),
    tellomiDiscoverCityRecord("cn:urumqi", "乌鲁木齐", "Urumqi"),
    tellomiDiscoverCityRecord("cn:hohhot", "呼和浩特", "Hohhot"),
    tellomiDiscoverCityRecord("cn:lhasa", "拉萨", "Lhasa"),
    tellomiDiscoverCityRecord("cn:hong-kong", "香港", "Hong Kong"),
    tellomiDiscoverCityRecord("cn:macau", "澳门", "Macau", ["Macao", "澳門"]),
    tellomiDiscoverCityRecord("cn:taipei", "台北", "Taipei"),
    tellomiDiscoverCityRecord("cn:kaohsiung", "高雄", "Kaohsiung"),
    tellomiDiscoverCityRecord("cn:taichung", "台中", "Taichung"),
    tellomiDiscoverCityRecord("cn:tainan", "台南", "Tainan"),
    tellomiDiscoverCityRecord("us:new-york", "纽约", "New York"),
    tellomiDiscoverCityRecord("us:los-angeles", "洛杉矶", "Los Angeles"),
    tellomiDiscoverCityRecord("us:san-francisco", "旧金山", "San Francisco"),
    tellomiDiscoverCityRecord("gb:london", "伦敦", "London"),
    tellomiDiscoverCityRecord("jp:tokyo", "东京", "Tokyo"),
    tellomiDiscoverCityRecord("jp:osaka", "大阪", "Osaka"),
    tellomiDiscoverCityRecord("kr:seoul", "首尔", "Seoul"),
    tellomiDiscoverCityRecord("sg:singapore", "新加坡", "Singapore"),
    tellomiDiscoverCityRecord("fr:paris", "巴黎", "Paris"),
    tellomiDiscoverCityRecord("de:berlin", "柏林", "Berlin"),
    tellomiDiscoverCityRecord("au:sydney", "悉尼", "Sydney"),
    tellomiDiscoverCityRecord("ca:toronto", "多伦多", "Toronto"),
    tellomiDiscoverCityRecord("th:bangkok", "曼谷", "Bangkok")
]
