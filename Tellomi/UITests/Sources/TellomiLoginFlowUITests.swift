import XCTest

/// Production test numbers in `99966XYYYY`. The code is the server's fixed
/// test-range code, not the dev provider code `12345`.
final class TellomiLoginFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAccountASubmitsTheFixedTestCode() throws {
        switch TellomiTestAccounts.lookup("TELLOMI_TEST_PHONE_A") {
        case .unset:
            TellomiUILog.report(Coverage.codeFlow, status: "blocked", error: "TELLOMI_TEST_PHONE_A is unset")
            throw XCTSkip("TELLOMI_TEST_PHONE_A is unset")
        case .refused(let reason):
            TellomiUILog.report(Coverage.codeFlow, status: "blocked", error: reason)
            throw XCTSkip(reason)
        case .ready:
            break
        }
        let app = TellomiApp.launch()
        let outcome = TellomiSession.signIn(app, account: TellomiTestAccounts.lookup("TELLOMI_TEST_PHONE_A"), test: self)
        tellomiScreenshot("account-a")
        reportCodeFlow(outcome)
        if !outcome.reachedCodeScreen {
            XCTFail(outcome.detail)
        }
    }

    func testAccountBReachesTheCodeScreen() throws {
        switch TellomiTestAccounts.lookup("TELLOMI_TEST_PHONE_B") {
        case .unset:
            throw XCTSkip("TELLOMI_TEST_PHONE_B is unset")
        case .refused(let reason):
            XCTFail(reason)
            return
        case .ready:
            break
        }
        let app = TellomiApp.launch()
        let outcome = TellomiSession.signIn(app, account: TellomiTestAccounts.lookup("TELLOMI_TEST_PHONE_B"), test: self)
        tellomiScreenshot("account-b")
        // Account A owns the backlog ids. B only proves the second secret
        // reaches the same code screen and is not a real subscriber number.
        XCTAssertTrue(outcome.reachedCodeScreen, outcome.detail)
    }

    private func reportCodeFlow(_ outcome: TellomiSession.Outcome) {
        if outcome.confirmLabel == "确定" {
            TellomiUILog.report(["I-LOGIN-004"], status: "pass")
        } else if let label = outcome.confirmLabel {
            TellomiUILog.report(["I-LOGIN-004"], status: "fail", error: "confirm button label is \(label)")
        } else {
            TellomiUILog.report(["I-LOGIN-004"], status: "blocked", error: "no phone confirm button")
        }
        if !outcome.reachedCodeScreen {
            TellomiUILog.report(["I-LOGIN-116"], status: "fail", error: outcome.detail)
        } else if !outcome.tappedCodeLoginButton {
            let label = outcome.submitLabel.isEmpty ? "phone continue" : outcome.submitLabel
            TellomiUILog.report(["I-LOGIN-116"], status: "fail", error: "no 验证码登录 button; code was requested from \(label)")
        } else if outcome.signedIn || outcome.signUp {
            TellomiUILog.report(["I-LOGIN-116"], status: "pass")
        } else {
            TellomiUILog.report(["I-LOGIN-116"], status: "fail", error: outcome.detail)
        }
        if !outcome.sawCodeNext {
            TellomiUILog.report(["I-LOGIN-222"], status: "blocked", error: "code screen has no 下一步 button")
        } else if outcome.signedIn || outcome.signUp {
            TellomiUILog.report(["I-LOGIN-222"], status: "pass")
        } else {
            TellomiUILog.report(["I-LOGIN-222"], status: "fail", error: outcome.detail)
        }
        if outcome.agreementVisible {
            TellomiUILog.report(["I-LOGIN-173", "I-LOGIN-174", "I-LOGIN-212"], status: outcome.signedIn ? "pass" : "fail", error: outcome.detail)
        } else {
            TellomiUILog.report(["I-LOGIN-173", "I-LOGIN-174", "I-LOGIN-212"], status: "blocked", error: "sign-up agreement was not shown")
        }
    }
}
