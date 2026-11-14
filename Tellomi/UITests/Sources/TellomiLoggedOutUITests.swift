import XCTest

/// Signed-out phone screen. Welcome is skipped. Closed login methods are the
/// backlog's buttons; this tree's phone screen is what the test records.
final class TellomiLoggedOutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPhoneEntrySkipsTheWelcomeCarousel() throws {
        let app = TellomiApp.launch()
        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        let appeared = phone.waitForExistence(timeout: 30)
        tellomiScreenshot("phone-entry")
        guard appeared else {
            TellomiUILog.report(Coverage.phoneEntry, status: "fail", error: "phone field did not appear")
            XCTFail("phone field did not appear")
            return
        }
        let welcome = app.buttons["Auth.Welcome.StartButton"]
        let english = tellomiLabel(app, "使用英文继续").exists || tellomiLabel(app, "Continue in English").exists
        if welcome.exists || english {
            TellomiUILog.report(Coverage.phoneEntry, status: "fail", error: "welcome carousel or Continue in English is on screen")
            XCTFail("welcome carousel is installed")
            return
        }
        TellomiUILog.report(Coverage.phoneEntry, status: "pass")
    }

    func testCountryCodeDefaultsTo86AndContinueFollowsTheNumber() throws {
        let app = TellomiApp.launch()
        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        XCTAssertTrue(phone.waitForExistence(timeout: 30))
        let country = app.textFields["Auth.PhoneEntry.CountryCodeField"]
        let send = app.buttons["Auth.PhoneEntry.ContinueButton"]
        tellomiScreenshot("phone-controls")
        guard country.exists, send.waitForExistence(timeout: 5) else {
            TellomiUILog.report(Coverage.phoneField, status: "fail", error: "country code or continue is missing")
            XCTFail("phone controls missing")
            return
        }
        let countryValue = country.value as? String ?? ""
        guard countryValue.contains("86") else {
            TellomiUILog.report(Coverage.phoneField, status: "fail", error: "country code is \(countryValue)")
            XCTFail("expected default country code 86, saw \(countryValue)")
            return
        }
        let label = send.label
        let phoneVisible = phone.exists
        if !phoneVisible {
            TellomiUILog.report(["I-LOGIN-067", "I-LOGIN-068", "I-LOGIN-155", "I-LOGIN-167"], status: "fail", error: "phone field missing")
        } else {
            TellomiUILog.report(["I-LOGIN-067", "I-LOGIN-068", "I-LOGIN-155", "I-LOGIN-167"], status: "pass")
        }
        // The backlog's 登录 button submits this step. Record the real label.
        if label.contains("登录") {
            XCTAssertFalse(send.isEnabled)
            phone.tap()
            phone.typeText("1380013")
            let enabled = NSPredicate(format: "isEnabled == true")
            expectation(for: enabled, evaluatedWith: send)
            waitForExpectations(timeout: 5)
            TellomiUILog.report(["I-LOGIN-121"], status: "pass")
        } else {
            TellomiUILog.report(["I-LOGIN-121"], status: "fail", error: "submit control label is \(label)")
            XCTFail("backlog expects a 登录 button, continue label is \(label)")
        }
    }

    func testClosedLoginMethods() throws {
        let app = TellomiApp.launch()
        XCTAssertTrue(app.textFields["Auth.PhoneEntry.PhoneNumberField"].waitForExistence(timeout: 30))
        let buttons: [(String, String)] = [
            ("I-LOGIN-114", "Apple 登录"),
            ("I-LOGIN-118", "邮箱登录"),
            ("I-LOGIN-119", "Google 登录"),
            ("I-LOGIN-122", "其他登录方式"),
            ("I-LOGIN-123", "密码登录"),
            ("I-LOGIN-156", "找回账号"),
        ]
        var sawClosedAlert = false
        for (id, title) in buttons {
            let button = app.buttons[title]
            if !button.exists {
                TellomiUILog.report([id], status: "fail", error: "\(title) is not on the phone screen")
                continue
            }
            TellomiApp.tap(button)
            let alert = app.alerts.firstMatch
            if alert.waitForExistence(timeout: 3), alert.label.contains("暂未开放") || alert.staticTexts["暂未开放"].exists {
                sawClosedAlert = true
                TellomiUILog.report([id], status: "pass")
                alert.buttons.firstMatch.tap()
            } else {
                TellomiUILog.report([id], status: "fail", error: "\(title) did not show 暂未开放")
            }
        }
        if sawClosedAlert {
            TellomiUILog.report(["I-LOGIN-163"], status: "pass")
        } else {
            TellomiUILog.report(["I-LOGIN-163"], status: "fail", error: "暂未开放 was not shown")
        }
        tellomiScreenshot("closed-login-methods")
        let failed = buttons.contains { !app.buttons[$0.1].exists }
        if failed || !sawClosedAlert {
            XCTFail("closed login methods are not the backlog's phone-screen buttons")
        }
    }

    func testHomeScreenNameIsTellomi() throws {
        let app = TellomiApp.launch()
        XCTAssertTrue(app.textFields["Auth.PhoneEntry.PhoneNumberField"].waitForExistence(timeout: 30))
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["Tellomi"]
        let found = icon.waitForExistence(timeout: 5)
        tellomiScreenshot("home-icon")
        if found {
            TellomiUILog.report(Coverage.brand, status: "pass")
        } else {
            TellomiUILog.report(Coverage.brand, status: "fail", error: "springboard has no Tellomi icon")
            XCTFail("springboard icon is not Tellomi")
        }
        app.activate()
    }
}
