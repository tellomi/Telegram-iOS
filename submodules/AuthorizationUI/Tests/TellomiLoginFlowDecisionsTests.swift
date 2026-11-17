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

    func testFirstLoginPasswordKeepsThePermanentKey() {
        // SMS accepted, cloud password still required. The login record exists.
        XCTAssertEqual(tellomiAccountHandoff(postboxIsAuthorized: false, promotedRecordExists: true), .keepSameRecord)

        // checkPassword stored AuthorizedAccountState and the record left the auth slot.
        // Enter the main UI on that same record. Do not start a new permanent key.
        XCTAssertEqual(tellomiAccountHandoff(postboxIsAuthorized: true, promotedRecordExists: true), .adoptAuthorized)

        // A new login, and therefore a new permanent key, only happens with no record left.
        XCTAssertEqual(tellomiAccountHandoff(postboxIsAuthorized: false, promotedRecordExists: false), .beginNewLogin)
        XCTAssertNotEqual(tellomiAccountHandoff(postboxIsAuthorized: true, promotedRecordExists: true), .beginNewLogin)

        // Asking for a code again offers proxy settings only when sendCode times out.
        XCTAssertTrue(tellomiPhoneEntryOffersProxy(sendCodeTimedOut: true))
        XCTAssertFalse(tellomiPhoneEntryOffersProxy(sendCodeTimedOut: false))
    }

    func testEmailLoginUsesTheOfficialSentCodeSteps() {
        XCTAssertEqual(tellomiOfficialEmailLoginStep(.setupRequired), .setupEmail)
        XCTAssertEqual(tellomiOfficialEmailLoginStep(.email(setup: true)), .verifySetupEmail)
        XCTAssertEqual(tellomiOfficialEmailLoginStep(.email(setup: false)), .signInWithEmailCode)
        XCTAssertNil(tellomiOfficialEmailLoginStep(.other))
    }
}
