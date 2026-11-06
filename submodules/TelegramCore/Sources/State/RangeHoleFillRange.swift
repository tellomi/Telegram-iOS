import Foundation
import Postbox

/// The hole a ranged `messages.getHistory` fill is allowed to close.
///
/// `loadingNewer` is the `start.id <= end.id` direction in `fetchMessageHistoryHole`: the closed
/// span runs from `boundaryId` through the highest returned id. The other direction runs from the
/// lowest returned id through `boundaryId`. That span is then clipped to `requested`.
///
/// A page whose ids all sit outside `requested` closes nothing. The private-chat history query does
/// not apply `min_id` / `max_id`, so a bounded hole fill can come back as a different page. Closing
/// from that page through the anchor treats the messages on screen as a gap with no hole, and the
/// next sample drops them.
func rangeHoleFilledRange(boundaryId: MessageId.Id, returnedIds: [MessageId.Id], requested: ClosedRange<MessageId.Id>, loadingNewer: Bool) -> ClosedRange<MessageId.Id>? {
    guard let lowest = returnedIds.min(), let highest = returnedIds.max() else {
        return nil
    }
    guard returnedIds.contains(where: { requested.contains($0) }) else {
        return nil
    }
    let raw: ClosedRange<MessageId.Id>
    if loadingNewer {
        raw = min(boundaryId, highest) ... max(boundaryId, highest)
    } else {
        raw = min(lowest, boundaryId) ... max(lowest, boundaryId)
    }
    let lower = max(raw.lowerBound, requested.lowerBound)
    let upper = min(raw.upperBound, requested.upperBound)
    guard lower <= upper else {
        return nil
    }
    return lower ... upper
}
