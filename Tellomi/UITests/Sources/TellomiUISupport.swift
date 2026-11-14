import XCTest

enum TellomiUILog {
    static func report(_ ids: [String], status: String, error: String? = nil) {
        let detail = (error ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        for id in ids where !id.isEmpty {
            NSLog("TELLOMI_UI_RESULT\t%@\t%@\t%@", id, status, detail)
        }
    }
}

enum TellomiAccountLookup {
    case unset
    case refused(String)
    case ready(countryCode: String, nationalNumber: String, code: String)
}

enum TellomiTestAccounts {
    /// Production fixed code for `99966XYYYY` (the digit after `99966`, five times).
    /// `99966170xx` is datacenter digit 1, so the code is `11111`.
    static func lookup(_ name: String) -> TellomiAccountLookup {
        guard let raw = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return .unset
        }
        let digits = raw.filter(\.isNumber)
        guard digits.count == 10, digits.hasPrefix("99966"), let dc = digits.dropFirst(5).first, dc.isNumber else {
            return .refused("\(name) is not a 99966XYYYY test number; this run will not send it a code")
        }
        let national = String(digits.dropFirst(3))
        let code: String
        if let override = ProcessInfo.processInfo.environment["TELLOMI_TEST_CODE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            code = override
        } else {
            code = String(repeating: String(dc), count: 5)
        }
        return .ready(countryCode: "999", nationalNumber: national, code: code)
    }
}

enum TellomiApp {
    static func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // `--ui-test` isolates data and also sets testingEnvironment. The
        // handshake then asks for datacenter id + 10000, which the production
        // server does not answer. CI wipes the app with simctl uninstall.
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_Hans_CN"]
        app.launch()
        return app
    }

    static func tap(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }
}

extension XCTestCase {
    func tellomiScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func tellomiLabel(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let text = app.staticTexts[label]
        if text.exists {
            return text
        }
        let cell = app.cells.staticTexts[label]
        if cell.exists {
            return cell
        }
        return text
    }

    func tellomiScrollToLabel(_ app: XCUIApplication, _ label: String, swipes: Int = 8) -> XCUIElement {
        let element = tellomiLabel(app, label)
        var remaining = swipes
        while !element.exists && remaining > 0 {
            app.swipeUp()
            remaining -= 1
        }
        return element
    }

    func tellomiDismissSystemAlerts(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.exists else {
            return
        }
        for title in ["允许", "Allow", "好", "OK", "稍后", "Not Now", "不允许", "Don’t Allow", "Don't Allow"] {
            let button = alert.buttons[title]
            if button.exists {
                button.tap()
                return
            }
        }
    }
}
