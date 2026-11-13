import XCTest

/// Scroll a few screens down, open a chat, let the unread count change, and come back.
/// The row that was at the top of the viewport stays there, including when the clear in
/// between has already clamped the offset to 0. Switching folders or tapping Chats again
/// is what goes to the top.
final class ChatListScrollAnchorTests: XCTestCase {
    private let rowHeight = 72.0
    private let screens = 3
    private let rowsPerScreen = 8

    private func chats(_ count: Int) -> [ChatListScrollRow] {
        return (0 ..< count).map { index in
            ChatListScrollRow(id: .peer(Int64(index)), height: self.rowHeight)
        }
    }

    private func scrolledViewport() -> (rows: [ChatListScrollRow], offset: Double, anchor: ChatListScrollAnchor) {
        let rows = self.chats(40)
        let offset = Double(self.screens * self.rowsPerScreen) * self.rowHeight
        let capture = captureChatListScrollAnchor(rows: rows, contentOffset: offset)
        guard case let .anchored(anchor) = capture else {
            XCTFail("expected an anchor below the top, got \(capture)")
            return (rows, offset, ChatListScrollAnchor(id: .peer(0), rowTopFromTop: 0))
        }
        return (rows, offset, anchor)
    }

    func testSeveralScreensDownAnchorsTheRowAtTheViewportEdge() {
        let scrolled = self.scrolledViewport()
        XCTAssertEqual(scrolled.anchor.id, .peer(Int64(self.screens * self.rowsPerScreen)))
        XCTAssertEqual(scrolled.anchor.rowTopFromTop, 0, accuracy: 0.001)
        XCTAssertGreaterThan(scrolled.offset, self.rowHeight * Double(self.rowsPerScreen))
    }

    func testOpenChatUnreadReorderKeepsTheAnchorAfterTheOffsetWasClamped() {
        let scrolled = self.scrolledViewport()
        var next = scrolled.rows
        // Opening the chat clears its unread count and the sort moves that row to the top.
        // It sat below the anchor, so every row from the anchor down shifts by one.
        let openedIndex = 30
        let opened = next.remove(at: openedIndex)
        next.insert(opened, at: 0)

        let cleared = resolveChatListScroll(ChatListScrollRequest(
            anchor: scrolled.anchor,
            nextRowIds: [],
            command: .keepAnchor,
            wouldScrollToFirstItem: false,
            structureChanged: true,
            currentlyScrolledDown: false
        ))
        XCTAssertEqual(cleared.target, .unchanged)
        XCTAssertEqual(cleared.anchor, scrolled.anchor)

        let returned = resolveChatListScroll(ChatListScrollRequest(
            anchor: cleared.anchor,
            nextRowIds: next.map(\.id),
            command: .keepAnchor,
            wouldScrollToFirstItem: true,
            structureChanged: true,
            currentlyScrolledDown: false
        ))
        guard case let .row(index, rowTop) = returned.target else {
            XCTFail("expected the anchor row, got \(returned.target)")
            return
        }
        XCTAssertEqual(next[index].id, scrolled.anchor.id)
        XCTAssertEqual(rowTop, scrolled.anchor.rowTopFromTop, accuracy: 0.001)
        let restored = chatListContentOffset(rows: next, target: returned.target, fallback: 0)
        let origin = Double(index) * self.rowHeight
        XCTAssertEqual(origin - restored, scrolled.anchor.rowTopFromTop, accuracy: 0.001)
        XCTAssertNotEqual(returned.target, .top)
        XCTAssertGreaterThan(restored, self.rowHeight)
    }

    func testUnreadBadgeWithoutAMoveDoesNotRequestTheTop() {
        let scrolled = self.scrolledViewport()
        let next = scrolled.rows
        let resolution = resolveChatListScroll(ChatListScrollRequest(
            anchor: scrolled.anchor,
            nextRowIds: next.map(\.id),
            command: .keepAnchor,
            wouldScrollToFirstItem: false,
            structureChanged: false,
            currentlyScrolledDown: true
        ))
        XCTAssertEqual(resolution.target, .unchanged)
        XCTAssertEqual(resolution.anchor, scrolled.anchor)
        XCTAssertEqual(chatListContentOffset(rows: next, target: resolution.target, fallback: scrolled.offset), scrolled.offset, accuracy: 0.001)
    }

