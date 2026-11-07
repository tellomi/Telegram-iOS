import XCTest

final class TellomiLoginFlowDecisionsTests: XCTestCase {
    func testLanguageSwitchRedrawsBeforeThePackDownload() {
        let plan = tellomiLanguageApplyPlan(selectedCode: "en", currentCode: "zh-hans")
        XCTAssertEqual(plan, TellomiLanguageApply(code: "en", redrawsBeforePackDownload: true))
        XCTAssertNil(tellomiLanguageApplyPlan(selectedCode: "zh-Hans", currentCode: "zh-hans"))
        XCTAssertEqual(tellomiLanguageApplyPlan(selectedCode: "zh-hant", currentCode: "en")?.redrawsBeforePackDownload, true)
    }

    func testDailyCodeLimitStopsResend() {
        XCTAssertTrue(tellomiCodeRequestIsDailyLimit("PHONE_CODE_FLOOD"))
        XCTAssertTrue(tellomiCodeRequestIsDailyLimit("FLOOD_WAIT_3600"))
        XCTAssertFalse(tellomiCodeRequestIsDailyLimit("PHONE_NUMBER_INVALID"))
        XCTAssertFalse(tellomiResendEnabledAfterCodeLimit(true))
        XCTAssertTrue(tellomiResendEnabledAfterCodeLimit(false))
    }

    func testDailyCodeLimitCopy() {
        XCTAssertTrue(tellomiCodeFloodSentence(languageCode: "zh-hans").contains("10"))
        XCTAssertTrue(tellomiCodeFloodSentence(languageCode: "zh-hant").contains("10"))
        XCTAssertTrue(tellomiCodeFloodSentence(languageCode: "en").contains("10"))
        XCTAssertNotEqual(tellomiCodeFloodSentence(languageCode: "zh-hans"), tellomiCodeFloodSentence(languageCode: "en"))
    }
}
