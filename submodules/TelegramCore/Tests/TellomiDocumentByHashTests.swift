import XCTest
import Postbox
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

    private func hex(_ data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined()
    }
}
