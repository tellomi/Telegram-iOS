import Foundation
import SwiftSignalKit

/// `CXCallController.request` runs its completion on
/// `com.apple.callkit.callcontroller.completion`. `CXProvider.reportNewIncomingCall`
/// runs its completion on an arbitrary queue. Neither is the main queue.
///
/// The outgoing success branch updates call state from that completion. The
/// outgoing failure branch presents an alert from that completion. Voice and
/// video share it. Any non-nil error is a refusal: CallKit unavailable, a
/// duplicate start, a cancelled transaction, or an existing system call the
/// system rejects.
enum CallKitCompletionThread {
    static func run(_ body: @escaping () -> Void) {
        Queue.mainQueue().async {
            dispatchPrecondition(condition: .onQueue(.main))
            body()
        }
    }
}

/// The two branches of an outgoing `CXStartCallAction` transaction.
/// `error != nil` abandons the attempt and forwards the error (the alert).
/// `nil` reports the call and marks it active, then forwards success.
func applyOutgoingCallKitTransactionResult(
    error: Error?,
    abandonAttempt: () -> Void,
    reportAccepted: () -> Void,
    completion: (Error?) -> Void
) {
    if error != nil {
        abandonAttempt()
        completion(error)
        return
    }
    reportAccepted()
    completion(nil)
}
