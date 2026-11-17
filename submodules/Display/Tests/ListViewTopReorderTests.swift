import XCTest
import SwiftSignalKit
@testable import Display

/// `deleteAndInsertItemsTransaction` for a normal chat-list message does not animate
/// the insert. It calls `listViewTopDownInsert` on the pre-delete frames, then
/// `removeNodeAtIndex`, then `insertionPoint`, then `insertNode`. This test calls
/// those same functions. The index renumber only matches the transaction's index
/// map so the hole is at item 0. It does not move frames.
final class ListViewTopReorderTests: XCTestCase {
    private let insetTop: CGFloat = 200
    private let rowHeight: CGFloat = 76
    private let viewportHeight: CGFloat = 800
    private let collapsedRestingTop: CGFloat = 146

    private func makeState(firstMinY: CGFloat, count: Int) -> ListViewState {
        var nodes: [ListViewStateNode] = []
        for index in 0 ..< count {
            let frame = CGRect(x: 0, y: firstMinY + CGFloat(index) * self.rowHeight, width: 390, height: self.rowHeight)
            nodes.append(.Node(index: index, frame: frame, referenceNode: nil, newNode: nil))
        }
        return ListViewState(
            insets: UIEdgeInsets(top: self.insetTop, left: 0, bottom: 0, right: 0),
            itemOffsetInsets: UIEdgeInsets(top: self.insetTop, left: 0, bottom: 0, right: 0),
            visibleSize: CGSize(width: 390, height: self.viewportHeight),
            invisibleInset: 500,
            nodes: nodes,
            scrollPosition: nil,
            stationaryOffset: nil,
            stackFromBottom: false
        )
    }

    private func renumberForDeleteThenInsert(_ state: inout ListViewState, deleted: Int, inserted: Int) {
        for i in 0 ..< state.nodes.count {
            guard case let .Node(index, frame, referenceNode, newNode) = state.nodes[i] else {
                continue
            }
            var updated = index
            if updated > deleted {
                updated -= 1
            }
            if inserted <= updated {
                updated += 1
            }
            if updated != index {
                state.nodes[i] = .Node(index: updated, frame: frame, referenceNode: referenceNode, newNode: newNode)
            }
        }
    }

    /// Same order as the transaction: read the removed maxY, decide, delete, renumber, insert.
    private func promote(_ state: inout ListViewState, listOptsIn: Bool) {
        let removedMaxY = state.nodes[1].frame.maxY
        let decision = listViewTopDownInsert(
            downHintAtIndexZero: true,
            deletedItemIndices: [1],
            deletedMaxYByIndex: [1: removedMaxY],
            itemOffsetInsetTop: state.itemOffsetInsets.top,
            listOptsIn: listOptsIn
        )
        var hints: [Int: ListViewItemOperationDirectionHint] = [0: .Down]
        let forceIndexZeroDown: Bool
        switch decision {
        case .forceDown:
            forceIndexZeroDown = true
        case .dropHint:
            forceIndexZeroDown = false
            hints[0] = nil
        case .upstream:
            forceIndexZeroDown = false
        }
        var operations: [ListViewStateOperation] = []
        state.removeNodeAtIndex(1, direction: nil, animated: false, operations: &operations)
        self.renumberForDeleteThenInsert(&state, deleted: 1, inserted: 0)
        let point = state.insertionPoint(hints, itemCount: state.nodes.count + 1, forceIndexZeroDown: forceIndexZeroDown)
        let layout = ListViewItemNodeLayout(contentSize: CGSize(width: 390, height: self.rowHeight), insets: UIEdgeInsets())
        let node = QueueLocalObject<ListViewItemNode>(queue: Queue.mainQueue(), generate: {
            ListViewItemNode(layerBacked: true)
        })
        state.insertNode(
            0,
            node: node,
            layout: layout,
            apply: { (nil, { _ in }) },
            offsetDirection: point?.direction ?? .Up,
            animated: false,
            operations: &operations,
            itemCount: state.nodes.count + 1
        )
    }

    func testUpstreamGateMovesTheEdgeForTheFirstTwoPromotionsThenStops() {
        var state = self.makeState(firstMinY: self.collapsedRestingTop, count: 8)
        var tops: [CGFloat] = [state.nodes[0].frame.minY]
        for _ in 0 ..< 4 {
            self.promote(&state, listOptsIn: false)
            tops.append(state.nodes[0].frame.minY)
        }
        XCTAssertEqual(tops[1], tops[0] - self.rowHeight, accuracy: 0.001)
        XCTAssertEqual(tops[2], tops[1] - self.rowHeight, accuracy: 0.001)
        XCTAssertEqual(tops[3], tops[2], accuracy: 0.001)
        XCTAssertEqual(tops[4], tops[3], accuracy: 0.001)
    }

