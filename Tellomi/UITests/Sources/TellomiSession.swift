import XCTest

enum TellomiSession {
    struct Outcome {
        var reachedCodeScreen = false
        var confirmLabel: String?
        var submitLabel = ""
        var sawCodeNext = false
        var tappedCodeLoginButton = false
        var signedIn = false
        var signUp = false
        var agreementVisible = false
        var detail = ""
    }

    /// Types the test-range number and the fixed code. Does not log the number.
    static func signIn(_ app: XCUIApplication, account: TellomiAccountLookup, test: XCTestCase) -> Outcome {
        var outcome = Outcome()
        guard case let .ready(countryCode, nationalNumber, code) = account else {
            outcome.detail = "account is not ready"
            return outcome
        }
        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        guard phone.waitForExistence(timeout: 30) else {
            outcome.detail = "phone field did not appear"
            return outcome
        }
        let country = app.textFields["Auth.PhoneEntry.CountryCodeField"]
        guard country.exists else {
            outcome.detail = "country code field missing"
            return outcome
        }
        country.tap()
        for _ in 0..<8 {
            country.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        country.typeText(countryCode)
        phone.tap()
        phone.typeText(nationalNumber)
        let send = app.buttons["Auth.PhoneEntry.ContinueButton"]
        guard send.waitForExistence(timeout: 5) else {
            outcome.detail = "continue button missing"
            return outcome
        }
        outcome.submitLabel = send.label
        if send.label.contains("验证码登录") {
            outcome.tappedCodeLoginButton = true
        }
        guard send.isEnabled else {
            outcome.detail = "continue stayed disabled for the test number"
            return outcome
        }
        TellomiApp.tap(send)
        let confirm = app.buttons["Auth.PhoneConfirm.ContinueButton"]
        if confirm.waitForExistence(timeout: 8) {
            outcome.confirmLabel = confirm.label
            TellomiApp.tap(confirm)
        }
        let codeField = app.textFields["Auth.CodeEntry.CodeField"]
        guard codeField.waitForExistence(timeout: 40) else {
            let alert = app.alerts.firstMatch
            if alert.exists {
                outcome.detail = "no code screen; alert \(alert.label)"
            } else {
                outcome.detail = "code screen did not appear"
            }
            return outcome
        }
        outcome.reachedCodeScreen = true
        codeField.tap()
        codeField.typeText(code)
        let next = app.buttons["下一步"]
        if next.exists {
            outcome.sawCodeNext = true
            if next.isEnabled {
                TellomiApp.tap(next)
            }
        }
        let signedIn = app.buttons["聊天"].waitForExistence(timeout: 25) || app.buttons["Chats"].exists || app.tabBars.buttons["聊天"].exists || app.tabBars.buttons["Chats"].exists
        if signedIn {
            outcome.signedIn = true
            test.tellomiDismissSystemAlerts(app)
            return outcome
        }
        let firstName = app.textFields["Auth.SetName.FirstNameField"]
        if firstName.waitForExistence(timeout: 8) {
            outcome.signUp = true
            let terms = test.tellomiLabel(app, "《用户服务协议》")
            let privacy = test.tellomiLabel(app, "《隐私政策》")
            let checkbox = app.buttons["Auth.Agreement.Checkbox"]
            outcome.agreementVisible = terms.exists || privacy.exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS '用户服务协议'")).firstMatch.exists
            if checkbox.exists {
                TellomiApp.tap(checkbox)
            }
            firstName.tap()
            firstName.typeText("UI")
            let lastName = app.textFields["Auth.SetName.LastNameField"]
            if lastName.exists {
                lastName.tap()
                lastName.typeText("Test")
            }
            let done = app.buttons["Auth.SetName.ContinueButton"]
            if done.exists && done.isEnabled {
                TellomiApp.tap(done)
            }
            if app.buttons["聊天"].waitForExistence(timeout: 20) || app.tabBars.buttons["聊天"].exists {
                outcome.signedIn = true
            } else {
                outcome.detail = "sign-up screen did not finish"
            }
            return outcome
        }
        outcome.detail = "code was submitted and neither the tab bar nor sign-up appeared"
        return outcome
    }
}
