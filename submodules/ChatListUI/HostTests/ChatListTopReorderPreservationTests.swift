import Foundation
import XCTest

/// Geometry of ListView's non-animated delete+insert, which is the path a normal
/// chat-list message takes (`disableAnimations` stays true, so there is no height
/// animation). Delete direction follows `removeNodeAtIndex` when the hint is nil:
/// If the removed row's maxY is less than the item-offset inset, the rows above
/// that slot move down. Otherwise the rows under that slot move up.
/// Insert `.up` places the row above the anchor and does not push the
/// rows below. Insert `.down` occupies the anchor's minY and pushes the rows below
/// down by the inserted height.
private struct ReorderRow: Equatable {
    var id: String
    var y: CGFloat
    var height: CGFloat
}

private enum ReorderInsertDirection {
    case up
    case down
}

private func promoteExistingPeer(rows: inout [ReorderRow], from index: Int, insert: ReorderInsertDirection, itemOffsetInsetTop: CGFloat) {
    precondition(index > 0 && index < rows.count)
    let moving = rows.remove(at: index)
    let removedMaxY = moving.y + moving.height
    if removedMaxY < itemOffsetInsetTop {
        for i in (0 ..< index).reversed() {
            rows[i].y += moving.height
        }
    } else {
        for i in index ..< rows.count {
            rows[i].y -= moving.height
        }
    }
    let anchorY = rows[0].y
    switch insert {
    case .down:
        rows.insert(ReorderRow(id: moving.id, y: anchorY, height: moving.height), at: 0)
        for i in 1 ..< rows.count {
            rows[i].y += moving.height
        }
    case .up:
        rows.insert(ReorderRow(id: moving.id, y: anchorY - moving.height, height: moving.height), at: 0)
    }
}

private func insertDirection(
    anchorMinY: CGFloat,
    anchorHeight: CGFloat,
    itemOffsetInsetTop: CGFloat,
    collapsedHeaderInset: CGFloat,
    viewportHeight: CGFloat
) -> ReorderInsertDirection {
    let legacyHonorsDown = anchorMinY >= itemOffsetInsetTop
    let extra = ChatListTopReorderPreservation.shouldHonorDownHint(
        hintIsDown: true,
        anchorMinY: anchorMinY,
        anchorMaxY: anchorMinY + anchorHeight,
        itemOffsetInsetTop: itemOffsetInsetTop,
        collapsedHeaderInset: collapsedHeaderInset,
        viewportMinY: 0,
        viewportMaxY: viewportHeight
    )
    return (legacyHonorsDown || extra) ? .down : .up
}

final class ChatListTopReorderPreservationTests: XCTestCase {
    /// Layout inset includes the expanded search. 54 matches `searchScrollHeight`.
    /// 76 is a typical chat row. The collapsed resting top is inset − 54.
    private let insetTop: CGFloat = 200
    private let searchCollapse: CGFloat = 54
    private let rowHeight: CGFloat = 76
    private let viewportHeight: CGFloat = 800

    private func restingRows(count: Int) -> [ReorderRow] {
        let names = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L"]
        let top = self.insetTop - self.searchCollapse
        return (0 ..< count).map { index in
            ReorderRow(id: names[index], y: top + CGFloat(index) * self.rowHeight, height: self.rowHeight)
        }
    }

    private func direction(for rows: [ReorderRow]) -> ReorderInsertDirection {
        let anchor = rows[0]
        return insertDirection(
            anchorMinY: anchor.y,
            anchorHeight: anchor.height,
            itemOffsetInsetTop: self.insetTop,
            collapsedHeaderInset: self.searchCollapse,
            viewportHeight: self.viewportHeight
        )
    }

    func testCollapsedSearchIgnoresTheDownHintAndStacksOneRowPerPromotion() {
        var rows = self.restingRows(count: 6)
        let top = rows[0].y
        XCTAssertFalse(rows[0].y >= self.insetTop)
        let legacy = insertDirection(
            anchorMinY: rows[0].y,
            anchorHeight: rows[0].height,
            itemOffsetInsetTop: self.insetTop,
            collapsedHeaderInset: 0,
            viewportHeight: self.viewportHeight
        )
        XCTAssertEqual(legacy, .up)
        promoteExistingPeer(rows: &rows, from: 1, insert: .up, itemOffsetInsetTop: self.insetTop)
        XCTAssertEqual(rows[0].y, top - self.rowHeight, accuracy: 0.001)
        promoteExistingPeer(rows: &rows, from: 1, insert: .up, itemOffsetInsetTop: self.insetTop)
        XCTAssertEqual(rows[0].y, top - 2 * self.rowHeight, accuracy: 0.001)
        XCTAssertLessThanOrEqual(rows[0].y + rows[0].height, top)
        XCTAssertLessThanOrEqual(rows[1].y + rows[1].height, top)
        XCTAssertEqual(rows[2].y, top, accuracy: 0.001)
    }

