import UIKit
import XCTest
import SwiftSignalKit
@testable import Display

/// One row of fixed height. The list lays it out through the normal item path.
private final class FixedHeightRow: ListViewItem {
    let rowHeight: CGFloat
    let neighborDescriptor: AnyEquatable = .noNeighborInfluence

    init(rowHeight: CGFloat) {
        self.rowHeight = rowHeight
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        let node = ListViewItemNode(layerBacked: true)
        node.contentSize = CGSize(width: params.width, height: self.rowHeight)
        completion(node, { (nil, { _ in }) })
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: self.rowHeight), insets: UIEdgeInsets())
        completion(layout, { _ in })
    }
}

/// Drives `ListView.transaction`, which is what calls `deleteAndInsertItemsTransaction`.
/// The test does not sample maxY, choose `forceIndexZeroDown`, or renumber indices.
final class ListViewTopReorderTests: XCTestCase {
    private let width: CGFloat = 390
    private let height: CGFloat = 800
    private let insetTop: CGFloat = 200
    private var hosts: [UIWindow] = []

    override func tearDown() {
        self.hosts.removeAll()
        super.tearDown()
    }

    private func makeList(preserves: Bool) -> ListViewImpl {
        let frame = CGRect(x: 0, y: 0, width: self.width, height: self.height)
        let window = UIWindow(frame: frame)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        self.hosts.append(window)
        let list = ListViewImpl()
        list.preservesTopDownInsert = preserves
        list.useMainQueueTransactions = true
        list.keepMinimalScrollHeightWithTopInset = 400
        list.frame = frame
        root.view.addSubview(list.view)
        list.view.frame = window.bounds
        return list
    }

