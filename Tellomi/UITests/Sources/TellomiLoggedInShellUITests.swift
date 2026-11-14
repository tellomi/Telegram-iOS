import XCTest

/// Settings, the nav-bar toggles, legal links, and premium rows that must
/// stay off the signed-in home. AI compose switches are not toggled.
final class TellomiLoggedInShellUITests: XCTestCase {
    private var loginError: String?

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func requireAccount(_ ids: [String]) throws -> TellomiAccountLookup {
        switch TellomiTestAccounts.lookup("TELLOMI_TEST_PHONE_A") {
        case .unset:
            TellomiUILog.report(ids, status: "blocked", error: "TELLOMI_TEST_PHONE_A is unset")
            throw XCTSkip("TELLOMI_TEST_PHONE_A is unset")
        case .refused(let reason):
            TellomiUILog.report(ids, status: "blocked", error: reason)
            throw XCTSkip(reason)
        case let ready:
            return ready
        }
    }

    private func openSignedInApp() throws -> XCUIApplication {
        _ = try requireAccount()
        let app = TellomiApp.launch()
        let outcome = TellomiSession.signIn(app, account: TellomiTestAccounts.lookup("TELLOMI_TEST_PHONE_A"), test: self)
        guard outcome.signedIn else {
            loginError = outcome.detail.isEmpty ? "login did not reach the tab bar" : outcome.detail
            return app
        }
        tellomiDismissSystemAlerts(app)
        return app
    }

    func testSettingsRows() throws {
        _ = try requireAccount(Coverage.tabsAndSettings)
        let app = try openSignedInApp()
        guard loginError == nil else {
            TellomiUILog.report(Coverage.tabsAndSettings, status: "blocked", error: loginError)
            tellomiScreenshot("settings-blocked")
            return
        }
        openSettings(app)
        tellomiScreenshot("settings-home")
        let checks: [(String, [String])] = [
            ("I-IDX-SETTINGS-001", ["账号", "通用", "帮助与关于"]),
            ("I-SETTINGS-475", ["账号"]),
            ("I-SETTINGS-501", ["隐私与安全"]),
            ("I-SETTINGS-481", ["设备"]),
            ("I-SETTINGS-503", ["资料"]),
            ("I-SETTINGS-486", ["语言"]),
            ("I-SETTINGS-496", ["发现"]),
            ("I-SETTINGS-484", ["帮助与关于"]),
            ("I-SETTINGS-487", ["协议与隐私"]),
            ("I-SETTINGS-473", ["关于 Tellomi"]),
        ]
        for (id, labels) in checks {
            let found = labels.allSatisfy { tellomiScrollToLabel(app, $0).exists }
            TellomiUILog.report([id], status: found ? "pass" : "fail", error: found ? nil : "missing \(labels.joined(separator: ", "))")
        }
        if tellomiScrollToLabel(app, "账号与绑定").exists {
            TellomiApp.tap(tellomiLabel(app, "账号与绑定"))
            let nested: [(String, String)] = [
                ("I-SETTINGS-476", "添加账号"),
                ("I-SETTINGS-482", "邮箱"),
                ("I-SETTINGS-488", "退出登录"),
                ("I-SETTINGS-497", "手机号"),
                ("I-SETTINGS-508", "用户名"),
            ]
            for (id, label) in nested {
                let found = tellomiScrollToLabel(app, label).exists
                TellomiUILog.report([id], status: found ? "pass" : "fail", error: found ? nil : "\(label) is not on 账号与绑定")
            }
            app.navigationBars.buttons.firstMatch.tap()
        } else {
            TellomiUILog.report(["I-SETTINGS-476", "I-SETTINGS-482", "I-SETTINGS-488", "I-SETTINGS-497", "I-SETTINGS-508"], status: "fail", error: "账号与绑定 row is missing")
        }
        if tellomiScrollToLabel(app, "更多").exists {
            TellomiApp.tap(tellomiLabel(app, "更多"))
            let licenses = tellomiScrollToLabel(app, "开源许可")
            TellomiUILog.report(["I-SETTINGS-493"], status: licenses.exists ? "pass" : "fail", error: licenses.exists ? nil : "开源许可 is not under 更多")
        } else {
            TellomiUILog.report(["I-SETTINGS-493"], status: "fail", error: "更多 row is missing")
        }
    }

    func testNavigationToggles() throws {
        _ = try requireAccount(Coverage.navigationToggles)
        let app = try openSignedInApp()
        guard loginError == nil else {
            TellomiUILog.report(Coverage.navigationToggles, status: "blocked", error: loginError)
            return
        }
        openSettings(app)
        guard tellomiScrollToLabel(app, "导航栏").exists else {
            TellomiUILog.report(Coverage.navigationToggles, status: "fail", error: "导航栏 row is missing")
            return
        }
        TellomiApp.tap(tellomiLabel(app, "导航栏"))
        tellomiScreenshot("navigation")
        let feed = switchValue(app, "发现")
        let calls = switchValue(app, "通话")
        let contacts = switchValue(app, "联系人")
        TellomiUILog.report(["I-SETTINGS-448"], status: feed != nil ? "pass" : "fail", error: feed == nil ? "发现 toggle missing" : nil)
        TellomiUILog.report(["I-SETTINGS-449"], status: calls != nil ? "pass" : "fail", error: calls == nil ? "通话 toggle missing" : nil)
        if contacts == "0" {
            TellomiUILog.report(["I-SETTINGS-450"], status: "pass")
        } else if contacts == nil {
            TellomiUILog.report(["I-SETTINGS-450"], status: "fail", error: "联系人 toggle missing")
        } else {
            TellomiUILog.report(["I-SETTINGS-450"], status: "fail", error: "联系人 toggle is on; default is off")
        }
    }