    func testTenAlternatingPromotionsKeepTheFirstRowOnTheCollapsedTop() {
        for count in [2, 4, 12] {
            var rows = self.restingRows(count: count)
            let top = rows[0].y
            for _ in 0 ..< 10 {
                let direction = self.direction(for: rows)
                XCTAssertEqual(direction, .down)
                promoteExistingPeer(rows: &rows, from: 1, insert: direction, itemOffsetInsetTop: self.insetTop)
                XCTAssertEqual(rows[0].y, top, accuracy: 0.001)
                XCTAssertEqual(rows[1].y, top + self.rowHeight, accuracy: 0.001)
            }
            XCTAssertEqual(rows[0].id, "A")
            XCTAssertEqual(rows[1].id, "B")
        }
    }

    func testSameSecondAndLaterSecondUseTheSamePreservation() {
        // A promotion in the same second and one in a later second are the same
        // delete-plus-insert. The sort key's timestamp is not an input.
        var immediate = self.restingRows(count: 5)
        var later = self.restingRows(count: 5)
        let top = immediate[0].y
        for _ in 0 ..< 10 {
            let immediateDirection = self.direction(for: immediate)
            let laterDirection = self.direction(for: later)
            XCTAssertEqual(immediateDirection, laterDirection)
            promoteExistingPeer(rows: &immediate, from: 1, insert: immediateDirection, itemOffsetInsetTop: self.insetTop)
            promoteExistingPeer(rows: &later, from: 1, insert: laterDirection, itemOffsetInsetTop: self.insetTop)
        }
        XCTAssertEqual(immediate, later)
        XCTAssertEqual(immediate[0].y, top, accuracy: 0.001)
    }

    func testExpandedSearchAlreadyHonorsDownAndDoesNotMove() {
        var rows = self.restingRows(count: 4)
        let shift = self.insetTop - rows[0].y
        for i in 0 ..< rows.count {
            rows[i].y += shift
        }
        let top = rows[0].y
        XCTAssertGreaterThanOrEqual(top, self.insetTop)
        for _ in 0 ..< 10 {
            XCTAssertEqual(self.direction(for: rows), .down)
            promoteExistingPeer(rows: &rows, from: 1, insert: .down, itemOffsetInsetTop: self.insetTop)
            XCTAssertEqual(rows[0].y, top, accuracy: 0.001)
        }
    }

    func testScrolledListDoesNotHonorDownAndIsNotPulledToTheTop() {
        var rows = self.restingRows(count: 8)
        let scrolled = self.searchCollapse + self.rowHeight + 20
        for i in 0 ..< rows.count {
            rows[i].y -= scrolled
        }
        let visibleTop = rows[0].y
        XCTAssertLessThan(visibleTop, self.insetTop - self.searchCollapse - ChatListTopReorderPreservation.tolerance)
        XCTAssertEqual(self.direction(for: rows), .up)
        let honored = ChatListTopReorderPreservation.shouldHonorDownHint(
            hintIsDown: true,
            anchorMinY: rows[0].y,
            anchorMaxY: rows[0].y + rows[0].height,
            itemOffsetInsetTop: self.insetTop,
            collapsedHeaderInset: self.searchCollapse,
            viewportMinY: 0,
            viewportMaxY: self.viewportHeight
        )
        XCTAssertFalse(honored)
        promoteExistingPeer(rows: &rows, from: 1, insert: .up, itemOffsetInsetTop: self.insetTop)
        XCTAssertEqual(rows[0].y, visibleTop, accuracy: 0.001)
        XCTAssertGreaterThan(abs(rows[0].y - (self.insetTop - self.searchCollapse)), 1)
    }

    func testOffScreenAnchorAndUpHintAreNotHonored() {
        XCTAssertFalse(ChatListTopReorderPreservation.shouldHonorDownHint(
            hintIsDown: true,
            anchorMinY: -200,
            anchorMaxY: -124,
            itemOffsetInsetTop: self.insetTop,
            collapsedHeaderInset: self.searchCollapse,
            viewportMinY: 0,
            viewportMaxY: self.viewportHeight
        ))
        XCTAssertFalse(ChatListTopReorderPreservation.shouldHonorDownHint(
            hintIsDown: false,
            anchorMinY: self.insetTop - self.searchCollapse,
            anchorMaxY: self.insetTop - self.searchCollapse + self.rowHeight,
            itemOffsetInsetTop: self.insetTop,
            collapsedHeaderInset: self.searchCollapse,
            viewportMinY: 0,
            viewportMaxY: self.viewportHeight
        ))
    }

    func testKillSwitchDisablesTheExtraHonor() {
        XCTAssertFalse(ChatListTopReorderPreservation.shouldHonorDownHint(
            hintIsDown: true,
            anchorMinY: self.insetTop - self.searchCollapse,
            anchorMaxY: self.insetTop - self.searchCollapse + self.rowHeight,
            itemOffsetInsetTop: self.insetTop,
            collapsedHeaderInset: self.searchCollapse,
            viewportMinY: 0,
            viewportMaxY: self.viewportHeight,
            enabled: false
        ))
    }
}
