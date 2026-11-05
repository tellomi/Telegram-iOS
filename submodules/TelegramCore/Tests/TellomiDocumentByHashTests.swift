import XCTest
import Postbox
import SwiftSignalKit
@testable import TelegramCore

final class TellomiDocumentByHashTests: XCTestCase {
    func testAGifIsLookedUpIncludingAnMp4Animation() {
        XCTAssertEqual(tellomiDocumentByHashDecision(self.traits(mimeType: "image/gif", isAnimated: true)), .lookup(.gif))
        XCTAssertEqual(tellomiDocumentByHashDecision(self.traits(mimeType: "video/mp4", isAnimated: true, isVideo: true)), .lookup(.gif))
        XCTAssertEqual(tellomiDocumentByHashDecision(self.traits(mimeType: "image/gif")), .lookup(.gif))
        XCTAssertTrue(tellomiDocumentByHashSizeIsEligible(role: .gif, size: tellomiDocumentByHashVideoByteLimit + 1))
    }

    func testAnOrdinaryDocumentIsLookedUpAndVoiceAudioRoundVideoAndStickersAreNot() {
        XCTAssertEqual(tellomiDocumentByHashDecision(self.traits(mimeType: "application/pdf")), .lookup(.document))
        XCTAssertEqual(tellomiDocumentByHashDecision(self.traits(mimeType: "video/mp4")), .lookup(.document))
        XCTAssertEqual(tellomiDocumentByHashDecision(self.traits(mimeType: "audio/ogg", isVoice: true)), .skip)
        XCTAssertEqual(tellomiDocumentByHashDecision(self.traits(mimeType: "audio/mpeg", isMusic: true)), .skip)
        XCTAssertEqual(tellomiDocumentByHashDecision(self.traits(mimeType: "video/mp4", isVideo: true, isInstantVideo: true)), .skip)
        XCTAssertEqual(tellomiDocumentByHashDecision(self.traits(mimeType: "image/webp", isSticker: true)), .skip)
        XCTAssertEqual(tellomiDocumentByHashDecision(self.traits(mimeType: "application/x-tgsticker", isAnimated: true, isAnimatedSticker: true)), .skip)
        XCTAssertEqual(tellomiDocumentByHashDecision(self.traits(mimeType: "video/webm", isVideoSticker: true, isSticker: true)), .skip)
        XCTAssertEqual(tellomiDocumentByHashDecision(self.traits(mimeType: "video/webm", isCustomEmoji: true)), .skip)
        XCTAssertEqual(tellomiDocumentByHashDecision(self.traits(mimeType: "", isAnimated: true)), .skip)
        XCTAssertEqual(tellomiDocumentByHashDecision(self.traits(mimeType: "application/pdf", encrypted: true)), .skip)
    }

    func testAVideoIsLookedUpOnlyUpToTheByteLimit() {
        XCTAssertEqual(tellomiDocumentByHashDecision(self.traits(mimeType: "video/mp4", isVideo: true)), .lookup(.video))
        XCTAssertTrue(tellomiDocumentByHashSizeIsEligible(role: .video, size: tellomiDocumentByHashVideoByteLimit))
        XCTAssertFalse(tellomiDocumentByHashSizeIsEligible(role: .video, size: tellomiDocumentByHashVideoByteLimit + 1))
        XCTAssertFalse(tellomiDocumentByHashSizeIsEligible(role: .video, size: 0))
        XCTAssertFalse(tellomiDocumentByHashSizeIsEligible(role: .document, size: 0))
        XCTAssertTrue(tellomiDocumentByHashSizeIsEligible(role: .document, size: tellomiDocumentByHashVideoByteLimit + 1))
    }

