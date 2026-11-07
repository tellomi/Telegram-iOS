import XCTest

final class StickerUploadOutcomeTests: XCTestCase {
    func testProgressStaysLoadingUntilATerminalEvent() {
        var session = StickerUploadSession.started
        XCTAssertEqual(stickerUploadReduce(&session, .progress(0.25)), .updateProgress(0.25))
        XCTAssertTrue(session.loading)
        XCTAssertFalse(session.sawSuccess)
        XCTAssertEqual(session.automaticRetryCount, 0)
    }

    func testSuccessIsNotAFailureAndALaterCompletionIsIgnored() {
        var session = StickerUploadSession.started
        XCTAssertEqual(stickerUploadReduce(&session, .progress(1.0)), .updateProgress(1.0))
        XCTAssertEqual(stickerUploadReduce(&session, .succeeded), .commitSuccess)
        XCTAssertTrue(session.sawSuccess)
        XCTAssertFalse(session.loading)
        XCTAssertEqual(stickerUploadReduce(&session, .completedWithoutValue), .none)
        XCTAssertEqual(stickerUploadReduce(&session, .failed), .none)
        XCTAssertEqual(session.automaticRetryCount, 0)
    }

    func testServerFailureClosesLoadingAndDoesNotRetryByItself() {
        var session = StickerUploadSession.started
        let _ = stickerUploadReduce(&session, .progress(0.4))
        XCTAssertEqual(stickerUploadReduce(&session, .failed), .stopLoadingAndOfferRetry)
        XCTAssertFalse(session.sawSuccess)
        XCTAssertFalse(session.loading)
        XCTAssertFalse(session.cancelled)
        XCTAssertEqual(session.automaticRetryCount, 0)
        XCTAssertEqual(stickerUploadReduce(&session, .failed), .none)
        XCTAssertEqual(stickerUploadReduce(&session, .completedWithoutValue), .none)
        XCTAssertNotEqual(stickerUploadReduce(&session, .failed), .commitSuccess)
        XCTAssertNotEqual(stickerUploadReduce(&session, .failed), .restart)
    }

    func testASignalThatEndsWithoutSuccessIsAFailure() {
        var session = StickerUploadSession.started
        XCTAssertEqual(stickerUploadReduce(&session, .completedWithoutValue), .stopLoadingAndOfferRetry)
        XCTAssertFalse(session.sawSuccess)
        XCTAssertEqual(session.automaticRetryCount, 0)
    }

    func testCancelSuppressesALateFailureAndDoesNotOfferRetry() {
        var session = StickerUploadSession.started
        let _ = stickerUploadReduce(&session, .progress(0.2))
        XCTAssertEqual(stickerUploadReduce(&session, .userCancelled), .none)
        XCTAssertTrue(session.cancelled)
        XCTAssertFalse(session.loading)
        XCTAssertFalse(session.sawSuccess)
        XCTAssertEqual(stickerUploadReduce(&session, .failed), .none)
        XCTAssertEqual(stickerUploadReduce(&session, .succeeded), .none)
        XCTAssertEqual(stickerUploadReduce(&session, .userRetried), .none)
        XCTAssertEqual(session.automaticRetryCount, 0)
    }

    func testRetryIsAnExplicitUserEventAfterFailure() {
        var session = StickerUploadSession.started
        XCTAssertEqual(stickerUploadReduce(&session, .failed), .stopLoadingAndOfferRetry)
        XCTAssertEqual(stickerUploadReduce(&session, .userRetried), .restart)
        XCTAssertTrue(session.loading)
        XCTAssertFalse(session.sawSuccess)
        XCTAssertFalse(session.cancelled)
        XCTAssertEqual(session.automaticRetryCount, 0)
        XCTAssertEqual(stickerUploadReduce(&session, .userRetried), .none)
    }
}
