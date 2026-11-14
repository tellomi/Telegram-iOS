import Foundation
import SwiftSignalKit

/// Runs Moments view work on the main queue.
///
/// `ListView` measures a new row on a global queue (`DispatchQueue.global`). The row node is
/// view-backed: its `UIStackView`, buttons and labels install Auto Layout constraints as soon as
/// the node is created. Doing that on the worker leaves an implicit `CATransaction`. When the
/// worker exits, `CA::Transaction::release_thread` commits it and CoreAutoLayout aborts in
/// `_AssertAutoLayoutOnAllowedThreadsOnly`. Measurement stays on the caller. Creating the node,
/// setting its frame and assigning images does not.
public func momentsOnMainQueue(_ f: @escaping () -> Void) {
    if Queue.mainQueue().isCurrent() {
        f()
    } else {
        Queue.mainQueue().async {
            assert(Queue.mainQueue().isCurrent())
            f()
        }
    }
}