    func testAttributeFlagsMatchTheSendRules() {
        let gif = tellomiDocumentByHashTraits(mimeType: "video/mp4", attributes: [
            .Animated,
            .Video(duration: 1, size: PixelDimensions(width: 8, height: 8), flags: [], preloadSize: nil, coverTime: nil, videoCodec: nil)
        ], encrypted: false)
        XCTAssertEqual(tellomiDocumentByHashDecision(gif), .lookup(.gif))

        let round = tellomiDocumentByHashTraits(mimeType: "video/mp4", attributes: [
            .Video(duration: 1, size: PixelDimensions(width: 8, height: 8), flags: [.instantRoundVideo], preloadSize: nil, coverTime: nil, videoCodec: nil)
        ], encrypted: false)
        XCTAssertEqual(tellomiDocumentByHashDecision(round), .skip)

        let voice = tellomiDocumentByHashTraits(mimeType: "audio/ogg", attributes: [
            .Audio(isVoice: true, duration: 1, title: nil, performer: nil, waveform: nil)
        ], encrypted: false)
        XCTAssertEqual(tellomiDocumentByHashDecision(voice), .skip)

        let file = tellomiDocumentByHashTraits(mimeType: "application/pdf", attributes: [
            .FileName(fileName: "a.pdf")
        ], encrypted: false)
        XCTAssertEqual(tellomiDocumentByHashDecision(file), .lookup(.document))

        let sticker = tellomiDocumentByHashTraits(mimeType: "application/x-tgsticker", attributes: [
            .FileName(fileName: "a.tgs"),
            .Animated,
            .Sticker(displayText: "", packReference: nil, maskData: nil)
        ], encrypted: false)
        XCTAssertEqual(tellomiDocumentByHashDecision(sticker), .skip)
    }

    func testAReusableDocumentMustMatchIdDcSizeAndMime() {
        XCTAssertTrue(tellomiDocumentByHashIsReusable(id: 7, dcId: 2, size: 10, mimeType: "image/gif", expectedSize: 10, expectedMimeType: "image/gif"))
        XCTAssertFalse(tellomiDocumentByHashIsReusable(id: 0, dcId: 2, size: 10, mimeType: "image/gif", expectedSize: 10, expectedMimeType: "image/gif"))
        XCTAssertFalse(tellomiDocumentByHashIsReusable(id: 7, dcId: 0, size: 10, mimeType: "image/gif", expectedSize: 10, expectedMimeType: "image/gif"))
        XCTAssertFalse(tellomiDocumentByHashIsReusable(id: 7, dcId: 2, size: 9, mimeType: "image/gif", expectedSize: 10, expectedMimeType: "image/gif"))
        XCTAssertFalse(tellomiDocumentByHashIsReusable(id: 7, dcId: 2, size: 10, mimeType: "video/mp4", expectedSize: 10, expectedMimeType: "image/gif"))
        XCTAssertFalse(tellomiDocumentByHashIsReusable(id: 7, dcId: 2, size: 10, mimeType: "", expectedSize: 10, expectedMimeType: ""))
    }

    func testKillSwitchDefaultsOnAndForcedOffSkipsTheLookup() {
        XCTAssertEqual(tellomiGetDocumentByHashKey, "tellomi_get_document_by_hash")
        tellomiGetDocumentByHashEnabledOverride = nil
        defer {
            tellomiGetDocumentByHashEnabledOverride = nil
        }

        let on = self.configuration(.dictionary([tellomiGetDocumentByHashKey: .bool(true)]))
        let off = self.configuration(.dictionary([tellomiGetDocumentByHashKey: .bool(false)]))
        XCTAssertTrue(tellomiGetDocumentByHashEnabled(configuration: .defaultValue))
        XCTAssertTrue(tellomiGetDocumentByHashEnabled(configuration: self.configuration(nil)))
        XCTAssertTrue(tellomiGetDocumentByHashEnabled(configuration: self.configuration(.dictionary(["other": .bool(false)]))))
        XCTAssertTrue(tellomiGetDocumentByHashEnabled(configuration: on))
        XCTAssertTrue(tellomiGetDocumentByHashEnabled(configuration: self.configuration(.dictionary([tellomiGetDocumentByHashKey: .number(0)]))))
        XCTAssertTrue(tellomiGetDocumentByHashEnabled(configuration: self.configuration(.dictionary([tellomiGetDocumentByHashKey: .string("false")]))))
        XCTAssertFalse(tellomiGetDocumentByHashEnabled(configuration: off))

        // The three upload lookups call this before SHA-256 or messages.getDocumentByHash.
        // "getDocumentByHash" is the stand-in for that work; "upload" is the immediate miss.
        XCTAssertEqual(self.lookupResult(enabled: tellomiGetDocumentByHashEnabled(configuration: .defaultValue)), "getDocumentByHash" as String?)
        XCTAssertEqual(self.lookupResult(enabled: tellomiGetDocumentByHashEnabled(configuration: on)), "getDocumentByHash" as String?)
        XCTAssertEqual(self.lookupResult(enabled: tellomiGetDocumentByHashEnabled(configuration: off)), "upload" as String?)

        tellomiGetDocumentByHashEnabledOverride = false
        XCTAssertFalse(tellomiGetDocumentByHashEnabled(configuration: on))
        XCTAssertEqual(self.lookupResult(enabled: tellomiGetDocumentByHashEnabled(configuration: on)), "upload" as String?)

        tellomiGetDocumentByHashEnabledOverride = nil
        XCTAssertTrue(tellomiGetDocumentByHashEnabled(configuration: .defaultValue))
        XCTAssertEqual(self.lookupResult(enabled: tellomiGetDocumentByHashEnabled(configuration: .defaultValue)), "getDocumentByHash" as String?)
    }

