import Foundation

/// Keeps a chat-list reorder from parking the new first row under the fixed title.
///
/// A normal incoming message is not an animated insertion (`disableAnimations` stays
/// true). MergeLists still describes an existing peer moving to the front as a delete
/// plus an insert, and `ChatListViewTransition` tags that insert `.Down`. ListView
/// only keeps the hint when the anchor row's minY is at or below `itemOffsetInsets.top`.
///
/// With the search field collapsed, the resting top sits `searchScrollHeight` (54pt)
/// above that inset: the first row is on screen, just under the title, but the hint
/// is dropped and the insert defaults to `.Up`. The new row is placed one row above
/// the current top and the rows below the deleted slot move up. Each later promotion
/// stacks another row above the title. The title and the tab bar do not move.
///
/// The extra honor applies only inside that collapsed-header band. A list the user
/// has actually scrolled further down keeps the upstream direction, so this does not
/// pull that list back to the top. Search expanded (minY at the layout inset) already
/// honors `.Down` upstream; this does not change that path.
enum ChatListTopReorderPreservation {
    /// Kill switch. `false` restores the upstream hint gate.
    static var enabled = true

    /// Pixel slack so a resting edge that rounds 1pt off the collapsed inset still counts.
    static let tolerance: CGFloat = 1

    static func shouldHonorDownHint(
        hintIsDown: Bool,
        anchorMinY: CGFloat,
        anchorMaxY: CGFloat,
        itemOffsetInsetTop: CGFloat,
        collapsedHeaderInset: CGFloat,
        viewportMinY: CGFloat,
        viewportMaxY: CGFloat,
        enabled: Bool? = nil
    ) -> Bool {
        guard enabled ?? Self.enabled, hintIsDown, collapsedHeaderInset >= 0 else {
            return false
        }
        let onScreen = anchorMaxY > viewportMinY && anchorMinY < viewportMaxY
        guard onScreen else {
            return false
        }
        let restingTop = itemOffsetInsetTop - collapsedHeaderInset - tolerance
        return anchorMinY >= restingTop
    }
}