    private func perform(_ list: ListViewImpl, delete: [ListViewDeleteItem] = [], insert: [ListViewInsertItem] = [], options: ListViewDeleteAndInsertOptions = [.Synchronous], size: ListViewUpdateSizeAndInsets? = nil) {
        let done = expectation(description: "transaction")
        list.transaction(
            deleteIndices: delete,
            insertIndicesAndItems: insert,
            updateIndicesAndItems: [],
            options: options,
            updateSizeAndInsets: size,
            updateOpaqueState: nil,
            completion: { _ in
                done.fulfill()
            }
        )
        wait(for: [done], timeout: 5)
        // endTransaction removes the queue entry on the next main turn. The next
        // transaction is dropped if that turn has not run.
        let drained = expectation(description: "transaction queue")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 5)
    }

    private func populate(_ list: ListViewImpl, heights: [CGFloat]) {
        let rows = heights.map { FixedHeightRow(rowHeight: $0) }
        let inserts = rows.enumerated().map { index, row in
            ListViewInsertItem(index: index, previousIndex: nil, item: row, directionHint: nil)
        }
        let size = ListViewUpdateSizeAndInsets(
            size: CGSize(width: self.width, height: self.height),
            insets: UIEdgeInsets(top: self.insetTop, left: 0, bottom: 0, right: 0),
            duration: 0,
            curve: .Default(duration: nil)
        )
        self.perform(list, insert: inserts, size: size)
    }

    private func topMinY(_ list: ListViewImpl) -> CGFloat {
        guard let node = list.itemNodeAtIndex(0) else {
            XCTFail("row 0 is missing")
            return 0
        }
        return node.frame.minY
    }

    /// Moves the rows up by `delta` through the scroll view. Returns the edge after the scroll.
    private func scroll(_ list: ListViewImpl, by delta: CGFloat) -> CGFloat {
        let before = self.topMinY(list)
        let offset = list.scroller.contentOffset
        list.scroller.setContentOffset(CGPoint(x: offset.x, y: offset.y + delta), animated: false)
        let after = self.topMinY(list)
        XCTAssertEqual(after, before - delta, accuracy: 0.5, "scroll by \(delta) did not move the rows")
        return after
    }

    private func promote(_ list: ListViewImpl, from index: Int, height: CGFloat, hint: ListViewItemOperationDirectionHint?, animated: Bool = false) {
        var options: ListViewDeleteAndInsertOptions = [.Synchronous]
        if animated {
            options.insert(.AnimateInsertion)
        }
        self.perform(
            list,
            delete: [ListViewDeleteItem(index: index, directionHint: nil)],
            insert: [ListViewInsertItem(index: 0, previousIndex: index, item: FixedHeightRow(rowHeight: height), directionHint: hint)],
            options: options
        )
    }

    func testUpstreamMovesTheFirstTwoPromotionsThenStops() {
        let list = self.makeList(preserves: false)
        let row: CGFloat = 76
        self.populate(list, heights: Array(repeating: row, count: 8))
        let collapsed = self.scroll(list, by: 54)
        var tops = [collapsed]
        for _ in 0 ..< 4 {
            self.promote(list, from: 1, height: row, hint: .Down)
            tops.append(self.topMinY(list))
        }
        XCTAssertEqual(tops[1], tops[0] - row, accuracy: 0.5)
        XCTAssertEqual(tops[2], tops[1] - row, accuracy: 0.5)
        XCTAssertEqual(tops[3], tops[2], accuracy: 0.5)
        XCTAssertEqual(tops[4], tops[3], accuracy: 0.5)
    }

    func testPreservingListKeepsTheAnchor() {
        let row: CGFloat = 76
        // These stay inside the scroll the short lists can actually hold. A two-row
        // scroll and an off-screen top are on the long list below.
        let scrolls: [CGFloat] = [54, 56, 74, 54 + 20.5, 54 + row]
        for count in [2, 4, 8, 12] {
            for delta in scrolls {
                let list = self.makeList(preserves: true)
                self.populate(list, heights: Array(repeating: row, count: count))
                let anchor = self.scroll(list, by: delta)
                self.promote(list, from: 1, height: row, hint: .Down)
                XCTAssertEqual(self.topMinY(list), anchor, accuracy: 0.5)
                self.promote(list, from: 1, height: row, hint: .Down)
                XCTAssertEqual(self.topMinY(list), anchor, accuracy: 0.5)
            }
        }
    }

    func testTwoRowScrollMatchesTheUnpreservedList() {
        let row: CGFloat = 76
        let kept = self.makeList(preserves: true)
        let plain = self.makeList(preserves: false)
        self.populate(kept, heights: Array(repeating: row, count: 20))
        self.populate(plain, heights: Array(repeating: row, count: 20))
        let keptAnchor = self.scroll(kept, by: 54 + (2 * row))
        let plainAnchor = self.scroll(plain, by: 54 + (2 * row))
        self.promote(kept, from: 1, height: row, hint: .Down)
        self.promote(plain, from: 1, height: row, hint: .Down)
        XCTAssertEqual(self.topMinY(kept), keptAnchor, accuracy: 0.5)
        XCTAssertEqual(self.topMinY(plain), plainAnchor, accuracy: 0.5)
        XCTAssertEqual(self.topMinY(kept), self.topMinY(plain), accuracy: 0.5)
    }

    func testSearchExpandedAlreadyStays() {
        let row: CGFloat = 76
        let kept = self.makeList(preserves: true)
        let plain = self.makeList(preserves: false)
        self.populate(kept, heights: Array(repeating: row, count: 4))
        self.populate(plain, heights: Array(repeating: row, count: 4))
        let anchor = self.topMinY(kept)
        XCTAssertEqual(anchor, self.insetTop, accuracy: 0.5)
        self.promote(kept, from: 1, height: row, hint: .Down)
        self.promote(plain, from: 1, height: row, hint: .Down)
        XCTAssertEqual(self.topMinY(kept), anchor, accuracy: 0.5)
        XCTAssertEqual(self.topMinY(plain), anchor, accuracy: 0.5)
    }

    func testUnequalHeightsKeepTheEdge() {
        let heights: [CGFloat] = [90, 40, 110, 55, 76]
        let list = self.makeList(preserves: true)
        self.populate(list, heights: heights)
        let anchor = self.scroll(list, by: 54 + 20)
        self.promote(list, from: 1, height: heights[1], hint: .Down)
        XCTAssertEqual(self.topMinY(list), anchor, accuracy: 0.5)
        self.promote(list, from: 2, height: heights[2], hint: .Down)
        XCTAssertEqual(self.topMinY(list), anchor, accuracy: 0.5)
    }

    func testIndexFourPromotionKeepsTheEdge() {
        let row: CGFloat = 76
        let list = self.makeList(preserves: true)
        self.populate(list, heights: Array(repeating: row, count: 8))
        let anchor = self.scroll(list, by: 54)
        self.promote(list, from: 4, height: row, hint: .Down)
        XCTAssertEqual(self.topMinY(list), anchor, accuracy: 0.5)
    }

    func testThirdRowPromotionKeepsTheEdge() {
        let row: CGFloat = 64
        let list = self.makeList(preserves: true)
        self.populate(list, heights: Array(repeating: row, count: 6))
        let anchor = self.scroll(list, by: 54)
        self.promote(list, from: 2, height: row, hint: .Down)
        XCTAssertEqual(self.topMinY(list), anchor, accuracy: 0.5)
        XCTAssertNotNil(list.itemNodeAtIndex(0))
    }

    func testOffScreenTopMatchesTheUnpreservedList() {
        let row: CGFloat = 76
        let kept = self.makeList(preserves: true)
        let plain = self.makeList(preserves: false)
        self.populate(kept, heights: Array(repeating: row, count: 20))
        self.populate(plain, heights: Array(repeating: row, count: 20))
        let delta = self.topMinY(kept) + row + 30
        let keptAnchor = self.scroll(kept, by: delta)
        let plainAnchor = self.scroll(plain, by: delta)
        XCTAssertLessThanOrEqual(keptAnchor + row, 0)
        self.promote(kept, from: 1, height: row, hint: .Down)
        self.promote(plain, from: 1, height: row, hint: .Down)
        XCTAssertEqual(self.topMinY(kept), self.topMinY(plain), accuracy: 0.5)
        XCTAssertEqual(self.topMinY(kept), keptAnchor, accuracy: 0.5)
        XCTAssertEqual(plainAnchor, keptAnchor, accuracy: 0.5)
    }

    func testNewPeerInsertWithoutADeleteIsNotForced() {
        let row: CGFloat = 76
        let kept = self.makeList(preserves: true)
        let plain = self.makeList(preserves: false)
        self.populate(kept, heights: Array(repeating: row, count: 4))
        self.populate(plain, heights: Array(repeating: row, count: 4))
        let _ = self.scroll(kept, by: 54)
        let _ = self.scroll(plain, by: 54)
        let insert = [ListViewInsertItem(index: 0, previousIndex: nil, item: FixedHeightRow(rowHeight: row), directionHint: .Down)]
        self.perform(kept, insert: insert)
        self.perform(plain, insert: insert)
        XCTAssertEqual(self.topMinY(kept), self.topMinY(plain), accuracy: 0.5)
    }

    func testTwoDeletesAreNotForced() {
        let row: CGFloat = 76
        let kept = self.makeList(preserves: true)
        let plain = self.makeList(preserves: false)
        self.populate(kept, heights: Array(repeating: row, count: 6))
        self.populate(plain, heights: Array(repeating: row, count: 6))
        let _ = self.scroll(kept, by: 54)
        let _ = self.scroll(plain, by: 54)
        let deletes = [
            ListViewDeleteItem(index: 1, directionHint: nil),
            ListViewDeleteItem(index: 2, directionHint: nil)
        ]
        let insert = [ListViewInsertItem(index: 0, previousIndex: 1, item: FixedHeightRow(rowHeight: row), directionHint: .Down)]
        self.perform(kept, delete: deletes, insert: insert)
        self.perform(plain, delete: deletes, insert: insert)
        XCTAssertEqual(self.topMinY(kept), self.topMinY(plain), accuracy: 0.5)
    }

    func testInsertBelowTheTopDoesNotMoveTheFirstRow() {
        let row: CGFloat = 76
        let kept = self.makeList(preserves: true)
        let plain = self.makeList(preserves: false)
        self.populate(kept, heights: Array(repeating: row, count: 8))
        self.populate(plain, heights: Array(repeating: row, count: 8))
        let keptTop = self.scroll(kept, by: 54 + 20)
        let plainTop = self.scroll(plain, by: 54 + 20)
        let delete = [ListViewDeleteItem(index: 4, directionHint: nil)]
        let insert = [ListViewInsertItem(index: 3, previousIndex: 4, item: FixedHeightRow(rowHeight: row), directionHint: .Down)]
        self.perform(kept, delete: delete, insert: insert)
        self.perform(plain, delete: delete, insert: insert)
        XCTAssertEqual(self.topMinY(kept), keptTop, accuracy: 0.5)
        XCTAssertEqual(self.topMinY(plain), plainTop, accuracy: 0.5)
    }

    func testAnimatedInsertionStillCompletes() {
        let row: CGFloat = 76
        let list = self.makeList(preserves: true)
        self.populate(list, heights: Array(repeating: row, count: 4))
        let _ = self.scroll(list, by: 54)
        self.promote(list, from: 1, height: row, hint: .Down, animated: true)
        XCTAssertNotNil(list.itemNodeAtIndex(0))
        XCTAssertNotNil(list.itemNodeAtIndex(3))
    }
}
