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
        self.openEmailLogin()
        let email = app.textFields["Auth.PhoneEntry.EmailField"]
        XCTAssertTrue(email.isHittable, "email login should be the screen after Start")
        XCTAssertFalse(app.textFields["Auth.PhoneEntry.PhoneNumberField"].isHittable)

        let switchToPhone = app.buttons["Auth.Login.SwitchToPhone"]
        XCTAssertTrue(switchToPhone.waitForExistence(timeout: 5.0))
        switchToPhone.tap()

        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5.0))
        XCTAssertTrue(phone.isHittable)

        let checkbox = app.buttons["Auth.Agreement.Checkbox"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5.0))
        checkbox.tap()

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

    func testSwitchToPhoneOpensThePhoneScreen() throws {
        self.openEmailLogin()

        let switchToPhone = app.buttons["Auth.Login.SwitchToPhone"]
        XCTAssertTrue(switchToPhone.waitForExistence(timeout: 5.0))
        XCTAssertTrue(switchToPhone.isHittable)
        switchToPhone.tap()

        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5.0))
        XCTAssertTrue(phone.isHittable)
        XCTAssertFalse(app.textFields["Auth.PhoneEntry.EmailField"].isHittable)
    }

    func testEmailLoginRowsDoNotOverlap() throws {
        self.openEmailLogin()
        let verify = app.buttons["Auth.PhoneEntry.ContinueButton"]
        XCTAssertTrue(verify.waitForExistence(timeout: 5.0))
        let screenHeight = app.frame.height
        // The email field takes focus after Start, so the keyboard may already be up.
        let keyboardAlreadyUp = verify.frame.height > 1.0 && verify.frame.maxY < screenHeight - 160.0
        if !keyboardAlreadyUp {
            self.assertLoginRowsDoNotOverlap(keyboardUp: false)
            let email = app.textFields["Auth.PhoneEntry.EmailField"]
            XCTAssertTrue(email.isHittable)
            let restingMinY = verify.frame.minY
            email.tap()
            let deadline = Date().addingTimeInterval(5.0)
            var raised = false
            while Date() < deadline {
                if verify.exists, verify.frame.minY < restingMinY - 80.0 {
                    raised = true
                    break
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            XCTAssertTrue(raised, "verify button did not move up with the keyboard (was \(restingMinY), now \(verify.frame.minY))")
        }
        self.assertLoginRowsDoNotOverlap(keyboardUp: true)
    }

    func testChineseLanguageDefaultsCountryCodeTo86() throws {
        self.openEmailLogin()
        let globe = app.buttons["Auth.Login.Language"]
        XCTAssertTrue(globe.waitForExistence(timeout: 5.0))
        globe.tap()
        let list = app.tables["Auth.Language.List"]
        XCTAssertTrue(list.waitForExistence(timeout: 5.0))
        // Two rows are titled 简体中文 (Classic and the normal pack). The English subtitle is one row.
        var simplified = list.cells.containing(.staticText, identifier: "Chinese (Simplified)").firstMatch
        if !simplified.waitForExistence(timeout: 2.0) {
            list.swipeUp()
            simplified = list.cells.containing(.staticText, identifier: "Chinese (Simplified)").firstMatch
        }
        XCTAssertTrue(simplified.waitForExistence(timeout: 5.0))
        simplified.tap()

        let switchToPhone = app.buttons["Auth.Login.SwitchToPhone"]
        XCTAssertTrue(switchToPhone.waitForExistence(timeout: 5.0))
        switchToPhone.tap()
        let code = app.textFields["Auth.PhoneEntry.CountryCodeField"]
        XCTAssertTrue(code.waitForExistence(timeout: 5.0))
        let value = (code.value as? String) ?? ""
        XCTAssertTrue(value.contains("86"), "country code was \(value)")
    }

    func testLanguagePickerListsMoreThanThreeLanguages() throws {
        self.openEmailLogin()

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
        self.openEmailLogin()
        let switchToPhone = app.buttons["Auth.Login.SwitchToPhone"]
        XCTAssertTrue(switchToPhone.waitForExistence(timeout: 5.0))
        switchToPhone.tap()

        let country = app.buttons["Auth.PhoneEntry.CountryButton"]
        XCTAssertTrue(country.waitForExistence(timeout: 5.0))
        country.tap()

        let list = app.tables["Auth.Country.List"]
        XCTAssertTrue(list.waitForExistence(timeout: 5.0))
        XCTAssertGreaterThan(list.cells.count, 0)
    }

    private func openEmailLogin() {
        app.launch()
        let start = app.buttons["Auth.Welcome.StartButton"]
        if start.waitForExistence(timeout: 20.0) {
            start.tap()
        }
        let email = app.textFields["Auth.PhoneEntry.EmailField"]
        XCTAssertTrue(email.waitForExistence(timeout: 25.0), "email login did not appear after Start")
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

    private func assertLoginRowsDoNotOverlap(keyboardUp: Bool) {
        let other = app.buttons["Auth.Login.OtherMethods"]
        let recover = app.buttons["Auth.Login.RecoverAccount"]
        let agreement = self.element("Auth.Login.Agreement")
        let verify = app.buttons["Auth.PhoneEntry.ContinueButton"]
        XCTAssertTrue(other.waitForExistence(timeout: 5.0))
        XCTAssertTrue(recover.waitForExistence(timeout: 5.0))
        XCTAssertTrue(agreement.waitForExistence(timeout: 5.0))
        XCTAssertTrue(verify.waitForExistence(timeout: 5.0))
        if keyboardUp {
            let form = app.otherElements["Auth.Login.Form"]
            XCTAssertTrue(form.waitForExistence(timeout: 2.0))
            let deadline = Date().addingTimeInterval(3.0)
            while Date() < deadline {
                let formClearsButton = form.frame.maxY <= verify.frame.minY + 1.0
                if formClearsButton && other.isHittable && recover.isHittable && self.framesAreDisjoint(other, verify) && self.framesAreDisjoint(recover, agreement) {
                    break
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            XCTAssertLessThanOrEqual(form.frame.maxY, verify.frame.minY + 1.0, "login column should end above the verify button while the keyboard is up, form \(form.frame) button \(verify.frame)")
            XCTAssertTrue(other.isHittable, "other methods should stay on screen above the keyboard, frame \(other.frame)")
            XCTAssertTrue(recover.isHittable, "recover account should stay on screen above the keyboard, frame \(recover.frame)")
        }
        self.assertDisjoint(other, agreement, "other methods and agreement")
        self.assertDisjoint(other, verify, "other methods and verify")
        self.assertDisjoint(recover, agreement, "recover account and agreement")
        self.assertDisjoint(recover, verify, "recover account and verify")
        self.assertDisjoint(agreement, verify, "agreement and verify")
    }

    private func framesAreDisjoint(_ a: XCUIElement, _ b: XCUIElement) -> Bool {
        let hit = a.frame.intersection(b.frame)
        return hit.isNull || hit.width < 1.0 || hit.height < 1.0
    }

    private func element(_ identifier: String) -> XCUIElement {
        let other = app.otherElements[identifier]
        if other.exists {
            return other
        }
        let text = app.staticTexts[identifier]
        if text.exists {
            return text
        }
        return app.buttons[identifier]
    }

    private func assertDisjoint(_ a: XCUIElement, _ b: XCUIElement, _ name: String) {
        let hit = a.frame.intersection(b.frame)
        XCTAssertTrue(hit.isNull || hit.width < 1.0 || hit.height < 1.0, "\(name) overlap \(a.frame) and \(b.frame)")
    }

    private func spinnerIsRunning() -> Bool {
        let button = app.buttons["Auth.PhoneEntry.ContinueButton"]
        guard button.exists else {
            return false
        }
        return (button.value as? String) == "progress"
    }
}
