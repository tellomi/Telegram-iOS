import XCTest
import TelegramCore

final class TellomiBuiltinLanguageTests: XCTestCase {
    func testSimplifiedChineseWithRegionUsesHans() {
        XCTAssertEqual(tellomiResolvedBuiltinLanguage(preferredLanguages: ["zh-Hans-US"], explicitChoice: nil), "zh-Hans")
        XCTAssertEqual(tellomiResolvedBuiltinLanguage(preferredLanguages: ["zh-Hans-CN"], explicitChoice: nil), "zh-Hans")
        XCTAssertEqual(tellomiResolvedBuiltinLanguage(preferredLanguages: ["zh-CN"], explicitChoice: nil), "zh-Hans")
        XCTAssertEqual(tellomiResolvedBuiltinLanguage(preferredLanguages: ["zh"], explicitChoice: nil), "zh-Hans")
    }

    func testTraditionalChineseVariantsUseHant() {
        XCTAssertEqual(tellomiResolvedBuiltinLanguage(preferredLanguages: ["zh-Hant-TW"], explicitChoice: nil), "zh-Hant")
        XCTAssertEqual(tellomiResolvedBuiltinLanguage(preferredLanguages: ["zh-Hant-HK"], explicitChoice: nil), "zh-Hant")
        XCTAssertEqual(tellomiResolvedBuiltinLanguage(preferredLanguages: ["zh-HK"], explicitChoice: nil), "zh-Hant")
        XCTAssertEqual(tellomiResolvedBuiltinLanguage(preferredLanguages: ["zh-TW"], explicitChoice: nil), "zh-Hant")
    }

    func testTraditionalWinsOverALaterSimplifiedEntry() {
        XCTAssertEqual(tellomiResolvedBuiltinLanguage(preferredLanguages: ["zh-Hant-HK", "zh-Hans-CN"], explicitChoice: nil), "zh-Hant")
    }

    func testOtherLanguagesFallBackToEnglish() {
        XCTAssertEqual(tellomiResolvedBuiltinLanguage(preferredLanguages: ["fr-FR", "zh-Hans-CN"], explicitChoice: nil), "zh-Hans")
        XCTAssertEqual(tellomiResolvedBuiltinLanguage(preferredLanguages: ["fr-FR"], explicitChoice: nil), "en")
        XCTAssertEqual(tellomiResolvedBuiltinLanguage(preferredLanguages: ["en-US"], explicitChoice: nil), "en")
    }

    func testExplicitChoiceWinsOverTheSystemLanguage() {
        XCTAssertEqual(tellomiResolvedBuiltinLanguage(preferredLanguages: ["zh-Hans-US"], explicitChoice: "en"), "en")
        XCTAssertEqual(tellomiResolvedBuiltinLanguage(preferredLanguages: ["en-US"], explicitChoice: "zh-Hant-TW"), "zh-Hant")
        XCTAssertEqual(tellomiResolvedBuiltinLanguage(preferredLanguages: ["zh-Hans-CN"], explicitChoice: "fr"), "fr")
    }
}
