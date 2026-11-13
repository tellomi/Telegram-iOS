import XCTest

final class TellomiLoginFlowDecisionsTests: XCTestCase {
    func testSkippedWelcomeOpensThePhoneScreen() {
        XCTAssertTrue(tellomiSkipsWelcomeSplash)
        XCTAssertEqual(tellomiLoggedOutRoot(skipsWelcome: true, countryCode: 86), .phoneEntry(countryCode: 86))
        XCTAssertEqual(tellomiLoggedOutRoot(skipsWelcome: false, countryCode: 86), .welcome)
        XCTAssertEqual(tellomiLoggedOutRoot(skipsWelcome: true, countryCode: 1), .phoneEntry(countryCode: 1))

        XCTAssertEqual(tellomiPhoneRootBack(hasOtherAccounts: false, skipsWelcome: true), .stayOnPhone)
        XCTAssertEqual(tellomiPhoneRootBack(hasOtherAccounts: true, skipsWelcome: true), .dismissAddAccount)
        XCTAssertEqual(tellomiPhoneRootBack(hasOtherAccounts: false, skipsWelcome: false), .showWelcome)
        XCTAssertEqual(tellomiPhoneRootBack(hasOtherAccounts: true, skipsWelcome: false), .dismissAddAccount)

        XCTAssertFalse(tellomiPhoneRootShowsDismiss(hasOtherAccounts: false, skipsWelcome: true))
        XCTAssertTrue(tellomiPhoneRootShowsDismiss(hasOtherAccounts: true, skipsWelcome: true))
        XCTAssertTrue(tellomiPhoneRootShowsDismiss(hasOtherAccounts: false, skipsWelcome: false))
    }

    func testSkippedWelcomeKeepsSystemLanguageAndASettingsChoice() {
        XCTAssertEqual(tellomiChromeLanguageCode(savedLanguageCode: "en", preferredInterfaceLanguage: nil, systemPackApplied: false, systemLangPackCode: "zh-hans"), "zh-hans")
        XCTAssertEqual(tellomiChromeLanguageCode(savedLanguageCode: "en", preferredInterfaceLanguage: nil, systemPackApplied: false, systemLangPackCode: "zh-hant"), "zh-hant")
        XCTAssertEqual(tellomiChromeLanguageCode(savedLanguageCode: "en", preferredInterfaceLanguage: "  ", systemPackApplied: false, systemLangPackCode: "zh-hans"), "zh-hans")
        XCTAssertEqual(tellomiChromeLanguageCode(savedLanguageCode: "en", preferredInterfaceLanguage: nil, systemPackApplied: false, systemLangPackCode: nil), "en")
        XCTAssertEqual(tellomiChromeLanguageCode(savedLanguageCode: "en", preferredInterfaceLanguage: "en", systemPackApplied: true, systemLangPackCode: "zh-hans"), "en")
        XCTAssertEqual(tellomiChromeLanguageCode(savedLanguageCode: "zh-hant", preferredInterfaceLanguage: nil, systemPackApplied: true, systemLangPackCode: "zh-hans"), "zh-hant")
        XCTAssertEqual(tellomiChromeLanguageCode(savedLanguageCode: "zh-hans", preferredInterfaceLanguage: nil, systemPackApplied: false, systemLangPackCode: "zh-hant"), "zh-hans")
    }

    func testEmailLoginUsesTheOfficialSentCodeSteps() {
        XCTAssertEqual(tellomiOfficialEmailLoginStep(.setupRequired), .setupEmail)
        XCTAssertEqual(tellomiOfficialEmailLoginStep(.email(setup: true)), .verifySetupEmail)
        XCTAssertEqual(tellomiOfficialEmailLoginStep(.email(setup: false)), .signInWithEmailCode)
        XCTAssertNil(tellomiOfficialEmailLoginStep(.other))
    }
}
