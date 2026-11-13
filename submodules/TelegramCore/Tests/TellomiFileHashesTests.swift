import XCTest
import Postbox
import TelegramApi
@testable import TelegramCore

final class TellomiFileHashesTests: XCTestCase {
    func testConstructorIsTheCurrentLongOffsetMethod() {
        XCTAssertEqual(UInt32(bitPattern: tellomiGetFileHashesConstructor), 0x9156982a)
        XCTAssertEqual(tellomiFileHashPartBytes, 128 * 1024)
        XCTAssertEqual(tellomiFileHashFailOpenSeconds, 12)
        XCTAssertNotEqual(tellomiGetFileHashesKey, tellomiGetDocumentByHashKey)

        let legacy = Api.InputFileLocation.inputFileLocation(.init(volumeId: 1, localId: 2, secret: 3, fileReference: Buffer(data: Data())))
        let document = Api.InputFileLocation.inputDocumentFileLocation(.init(id: 1, accessHash: 2, fileReference: Buffer(data: Data()), thumbSize: ""))
        XCTAssertFalse(tellomiFileHashLocationIsSupported(legacy))
        XCTAssertTrue(tellomiFileHashLocationIsSupported(document))
    }

    func testKillSwitchDefaultsOn() {
        XCTAssertEqual(tellomiGetFileHashesKey, "tellomi_get_file_hashes")
        tellomiGetFileHashesEnabledOverride = nil
        defer {
            tellomiGetFileHashesEnabledOverride = nil
        }

        let on = self.configuration(.dictionary([tellomiGetFileHashesKey: .bool(true)]))
        let off = self.configuration(.dictionary([tellomiGetFileHashesKey: .bool(false)]))
        XCTAssertTrue(tellomiGetFileHashesEnabled(configuration: .defaultValue))
        XCTAssertTrue(tellomiGetFileHashesEnabled(configuration: self.configuration(nil)))
        XCTAssertTrue(tellomiGetFileHashesEnabled(configuration: self.configuration(.dictionary(["other": .bool(false)]))))
        XCTAssertTrue(tellomiGetFileHashesEnabled(configuration: on))
        XCTAssertTrue(tellomiGetFileHashesEnabled(configuration: self.configuration(.dictionary([tellomiGetFileHashesKey: .number(0)]))))
        XCTAssertTrue(tellomiGetFileHashesEnabled(configuration: self.configuration(.dictionary([tellomiGetFileHashesKey: .string("false")]))))
        XCTAssertFalse(tellomiGetFileHashesEnabled(configuration: off))

        XCTAssertTrue(self.plainDownload(enabled: tellomiGetFileHashesEnabled(configuration: .defaultValue)))
        XCTAssertFalse(self.plainDownload(enabled: false))

        tellomiGetFileHashesEnabledOverride = false
        XCTAssertFalse(tellomiGetFileHashesEnabled(configuration: on))
        XCTAssertFalse(self.plainDownload(enabled: tellomiGetFileHashesEnabled(configuration: on)))

        tellomiGetFileHashesEnabledOverride = nil
        XCTAssertTrue(tellomiGetFileHashesEnabled(configuration: .defaultValue))
    }