    func testOptedInListKeepsTheAnchorAcrossTheReportedScrolls() {
        let starts: [CGFloat] = [
            self.collapsedRestingTop,
            self.collapsedRestingTop - 2,
            self.collapsedRestingTop - 20,
            self.collapsedRestingTop - self.rowHeight,
            self.collapsedRestingTop - (2 * self.rowHeight),
            self.collapsedRestingTop - 20.5,
            -200
        ]
        for start in starts {
            var state = self.makeState(firstMinY: start, count: 8)
            for _ in 0 ..< 4 {
                self.promote(&state, listOptsIn: true)
                XCTAssertEqual(state.nodes[0].frame.minY, start, accuracy: 0.001)
            }
        }
    }

    func testTwoPointsOutsideTheCollapsedRestStillJumpsUpstreamAndStaysWhenOptedIn() {
        let start = self.collapsedRestingTop - 2
        var upstream = self.makeState(firstMinY: start, count: 8)
        var kept = self.makeState(firstMinY: start, count: 8)
        self.promote(&upstream, listOptsIn: false)
        self.promote(&kept, listOptsIn: true)
        XCTAssertEqual(upstream.nodes[0].frame.minY, start - self.rowHeight, accuracy: 0.001)
        XCTAssertEqual(kept.nodes[0].frame.minY, start, accuracy: 0.001)
        XCTAssertGreaterThan(abs(kept.nodes[0].frame.minY - self.collapsedRestingTop), 1)
    }

    func testTwentyPointScrollStaysAtThatEdge() {
        let start = self.collapsedRestingTop - 20
        var kept = self.makeState(firstMinY: start, count: 8)
        self.promote(&kept, listOptsIn: true)
        XCTAssertEqual(kept.nodes[0].frame.minY, start, accuracy: 0.001)
        XCTAssertGreaterThan(abs(kept.nodes[0].frame.minY - self.collapsedRestingTop), 1)
    }

    func testARowAlreadyAboveTheInsetIsNotForcedDown() {
        let start: CGFloat = -200
        let removedMaxY = start + (2 * self.rowHeight)
        XCTAssertFalse(listViewNilHintRemovalMovesFollowingRows(removedMaxY: removedMaxY, itemOffsetInsetTop: self.insetTop))
        XCTAssertEqual(
            listViewTopDownInsert(
                downHintAtIndexZero: true,
                deletedItemIndices: [1],
                deletedMaxYByIndex: [1: removedMaxY],
                itemOffsetInsetTop: self.insetTop,
                listOptsIn: true
            ),
            .dropHint
        )
        var upstream = self.makeState(firstMinY: start, count: 8)
        var kept = self.makeState(firstMinY: start, count: 8)
        self.promote(&upstream, listOptsIn: false)
        self.promote(&kept, listOptsIn: true)
        XCTAssertEqual(kept.nodes[0].frame.minY, upstream.nodes[0].frame.minY, accuracy: 0.001)
        XCTAssertEqual(kept.nodes[0].frame.minY, start, accuracy: 0.001)
    }

    func testNoDownHintAndANonZeroDeleteStayUpstream() {
        XCTAssertEqual(
            listViewTopDownInsert(
                downHintAtIndexZero: false,
                deletedItemIndices: [1],
                deletedMaxYByIndex: [1: 300],
                itemOffsetInsetTop: self.insetTop,
                listOptsIn: true
            ),
            .upstream
        )
        XCTAssertEqual(
            listViewTopDownInsert(
                downHintAtIndexZero: true,
                deletedItemIndices: [4],
                deletedMaxYByIndex: [4: 500],
                itemOffsetInsetTop: self.insetTop,
                listOptsIn: false
            ),
            .upstream
        )
        XCTAssertEqual(
            listViewTopDownInsert(
                downHintAtIndexZero: true,
                deletedItemIndices: [1, 2],
                deletedMaxYByIndex: [1: 300, 2: 400],
                itemOffsetInsetTop: self.insetTop,
                listOptsIn: true
            ),
            .upstream
        )
    }
}
