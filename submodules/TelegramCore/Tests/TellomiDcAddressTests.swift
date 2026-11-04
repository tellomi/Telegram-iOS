import XCTest
@testable import TelegramCore

/// Pins the same literals as Android `TMessagesProj/tellomi/check_dc_address.cpp`
/// (tellomi/Telegram #52). Comparisons use structs, not tuples.
final class TellomiDcAddressTests: XCTestCase {
    private let ipv6Flag = 1 << 0
    private let mediaFlag = 1 << 1
    private let tcpFlag = 1 << 2
    private let cdnFlag = 1 << 3
    private let staticFlag = 1 << 4

    private func option(datacenterId: Int = 1, host: String, port: Int = 10443, flags: Int = 0, secret: Data? = nil) -> TellomiDcOptionInput {
        return TellomiDcOptionInput(datacenterId: datacenterId, host: host, port: port, flags: flags, secret: secret)
    }

    private func accepted(_ options: [TellomiDcOptionInput]) -> [TellomiAcceptedDcAddress] {
        return tellomiAcceptedDatacenterAddresses(options)[1] ?? []
    }

    func testProductionLiteralsMatchAndroid() {
        XCTAssertTrue(tellomiAcceptDcAddress(host: "8.137.39.82", port: 10443, ipv6: false))
        XCTAssertTrue(tellomiAcceptDcAddress(host: "8.137.39.82", port: 5222, ipv6: false))
        XCTAssertTrue(tellomiAcceptDcAddress(host: "10.0.2.2", port: 10443, ipv6: false))
        XCTAssertTrue(tellomiAcceptDcAddress(host: "127.0.0.1", port: 10443, ipv6: false))
        XCTAssertTrue(tellomiAcceptDcAddress(host: "2001:db8::1", port: 10443, ipv6: true))
        XCTAssertFalse(tellomiAcceptDcAddress(host: "api.tellomi.cn", port: 10443, ipv6: false))
        XCTAssertFalse(tellomiAcceptDcAddress(host: "api.tellomi.cn", port: 10443, ipv6: true))
        XCTAssertFalse(tellomiAcceptDcAddress(host: "8.137.39.82", port: 10443, ipv6: true))
        XCTAssertFalse(tellomiAcceptDcAddress(host: "2001:db8::1", port: 10443, ipv6: false))
        XCTAssertFalse(tellomiAcceptDcAddress(host: "8.137.39.82:10443", port: 10443, ipv6: false))
        XCTAssertFalse(tellomiAcceptDcAddress(host: "[2001:db8::1]", port: 10443, ipv6: true))
        XCTAssertFalse(tellomiAcceptDcAddress(host: "", port: 10443, ipv6: false))
        XCTAssertFalse(tellomiAcceptDcAddress(host: "8.137.39.82", port: 0, ipv6: false))
        XCTAssertFalse(tellomiAcceptDcAddress(host: "8.137.39.82", port: 65536, ipv6: false))
        XCTAssertFalse(tellomiAcceptDcAddress(host: " 8.137.39.82", port: 10443, ipv6: false))
        XCTAssertTrue(tellomiAcceptDcAddress(host: "8.137.39.82", port: 65535, ipv6: false))
        XCTAssertFalse(tellomiAcceptDcAddress(host: "8.137.39.82", port: -1, ipv6: false))
    }

    func testEmptyConfigDoesNotReplace() {
        XCTAssertTrue(tellomiAcceptedDatacenterAddresses([]).isEmpty)
    }

    func testHostnameOnlyDoesNotReplace() {
        let lists = tellomiAcceptedDatacenterAddresses([
            option(host: "api.tellomi.cn"),
            option(datacenterId: 2, host: "api.tellomi.cn", port: 5222)
        ])
        XCTAssertTrue(lists.isEmpty)
    }

    func testIpLiteralReplacesAndKeepsBothPorts() {
        let list = accepted([
            option(host: "8.137.39.82", port: 10443),
            option(host: "8.137.39.82", port: 5222)
        ])
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].host, "8.137.39.82")
        XCTAssertEqual(list[0].port, UInt16(10443))
        XCTAssertEqual(list[1].host, "8.137.39.82")
        XCTAssertEqual(list[1].port, UInt16(5222))
        XCTAssertFalse(list[0].preferForMedia)
    }

    func testHostnameIsDroppedWhenAnIpRemains() {
        let lists = tellomiAcceptedDatacenterAddresses([
            option(host: "api.tellomi.cn"),
            option(host: "8.137.39.82", port: 10443),
            option(datacenterId: 2, host: "not-an-ip")
        ])
        let kept = lists[1] ?? []
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept[0].host, "8.137.39.82")
        XCTAssertNil(lists[2])
    }

    func testIpv4MarkedIpv6IsRejected() {
        XCTAssertTrue(tellomiAcceptedDatacenterAddresses([
            option(host: "8.137.39.82", flags: ipv6Flag)
        ]).isEmpty)
    }

    func testIpv6RequiresTheFlag() {
        XCTAssertTrue(tellomiAcceptedDatacenterAddresses([
            option(host: "2001:db8::1")
        ]).isEmpty)
        let list = accepted([
            option(host: "2001:db8::1", flags: ipv6Flag)
        ])
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].host, "2001:db8::1")
        XCTAssertEqual(list[0].port, UInt16(10443))
    }

    func testRepeatedAddressInOneFamilyIsDropped() {
        let list = accepted([
            option(host: "8.137.39.82", port: 10443),
            option(host: "8.137.39.82", port: 10443, secret: Data([1]))
        ])
        XCTAssertEqual(list.count, 1)
        XCTAssertNil(list[0].secret)
    }

    func testMediaAddressIsASeparateEntry() {
        let secret = Data([9, 8, 7])
        let list = accepted([
            option(host: "8.137.39.82", port: 10443, flags: mediaFlag | tcpFlag | cdnFlag | staticFlag, secret: secret)
        ])
        XCTAssertEqual(list.count, 1)
        XCTAssertTrue(list[0].preferForMedia)
        XCTAssertTrue(list[0].restrictToTcp)
        XCTAssertTrue(list[0].cdn)
        XCTAssertTrue(list[0].preferForProxy)
        XCTAssertEqual(list[0].secret, Optional(secret))
        let both = accepted([
            option(host: "8.137.39.82"),
            option(host: "8.137.39.82", flags: mediaFlag)
        ])
        XCTAssertEqual(both.count, 2)
        XCTAssertFalse(both[0].preferForMedia)
        XCTAssertTrue(both[1].preferForMedia)
    }

    func testNonPositiveDatacenterIdIsIgnored() {
        XCTAssertTrue(tellomiAcceptedDatacenterAddresses([
            option(datacenterId: 0, host: "8.137.39.82"),
            option(datacenterId: -1, host: "8.137.39.82")
        ]).isEmpty)
    }
}
