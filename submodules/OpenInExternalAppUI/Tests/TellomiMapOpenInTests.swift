import XCTest

final class TellomiMapOpenInTests: XCTestCase {
    private let latitude = 39.908692
    private let longitude = 116.397477
    private let placeName = "天安门"
    private let encodedName = "%E5%A4%A9%E5%AE%89%E9%97%A8"
    private let address = "东城区"
    private let encodedAddress = "%E4%B8%9C%E5%9F%8E%E5%8C%BA"

    func testWgs84ToGcj02MatchesThePublishedVectorAndStaysPutOutsideChina() {
        let converted = tellomiWgs84ToGcj02(latitude: 39.915, longitude: 116.404)
        XCTAssertEqual(converted.longitude, 116.41024449916938, accuracy: 1.0e-8)
        XCTAssertEqual(converted.latitude, 39.91640428150164, accuracy: 1.0e-8)

        let london = tellomiWgs84ToGcj02(latitude: 51.5074, longitude: -0.1278)
        XCTAssertEqual(london.latitude, 51.5074)
        XCTAssertEqual(london.longitude, -0.1278)

        let ocean = tellomiWgs84ToGcj02(latitude: 0.0, longitude: 0.0)
        XCTAssertEqual(ocean.latitude, 0.0)
        XCTAssertEqual(ocean.longitude, 0.0)

        let beijing = tellomiWgs84ToGcj02(latitude: self.latitude, longitude: self.longitude)
        XCTAssertNotEqual(beijing.latitude, self.latitude)
        XCTAssertNotEqual(beijing.longitude, self.longitude)
    }

    func testAmapPassesWgs84WithDev1AndThePlaceName() {
        let lat = tellomiMapCoordinateText(self.latitude)
        let lon = tellomiMapCoordinateText(self.longitude)
        XCTAssertEqual(
            tellomiAmapURL(latitude: self.latitude, longitude: self.longitude, name: self.placeName, mode: nil),
            "iosamap://viewMap?sourceApplication=Tellomi&poiname=\(self.encodedName)&lat=\(lat)&lon=\(lon)&dev=1"
        )
        XCTAssertEqual(
            tellomiAmapURL(latitude: self.latitude, longitude: self.longitude, name: "", mode: nil),
            "iosamap://viewMap?sourceApplication=Tellomi&lat=\(lat)&lon=\(lon)&dev=1"
        )
        XCTAssertEqual(
            tellomiAmapURL(latitude: self.latitude, longitude: self.longitude, name: self.placeName, mode: .driving),
            "iosamap://path?sourceApplication=Tellomi&dlat=\(lat)&dlon=\(lon)&dname=\(self.encodedName)&dev=1&t=0"
        )
        XCTAssertEqual(
            tellomiAmapURL(latitude: self.latitude, longitude: self.longitude, name: self.placeName, mode: .transit),
            "iosamap://path?sourceApplication=Tellomi&dlat=\(lat)&dlon=\(lon)&dname=\(self.encodedName)&dev=1&t=1"
        )
        XCTAssertEqual(
            tellomiAmapURL(latitude: self.latitude, longitude: self.longitude, name: self.placeName, mode: .walking),
            "iosamap://path?sourceApplication=Tellomi&dlat=\(lat)&dlon=\(lon)&dname=\(self.encodedName)&dev=1&t=2"
        )
        let shown = tellomiAmapURL(latitude: self.latitude, longitude: self.longitude, name: self.placeName, mode: nil)
        XCTAssertFalse(shown.contains("dev=0"))
        let gcj = tellomiWgs84ToGcj02(latitude: self.latitude, longitude: self.longitude)
        XCTAssertFalse(shown.contains(tellomiMapCoordinateText(gcj.latitude)))
    }

    func testBaiduPassesWgs84WithCoordTypeAndThePlaceName() {
        let lat = tellomiMapCoordinateText(self.latitude)
        let lon = tellomiMapCoordinateText(self.longitude)
        XCTAssertEqual(
            tellomiBaiduMapURL(latitude: self.latitude, longitude: self.longitude, name: self.placeName, address: self.address, mode: nil),
            "baidumap://map/marker?location=\(lat),\(lon)&title=\(self.encodedName)&content=\(self.encodedAddress)&coord_type=wgs84&src=ios.tellomi.chat"
        )
        XCTAssertEqual(
            tellomiBaiduMapURL(latitude: self.latitude, longitude: self.longitude, name: self.placeName, address: self.address, mode: .driving),
            "baidumap://map/direction?origin=%E6%88%91%E7%9A%84%E4%BD%8D%E7%BD%AE&destination=latlng:\(lat),\(lon)%7Cname:\(self.encodedName)&mode=driving&coord_type=wgs84&src=ios.tellomi.chat"
        )
        XCTAssertTrue(tellomiBaiduMapURL(latitude: self.latitude, longitude: self.longitude, name: self.placeName, address: "", mode: .walking).contains("mode=walking"))
        XCTAssertTrue(tellomiBaiduMapURL(latitude: self.latitude, longitude: self.longitude, name: self.placeName, address: "", mode: .transit).contains("mode=transit"))
        let unnamed = tellomiBaiduMapURL(latitude: self.latitude, longitude: self.longitude, name: "", address: "", mode: .driving)
        XCTAssertTrue(unnamed.contains("destination=\(lat),\(lon)"))
        XCTAssertFalse(unnamed.contains("name:"))
        let shown = tellomiBaiduMapURL(latitude: self.latitude, longitude: self.longitude, name: self.placeName, address: self.address, mode: nil)
        XCTAssertFalse(shown.contains("gcj02"))
        XCTAssertFalse(shown.contains("bd09"))
    }

