import Foundation
import XCTest
import SwiftSignalKit
@testable import Postbox

/// A chat-list hole is the cursor of the next `messages.getDialogs` page. The dialogs
/// at and above that cursor are already loaded. Dropping them (the hole used to
/// `removeAll` every entry seen so far, and it sorts before every newer dialog)
/// replaces the list with the hole. The list view then has nothing to anchor, and
/// the scroll offset clamps to the top when the page comes back.
final class ChatListHoleKeepsLoadedDialogsTests: XCTestCase {
    private var fixture: PostboxFixture!

    private let oldest = MessageHistoryTableFixture.peerId(910)
    private let middle = MessageHistoryTableFixture.peerId(911)
    private let newest = MessageHistoryTableFixture.peerId(912)
    private let namespace = PostboxFixture.messageNamespace

    override func setUp() {
        super.setUp()
        self.fixture = PostboxFixture(name: "ChatListHoleKeepsLoadedDialogsTests")
    }

    override func tearDown() {
        self.fixture.close()
        self.fixture = nil
        super.tearDown()
    }

    private func message(peerId: PeerId, timestamp: Int32) -> StoreMessage {
        return MessageHistoryTableFixture.storeMessage(id: MessageId(peerId: peerId, namespace: self.namespace, id: 1), timestamp: timestamp, text: "m", flags: [.Incoming])
    }

    private func seedThreeChats() {
        self.fixture.transaction { transaction in
            transaction.updatePeersInternal([
                FixturePeer(id: self.oldest, title: "Oldest"),
                FixturePeer(id: self.middle, title: "Middle"),
                FixturePeer(id: self.newest, title: "Newest")
            ], update: { _, updated in updated })
            for peerId in [self.oldest, self.middle, self.newest] {
                transaction.updatePeerChatListInclusion(peerId, inclusion: .ifHasMessagesOrOneOf(groupId: .root, pinningIndex: nil, minTimestamp: nil))
            }
            let _ = transaction.addMessages([
                self.message(peerId: self.oldest, timestamp: 1000),
                self.message(peerId: self.middle, timestamp: 2000),
                self.message(peerId: self.newest, timestamp: 3000)
            ], location: .Random)
        }
    }

    private func peerOrder(in view: ChatListView?) -> [PeerId] {
        return (view?.entries ?? []).compactMap { entry -> PeerId? in
            if case let .MessageEntry(data) = entry {
                return data.index.messageIndex.id.peerId
            }
            return nil
        }
    }

    private func tailView() -> ChatListView? {
        let recorder = self.fixture.observe(self.fixture.postbox.tailChatListView(groupId: .root, filterPredicate: nil, count: 10, summaryComponents: ChatListEntrySummaryComponents()) |> map { $0.0 })
        return recorder.waitForValues(count: 1).last
    }

    func testPaginationHoleKeepsDialogsAtAndNewerThanTheCursor() {
        self.seedThreeChats()
        self.fixture.transaction { transaction in
            for hole in transaction.allChatListHoles(groupId: .root) {
                transaction.replaceChatListHole(groupId: .root, index: hole.index, hole: nil)
            }
            let cursor = MessageIndex(id: MessageId(peerId: self.oldest, namespace: self.namespace, id: 1), timestamp: 1000)
            transaction.addChatListHole(groupId: .root, hole: ChatListHole(index: cursor))
        }

        let view = self.tailView()
        XCTAssertEqual(self.peerOrder(in: view), [self.oldest, self.middle, self.newest])
        guard let entries = view?.entries, let last = entries.last else {
            XCTFail("expected a chat list view")
            return
        }
        guard case .HoleEntry = last else {
            XCTFail("the pagination hole stays after the loaded dialogs, got \(entries)")
            return
        }
        XCTAssertEqual(entries.count, 4)
    }

    func testHoleNewerThanEveryDialogDropsTheUnloadedPage() {
        self.seedThreeChats()
        self.fixture.transaction { transaction in
            for hole in transaction.allChatListHoles(groupId: .root) {
                transaction.replaceChatListHole(groupId: .root, index: hole.index, hole: nil)
            }
            let aboveEverything = MessageIndex(id: MessageId(peerId: MessageHistoryTableFixture.peerId(0), namespace: self.namespace, id: 1), timestamp: Int32.max - 1)
            transaction.addChatListHole(groupId: .root, hole: ChatListHole(index: aboveEverything))
        }

        let view = self.tailView()
        XCTAssertEqual(self.peerOrder(in: view), [], "dialogs older than an unfilled top hole are not a loaded page")
        guard let entries = view?.entries, entries.count == 1, case .HoleEntry = entries[0] else {
            XCTFail("expected only the top hole, got \(String(describing: view?.entries))")
            return
        }
    }
}
