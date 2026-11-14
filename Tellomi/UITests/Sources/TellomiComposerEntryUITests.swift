import XCTest

/// UI entry only. This test does not toggle `tellomi_ai_compose_enabled`
/// or any other AI compose switch.
final class TellomiComposerEntryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAIAndTranslateEntriesStayAtTheirDefaults() throws {
        switch TellomiTestAccounts.lookup("TELLOMI_TEST_PHONE_A") {
        case .unset:
            TellomiUILog.report(Coverage.translationEntry, status: "blocked", error: "TELLOMI_TEST_PHONE_A is unset")
            throw XCTSkip("TELLOMI_TEST_PHONE_A is unset")
        case .refused(let reason):
            TellomiUILog.report(Coverage.translationEntry, status: "blocked", error: reason)
            throw XCTSkip(reason)
        case .ready:
            break
        }
        let app = TellomiApp.launch()
        let outcome = TellomiSession.signIn(app, account: TellomiTestAccounts.lookup("TELLOMI_TEST_PHONE_A"), test: self)
        guard outcome.signedIn else {
            TellomiUILog.report(Coverage.translationEntry, status: "blocked", error: outcome.detail)
            tellomiScreenshot("composer-blocked")
            return
        }
        tellomiDismissSystemAlerts(app)
        let chats = app.tabBars.buttons["聊天"].exists ? app.tabBars.buttons["聊天"] : app.buttons["聊天"]
        if chats.exists {
            TellomiApp.tap(chats)
        }
        let saved = app.staticTexts["收藏夹"].exists ? app.staticTexts["收藏夹"] : app.staticTexts["Saved Messages"]
        guard saved.waitForExistence(timeout: 5) else {
            TellomiUILog.report(["I-TRANSLATION-052", "I-TRANSLATION-057", "I-TRANSLATION-061", "I-TRANSLATION-062", "I-TRANSLATION-063", "I-TRANSLATION-066"], status: "blocked", error: "no Saved Messages chat to open a composer")
            reportTranslateRows(app)
            return
        }
        TellomiApp.tap(saved)
        let field = app.textViews.firstMatch
        guard field.waitForExistence(timeout: 8) else {
            TellomiUILog.report(["I-TRANSLATION-052", "I-TRANSLATION-057", "I-TRANSLATION-061", "I-TRANSLATION-062", "I-TRANSLATION-063", "I-TRANSLATION-066"], status: "blocked", error: "composer did not appear")
            reportTranslateRows(app)
            return
        }
        tellomiScreenshot("composer")
        let hidden = ["校对", "X50", "修正", "风格", "翻译", "拷贝译文"]
        let ids = ["I-TRANSLATION-052", "I-TRANSLATION-057", "I-TRANSLATION-061", "I-TRANSLATION-062", "I-TRANSLATION-063", "I-TRANSLATION-066"]
        for (id, label) in zip(ids, hidden) {
            let present = app.buttons[label].exists || app.staticTexts[label].exists
            if present {
                TellomiUILog.report([id], status: "fail", error: "\(label) is visible while AI compose stays at its default")
            } else {
                TellomiUILog.report([id], status: "pass")
            }
        }
        reportTranslateRows(app)
    }

    private func reportTranslateRows(_ app: XCUIApplication) {
        let me = app.tabBars.buttons["我"].exists ? app.tabBars.buttons["我"] : app.buttons["我"]
        if me.exists {
            TellomiApp.tap(me)
        }
        let settings = app.navigationBars.buttons["设置"]
        if settings.exists {
            TellomiApp.tap(settings)
        } else if app.buttons["设置"].exists {
            TellomiApp.tap(app.buttons["设置"])
        }
        guard tellomiScrollToLabel(app, "语言").exists else {
            TellomiUILog.report(["I-TRANSLATION-073"], status: "blocked", error: "语言 row was not opened")
            return
        }
        TellomiApp.tap(tellomiLabel(app, "语言"))
        let translate = tellomiScrollToLabel(app, "翻译")
        if translate.exists {
            TellomiApp.tap(translate)
        }
        let show = tellomiScrollToLabel(app, "显示翻译按钮").exists || tellomiLabel(app, "显示翻译").exists
        if show {
            TellomiUILog.report(["I-TRANSLATION-073"], status: "pass")
        } else {
            TellomiUILog.report(["I-TRANSLATION-073"], status: "blocked", error: "显示翻译按钮 was not on the language screen")
        }
        tellomiScreenshot("translate-rows")
    }
}
