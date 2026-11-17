import XCTest

/// The signed-out root is Telegram's phone screen. The welcome carousel is not installed.
/// `//Telegram:iOSAppUITestSuite`.
final class TellomiLoginUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--ui-test")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testPhoneLoginIsTheDefaultAndWelcomeIsSkipped() throws {
        app.launch()
        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        XCTAssertTrue(phone.waitForExistence(timeout: 25.0))
        XCTAssertFalse(app.buttons["Auth.Welcome.StartButton"].exists)
        XCTAssertTrue(app.textFields["Auth.PhoneEntry.CountryCodeField"].exists)
        XCTAssertTrue(app.buttons["Auth.PhoneEntry.ContinueButton"].waitForExistence(timeout: 5.0))
        XCTAssertFalse(app.buttons["Auth.Login.Email"].exists)
        XCTAssertFalse(app.textFields["Auth.PhoneEntry.EmailField"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["Auth.Login.Agreement"].exists)
        XCTAssertFalse(app.buttons["Auth.Agreement.Checkbox"].exists)
    }

    func testContinueEnablesWhenANationalNumberIsEntered() throws {
        app.launch()
        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        XCTAssertTrue(phone.waitForExistence(timeout: 25.0))
        let send = app.buttons["Auth.PhoneEntry.ContinueButton"]
        XCTAssertTrue(send.waitForExistence(timeout: 5.0))
        XCTAssertFalse(send.isEnabled)
        phone.tap()
        phone.typeText("138")
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: send)
        waitForExpectations(timeout: 5.0)
    }
}
