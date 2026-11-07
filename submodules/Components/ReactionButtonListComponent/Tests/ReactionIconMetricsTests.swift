import XCTest
import CoreGraphics

final class ReactionIconMetricsTests: XCTestCase {
    func testBuiltinIconFillsTheSlotAndCannotLeaveIt() {
        let slot = CGSize(width: 20.0, height: 20.0)
        let metrics = reactionIconMetrics(slot: slot, kind: .builtin)
        XCTAssertEqual(metrics.size, slot)
        XCTAssertEqual(metrics.origin, .zero)
        XCTAssertTrue(metrics.clipsToBounds)
    }

    func testCustomEmojiStaysLargerAndClipped() {
        let metrics = reactionIconMetrics(slot: CGSize(width: 20.0, height: 20.0), kind: .custom)
        XCTAssertEqual(metrics.size, CGSize(width: 25.0, height: 25.0))
        XCTAssertEqual(metrics.origin, CGPoint(x: -2.0, y: -2.0))
        XCTAssertTrue(metrics.clipsToBounds)
    }

    func testStarsStayUnclipped() {
        let metrics = reactionIconMetrics(slot: CGSize(width: 20.0, height: 20.0), kind: .stars)
        XCTAssertEqual(metrics.size, CGSize(width: 25.0, height: 25.0))
        XCTAssertFalse(metrics.clipsToBounds)
    }
}
