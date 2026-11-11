import Foundation
import XCTest

final class CrashReportPromptTests: XCTestCase {
    private let active = CrashReportPromptEnvironment(canPresent: true, alertsEnabled: true, hasPending: true)
    private let inactive = CrashReportPromptEnvironment(canPresent: false, alertsEnabled: true, hasPending: true)

    func testShowResignActiveBecomeActiveShowsAgain() {
        var machine = CrashReportPromptMachine()
        XCTAssertEqual(machine.environment(self.active), [.present])
        XCTAssertEqual(machine.phase, .showing)

        XCTAssertEqual(machine.environment(self.inactive), [.dismiss])
        XCTAssertEqual(machine.phase, .waiting)
        XCTAssertEqual(machine.environment(self.inactive), [])

        XCTAssertEqual(machine.environment(self.active), [.present])
        XCTAssertEqual(machine.phase, .showing)
        XCTAssertEqual(machine.environment(self.active), [])
    }

    func testDeclineMarksDone() {
        var machine = CrashReportPromptMachine()
        XCTAssertEqual(machine.environment(self.active), [.present])
        XCTAssertEqual(machine.decline(), [.markResolved])
        XCTAssertEqual(machine.phase, .done)
        XCTAssertEqual(machine.environment(self.inactive), [])
        XCTAssertEqual(machine.environment(self.active), [])
        XCTAssertEqual(machine.decline(), [])
    }

    func testSendStaysPendingUntilTheServerConfirms() {
        var machine = CrashReportPromptMachine()
        XCTAssertEqual(machine.environment(self.active), [.present])
        XCTAssertEqual(machine.beginSend(), [])
        XCTAssertEqual(machine.phase, .sending)
        XCTAssertEqual(machine.environment(self.active), [])
        XCTAssertEqual(machine.environment(self.inactive), [])
        XCTAssertEqual(machine.phase, .sending)

        XCTAssertEqual(machine.sendConfirmed(), [.markResolved])
        XCTAssertEqual(machine.phase, .done)
        XCTAssertEqual(machine.environment(self.active), [])
        XCTAssertEqual(machine.sendConfirmed(), [])
    }

    func testSendFailureLeavesTheReportPending() {
        var machine = CrashReportPromptMachine()
        XCTAssertEqual(machine.environment(self.active), [.present])
        XCTAssertEqual(machine.beginSend(), [])
        XCTAssertEqual(machine.sendFailed(), [])
        XCTAssertEqual(machine.phase, .waiting)
        XCTAssertEqual(machine.environment(self.inactive), [])
        XCTAssertEqual(machine.environment(self.active), [.present])
        XCTAssertEqual(machine.phase, .showing)
    }

    func testDoesNotPresentTwiceWhileThePromptIsVisible() {
        var machine = CrashReportPromptMachine()
        XCTAssertEqual(machine.environment(self.active), [.present])
        XCTAssertEqual(machine.environment(self.active), [])
        XCTAssertEqual(machine.environment(self.active), [])
        XCTAssertEqual(machine.phase, .showing)
    }

    func testNothingToAskDoesNotPresent() {
        var machine = CrashReportPromptMachine()
        XCTAssertEqual(machine.environment(CrashReportPromptEnvironment(canPresent: true, alertsEnabled: true, hasPending: false)), [])
        XCTAssertEqual(machine.environment(CrashReportPromptEnvironment(canPresent: true, alertsEnabled: false, hasPending: true)), [])
        XCTAssertEqual(machine.environment(CrashReportPromptEnvironment(canPresent: false, alertsEnabled: true, hasPending: true)), [])
        XCTAssertEqual(machine.phase, .waiting)
    }

    func testDeliveryWaitsUntilTheServerAcceptsOrRefuses() {
        XCTAssertEqual(crashReportDelivery(failed: false, stillSending: true), .waiting)
        XCTAssertEqual(crashReportDelivery(failed: false, stillSending: false), .sent)
        XCTAssertEqual(crashReportDelivery(failed: true, stillSending: false), .failed)
        XCTAssertEqual(crashReportDelivery(failed: true, stillSending: true), .failed)
    }

    func testBotNameComesFromAppConfigOrTheFallback() {
        XCTAssertEqual(crashReportBotConfigKey, "tellomi_crash_report_bot")
        XCTAssertEqual(crashReportBotUsername(configured: nil), "TellomiBot")
        XCTAssertEqual(crashReportBotUsername(configured: ""), "TellomiBot")
        XCTAssertEqual(crashReportBotUsername(configured: "  @TellomiBot "), "TellomiBot")
        XCTAssertEqual(crashReportBotUsername(configured: "OtherBot"), "OtherBot")
        XCTAssertEqual(crashReportBotUsername(configured: "no"), "TellomiBot")
        XCTAssertEqual(crashReportBotUsername(configured: "1bad"), "TellomiBot")
    }

    func testDocumentIsAZipWithTheCollectorCaption() {
        let document = crashReportDocument(applicationVersion: "14.0.3", deviceType: "iPhone15,2")
        XCTAssertEqual(document.fileName, "Tellomi-iOS-14.0.3-crash.zip")
        XCTAssertEqual(document.mimeType, "application/zip")
        XCTAssertEqual(document.caption, "app=14.0.3 device=iPhone15,2")

        let blank = crashReportDocument(applicationVersion: " ", deviceType: "")
        XCTAssertEqual(blank.fileName, "Tellomi-iOS-0-crash.zip")
        XCTAssertEqual(blank.caption, "app=0 device=iOS")
    }
}
