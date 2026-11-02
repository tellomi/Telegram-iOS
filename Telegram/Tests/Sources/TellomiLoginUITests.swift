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
        app.launchArguments.append("--tellomi-reset-language")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testSendCodeLeavesTheSpinner() throws {
        self.openEmailLogin()
        let email = app.textFields["Auth.PhoneEntry.EmailField"]
        XCTAssertTrue(email.exists, "email login should be the screen after Start")
        XCTAssertFalse(app.textFields["Auth.PhoneEntry.PhoneNumberField"].exists && app.textFields["Auth.PhoneEntry.PhoneNumberField"].isHittable)

        let switchToPhone = app.buttons["Auth.Login.SwitchToPhone"]
        XCTAssertTrue(switchToPhone.waitForExistence(timeout: 5.0))
        switchToPhone.tap()

        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5.0))
        XCTAssertTrue(phone.exists)

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
        switchToPhone.tap()

        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5.0))
        XCTAssertTrue(phone.exists)
        XCTAssertFalse(app.textFields["Auth.PhoneEntry.EmailField"].isHittable)
    }

    func testEmailLoginRowsDoNotOverlap() throws {
        self.openEmailLogin()
        self.dismissLoginKeyboard()
        XCTAssertEqual(app.keyboards.count, 0, "keyboard should be dismissed before the keyboard-down layout check")
        self.assertLoginRowsDoNotOverlap(keyboardUp: false)

        let verify = app.buttons["Auth.PhoneEntry.ContinueButton"]
        let restingMinY = verify.frame.minY
        let email = app.textFields["Auth.PhoneEntry.EmailField"]
        XCTAssertTrue(email.exists)
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
        XCTAssertGreaterThan(app.keyboards.count, 0)
        self.assertLoginRowsDoNotOverlap(keyboardUp: true)
        let headerBottom = app.buttons["Auth.Login.Language"].frame.maxY
        let form = app.scrollViews["Auth.Login.Form"]
        let emailFrame = self.screenFrame(email, scroll: form)
        XCTAssertGreaterThan(emailFrame.minY, headerBottom, "email field is under the header at \(emailFrame), header ends at \(headerBottom)")
        XCTAssertGreaterThan(emailFrame.intersection(form.frame).height, 30.0, "email field is not in the form while the keyboard is up \(emailFrame) form \(form.frame)")
    }

    func testEmailKeyboardDismissesThreeWays() throws {
        self.openEmailLogin()
        let globe = app.buttons["Auth.Login.Language"]
        XCTAssertTrue(globe.waitForExistence(timeout: 5.0))

        self.showEmailKeyboard()
        let headerBlank = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.0)).withOffset(CGVector(dx: app.frame.midX, dy: globe.frame.maxY + 20.0))
        headerBlank.tap()
        self.waitUntilKeyboardHidden()
        XCTAssertEqual(app.keyboards.count, 0, "a tap on the header blank should dismiss the keyboard")

        self.showEmailKeyboard()
        var tappedReturn = false
        for name in ["Done", "完成", "Return", "return"] {
            let button = app.keyboards.buttons[name]
            if button.exists {
                button.tap()
                tappedReturn = true
                break
            }
        }
        XCTAssertTrue(tappedReturn, "keyboard has no Done or Return key")
        self.waitUntilKeyboardHidden()
        XCTAssertEqual(app.keyboards.count, 0, "Done should dismiss the keyboard")

        self.showEmailKeyboard()
        let dragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.0)).withOffset(CGVector(dx: app.frame.midX, dy: globe.frame.maxY + 28.0))
        let dragEnd = dragStart.withOffset(CGVector(dx: 0.0, dy: 140.0))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        self.waitUntilKeyboardHidden()
        XCTAssertEqual(app.keyboards.count, 0, "dragging the form from a blank area should dismiss the keyboard")
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

        let agreement = self.element("Auth.Login.Agreement")
        XCTAssertTrue(agreement.waitForExistence(timeout: 5.0))
        let agreementText = agreement.label
        XCTAssertTrue(agreementText.contains("用户协议") || agreementText.contains("已阅读并同意"), "agreement stayed \(agreementText)")
        let box = app.buttons["Auth.Agreement.Checkbox"]
        let sentence = app.otherElements["Auth.Login.AgreementText"]
        let sentenceText = app.staticTexts["Auth.Login.AgreementText"]
        let text = sentence.exists ? sentence : sentenceText
        XCTAssertTrue(text.waitForExistence(timeout: 5.0))
        XCTAssertLessThanOrEqual(text.frame.minX - box.frame.maxX, 24.0, "Chinese agreement \(text.frame) is not next to the checkbox \(box.frame)")
        XCTAssertGreaterThan(text.frame.minX, box.frame.minX)

        let switchToPhone = app.buttons["Auth.Login.SwitchToPhone"]
        XCTAssertTrue(switchToPhone.waitForExistence(timeout: 5.0))
        switchToPhone.tap()
        let code = app.textFields["Auth.PhoneEntry.CountryCodeField"]
        XCTAssertTrue(code.waitForExistence(timeout: 5.0))
        let value = (code.value as? String) ?? ""
        XCTAssertEqual(self.callingCode(value), "86", "country code was \(value)")
    }

    func testEnglishLanguageUsesDeviceRegionCountryCode() throws {
        self.openEmailLogin()
        self.selectLanguage(subtitle: "English")
        let agreement = self.element("Auth.Login.Agreement")
        XCTAssertTrue(agreement.waitForExistence(timeout: 5.0))
        XCTAssertTrue(agreement.label.contains("Privacy Policy") || agreement.label.contains("I have read"), "agreement stayed \(agreement.label)")

        let switchToPhone = app.buttons["Auth.Login.SwitchToPhone"]
        XCTAssertTrue(switchToPhone.waitForExistence(timeout: 5.0))
        switchToPhone.tap()
        let code = app.textFields["Auth.PhoneEntry.CountryCodeField"]
        XCTAssertTrue(code.waitForExistence(timeout: 5.0))
        let regionElement = self.element("Auth.PhoneEntry.DeviceRegionCode")
        XCTAssertTrue(regionElement.waitForExistence(timeout: 5.0))
        let region = self.callingCode(regionElement.label)
        let field = self.callingCode((code.value as? String) ?? "")
        XCTAssertFalse(region.isEmpty, "device region code was not published")
        XCTAssertEqual(field, region, "English UI used \(field), device region is \(region)")
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

    private func showEmailKeyboard() {
        if app.keyboards.count > 0 {
            return
        }
        let email = app.textFields["Auth.PhoneEntry.EmailField"]
        XCTAssertTrue(email.waitForExistence(timeout: 5.0))
        email.tap()
        let deadline = Date().addingTimeInterval(5.0)
        while Date() < deadline && app.keyboards.count == 0 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertGreaterThan(app.keyboards.count, 0, "email field did not raise the keyboard")
    }

    private func waitUntilKeyboardHidden() {
        let deadline = Date().addingTimeInterval(4.0)
        while Date() < deadline && app.keyboards.count > 0 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    private func dismissLoginKeyboard() {
        if app.keyboards.count == 0 {
            return
        }
        let form = app.scrollViews["Auth.Login.Form"]
        if form.exists {
            form.swipeDown()
        }
        if app.keyboards.count > 0 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        }
        if app.keyboards.count > 0 {
            for name in ["Done", "完成", "Return", "return"] {
                let button = app.keyboards.buttons[name]
                if button.exists {
                    button.tap()
                    break
                }
            }
        }
        let deadline = Date().addingTimeInterval(4.0)
        while Date() < deadline && app.keyboards.count > 0 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    private func selectLanguage(subtitle: String) {
        let globe = app.buttons["Auth.Login.Language"]
        XCTAssertTrue(globe.waitForExistence(timeout: 5.0))
        globe.tap()
        let list = app.tables["Auth.Language.List"]
        XCTAssertTrue(list.waitForExistence(timeout: 5.0))
        var row = list.cells.containing(.staticText, identifier: subtitle).firstMatch
        if !row.waitForExistence(timeout: 2.0) {
            list.swipeUp()
            row = list.cells.containing(.staticText, identifier: subtitle).firstMatch
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5.0))
        row.tap()
    }

    private func callingCode(_ value: String) -> String {
        return value.filter { $0.isNumber }
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
        let form = app.scrollViews["Auth.Login.Form"]
        if keyboardUp {
            XCTAssertTrue(form.waitForExistence(timeout: 2.0))
            let deadline = Date().addingTimeInterval(3.0)
            while Date() < deadline {
                let formClearsButton = form.frame.maxY <= verify.frame.minY + 1.0
                let otherFrame = self.screenFrame(other, scroll: form)
                let recoverFrame = self.screenFrame(recover, scroll: form)
                if formClearsButton && self.frameIsOnScreen(otherFrame, in: form) && self.frameIsOnScreen(recoverFrame, in: form) && self.rectsAreDisjoint(otherFrame, verify.frame) && self.rectsAreDisjoint(recoverFrame, agreement.frame) {
                    break
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            XCTAssertLessThanOrEqual(form.frame.maxY, verify.frame.minY + 1.0, "login column should end above the verify button while the keyboard is up, form \(form.frame) button \(verify.frame)")
            let otherFrame = self.screenFrame(other, scroll: form)
            let recoverFrame = self.screenFrame(recover, scroll: form)
            XCTAssertTrue(self.frameIsOnScreen(otherFrame, in: form), "other methods should stay on screen above the keyboard, frame \(otherFrame) form \(form.frame)")
            XCTAssertTrue(self.frameIsOnScreen(recoverFrame, in: form), "recover account should stay on screen above the keyboard, frame \(recoverFrame) form \(form.frame)")
        }
        let otherFrame = self.screenFrame(other, scroll: form.exists ? form : nil)
        let recoverFrame = self.screenFrame(recover, scroll: form.exists ? form : nil)
        self.assertRectDisjoint(otherFrame, agreement.frame, "other methods and agreement")
        self.assertRectDisjoint(otherFrame, verify.frame, "other methods and verify")
        self.assertRectDisjoint(recoverFrame, agreement.frame, "recover account and agreement")
        self.assertRectDisjoint(recoverFrame, verify.frame, "recover account and verify")
        self.assertDisjoint(agreement, verify, "agreement and verify")
    }

    /// `ASScrollView` used to expose children in content coordinates. A frame that sits above the
    /// scroll view is shifted by the scroll view's origin; a frame already on screen is left alone.
    private func screenFrame(_ element: XCUIElement, scroll: XCUIElement?) -> CGRect {
        let frame = element.frame
        guard let scroll, scroll.exists, scroll.frame.width > 1.0, scroll.frame.height > 1.0 else {
            return frame
        }
        if frame.intersects(scroll.frame) {
            return frame
        }
        let shifted = frame.offsetBy(dx: scroll.frame.minX, dy: scroll.frame.minY)
        if shifted.intersects(scroll.frame) {
            return shifted
        }
        return frame
    }

    private func frameIsOnScreen(_ frame: CGRect, in scroll: XCUIElement) -> Bool {
        let visible = frame.intersection(scroll.frame)
        return !visible.isNull && visible.width > 20.0 && visible.height > 20.0
    }

    private func rectsAreDisjoint(_ a: CGRect, _ b: CGRect) -> Bool {
        let hit = a.intersection(b)
        return hit.isNull || hit.width < 1.0 || hit.height < 1.0
    }

    private func assertRectDisjoint(_ a: CGRect, _ b: CGRect, _ name: String) {
        let hit = a.intersection(b)
        XCTAssertTrue(hit.isNull || hit.width < 1.0 || hit.height < 1.0, "\(name) overlap \(a) and \(b)")
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
