import XCTest
import UIKit
import Display
import TabBarLayout

final class TellomiTabBarPhoneLayoutTests: XCTestCase {
    // Two titled tabs on a 440pt phone (416pt after the 12pt side insets) are the measured capsule: 188pt.

    func test_twoTitledTabs_hugAt90pt() {
        let result = tellomiPhoneTabBarHugLayout(showsItemTitles: true, unboundItemWidths: [40.0, 36.0], availableLength: 416.0)
        XCTAssertEqual(result?.size, CGSize(width: 188.0, height: 64.0))
        XCTAssertEqual(result?.itemFrames, [
            CGRect(x: 4.0, y: 4.0, width: 90.0, height: 56.0),
            CGRect(x: 94.0, y: 4.0, width: 90.0, height: 56.0)
        ])
    }

    func test_threeTitledTabs_hugInsteadOfTheFullWidth() {
        let result = tellomiPhoneTabBarHugLayout(showsItemTitles: true, unboundItemWidths: [40.0, 40.0, 40.0], availableLength: 416.0)
        XCTAssertEqual(result?.size, CGSize(width: 278.0, height: 64.0))
        XCTAssertEqual(result?.itemFrames[1], CGRect(x: 94.0, y: 4.0, width: 90.0, height: 56.0))
    }

    func test_longTitle_widensOnlyThatTab() {
        let result = tellomiPhoneTabBarHugLayout(showsItemTitles: true, unboundItemWidths: [120.0, 40.0], availableLength: 416.0)
        XCTAssertEqual(result?.size, CGSize(width: 218.0, height: 64.0))
        XCTAssertEqual(result?.itemFrames, [
            CGRect(x: 4.0, y: 4.0, width: 120.0, height: 56.0),
            CGRect(x: 124.0, y: 4.0, width: 90.0, height: 56.0)
        ])
    }

    func test_fourTitledTabs_within60pt_returnsNilSoTheBarFills() {
        // 4 * 90 + 8 = 368. 416 - 368 = 48 < 60.
        XCTAssertNil(tellomiPhoneTabBarHugLayout(showsItemTitles: true, unboundItemWidths: [40.0, 40.0, 40.0, 40.0], availableLength: 416.0))
    }

    func test_fourTitledTabs_exactly60ptShort_stillHugs() {
        // 428 - 368 = 60, which is not under the threshold.
        let result = tellomiPhoneTabBarHugLayout(showsItemTitles: true, unboundItemWidths: [40.0, 40.0, 40.0, 40.0], availableLength: 428.0)
        XCTAssertEqual(result?.size.width, 368.0)
    }

    func test_hideTitles_twoTabs_hugAtTheIconLength() {
        let result = tellomiPhoneTabBarHugLayout(showsItemTitles: false, unboundItemWidths: [80.0, 80.0], availableLength: 416.0)
        XCTAssertEqual(result?.size, CGSize(width: 120.0, height: 48.0))
        XCTAssertEqual(result?.itemFrames, [
            CGRect(x: 4.0, y: 4.0, width: 56.0, height: 40.0),
            CGRect(x: 60.0, y: 4.0, width: 56.0, height: 40.0)
        ])
    }

    func test_hideTitles_ignoresAWideMeasuredTitle() {
        let result = tellomiPhoneTabBarHugLayout(showsItemTitles: false, unboundItemWidths: [140.0, 140.0], availableLength: 416.0)
        XCTAssertEqual(result?.size.width, 120.0)
    }

    func test_noItems_insetOnlyBar() {
        let result = tellomiPhoneTabBarHugLayout(showsItemTitles: true, unboundItemWidths: [], availableLength: 416.0)
        XCTAssertEqual(result?.size, CGSize(width: 8.0, height: 64.0))
        XCTAssertEqual(result?.itemFrames, [])
    }
}
