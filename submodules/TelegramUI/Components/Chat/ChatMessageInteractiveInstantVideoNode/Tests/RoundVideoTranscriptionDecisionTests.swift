import XCTest

final class RoundVideoTranscriptionDecisionTests: XCTestCase {
    func testWaitingAndPendingKeepTheRoundVideo() {
        let waiting = roundVideoTranscriptLayout(phase: .inProgress, fact: .none)
        XCTAssertTrue(waiting.keepsRoundVideo)
        XCTAssertFalse(waiting.replaceVideo)
        XCTAssertEqual(waiting.phase, .inProgress)

        let pending = roundVideoTranscriptLayout(phase: .inProgress, fact: .pending)
        XCTAssertTrue(pending.keepsRoundVideo)
        XCTAssertFalse(pending.replaceVideo)
    }

    func testOnlyRealTextReplacesTheVideo() {
        let shown = roundVideoTranscriptLayout(phase: .inProgress, fact: .text("hello"))
        XCTAssertTrue(shown.replaceVideo)
        XCTAssertTrue(shown.showsText)
        XCTAssertFalse(shown.keepsRoundVideo)
        XCTAssertEqual(shown.phase, .expanded)

        let still = roundVideoTranscriptLayout(phase: .expanded, fact: .text("hello"))
        XCTAssertTrue(still.replaceVideo)
        XCTAssertEqual(still.phase, .expanded)
    }

    func testFailureAndEmptyRestoreTheVideoInsteadOfCoveringIt() {
        let failed = roundVideoTranscriptLayout(phase: .inProgress, fact: .failure)
        XCTAssertTrue(failed.keepsRoundVideo)
        XCTAssertFalse(failed.replaceVideo)
        XCTAssertFalse(failed.showsText)
        XCTAssertEqual(failed.phase, .collapsed)

        let empty = roundVideoTranscriptLayout(phase: .expanded, fact: .none)
        XCTAssertTrue(empty.keepsRoundVideo)
        XCTAssertFalse(empty.replaceVideo)
        XCTAssertEqual(empty.phase, .collapsed)

        let stuckExpanded = roundVideoTranscriptLayout(phase: .expanded, fact: .failure)
        XCTAssertEqual(stuckExpanded.phase, .collapsed)
        XCTAssertTrue(stuckExpanded.keepsRoundVideo)
    }

    func testCollapsedAndLockedDoNotHideTheVideo() {
        XCTAssertTrue(roundVideoTranscriptLayout(phase: .collapsed, fact: .text("hello")).keepsRoundVideo)
        XCTAssertFalse(roundVideoTranscriptLayout(phase: .collapsed, fact: .text("hello")).replaceVideo)
        XCTAssertTrue(roundVideoTranscriptLayout(phase: .locked, fact: .none).keepsRoundVideo)
        XCTAssertEqual(roundVideoTranscriptLayout(phase: .locked, fact: .failure).phase, .locked)
    }

    func testFactTreatsEmptyAndFailedAsNotText() {
        XCTAssertEqual(roundVideoTranscriptFact(nonEmptyText: nil, isPending: true, failed: false), .pending)
        XCTAssertEqual(roundVideoTranscriptFact(nonEmptyText: nil, isPending: false, failed: true), .failure)
        XCTAssertEqual(roundVideoTranscriptFact(nonEmptyText: "", isPending: false, failed: false), .none)
        XCTAssertEqual(roundVideoTranscriptFact(nonEmptyText: "ok", isPending: false, failed: false), .text("ok"))
        XCTAssertEqual(roundVideoTranscriptFact(nonEmptyText: "ok", isPending: false, failed: true), .failure)
    }

    func testSignalFailureAndCancelRestoreOnceAndDoNotRetry() {
        var session = RoundVideoTranscriptSession.waiting
        XCTAssertEqual(roundVideoTranscriptReduce(&session, .reportedFailure), .restoreVideo)
        XCTAssertFalse(session.waiting)
        XCTAssertEqual(session.automaticRetryCount, 0)
        XCTAssertEqual(roundVideoTranscriptReduce(&session, .reportedFailure), .none)
        XCTAssertEqual(roundVideoTranscriptReduce(&session, .finished), .none)

        session = .waiting
        XCTAssertEqual(roundVideoTranscriptReduce(&session, .userCancelled), .restoreVideo)
        XCTAssertEqual(session.automaticRetryCount, 0)
    }

    func testSuccessWaitsForTheMessageAndALaterFinishDoesNotRestore() {
        var session = RoundVideoTranscriptSession.waiting
        XCTAssertEqual(roundVideoTranscriptReduce(&session, .reportedSuccess), .keepWaiting)
        XCTAssertTrue(session.sawSuccess)
        XCTAssertEqual(roundVideoTranscriptReduce(&session, .finished), .none)
        XCTAssertEqual(session.automaticRetryCount, 0)
    }

    func testFinishWithoutSuccessRestoresTheVideo() {
        var session = RoundVideoTranscriptSession.waiting
        XCTAssertEqual(roundVideoTranscriptReduce(&session, .finished), .restoreVideo)
        XCTAssertFalse(session.sawSuccess)
        XCTAssertEqual(session.automaticRetryCount, 0)
    }
}
