import XCTest
import Postbox
@testable import TelegramCore

/// A ranged history fill closes the span from the request boundary through the returned ids, clipped
/// to the window the request asked for. A page that misses that window entirely — `min_id` / `max_id`
/// ignored — does not close the hole.
final class RangeHoleFillRangeTests: XCTestCase {
    func testOlderPageClosesUpToTheBoundary() {
        let ids = Array(Int32(300) ... 399)
        XCTAssertEqual(rangeHoleFilledRange(boundaryId: 400, returnedIds: ids, requested: 1 ... 400, loadingNewer: false), 300 ... 400)
    }

    func testNewerPageClosesFromTheBoundary() {
        let ids = Array(Int32(101) ... 200)
        XCTAssertEqual(rangeHoleFilledRange(boundaryId: 100, returnedIds: ids, requested: 100 ... (Int32.max - 1), loadingNewer: true), 100 ... 200)
    }

    func testPageOutsideTheRequestClosesNothing() {
        let ids = Array(Int32(500) ... 550)
        XCTAssertNil(rangeHoleFilledRange(boundaryId: 400, returnedIds: ids, requested: 1 ... 400, loadingNewer: false))
    }

    func testPartialOverlapIsClippedToTheRequest() {
        let ids = Array(Int32(350) ... 450)
        XCTAssertEqual(rangeHoleFilledRange(boundaryId: 400, returnedIds: ids, requested: 1 ... 400, loadingNewer: false), 350 ... 400)
    }

    func testEmptyPageHasNoRange() {
        XCTAssertNil(rangeHoleFilledRange(boundaryId: 400, returnedIds: [], requested: 1 ... 400, loadingNewer: false))
    }
}
