import XCTest

final class TellomiFeedChromeMotionTests: XCTestCase {
    private let threshold = TellomiFeedNavigationScroll.threshold

    func testEmptyListKeepsTheBarVisible() {
        var state = TellomiFeedNavigationScrollState(visible: false, pending: 40)
        let hidden = TellomiFeedNavigationScroll.step(state: state, offsetY: 400, delta: 80, hasPosts: false)
        XCTAssertEqual(hidden.change, .shown)
        XCTAssertTrue(hidden.state.visible)
        XCTAssertEqual(hidden.state.pending, 0)
        state = hidden.state
        let stay = TellomiFeedNavigationScroll.step(state: state, offsetY: 400, delta: 80, hasPosts: false)
        XCTAssertEqual(stay.change, .unchanged)
        XCTAssertTrue(stay.state.visible)
    }

    func testTopOfTheListRestoresTheBar() {
        let state = TellomiFeedNavigationScrollState(visible: false, pending: -4)
        let top = TellomiFeedNavigationScroll.step(state: state, offsetY: 0, delta: 30, hasPosts: true)
        XCTAssertEqual(top.change, .shown)
        XCTAssertEqual(top.state, .resting)
        let already = TellomiFeedNavigationScroll.step(state: .resting, offsetY: TellomiFeedNavigationScroll.topReset, delta: 40, hasPosts: true)
        XCTAssertEqual(already.change, .unchanged)
    }

    func testDownwardTravelHidesOnlyAfterTheThreshold() {
        var state = TellomiFeedNavigationScrollState.resting
        let short = TellomiFeedNavigationScroll.step(state: state, offsetY: 80, delta: self.threshold - 1, hasPosts: true)
        XCTAssertEqual(short.change, .unchanged)
        XCTAssertTrue(short.state.visible)
        state = short.state
        let hide = TellomiFeedNavigationScroll.step(state: state, offsetY: 120, delta: 1, hasPosts: true)
        XCTAssertEqual(hide.change, .hidden)
        XCTAssertFalse(hide.state.visible)
        XCTAssertEqual(hide.state.pending, 0)
    }

    func testUpwardTravelShowsOnlyAfterTheThreshold() {
        var state = TellomiFeedNavigationScrollState(visible: false, pending: 0)
        let short = TellomiFeedNavigationScroll.step(state: state, offsetY: 200, delta: -(self.threshold - 1), hasPosts: true)
        XCTAssertEqual(short.change, .unchanged)
        XCTAssertFalse(short.state.visible)
        state = short.state
        let show = TellomiFeedNavigationScroll.step(state: state, offsetY: 160, delta: -1, hasPosts: true)
        XCTAssertEqual(show.change, .shown)
        XCTAssertTrue(show.state.visible)
    }

    func testADirectionChangeDoesNotAccumulateIntoAFlicker() {
        var state = TellomiFeedNavigationScrollState.resting
        state = TellomiFeedNavigationScroll.step(state: state, offsetY: 40, delta: 12, hasPosts: true).state
        let reversed = TellomiFeedNavigationScroll.step(state: state, offsetY: 48, delta: -12, hasPosts: true)
        XCTAssertEqual(reversed.change, .unchanged)
        XCTAssertTrue(reversed.state.visible)
        XCTAssertEqual(reversed.state.pending, -12)
        let noise = TellomiFeedNavigationScroll.step(state: reversed.state, offsetY: 48.4, delta: 0.4, hasPosts: true)
        XCTAssertEqual(noise.state, reversed.state)
        XCTAssertEqual(noise.change, .unchanged)
    }

    func testOneLongDownwardDragHides() {
        let drag = TellomiFeedNavigationScroll.step(state: .resting, offsetY: 200, delta: 180, hasPosts: true)
        XCTAssertEqual(drag.change, .hidden)
    }

    func testReduceMotionDropsTheAnimationOnly() {
        XCTAssertFalse(tellomiFeedNavigationTransitionAnimated(reduceMotion: true))
        XCTAssertTrue(tellomiFeedNavigationTransitionAnimated(reduceMotion: false))
    }

    func testComposeButtonSitsAboveTheBarAndTheKeyboard() {
        let resting = tellomiDiscoverComposeButtonFrame(containerWidth: 390, containerHeight: 800, bottomInset: 83, keyboardOverlap: 0)
        XCTAssertEqual(resting.width, 56)
        XCTAssertEqual(resting.height, 56)
        XCTAssertEqual(resting.maxX, 390 - 16, accuracy: 0.01)
        XCTAssertEqual(resting.maxY, 800 - 83 - 16, accuracy: 0.01)
        let keyboard = tellomiDiscoverComposeButtonFrame(containerWidth: 390, containerHeight: 800, bottomInset: 83, keyboardOverlap: 320)
        XCTAssertEqual(keyboard.maxY, 800 - 320 - 16, accuracy: 0.01)
        XCTAssertGreaterThan(keyboard.minY, 0)
        let narrow = tellomiDiscoverComposeButtonFrame(containerWidth: 40, containerHeight: 200, bottomInset: 0, keyboardOverlap: 0)
        XCTAssertGreaterThanOrEqual(narrow.minX, 16)
        XCTAssertLessThanOrEqual(narrow.maxX, 40 - 16)
    }

    func testComposeButtonUsesTheExistingComposeGate() {
        XCTAssertTrue(tellomiDiscoverComposeButtonVisible(showsCompose: true, engineVisible: true))
        XCTAssertFalse(tellomiDiscoverComposeButtonVisible(showsCompose: false, engineVisible: true))
        XCTAssertFalse(tellomiDiscoverComposeButtonVisible(showsCompose: true, engineVisible: false))
    }
}
