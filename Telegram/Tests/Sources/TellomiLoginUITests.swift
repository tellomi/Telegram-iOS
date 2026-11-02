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
        XCTAssertFalse(app.textFields["Auth.PhoneEntry.EmailField"].isHittable)
        XCTAssertTrue(app.buttons["Auth.Login.Email"].isHittable)
        XCTAssertTrue(app.buttons["Auth.Login.OtherMethods"].isHittable)
        XCTAssertTrue(app.buttons["Auth.Login.RecoverAccount"].isHittable)
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

    func testPasswordScreenReturnsToThePhoneCode() throws {
        self.openPhoneLogin()
        let switchButton = app.buttons["Auth.PhoneEntry.EmailSwitch"]
        XCTAssertTrue(switchButton.waitForExistence(timeout: 5.0))
        switchButton.tap()
        let password = app.secureTextFields["Auth.PhoneEntry.PasswordField"]
        let passwordField = password.exists ? password : app.textFields["Auth.PhoneEntry.PasswordField"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5.0))
        XCTAssertTrue(passwordField.isHittable)
        switchButton.tap()
        XCTAssertTrue(app.textFields["Auth.PhoneEntry.PhoneNumberField"].waitForExistence(timeout: 5.0))
        XCTAssertFalse(passwordField.isHittable)
    }

    func testEmailScreenOpensFromThePhoneHome() throws {
        self.openPhoneLogin()
        app.buttons["Auth.Login.Email"].tap()
        let email = app.textFields["Auth.PhoneEntry.EmailField"]
        XCTAssertTrue(email.waitForExistence(timeout: 5.0))
        XCTAssertTrue(email.isHittable)
        XCTAssertFalse(app.textFields["Auth.PhoneEntry.PhoneNumberField"].isHittable)
        XCTAssertTrue(app.buttons["Auth.Login.More"].waitForExistence(timeout: 5.0))
        XCTAssertFalse(app.buttons["Auth.Login.CircleEmail"].isHittable)
    }

    func testOtherMethodsSheetIsRecoverAndCancel() throws {
        self.openPhoneLogin()
        app.buttons["Auth.Login.OtherMethods"].tap()
        let recover = self.button(named: ["找回账号", "找回帳號", "Recover account"])
        let cancel = self.button(named: ["取消", "Cancel"])
        XCTAssertTrue(recover.waitForExistence(timeout: 5.0))
        XCTAssertTrue(cancel.waitForExistence(timeout: 5.0))
        XCTAssertFalse(app.buttons["微博登录"].exists)
        XCTAssertFalse(app.buttons["微信登录"].exists)
        XCTAssertFalse(app.buttons["QQ 登录"].exists)
        cancel.tap()
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
        country.tap()
        let list = app.tables["Auth.Country.List"]
        XCTAssertTrue(list.waitForExistence(timeout: 5.0))
        XCTAssertGreaterThan(list.cells.count, 0)
    }

    func testSendCodeLeavesThePhoneScreen() throws {
        self.openPhoneLogin()
        app.buttons["Auth.Agreement.Checkbox"].tap()
        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        phone.tap()
        phone.typeText("13800000000")
        let send = app.buttons["Auth.PhoneEntry.ContinueButton"]
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: send)
        waitForExpectations(timeout: 5.0)
        send.tap()

        let deadline = Date().addingTimeInterval(30.0)
        while Date() < deadline {
            if app.textFields["Auth.CodeEntry.CodeField"].exists || app.alerts.firstMatch.exists {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        XCTFail("send code did not reach the code screen or an error alert within 30s")
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

    private func button(named titles: [String]) -> XCUIElement {
        for title in titles {
            let button = app.buttons[title]
            if button.exists {
                return button
            }
        }
        return app.buttons[titles[0]]
    }
}
