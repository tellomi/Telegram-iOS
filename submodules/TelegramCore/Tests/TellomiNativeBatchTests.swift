import XCTest

final class TellomiNativeBatchTests: XCTestCase {
    func testTranslationIsEnglishToChineseOnTheServerOnly() {
        XCTAssertEqual(tellomiTranslationRoute(from: "en", to: "zh-Hans", enabled: true, healthy: true), .server)
        XCTAssertEqual(tellomiTranslationRoute(from: nil, to: "zh", enabled: true, healthy: true), .server)
        XCTAssertEqual(tellomiTranslationRoute(from: "ja", to: "zh", enabled: true, healthy: true), .refused)
        XCTAssertEqual(tellomiTranslationRoute(from: "en", to: "fr", enabled: true, healthy: true), .refused)
        XCTAssertEqual(tellomiTranslationRoute(from: "en", to: "zh", enabled: false, healthy: true), .refused)
        XCTAssertEqual(tellomiTranslationRoute(from: "en", to: "zh", enabled: true, healthy: false), .unavailable)
        XCTAssertFalse(tellomiTranslationAllowsLocalEngine())
        XCTAssertFalse(tellomiTranslationAllowsAlternativeEngine())
        XCTAssertFalse(tellomiTranslationExplicitlyDisabled(nil))
        XCTAssertTrue(tellomiTranslationExplicitlyDisabled("disabled"))
    }

    func testPhoneNumberFloodIsDailyAndFloodWaitIsShort() {
        XCTAssertEqual(tellomiCodeRequestLimit("PHONE_NUMBER_FLOOD"), .daily)
        XCTAssertEqual(tellomiCodeRequestLimit("FLOOD_WAIT_30"), .shortWait)
        XCTAssertEqual(tellomiCodeRequestLimit("PHONE_CODE_FLOOD"), .none)
        XCTAssertEqual(tellomiCodeRequestLimit("PHONE_NUMBER_INVALID"), .none)
    }

    func testDictationFillsTheDraftAndDoesNotSendVoice() {
        XCTAssertEqual(tellomiDictationOutcome(transcript: " 你好 ", healthy: true), .insertDraft("你好"))
        XCTAssertEqual(tellomiDictationOutcome(transcript: "   ", healthy: true), .unavailable)
        XCTAssertEqual(tellomiDictationOutcome(transcript: "你好", healthy: false), .unavailable)
        XCTAssertFalse(tellomiDictationSendsVoice())
    }
}
