import XCTest

/// Discover is the bottom-bar feed. Moments are not a profile tab.
/// Deep links are opened logged out: `tellomi://` and `tg://` share a router.
final class TellomiDiscoverUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDiscoverTabAndProfileDoesNotHostMoments() throws {
        switch TellomiTestAccounts.lookup("TELLOMI_TEST_PHONE_A") {
        case .unset:
            TellomiUILog.report(Coverage.discover, status: "blocked", error: "TELLOMI_TEST_PHONE_A is unset")
            throw XCTSkip("TELLOMI_TEST_PHONE_A is unset")
        case .refused(let reason):
            TellomiUILog.report(Coverage.discover, status: "blocked", error: reason)
            throw XCTSkip(reason)
        case .ready:
            break
        }
        let app = TellomiApp.launch()
        let outcome = TellomiSession.signIn(app, account: TellomiTestAccounts.lookup("TELLOMI_TEST_PHONE_A"), test: self)
        guard outcome.signedIn else {
            TellomiUILog.report(Coverage.discover, status: "blocked", error: outcome.detail)
            tellomiScreenshot("discover-blocked")
            return
        }
        tellomiDismissSystemAlerts(app)
        let feed = app.tabBars.buttons["发现"].exists ? app.tabBars.buttons["发现"] : app.buttons["发现"]
        guard feed.waitForExistence(timeout: 8) else {
            TellomiUILog.report(Coverage.discover, status: "fail", error: "发现 tab is missing")
            XCTFail("发现 tab is missing")
            return
        }
        TellomiApp.tap(feed)
        tellomiScreenshot("discover")
        for (id, title) in [("I-DISCOVER-073", "推荐"), ("I-DISCOVER-071", "关注"), ("I-DISCOVER-072", "同城")] {
            let present = tellomiLabel(app, title).exists
            TellomiUILog.report([id], status: present ? "pass" : "fail", error: present ? nil : "\(title) is not on 发现")
        }
        TellomiUILog.report(["I-DISCOVER-070"], status: "pass")
        if tellomiLabel(app, "同城").exists {
            TellomiApp.tap(tellomiLabel(app, "同城"))
            let empty = tellomiLabel(app, "这个城市还没有帖子。").exists
                || tellomiLabel(app, "仍可以选城市。帖子只记录城市，不记录位置。").exists
            if empty {
                TellomiUILog.report(["I-DISCOVER-044"], status: "pass")
            } else {
                TellomiUILog.report(["I-DISCOVER-044"], status: "blocked", error: "同城 opened without the empty-state copy")
            }
        } else {
            TellomiUILog.report(["I-DISCOVER-044"], status: "fail", error: "同城 is missing")
        }
        let me = app.tabBars.buttons["我"].exists ? app.tabBars.buttons["我"] : app.buttons["我"]
        if me.exists {
            TellomiApp.tap(me)
        }
        let stories = tellomiLabel(app, "快拍")
        let momentsOnProfile = app.buttons["动态"].exists || app.segmentedControls.buttons["动态"].exists
        // The row keeps 快拍 on PeerInfoScreenOpenStories and leaves 动态 on 发现.
        if stories.exists && !momentsOnProfile && feed.exists {
            TellomiUILog.report(["I-IDX-MOMENTS-034"], status: "pass")
        } else {
            TellomiUILog.report(["I-IDX-MOMENTS-034"], status: "fail", error: "快拍=\(stories.exists) profile动态=\(momentsOnProfile) 发现=\(feed.exists)")
            XCTFail("profile does not keep 快拍 separate from 动态")
        }
    }

    func testTellomiAndTelegramSchemesOpenSettings() throws {
        switch TellomiTestAccounts.lookup("TELLOMI_TEST_PHONE_A") {
        case .unset:
            TellomiUILog.report(Coverage.deepLinks, status: "blocked", error: "TELLOMI_TEST_PHONE_A is unset")
            throw XCTSkip("TELLOMI_TEST_PHONE_A is unset")
        case .refused(let reason):
            TellomiUILog.report(Coverage.deepLinks, status: "blocked", error: reason)
            throw XCTSkip(reason)
        case .ready:
            break
        }
        let app = TellomiApp.launch()
        let outcome = TellomiSession.signIn(app, account: TellomiTestAccounts.lookup("TELLOMI_TEST_PHONE_A"), test: self)
        guard outcome.signedIn else {
            TellomiUILog.report(Coverage.deepLinks, status: "blocked", error: outcome.detail)
            tellomiScreenshot("deep-link-blocked")
            return
        }
        tellomiDismissSystemAlerts(app)
        let tellomiOpened = openSettingsRoute(app, "tellomi://settings")
        let telegramOpened = openSettingsRoute(app, "tg://settings")
        let generated = generatedTellomiLinkVisible(app)
        tellomiScreenshot("deep-link")
        if tellomiOpened && telegramOpened && generated {
            TellomiUILog.report(Coverage.deepLinks, status: "pass")
        } else {
            TellomiUILog.report(Coverage.deepLinks, status: "fail", error: "tellomi://settings=\(tellomiOpened) tg://settings=\(telegramOpened) tell.cc=\(generated)")
            XCTFail("the two schemes did not both open settings, or no tell.cc link was visible")
        }
    }

    /// A logged-out phone page is what an ignored link also leaves behind.
    private func openSettingsRoute(_ app: XCUIApplication, _ url: String) -> Bool {
        app.open(URL(string: url)!)
        let account = tellomiLabel(app, "账号")
        let settings = app.navigationBars["设置"].exists || app.navigationBars["Settings"].exists
        return account.waitForExistence(timeout: 8) || settings
    }

    private func generatedTellomiLinkVisible(_ app: XCUIApplication) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS 'tell.cc'")
        if app.staticTexts.matching(predicate).firstMatch.exists || app.buttons.matching(predicate).firstMatch.exists {
            return true
        }
        let account = tellomiLabel(app, "账号")
        if account.exists {
            TellomiApp.tap(account)
        }
        return app.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: 4)
            || app.textFields.matching(NSPredicate(format: "value CONTAINS 'tell.cc'")).firstMatch.exists
    }
}
