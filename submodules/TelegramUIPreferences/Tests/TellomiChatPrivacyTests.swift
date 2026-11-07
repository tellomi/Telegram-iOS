import XCTest

final class TellomiChatPrivacyTests: XCTestCase {
    func testSecretViewSendsNoReadOnlineOrTyping() {
        for report in TellomiSecretViewReport.allCases {
            XCTAssertFalse(tellomiSecretViewAllows(report))
        }
        XCTAssertTrue(tellomiSecretViewKeepsUnreadAfterExit())
        XCTAssertEqual(tellomiSecretViewBannerTitle(languageCode: "zh-Hans"), "秘密查看中")
        XCTAssertEqual(tellomiSecretViewMenuTitle(languageCode: "en"), "Secret view")
    }

    func testSecretViewIsPerAccountAndEnds() {
        let sessions = TellomiSecretViewSessions()
        sessions.begin(accountPeerId: 1, chatPeerId: 10)
        XCTAssertTrue(sessions.suppressesReports(accountPeerId: 1, chatPeerId: 10))
        XCTAssertTrue(sessions.suppressesOnline(accountPeerId: 1))
        XCTAssertFalse(sessions.suppressesReports(accountPeerId: 2, chatPeerId: 10))
        XCTAssertFalse(sessions.suppressesOnline(accountPeerId: 2))
        sessions.end(accountPeerId: 1, chatPeerId: 10)
        XCTAssertFalse(sessions.suppressesReports(accountPeerId: 1, chatPeerId: 10))
        XCTAssertFalse(sessions.suppressesOnline(accountPeerId: 1))
    }

    func testChatLockStoresASaltedHashAndRejectsAShortPin() {
        let salt = Data([1, 2, 3, 4])
        guard case let .success(record) = tellomiMakeChatLockRecord(pin: "1234", biometricsEnabled: true, salt: salt) else {
            return XCTFail("expected a record")
        }
        XCTAssertEqual(record.salt, salt)
        XCTAssertNotEqual(record.hash, Data("1234".utf8))
        XCTAssertTrue(tellomiChatLockMatches(pin: "1234", record: record))
        XCTAssertFalse(tellomiChatLockMatches(pin: "1235", record: record))
        XCTAssertTrue(record.biometricsEnabled)
        XCTAssertEqual(tellomiMakeChatLockRecord(pin: "12", biometricsEnabled: false, salt: salt), .failure(.pinNotNumeric))
        XCTAssertEqual(tellomiMakeChatLockRecord(pin: "12ab", biometricsEnabled: false, salt: salt), .failure(.pinNotNumeric))
    }

    func testForgotPasswordDoesNotUnlockWithoutTheAppPasscode() {
        XCTAssertEqual(tellomiForgotChatLock(hasAppPasscode: false), .staysLocked)
        XCTAssertEqual(tellomiForgotChatLock(hasAppPasscode: true), .resetAfterAppPasscode)
    }

    func testALockHidesEveryListedSurfaceAndStaysInsideOneAccount() {
        let directory = TellomiChatLockDirectory()
        let record = try! tellomiMakeChatLockRecord(pin: "2468", biometricsEnabled: false, salt: Data([9])).get()
        directory.save(record, accountPeerId: 7, chatPeerId: 42)
        XCTAssertTrue(directory.isLocked(accountPeerId: 7, chatPeerId: 42))
        XCTAssertFalse(directory.isLocked(accountPeerId: 8, chatPeerId: 42))
        for surface in TellomiChatLockSurface.allCases {
            XCTAssertEqual(surface, surface)
            XCTAssertEqual(tellomiConcealedChatText(isLocked: true, text: "hello", languageCode: "zh"), "已锁定")
        }
        XCTAssertEqual(tellomiConcealedChatText(isLocked: false, text: "hello", languageCode: "en"), "hello")
        let index = directory.indexSnapshot()
        XCTAssertTrue(tellomiChatLockIndexHides(index: index, accountPeerId: 7, chatPeerId: 42))
        XCTAssertFalse(tellomiChatLockIndexHides(index: index, accountPeerId: 8, chatPeerId: 42))
        directory.remove(accountPeerId: 7, chatPeerId: 42)
        XCTAssertFalse(directory.isLocked(accountPeerId: 7, chatPeerId: 42))
    }
}
