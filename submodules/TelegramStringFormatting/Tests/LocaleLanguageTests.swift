import XCTest
@testable import TelegramStringFormatting

final class LocaleLanguageTests: XCTestCase {
    func testChineseUIUsesPrimaryWhenBaseIsEnglish() {
        XCTAssertEqual(localeIdentifierLanguageCode(baseLanguageCode: "en", primaryLanguageCode: "zh-hans"), "zh-hans")
        XCTAssertEqual(localeIdentifierLanguageCode(baseLanguageCode: "en", primaryLanguageCode: "zh-hant"), "zh-hant")
        XCTAssertEqual(localeIdentifierLanguageCode(baseLanguageCode: "en-US", primaryLanguageCode: "zh-hans"), "zh-hans")
        XCTAssertEqual(localeIdentifierLanguageCode(baseLanguageCode: "en_GB", primaryLanguageCode: "zh-hant"), "zh-hant")
        XCTAssertEqual(localeIdentifierLanguageCode(baseLanguageCode: "EN", primaryLanguageCode: "zh-Hans"), "zh-Hans")
    }

    func testEnglishUIKeepsTheBaseCode() {
        XCTAssertEqual(localeIdentifierLanguageCode(baseLanguageCode: "en", primaryLanguageCode: "en"), "en")
        XCTAssertEqual(localeIdentifierLanguageCode(baseLanguageCode: "en", primaryLanguageCode: "en-US"), "en")
        XCTAssertEqual(localeIdentifierLanguageCode(baseLanguageCode: "en_US", primaryLanguageCode: "en"), "en_US")
        XCTAssertEqual(localeIdentifierLanguageCode(baseLanguageCode: "en", primaryLanguageCode: ""), "en")
    }

    func testNonEnglishBaseStaysOnTheBasePack() {
        XCTAssertEqual(localeIdentifierLanguageCode(baseLanguageCode: "zh-hans", primaryLanguageCode: "zh-hans"), "zh-hans")
        XCTAssertEqual(localeIdentifierLanguageCode(baseLanguageCode: "ru", primaryLanguageCode: "uk"), "ru")
    }
}
