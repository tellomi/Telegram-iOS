import XCTest

/// Headless login checks for the Mac Studio. `xcodebuild test` boots a simulator
/// without opening Simulator.app. The suite is `//Telegram:iOSAppUITestSuite`
/// (`Telegram/Tests/Sources/` is globbed into that target).
///
/// Send-code stops at the code screen or the error alert. It fails if the
/// primary button is still in its progress state after 30 seconds.
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

    func testSendCodeLeavesTheSpinner() throws {
        self.openPhoneLogin()

        let checkbox = app.buttons["Auth.Agreement.Checkbox"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5.0))
        checkbox.tap()

        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        phone.tap()
        phone.typeText("13800000000")

        let send = app.buttons["Auth.PhoneEntry.ContinueButton"]
        XCTAssertTrue(send.waitForExistence(timeout: 5.0))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: send)
        waitForExpectations(timeout: 5.0)
        send.tap()

        let deadline = Date().addingTimeInterval(30.0)
        while Date() < deadline {
            if self.sendCodeSettled() {
                XCTAssertFalse(self.spinnerIsRunning(), "spinner still running after send-code settled")
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        XCTAssertFalse(self.spinnerIsRunning(), "spinner still running after 30s")
        XCTFail("send code did not reach the code screen or an error alert within 30s")
    }

    func testLanguagePickerListsMoreThanThreeLanguages() throws {
        self.openPhoneLogin()

        let globe = app.buttons["Auth.Login.Language"]
        XCTAssertTrue(globe.waitForExistence(timeout: 5.0))
        globe.tap()

        let list = app.tables["Auth.Language.List"]
        XCTAssertTrue(list.waitForExistence(timeout: 5.0))

        let rows = app.cells.matching(identifier: "Auth.Language.Row")
        let deadline = Date().addingTimeInterval(10.0)
        var count = rows.count
        while Date() < deadline && count <= 3 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            count = rows.count
        }
        XCTAssertGreaterThan(count, 3, "language picker listed \(count) rows")
    }

    func testCountryPickerOpens() throws {
        self.openPhoneLogin()

        let country = app.buttons["Auth.PhoneEntry.CountryButton"]
        XCTAssertTrue(country.waitForExistence(timeout: 5.0))
        country.tap()

        let list = app.tables["Auth.Country.List"]
        XCTAssertTrue(list.waitForExistence(timeout: 5.0))
        XCTAssertGreaterThan(list.cells.count, 0)
    }

    private func openPhoneLogin() {
        app.launch()
        let start = app.buttons["Auth.Welcome.StartButton"]
        if start.waitForExistence(timeout: 20.0) {
            start.tap()
        }
        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        XCTAssertTrue(phone.waitForExistence(timeout: 25.0), "phone login did not appear after Start")
    }

    private func sendCodeSettled() -> Bool {
        if app.textFields["Auth.CodeEntry.CodeField"].exists {
            return true
        }
        if app.staticTexts["Auth.CodeEntry.Title"].exists || app.otherElements["Auth.CodeEntry.Title"].exists {
            return true
        }
        if app.otherElements["Auth.Login.ErrorAlert"].exists || app.alerts.firstMatch.exists {
            return true
        }
        return false
    }

    private func spinnerIsRunning() -> Bool {
        let button = app.buttons["Auth.PhoneEntry.ContinueButton"]
        guard button.exists else {
            return false
        }
        return (button.value as? String) == "progress"
    }
}
