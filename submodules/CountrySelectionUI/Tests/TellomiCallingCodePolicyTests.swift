import XCTest

final class TellomiCallingCodePolicyTests: XCTestCase {
    func testDefaultListIsChinaOnly() {
        XCTAssertTrue(TellomiCallingCodePolicy.allows(86))
        XCTAssertFalse(TellomiCallingCodePolicy.allows(1))
        XCTAssertFalse(TellomiCallingCodePolicy.allows(66))
        XCTAssertFalse(TellomiCallingCodePolicy.allows(852))
    }

    func testWhitelistCanBeOpenedLater() {
        let previous = TellomiCallingCodePolicy.allowedCallingCodes
        defer {
            TellomiCallingCodePolicy.allowedCallingCodes = previous
        }
        TellomiCallingCodePolicy.allowedCallingCodes = [86, 852]
        XCTAssertTrue(TellomiCallingCodePolicy.allows(852))
        XCTAssertFalse(TellomiCallingCodePolicy.allows(1))
    }

    func testPasteNoticeNamesChina() {
        XCTAssertTrue(TellomiCallingCodePolicy.message(languageCode: "zh-hans").contains("+86"))
        XCTAssertTrue(TellomiCallingCodePolicy.message(languageCode: "zh-hant").contains("+86"))
        XCTAssertTrue(TellomiCallingCodePolicy.message(languageCode: "en").contains("+86"))
    }
}
