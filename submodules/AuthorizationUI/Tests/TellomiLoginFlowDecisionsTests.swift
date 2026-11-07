import XCTest

final class TellomiLoginFlowDecisionsTests: XCTestCase {
    func testLanguageSwitchRedrawsBeforeThePackDownload() {
        let plan = tellomiLanguageApplyPlan(selectedCode: "en", currentCode: "zh-hans")
        XCTAssertEqual(plan, TellomiLanguageApply(code: "en", redrawsBeforePackDownload: true))
        XCTAssertNil(tellomiLanguageApplyPlan(selectedCode: "zh-Hans", currentCode: "zh-hans"))
        let back = tellomiLanguageApplyPlan(selectedCode: "zh-hans", currentCode: "en")
        XCTAssertEqual(back?.redrawsBeforePackDownload, true)
        XCTAssertNotEqual(tellomiBundledPhoneTitle(languageCode: "zh-hans"), tellomiBundledPhoneTitle(languageCode: "en"))
        XCTAssertNotEqual(tellomiBundledPhoneTitle(languageCode: "zh-hant"), tellomiBundledPhoneTitle(languageCode: "zh-hans"))
        XCTAssertEqual(tellomiBundledPhoneTitle(languageCode: "zh-hans"), "登录发现更多精彩")
        XCTAssertEqual(tellomiBundledPhoneTitle(languageCode: "en"), "Log in to see more")
    }

    func testDailyCapAndShortResendWaitAreDifferent() {
        XCTAssertEqual(tellomiSendCodeThrottle(description: "PHONE_NUMBER_FLOOD"), .dailyLimit)
        XCTAssertEqual(tellomiSendCodeThrottle(description: "FLOOD_WAIT_60"), .resendWait(60))
        XCTAssertEqual(tellomiSendCodeThrottle(description: "FLOOD_WAIT_5"), .resendWait(5))
        XCTAssertEqual(tellomiSendCodeThrottle(description: "PHONE_CODE_FLOOD"), .none)
        XCTAssertEqual(tellomiSendCodeThrottle(description: "PHONE_NUMBER_INVALID"), .none)
        XCTAssertNil(tellomiFloodWaitSeconds("PHONE_NUMBER_FLOOD"))
        XCTAssertEqual(tellomiFloodWaitSeconds("FLOOD_WAIT_60"), 60)

        XCTAssertTrue(tellomiResendLockedForTheDay(.dailyLimit))
        XCTAssertFalse(tellomiResendLockedForTheDay(.resendWait(60)))
        XCTAssertNil(tellomiResendPauseSeconds(.dailyLimit))
        XCTAssertEqual(tellomiResendPauseSeconds(.resendWait(60)), 60)

        let daily = tellomiCodeFloodSentence(languageCode: "zh-hans")
        let wait = tellomiResendWaitSentence(languageCode: "zh-hans", seconds: 60)
        XCTAssertTrue(daily.contains("10"))
        XCTAssertFalse(wait.contains("10"))
        XCTAssertTrue(wait.contains("60"))
        XCTAssertNotEqual(daily, wait)
        XCTAssertTrue(tellomiCodeFloodSentence(languageCode: "en").contains("10"))
        XCTAssertFalse(tellomiResendWaitSentence(languageCode: "en", seconds: 60).contains("10"))
    }

    func testPastedForeignCallingCodeStaysOnChina() {
        let foreign = tellomiPastedCallingCode(recognized: 66, allowed: [86], fallback: 86)
        XCTAssertTrue(foreign.rejected)
        XCTAssertEqual(foreign.code, 86)
        let china = tellomiPastedCallingCode(recognized: 86, allowed: [86], fallback: 86)
        XCTAssertFalse(china.rejected)
        XCTAssertEqual(china.code, 86)
        let national = tellomiPastedCallingCode(recognized: nil, allowed: [86], fallback: 86)
        XCTAssertFalse(national.rejected)
        let opened = tellomiPastedCallingCode(recognized: 852, allowed: [86, 852], fallback: 86)
        XCTAssertFalse(opened.rejected)
        XCTAssertEqual(opened.code, 852)
    }
}
