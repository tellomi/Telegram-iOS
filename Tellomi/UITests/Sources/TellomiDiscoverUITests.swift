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
        let momentsTab = app.buttons["动态"].exists || app.segmentedControls.buttons["动态"].exists
        if momentsTab {
            TellomiUILog.report(["I-IDX-MOMENTS-034"], status: "fail", error: "资料页 has a 动态 tab")
            XCTFail("Moments tab is on the profile")
        } else {
            TellomiUILog.report(["I-IDX-MOMENTS-034"], status: "pass")
        }
    }

    func testTellomiAndTelegramSchemesOpenTheLoggedOutApp() throws {
        let app = TellomiApp.launch()
        XCTAssertTrue(app.textFields["Auth.PhoneEntry.PhoneNumberField"].waitForExistence(timeout: 30))
        for url in ["tellomi://settings", "tg://settings"] {
            app.open(URL(string: url)!)
        }
        let phone = app.textFields["Auth.PhoneEntry.PhoneNumberField"]
        let stillThere = phone.waitForExistence(timeout: 10)
        tellomiScreenshot("deep-link")
        if stillThere && app.state == .runningForeground {
            TellomiUILog.report(Coverage.deepLinks, status: "pass")
        } else {
            TellomiUILog.report(Coverage.deepLinks, status: "fail", error: "app did not stay on the phone screen after tellomi:// and tg://")
            XCTFail("deep link did not return to the phone screen")
        }
    }
}