    func testSha256OfTheBytesThatWouldBeUploaded() throws {
        let digest = tellomiSha256(data: Data("abc".utf8))
        XCTAssertEqual(self.hex(digest), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tellomi-doc-hash-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
        }
        XCTAssertEqual(tellomiSha256File(path: url.path, expectedSize: 3).map { self.hex($0) }, self.hex(digest))
        XCTAssertNil(tellomiSha256File(path: url.path, expectedSize: 2))
        XCTAssertNil(tellomiSha256File(path: url.path, expectedSize: 0))
        XCTAssertNil(tellomiSha256File(path: url.path + "-missing", expectedSize: 3))
    }

    private func traits(mimeType: String, encrypted: Bool = false, isAnimated: Bool = false, isAnimatedSticker: Bool = false, isVideoSticker: Bool = false, isSticker: Bool = false, isCustomEmoji: Bool = false, isVoice: Bool = false, isMusic: Bool = false, isVideo: Bool = false, isInstantVideo: Bool = false) -> TellomiDocumentByHashTraits {
        return TellomiDocumentByHashTraits(mimeType: mimeType, encrypted: encrypted, isAnimated: isAnimated, isAnimatedSticker: isAnimatedSticker, isVideoSticker: isVideoSticker, isSticker: isSticker, isCustomEmoji: isCustomEmoji, isVoice: isVoice, isMusic: isMusic, isVideo: isVideo, isInstantVideo: isInstantVideo)
    }

    private func configuration(_ data: JSON?) -> AppConfiguration {
        return AppConfiguration(data: data, hash: data == nil ? 0 : 1)
    }

    /// Runs the same gate the upload path uses. A disabled switch must emit the miss without calling the lookup.
    private func lookupResult(enabled: Bool, file: StaticString = #file, line: UInt = #line) -> String? {
        var lookedUp = false
        let value = self.wait(tellomiDocumentByHashLookupIfEnabled(enabled: enabled, skipped: "upload") {
            lookedUp = true
            return .single("getDocumentByHash")
        }, file: file, line: line)
        if enabled {
            XCTAssertTrue(lookedUp, "lookup was not started", file: file, line: line)
        } else {
            XCTAssertFalse(lookedUp, "getDocumentByHash ran while the switch was off", file: file, line: line)
        }
        return value
    }

    /// Subscribes and returns the first value. A lookup that never emits fails the test.
    private func wait<T>(_ signal: Signal<T, NoError>, file: StaticString = #file, line: UInt = #line) -> T? {
        let result = Atomic<T?>(value: nil)
        let emitted = Atomic<Bool>(value: false)
        let done = DispatchSemaphore(value: 0)
        let disposable = (signal |> take(1)).start(next: { value in
            let _ = emitted.swap(true)
            let _ = result.swap(value)
        }, completed: {
            done.signal()
        })
        let status = done.wait(timeout: .now() + 2.0)
        disposable.dispose()
        XCTAssertEqual(status, .success, "lookup did not return", file: file, line: line)
        XCTAssertTrue(emitted.with { $0 }, "lookup emitted nothing", file: file, line: line)
        return result.with { $0 }
    }

    private func hex(_ data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined()
    }
}