    func testLegalLinks() throws {
        _ = try requireAccount(Coverage.legalLinks)
        let app = try openSignedInApp()
        guard loginError == nil else {
            TellomiUILog.report(Coverage.legalLinks, status: "blocked", error: loginError)
            return
        }
        openSettings(app)
        guard tellomiScrollToLabel(app, "协议与隐私").exists else {
            TellomiUILog.report(Coverage.legalLinks, status: "fail", error: "协议与隐私 row is missing")
            return
        }
        TellomiApp.tap(tellomiLabel(app, "协议与隐私"))
        let terms = openExternalLink(app, title: "用户服务协议", hostPath: "tellomi.cn/legal/terms")
        TellomiUILog.report(["I-SETTINGS-507", "I-IDX-SETTINGS-016"], status: terms.ok ? "pass" : "fail", error: terms.ok ? nil : terms.error)
        app.activate()
        let privacy = openExternalLink(app, title: "隐私政策", hostPath: "tellomi.cn/legal/privacy")
        TellomiUILog.report(["I-SETTINGS-502"], status: privacy.ok ? "pass" : "fail", error: privacy.ok ? nil : privacy.error)
        tellomiScreenshot("legal")
    }

    func testPremiumEntriesStayHidden() throws {
        _ = try requireAccount(Coverage.premiumHidden)
        let app = try openSignedInApp()
        guard loginError == nil else {
            TellomiUILog.report(Coverage.premiumHidden, status: "blocked", error: loginError)
            return
        }
        let labels: [(String, String)] = [
            ("I-PREMIUM-280", "不要隐藏广告"),
            ("I-PREMIUM-281", "我的礼物"),
            ("I-PREMIUM-282", "动态表情"),
            ("I-PREMIUM-284", "动态头像"),
            ("I-PREMIUM-285", "形象勋章"),
            ("I-PREMIUM-286", "高级聊天管理"),
            ("I-PREMIUM-287", "表情符号状态"),
            ("I-PREMIUM-288", "更快的下载速度"),
            ("I-PREMIUM-289", "无广告"),
            ("I-PREMIUM-290", "专属表情回应"),
            ("I-PREMIUM-291", "高级版贴纸"),
            ("I-PREMIUM-292", "无限云端存储空间"),
            ("I-PREMIUM-293", "语音转文字"),
            ("I-PREMIUM-295", "赠送礼物"),
            ("I-PREMIUM-307", "给自己买一份礼物"),
            ("I-PREMIUM-308", "发送自己一份礼物"),
            ("I-PREMIUM-309", "赠送星星"),
            ("I-SETTINGS-500", "你的会员即将到期。"),
        ]
        openMe(app)
        openSettings(app)
        tellomiScreenshot("premium-hidden")
        var visible: [String] = []
        for (id, label) in labels {
            if tellomiLabel(app, label).exists {
                visible.append(label)
                TellomiUILog.report([id], status: "fail", error: "\(label) is visible")
            } else {
                TellomiUILog.report([id], status: "pass")
            }
        }
        if !visible.isEmpty {
            XCTFail("premium entries visible: \(visible.joined(separator: ", "))")
        }
    }

    private func openMe(_ app: XCUIApplication) {
        for title in ["我", "Me"] {
            let tab = app.tabBars.buttons[title]
            if tab.exists {
                TellomiApp.tap(tab)
                return
            }
            let button = app.buttons[title]
            if button.exists {
                TellomiApp.tap(button)
                return
            }
        }
    }

    private func openSettings(_ app: XCUIApplication) {
        openMe(app)
        for title in ["设置", "Settings"] {
            let button = app.buttons[title]
            if button.exists {
                TellomiApp.tap(button)
                return
            }
            let nav = app.navigationBars.buttons[title]
            if nav.exists {
                TellomiApp.tap(nav)
                return
            }
        }
        // The gear is often the trailing nav button without a title.
        let buttons = app.navigationBars.buttons
        if buttons.count > 0 {
            TellomiApp.tap(buttons.element(boundBy: buttons.count - 1))
        }
    }

    private func switchValue(_ app: XCUIApplication, _ label: String) -> String? {
        let direct = app.switches[label]
        if direct.exists {
            return direct.value as? String
        }
        let cell = app.cells.containing(.staticText, identifier: label).firstMatch
        guard cell.waitForExistence(timeout: 2) else {
            return nil
        }
        let toggle = cell.switches.firstMatch
        guard toggle.exists else {
            return nil
        }
        return toggle.value as? String
    }

    private func openExternalLink(_ app: XCUIApplication, title: String, hostPath: String) -> (ok: Bool, error: String?) {
        let row = tellomiScrollToLabel(app, title)
        guard row.exists else {
            return (false, "\(title) is not on 协议与隐私")
        }
        TellomiApp.tap(row)
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 3) {
            for label in ["打开", "Open", "允许", "Allow"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    break
                }
            }
        }
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        guard safari.wait(for: .runningForeground, timeout: 15) else {
            return (false, "Safari did not open for \(title)")
        }
        let tree = safari.debugDescription
        if tree.contains(hostPath) {
            return (true, nil)
        }
        return (false, "Safari did not show \(hostPath)")
    }
}
