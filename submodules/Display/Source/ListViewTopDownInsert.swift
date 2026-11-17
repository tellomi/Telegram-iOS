import Foundation

/// The nil-hint branch in `ListViewState.removeNodeAtIndex`.
/// True when the removed row's bottom still reaches the item-offset inset, so the
/// rows under that slot move up. False when the row is already above the inset, so
/// the rows above the slot move down.
public func listViewNilHintRemovalMovesFollowingRows(removedMaxY: CGFloat, itemOffsetInsetTop: CGFloat) -> Bool {
    return removedMaxY > itemOffsetInsetTop - CGFloat.ulpOfOne
}

public enum ListViewTopDownInsert: Equatable {
    /// Leave the index-0 hint alone. Upstream `insertionPoint` decides.
    case upstream
    /// Keep `.Down` even though the anchor is above the layout inset.
    /// The delete moved the rows under the removed slot up; `.Down` pushes them back
    /// and the visible edge stays.
    case forceDown
    /// Remove the index-0 `.Down` hint so the insert stays `.Up`.
    /// The delete moved the rows above the slot down; `.Up` puts the new row back
    /// on the previous edge. Forcing `.Down` would move that edge down by a row.
    case dropHint
}

/// One `.Down` insert at item index 0, paired with exactly one delete of a later row.
/// Anything else, including paging reloads (no hint) and an insert that is not index 0,
/// stays `.upstream`.
public func listViewTopDownInsert(
    downHintAtIndexZero: Bool,
    deletedItemIndices: [Int],
    deletedMaxYByIndex: [Int: CGFloat],
    itemOffsetInsetTop: CGFloat,
    listOptsIn: Bool
) -> ListViewTopDownInsert {
    guard listOptsIn, downHintAtIndexZero else {
        return .upstream
    }
    guard deletedItemIndices.count == 1, let deleted = deletedItemIndices.first, deleted > 0 else {
        return .upstream
    }
    guard let maxY = deletedMaxYByIndex[deleted] else {
        return .upstream
    }
    if listViewNilHintRemovalMovesFollowingRows(removedMaxY: maxY, itemOffsetInsetTop: itemOffsetInsetTop) {
        return .forceDown
    }
    return .dropHint
}