    func testOnlyAPlainFullDownloadIsChecked() {
        XCTAssertTrue(self.plainDownload(enabled: true))
        XCTAssertFalse(tellomiFileHashDownloadApplies(enabled: true, hasLocation: false, locationIsLegacy: false, webFile: false, cdn: false, preload: false, alreadyOnDisk: false, secretEncrypted: false, cacheEncrypted: false, prefixOnly: false))
        XCTAssertFalse(tellomiFileHashDownloadApplies(enabled: true, hasLocation: true, locationIsLegacy: true, webFile: false, cdn: false, preload: false, alreadyOnDisk: false, secretEncrypted: false, cacheEncrypted: false, prefixOnly: false))
        XCTAssertFalse(tellomiFileHashDownloadApplies(enabled: true, hasLocation: true, locationIsLegacy: false, webFile: true, cdn: false, preload: false, alreadyOnDisk: false, secretEncrypted: false, cacheEncrypted: false, prefixOnly: false))
        XCTAssertFalse(tellomiFileHashDownloadApplies(enabled: true, hasLocation: true, locationIsLegacy: false, webFile: false, cdn: true, preload: false, alreadyOnDisk: false, secretEncrypted: false, cacheEncrypted: false, prefixOnly: false))
        XCTAssertFalse(tellomiFileHashDownloadApplies(enabled: true, hasLocation: true, locationIsLegacy: false, webFile: false, cdn: false, preload: true, alreadyOnDisk: false, secretEncrypted: false, cacheEncrypted: false, prefixOnly: false))
        XCTAssertFalse(tellomiFileHashDownloadApplies(enabled: true, hasLocation: true, locationIsLegacy: false, webFile: false, cdn: false, preload: false, alreadyOnDisk: true, secretEncrypted: false, cacheEncrypted: false, prefixOnly: false))
        XCTAssertFalse(tellomiFileHashDownloadApplies(enabled: true, hasLocation: true, locationIsLegacy: false, webFile: false, cdn: false, preload: false, alreadyOnDisk: false, secretEncrypted: true, cacheEncrypted: false, prefixOnly: false))
        XCTAssertFalse(tellomiFileHashDownloadApplies(enabled: true, hasLocation: true, locationIsLegacy: false, webFile: false, cdn: false, preload: false, alreadyOnDisk: false, secretEncrypted: false, cacheEncrypted: true, prefixOnly: false))
        XCTAssertFalse(tellomiFileHashDownloadApplies(enabled: true, hasLocation: true, locationIsLegacy: false, webFile: false, cdn: false, preload: false, alreadyOnDisk: false, secretEncrypted: false, cacheEncrypted: false, prefixOnly: true))
        XCTAssertFalse(tellomiFileHashShouldObserve(webFile: true, secretEncrypted: false, cacheEncrypted: false))
        XCTAssertFalse(tellomiFileHashShouldObserve(webFile: false, secretEncrypted: true, cacheEncrypted: false))
        XCTAssertFalse(tellomiFileHashShouldObserve(webFile: false, secretEncrypted: false, cacheEncrypted: true))
        XCTAssertTrue(tellomiFileHashShouldObserve(webFile: false, secretEncrypted: false, cacheEncrypted: false))
    }