    func testSortChangeKeepsTheSameRowAndOffset() {
        let scrolled = self.scrolledViewport()
        var next = scrolled.rows
        let moved = next.remove(at: 3)
        next.append(moved)
        let resolution = resolveChatListScroll(ChatListScrollRequest(
            anchor: scrolled.anchor,
            nextRowIds: next.map(\.id),
            command: .keepAnchor,
            wouldScrollToFirstItem: false,
            structureChanged: true,
            currentlyScrolledDown: true
        ))
        guard case let .row(index, _) = resolution.target else {
            XCTFail("expected the anchor row, got \(resolution.target)")
            return
        }
        XCTAssertEqual(next[index].id, scrolled.anchor.id)
        let restored = chatListContentOffset(rows: next, target: resolution.target, fallback: 0)
        let origin = next.prefix(index).reduce(0.0) { $0 + $1.height }
        XCTAssertEqual(origin - restored, 0, accuracy: 0.001)
    }

    func testRefreshThatLooksEmptyDoesNotGoToTheTopWhileAnAnchorIsSaved() {
        let scrolled = self.scrolledViewport()
        let resolution = resolveChatListScroll(ChatListScrollRequest(
            anchor: scrolled.anchor,
            nextRowIds: scrolled.rows.map(\.id),
            command: .keepAnchor,
            wouldScrollToFirstItem: true,
            structureChanged: true,
            currentlyScrolledDown: true
        ))
        guard case let .row(index, _) = resolution.target else {
            XCTFail("expected the anchor row, got \(resolution.target)")
            return
        }
        XCTAssertEqual(scrolled.rows[index].id, scrolled.anchor.id)
        XCTAssertEqual(chatListContentOffset(rows: scrolled.rows, target: resolution.target, fallback: 0), scrolled.offset, accuracy: 0.001)
    }

    func testFolderSwitchAndChatsTabGoToTheTop() {
        let scrolled = self.scrolledViewport()
        XCTAssertEqual(chatListScrollCommand(folderChanged: false, chatsTabRetapped: false), .keepAnchor)
        for command in [
            chatListScrollCommand(folderChanged: true, chatsTabRetapped: false),
            chatListScrollCommand(folderChanged: false, chatsTabRetapped: true)
        ] {
            let resolution = resolveChatListScroll(ChatListScrollRequest(
                anchor: scrolled.anchor,
                nextRowIds: self.chats(10).map(\.id),
                command: command,
                wouldScrollToFirstItem: true,
                structureChanged: true,
                currentlyScrolledDown: true
            ))
            XCTAssertEqual(resolution.target, .top)
            XCTAssertNil(resolution.anchor)
            XCTAssertEqual(chatListContentOffset(rows: self.chats(10), target: resolution.target, fallback: scrolled.offset), 0, accuracy: 0.001)
        }
    }

    func testFirstPopulationWithoutAnAnchorStillOpensAtTheTop() {
        let resolution = resolveChatListScroll(ChatListScrollRequest(
            anchor: nil,
            nextRowIds: self.chats(5).map(\.id),
            command: .keepAnchor,
            wouldScrollToFirstItem: true,
            structureChanged: true,
            currentlyScrolledDown: false
        ))
        XCTAssertEqual(resolution.target, .top)
        XCTAssertNil(resolution.anchor)
    }

    func testAtTopCaptureForgetsTheAnchorAndAnEmptyListDoesNot() {
        let rows = self.chats(5)
        XCTAssertEqual(captureChatListScrollAnchor(rows: rows, contentOffset: 0), .atTop)
        let saved = ChatListScrollAnchor(id: .peer(9), rowTopFromTop: -12)
        XCTAssertNil(rememberChatListScrollAnchor(previous: saved, capture: .atTop))
        XCTAssertEqual(rememberChatListScrollAnchor(previous: saved, capture: .unavailable), saved)
        XCTAssertEqual(captureChatListScrollAnchor(rows: [], contentOffset: 0), .unavailable)
    }
}
