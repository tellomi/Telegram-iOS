import XCTest
import SwiftSignalKit

/// CallKit error codes that all take the refusal branch. The values are
/// `CXErrorCodeRequestTransactionError`: unentitled, callUUIDAlreadyExists,
/// unknown, maximumCallGroupsReached.
private enum OutgoingCallKitRefusal: Int, CaseIterable {
    case unavailable = 1
    case duplicate = 5
    case cancelled = 0
    case existingSystemCall = 6

    var error: NSError {
        return NSError(domain: "com.apple.CallKit.error.requesttransaction", code: self.rawValue, userInfo: nil)
    }
}

final class CallKitCompletionThreadTests: XCTestCase {
    func testBackgroundCompletionRunsOnMain() {
        let finished = expectation(description: "main")
        let queue = DispatchQueue(label: "com.apple.callkit.callcontroller.completion")
        queue.async {
            XCTAssertFalse(Thread.isMainThread)
            CallKitCompletionThread.run {
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertTrue(Queue.mainQueue().isCurrent())
                finished.fulfill()
            }
        }
        wait(for: [finished], timeout: 2)
    }

    func testMainQueueRunsInline() {
        var ran = false
        CallKitCompletionThread.run {
            ran = true
            XCTAssertTrue(Thread.isMainThread)
        }
        XCTAssertTrue(ran)
    }

    func testAcceptedResultUpdatesStateAndDoesNotAbandon() {
        var abandoned = false
        var accepted = false
        var forwarded: Error? = NSError(domain: "unset", code: 1)
        var forwardedNil = false
        applyOutgoingCallKitTransactionResult(error: nil, abandonAttempt: {
            abandoned = true
        }, reportAccepted: {
            accepted = true
        }, completion: { error in
            forwarded = error
            forwardedNil = error == nil
        })
        XCTAssertFalse(abandoned)
        XCTAssertTrue(accepted)
        XCTAssertTrue(forwardedNil)
        XCTAssertNil(forwarded)
    }

    func testVoiceAndVideoRefusalsPresentOnTheMainThread() {
        // Voice and video pass isVideo into CXStartCallAction only. The
        // transaction completion does not read it, so both kinds share this
        // delivery. Each refusal presents; none of them marks the call active.
        let kinds = [false, true]
        for isVideo in kinds {
            for refusal in OutgoingCallKitRefusal.allCases {
                let finished = expectation(description: "video=\(isVideo) \(refusal)")
                let queue = DispatchQueue(label: "com.apple.callkit.callcontroller.completion")
                queue.async {
                    XCTAssertFalse(Thread.isMainThread)
                    CallKitCompletionThread.run {
                        var abandoned = false
                        var accepted = false
                        var presented = false
                        applyOutgoingCallKitTransactionResult(error: refusal.error, abandonAttempt: {
                            abandoned = true
                            XCTAssertTrue(Thread.isMainThread)
                        }, reportAccepted: {
                            accepted = true
                        }, completion: { error in
                            presented = error != nil
                            XCTAssertEqual((error as NSError?)?.code, refusal.rawValue)
                            XCTAssertTrue(Thread.isMainThread)
                        })
                        XCTAssertTrue(abandoned)
                        XCTAssertFalse(accepted)
                        XCTAssertTrue(presented)
                        finished.fulfill()
                    }
                }
            }
        }
        waitForExpectations(timeout: 2)
    }
}
