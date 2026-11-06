import XCTest

final class ChatHistoryEmptyLoadingDecisionTests: XCTestCase {
    func testSameLoadKeepsRowsWhileTheHoleIsEmpty() {
        XCTAssertEqual(
            historyEmptyLoadingDecision(
                isLoading: true,
                incomingEntriesEmpty: true,
                previousEntriesEmpty: false,
                frameGeneration: 3,
                appliedGeneration: 3
            ),
            .keepDisplayedRows
        )
    }

    func testChatSwitchAppliesTheEmptyFrameInsteadOfKeepingThePreviousChat() {
        XCTAssertEqual(
            historyEmptyLoadingDecision(
                isLoading: true,
                incomingEntriesEmpty: true,
                previousEntriesEmpty: false,
                frameGeneration: 4,
                appliedGeneration: 3
            ),
            .applyIncomingFrame
        )
    }

    func testEmptyLoadingWithNoPreviousRowsIsApplied() {
        XCTAssertEqual(
            historyEmptyLoadingDecision(
                isLoading: true,
                incomingEntriesEmpty: true,
                previousEntriesEmpty: true,
                frameGeneration: 1,
                appliedGeneration: 1
            ),
            .applyIncomingFrame
        )
    }

    func testFinishedEmptyChatIsApplied() {
        XCTAssertEqual(
            historyEmptyLoadingDecision(
                isLoading: false,
                incomingEntriesEmpty: true,
                previousEntriesEmpty: false,
                frameGeneration: 2,
                appliedGeneration: 2
            ),
            .applyIncomingFrame
        )
    }

    func testLoadingFrameThatAlreadyHasEntriesIsApplied() {
        XCTAssertEqual(
            historyEmptyLoadingDecision(
                isLoading: true,
                incomingEntriesEmpty: false,
                previousEntriesEmpty: false,
                frameGeneration: 2,
                appliedGeneration: 2
            ),
            .applyIncomingFrame
        )
    }

    func testAStaleSubscriptionIsNotTheCurrentLoad() {
        XCTAssertFalse(historyLoadEventIsCurrent(eventGeneration: 3, currentGeneration: 4))
        XCTAssertTrue(historyLoadEventIsCurrent(eventGeneration: 4, currentGeneration: 4))
    }
}