    func testTencentUsesGcj02AndThePlaceName() {
        let gcj = tellomiWgs84ToGcj02(latitude: self.latitude, longitude: self.longitude)
        let lat = tellomiMapCoordinateText(gcj.latitude)
        let lon = tellomiMapCoordinateText(gcj.longitude)
        let wgs = "\(tellomiMapCoordinateText(self.latitude)),\(tellomiMapCoordinateText(self.longitude))"
        XCTAssertNotEqual("\(lat),\(lon)", wgs)

        let marker = tellomiTencentMapURL(latitude: self.latitude, longitude: self.longitude, name: self.placeName, address: self.address, mode: nil)
        XCTAssertEqual(
            marker,
            "qqmap://map/marker?marker=coord:\(lat),\(lon);title:\(self.encodedName);addr:\(self.encodedAddress)&referer=Tellomi"
        )
        XCTAssertFalse(marker.contains(wgs))

        XCTAssertEqual(
            tellomiTencentMapURL(latitude: self.latitude, longitude: self.longitude, name: "", address: "", mode: nil),
            "qqmap://map/geocoder?coord=\(lat),\(lon)&referer=Tellomi"
        )
        XCTAssertEqual(
            tellomiTencentMapURL(latitude: self.latitude, longitude: self.longitude, name: self.placeName, address: "", mode: .driving),
            "qqmap://map/routeplan?type=drive&fromcoord=CurrentLocation&to=\(self.encodedName)&tocoord=\(lat),\(lon)&referer=Tellomi"
        )
        XCTAssertTrue(tellomiTencentMapURL(latitude: self.latitude, longitude: self.longitude, name: self.placeName, address: "", mode: .walking).contains("type=walk"))
        XCTAssertTrue(tellomiTencentMapURL(latitude: self.latitude, longitude: self.longitude, name: self.placeName, address: "", mode: .transit).contains("type=bus"))
        let walk = tellomiTencentMapURL(latitude: self.latitude, longitude: self.longitude, name: self.placeName, address: "", mode: .walking)
        XCTAssertFalse(walk.contains(wgs))
    }

    func testLabelsFollowZhHansAndEnglish() {
        XCTAssertEqual(tellomiOpenInMapAppTitle(.amap, languageCode: "zh-hans"), "高德地图")
        XCTAssertEqual(tellomiOpenInMapAppTitle(.baidu, languageCode: "zh-Hans"), "百度地图")
        XCTAssertEqual(tellomiOpenInMapAppTitle(.tencent, languageCode: "zh-CN"), "腾讯地图")
        XCTAssertEqual(tellomiOpenInMapAppTitle(.apple, languageCode: "zh"), "地图")
        XCTAssertEqual(tellomiOpenInMapAppTitle(.google, languageCode: "zh-hans"), "谷歌地图")

        XCTAssertEqual(tellomiOpenInMapAppTitle(.amap, languageCode: "en"), "Amap")
        XCTAssertEqual(tellomiOpenInMapAppTitle(.baidu, languageCode: "en"), "Baidu Maps")
        XCTAssertEqual(tellomiOpenInMapAppTitle(.tencent, languageCode: "en-US"), "Tencent Maps")
        XCTAssertEqual(tellomiOpenInMapAppTitle(.apple, languageCode: "en"), "Maps")
        XCTAssertEqual(tellomiOpenInMapAppTitle(.google, languageCode: "en"), "Google Maps")
        XCTAssertEqual(tellomiOpenInMapAppTitle(.amap, languageCode: "zh-hant"), "Amap")
        XCTAssertEqual(tellomiOpenInMapAppTitle(.baidu, languageCode: "zh-TW"), "Baidu Maps")
    }

    func testLanguageFollowsTheSavedPackAfterItIsApplied() {
        XCTAssertEqual(
            tellomiOpenInLanguageCode(savedLanguageCode: "en", systemLanguages: ["zh-Hans-CN", "en"], systemLangPackApplied: false),
            "zh-Hans-CN"
        )
        XCTAssertEqual(
            tellomiOpenInLanguageCode(savedLanguageCode: "en", systemLanguages: ["zh-Hans-CN"], systemLangPackApplied: true),
            "en"
        )
        XCTAssertEqual(
            tellomiOpenInLanguageCode(savedLanguageCode: "zh-hans", systemLanguages: ["en"], systemLangPackApplied: false),
            "zh-hans"
        )
        XCTAssertEqual(
            tellomiOpenInLanguageCode(savedLanguageCode: "en", systemLanguages: [], systemLangPackApplied: false),
            "en"
        )
    }

    func testOrderIsAppleThenChineseAppsThenTheRest() {
        let installed = ["googleMaps", "foursquare", "appleMaps", "tencentMaps", "waze", "baiduMaps", "amap"]
        XCTAssertEqual(
            tellomiOrderedLocationOpenInIdentifiers(installed),
            ["appleMaps", "amap", "baiduMaps", "tencentMaps", "googleMaps", "foursquare", "waze"]
        )
        let noneInstalled = ["appleMaps", "googleMaps", "yandexMaps"]
        XCTAssertEqual(
            tellomiOrderedLocationOpenInIdentifiers(noneInstalled),
            ["appleMaps", "googleMaps", "yandexMaps"]
        )
        XCTAssertEqual(tellomiAmapURLScheme, "iosamap")
        XCTAssertEqual(tellomiBaiduMapURLScheme, "baidumap")
        XCTAssertEqual(tellomiTencentMapURLScheme, "qqmap")
    }
}