    func testPartsMatchCdnPartHashes() throws {
        var body = Data(count: tellomiFileHashPartBytes + 80)
        for index in 0 ..< body.count {
            body[index] = UInt8(truncatingIfNeeded: index)
        }
        let all = tellomiFileHashParts(of: body, requestOffset: 0)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].offset, 0)
        XCTAssertEqual(all[0].limit, tellomiFileHashPartBytes)
        XCTAssertEqual(all[0].hash, self.digest(body, offset: 0, length: tellomiFileHashPartBytes))
        XCTAssertEqual(all[1].offset, Int64(tellomiFileHashPartBytes))
        XCTAssertEqual(all[1].limit, 80)
        XCTAssertEqual(all[1].hash, self.digest(body, offset: tellomiFileHashPartBytes, length: 80))

        XCTAssertEqual(Array(all.suffix(1)), tellomiFileHashParts(of: body, requestOffset: 1))
        XCTAssertEqual(Array(all.suffix(1)), tellomiFileHashParts(of: body, requestOffset: Int64(tellomiFileHashPartBytes - 1)))
        XCTAssertEqual(Array(all.suffix(1)), tellomiFileHashParts(of: body, requestOffset: Int64(tellomiFileHashPartBytes)))
        XCTAssertTrue(tellomiFileHashParts(of: body, requestOffset: Int64(body.count)).isEmpty)
        XCTAssertTrue(tellomiFileHashParts(of: body, requestOffset: Int64(body.count) + 10).isEmpty)
        XCTAssertTrue(tellomiFileHashParts(of: body, requestOffset: -1).isEmpty)
        XCTAssertTrue(tellomiFileHashParts(of: Data(), requestOffset: 0).isEmpty)

        let abc = Data("abc".utf8)
        let one = tellomiFileHashParts(of: abc, requestOffset: 0)
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one[0].limit, 3)
        XCTAssertEqual(self.hex(one[0].hash), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testMismatchFailsAndAMissStaysOpen() throws {
        var body = Data(count: tellomiFileHashPartBytes + 3)
        for index in 0 ..< body.count {
            body[index] = UInt8(truncatingIfNeeded: index)
        }
        let all = tellomiFileHashParts(of: body, requestOffset: 0)
        XCTAssertEqual(tellomiFileHashCheck(body: body, parts: all, confirmedEnd: false), .match)
        XCTAssertEqual(tellomiFileHashCheck(body: body, parts: [], confirmedEnd: false), .failOpen)
        let broken = TellomiFileHashPart(offset: 0, limit: 3, hash: Data([1, 2, 3]))
        XCTAssertFalse(broken.wellFormed)
        XCTAssertEqual(tellomiFileHashCheck(body: body, parts: [broken], confirmedEnd: false), .failOpen)

        body[tellomiFileHashPartBytes + 1] ^= 0x5a
        XCTAssertEqual(tellomiFileHashCheck(body: body, parts: all, confirmedEnd: false), .mismatch)

        var intact = Data(count: body.count)
        for index in 0 ..< intact.count {
            intact[index] = UInt8(truncatingIfNeeded: index)
        }
        let first = [all[0]]
        XCTAssertEqual(tellomiFileHashCheck(body: intact, parts: first, confirmedEnd: false), .match)
        XCTAssertEqual(tellomiFileHashCheck(body: intact, parts: first, confirmedEnd: true), .mismatch)

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tellomi-file-hash-\(UUID().uuidString)")
        let shortFile = FileManager.default.temporaryDirectory.appendingPathComponent("tellomi-file-hash-short-\(UUID().uuidString)")
        try intact.write(to: file)
        defer {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: shortFile)
        }
        XCTAssertEqual(tellomiFileHashCheck(path: file.path, fileSize: Int64(intact.count), parts: all, confirmedEnd: false), .match)
        XCTAssertEqual(tellomiFileHashCheck(path: file.path + "-missing", fileSize: Int64(intact.count), parts: all, confirmedEnd: false), .failOpen)
        let shortBody = Data([1, 2, 3])
        try shortBody.write(to: shortFile)
        let claimsTen = TellomiFileHashPart(offset: 0, limit: 10, hash: self.digest(Data(count: 10), offset: 0, length: 10))
        XCTAssertEqual(tellomiFileHashCheck(path: shortFile.path, fileSize: Int64(shortBody.count), parts: [claimsTen], confirmedEnd: false), .mismatch)
        XCTAssertEqual(tellomiFileHashCheck(path: shortFile.path, fileSize: 10, parts: [claimsTen], confirmedEnd: false), .mismatch)
    }

    func testSessionPagesLikeTheServerAndStopsOnAMiss() {
        var body = Data(count: tellomiFileHashPartBytes + 3)
        for index in 0 ..< body.count {
            body[index] = UInt8(truncatingIfNeeded: index)
        }
        let all = tellomiFileHashParts(of: body, requestOffset: 0)
        var session = TellomiFileHashSession()
        XCTAssertEqual(session.open(), 0)
        XCTAssertEqual(session.open(), -1)
        XCTAssertEqual(session.requestNext(fileSize: Int64(body.count)), -1)
        XCTAssertFalse(session.stopped)
        XCTAssertEqual(session.accept(fileSize: Int64(body.count), page: [all[0]]), Int64(tellomiFileHashPartBytes))
        XCTAssertEqual(session.accept(fileSize: Int64(body.count), page: [all[1]]), -1)
        XCTAssertTrue(session.hasParts)
        XCTAssertFalse(session.confirmedEnd)
        XCTAssertEqual(tellomiFileHashNextOffset(fileSize: Int64(body.count), parts: session.parts), -1)

        var miss = TellomiFileHashSession()
        XCTAssertEqual(miss.open(), 0)
        XCTAssertEqual(miss.accept(fileSize: Int64(body.count), page: []), -1)
        XCTAssertTrue(miss.confirmedEnd)
        XCTAssertTrue(miss.stopped)
        XCTAssertFalse(miss.hasParts)

        var error = TellomiFileHashSession()
        XCTAssertEqual(error.open(), 0)
        error.stop()
        XCTAssertEqual(error.accept(fileSize: Int64(body.count), page: all), -1)
        XCTAssertTrue(error.stopped)
        XCTAssertFalse(error.confirmedEnd)
        XCTAssertEqual(tellomiFileHashNextOffset(fileSize: Int64(body.count), parts: []), 0)
        XCTAssertEqual(tellomiFileHashNextOffset(fileSize: 0, parts: all), -1)
    }

    private func plainDownload(enabled: Bool) -> Bool {
        return tellomiFileHashDownloadApplies(enabled: enabled, hasLocation: true, locationIsLegacy: false, webFile: false, cdn: false, preload: false, alreadyOnDisk: false, secretEncrypted: false, cacheEncrypted: false, prefixOnly: false)
    }

    private func configuration(_ data: JSON?) -> AppConfiguration {
        return AppConfiguration(data: data, hash: data == nil ? 0 : 1)
    }

    private func digest(_ data: Data, offset: Int, length: Int) -> Data {
        return tellomiFileHashSha256(data.subdata(in: offset ..< (offset + length)))
    }

    private func hex(_ data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined()
    }
}
