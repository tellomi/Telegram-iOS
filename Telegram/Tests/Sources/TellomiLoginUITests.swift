import XCTest

/// Headless checks for the phone-default login. The suite is `//Telegram:iOSAppUITestSuite`.
/// Send-code stops at the code screen or an error alert.
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

    func testPhoneLoginIsTheDefault() throws {
        self.openPhoneLogin()
        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        XCTAssertTrue(phone.isHittable)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertFalse(self.keyboardIsVisible(), "phone login should open without a keyboard")
        XCTAssertFalse(app.textFields["Auth.PhoneEntry.EmailField"].isHittable)
        XCTAssertTrue(app.buttons["Auth.Login.Email"].isHittable)
        XCTAssertFalse(app.buttons["Auth.Login.Apple"].exists)
        XCTAssertFalse(app.buttons["Auth.Login.Google"].exists)
        XCTAssertFalse(app.buttons["Auth.Login.OtherMethods"].exists)
        XCTAssertFalse(app.buttons["Auth.Login.RecoverAccount"].exists)
        XCTAssertFalse(app.buttons["Auth.PhoneEntry.EmailSwitch"].exists)
        let agreement = app.descendants(matching: .any)["Auth.Login.Agreement"]
        XCTAssertTrue(agreement.waitForExistence(timeout: 5.0))
        XCTAssertFalse(agreement.label.isEmpty, "agreement accessibility label is empty")
        XCTAssertTrue(agreement.label.contains("Privacy") || agreement.label.contains("隐私") || agreement.label.contains("隱私"), "agreement label is truncated: \(agreement.label)")
        let send = app.buttons["Auth.PhoneEntry.ContinueButton"]
        XCTAssertTrue(send.waitForExistence(timeout: 5.0))
        XCTAssertLessThan(send.frame.maxY, agreement.frame.minY, "verify button overlaps the agreement row")
    }

    func testContinueStaysDisabledUntilTheNumberIsComplete() throws {
        self.openPhoneLogin()
        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        let send = app.buttons["Auth.PhoneEntry.ContinueButton"]
        XCTAssertTrue(send.waitForExistence(timeout: 5.0))
        phone.tap()
        phone.typeText("138")
        XCTAssertFalse(send.isEnabled)
        phone.typeText("00000000")
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: send)
        waitForExpectations(timeout: 5.0)
    }

    func testEmailScreenOpensFromThePhoneHome() throws {
        self.openPhoneLogin()
        app.buttons["Auth.Login.Email"].tap()
        let email = app.textFields["Auth.PhoneEntry.EmailField"]
        XCTAssertTrue(email.waitForExistence(timeout: 5.0))
        XCTAssertTrue(email.isHittable)
        XCTAssertFalse(app.textFields["Auth.PhoneEntry.PhoneNumberField"].isHittable)
        XCTAssertFalse(app.buttons["Auth.PhoneEntry.EmailSwitch"].exists)
        XCTAssertFalse(app.buttons["Auth.Login.More"].exists)
        XCTAssertFalse(app.buttons["Auth.Login.CircleApple"].exists)
    }

    func testAgreementPromptDoesNotSendTheCode() throws {
        self.openPhoneLogin()
        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        phone.tap()
        phone.typeText("13800000000")
        let send = app.buttons["Auth.PhoneEntry.ContinueButton"]
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: send)
        waitForExpectations(timeout: 5.0)
        send.tap()
        let agree = app.buttons["Auth.Login.Agree"]
        XCTAssertTrue(agree.waitForExistence(timeout: 5.0))
        XCTAssertFalse(app.textFields["Auth.CodeEntry.CodeField"].exists)
        app.buttons["Auth.Login.Disagree"].tap()
        XCTAssertFalse(agree.waitForExistence(timeout: 2.0))
    }

    func testLanguageSwitcherListsTheThreeBuiltInLanguages() throws {
        self.openPhoneLogin()
        let globe = app.buttons["Auth.Login.Language"]
        XCTAssertTrue(globe.waitForExistence(timeout: 5.0))
        globe.tap()
        XCTAssertTrue(app.buttons["简体中文"].waitForExistence(timeout: 5.0))
        XCTAssertTrue(app.buttons["繁體中文"].exists)
        XCTAssertTrue(app.buttons["English"].exists)
    }

    func testCountryPickerOpens() throws {
        self.openPhoneLogin()
        let country = app.buttons["Auth.PhoneEntry.CountryButton"]
        XCTAssertTrue(country.waitForExistence(timeout: 5.0))
        let language = app.buttons["Auth.Login.Language"]
        if language.label.contains("中文") {
            let localized = country.label.unicodeScalars.contains { scalar in
                scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
            }
            XCTAssertTrue(localized, "country accessibility label is not localized: \(country.label)")
        }
        country.tap()
        let list = app.tables["Auth.Country.List"]
        XCTAssertTrue(list.waitForExistence(timeout: 5.0))
        XCTAssertGreaterThan(list.cells.count, 0)
    }

    func testEnglishAgreementWrapsAndCheckboxKeepsTheKeyboard() throws {
        self.openPhoneLogin()
        let language = app.buttons["Auth.Login.Language"]
        XCTAssertTrue(language.waitForExistence(timeout: 5.0))
        if !language.label.contains("English") {
            language.tap()
            let english = app.buttons["English"]
            XCTAssertTrue(english.waitForExistence(timeout: 5.0))
            english.tap()
        }
        let agreement = app.descendants(matching: .any)["Auth.Login.Agreement"]
        XCTAssertTrue(agreement.waitForExistence(timeout: 5.0))
        let englishSentence = NSPredicate(format: "label CONTAINS %@", "Privacy")
        expectation(for: englishSentence, evaluatedWith: agreement)
        waitForExpectations(timeout: 5.0)
        XCTAssertGreaterThan(agreement.frame.height, 30.0, "English agreement is still one line: \(agreement.frame) \(agreement.label)")

        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        let checkbox = app.buttons["Auth.Agreement.Checkbox"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5.0))
        phone.tap()
        let hittable = NSPredicate(format: "isHittable == true")
        expectation(for: hittable, evaluatedWith: checkbox)
        waitForExpectations(timeout: 5.0)
        XCTAssertTrue(self.keyboardIsVisible(), "tapping the phone field should show the keyboard")
        checkbox.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertTrue(self.keyboardIsVisible(), "toggling the agreement checkbox dismissed the keyboard")
        XCTAssertEqual(checkbox.value as? String, "1")
    }

    func testSendCodeLeavesThePhoneScreen() throws {
        self.openPhoneLogin()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertFalse(self.keyboardIsVisible(), "phone login should open without a keyboard")
        let checkbox = app.buttons["Auth.Agreement.Checkbox"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5.0))
        XCTAssertTrue(checkbox.isHittable)
        checkbox.tap()
        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        phone.tap()
        phone.typeText("13800000000")
        let send = app.buttons["Auth.PhoneEntry.ContinueButton"]
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: send)
        waitForExpectations(timeout: 5.0)
        send.tap()

        let deadline = Date().addingTimeInterval(12.0)
        while Date() < deadline {
            if app.textFields["Auth.CodeEntry.CodeField"].exists {
                return
            }
            let alert = app.descendants(matching: .any)["Auth.Login.ErrorAlert"]
            if alert.exists {
                let nested = alert.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }.joined(separator: "\n")
                let message = [alert.label, nested].filter { !$0.isEmpty }.joined(separator: "\n")
                XCTFail("server error alert: \(message.isEmpty ? "(no text)" : message)")
                return
            }
            if app.alerts.firstMatch.exists {
                XCTFail("system alert: \(app.alerts.firstMatch.label)")
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        XCTFail("send code did not reach the code screen or an error alert")
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

    private func keyboardIsVisible() -> Bool {
        return app.keyboards.firstMatch.exists
    }
}
