/// What to do with a history snapshot that has no entries yet.
///
/// An anchor that is still inside a hole is an empty loading view. Applying it deletes the rows
/// already on screen, and the list then anchors the replacement at index 0 (the newest edge).
/// That snapshot is kept off the screen only while it belongs to the load that put the current
/// rows there. A newer load — switching chats, or switching the history tag — applies the empty
/// frame, so the previous chat's messages are not left up.
enum HistoryEmptyLoadingDecision: Equatable {
    case keepDisplayedRows
    case applyIncomingFrame
}

func historyEmptyLoadingDecision(
    isLoading: Bool,
    incomingEntriesEmpty: Bool,
    previousEntriesEmpty: Bool,
    frameGeneration: Int,
    appliedGeneration: Int
) -> HistoryEmptyLoadingDecision {
    if isLoading && incomingEntriesEmpty && !previousEntriesEmpty && frameGeneration == appliedGeneration {
        return .keepDisplayedRows
    }
    return .applyIncomingFrame
}

/// A history subscription is current only for the load that started it. `updateChatLocation`
/// starts a new load before the new chat's first snapshot, and a snapshot from the previous
/// subscription must not write that chat's rows into the new one.
func historyLoadEventIsCurrent(eventGeneration: Int, currentGeneration: Int) -> Bool {
    return eventGeneration == currentGeneration
}
