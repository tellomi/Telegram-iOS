/// One row the chat list can keep on screen. Visual index 0 is the top row.
enum ChatListScrollRowId: Hashable {
    case peer(Int64)
    case thread(Int64)
    case group(Int32)
    case header
}

struct ChatListScrollAnchor: Equatable {
    var id: ChatListScrollRowId
    /// Row top relative to the viewport's top edge. Zero puts that edge on the row's top.
    /// Negative means the row starts above the viewport.
    var rowTopFromTop: Double
}

enum ChatListAnchorCapture: Equatable {
    /// Row 0 is on screen and the list is at its top edge. Forget any saved anchor.
    case atTop
    /// A row is on screen below that edge.
    case anchored(ChatListScrollAnchor)
    /// No row is loaded. The previous anchor stays; a clamped offset of 0 is not a new position.
    case unavailable
}

enum ChatListScrollCommand: Equatable {
    /// Refresh, a read-state change, or a sort of the same folder.
    case keepAnchor
    /// Switching folders, or tapping the Chats tab again.
    case scrollToTop
}

/// Folder switches and a second tap on the Chats tab are the only two gestures that go to the top.
func chatListScrollCommand(folderChanged: Bool, chatsTabRetapped: Bool) -> ChatListScrollCommand {
    if folderChanged || chatsTabRetapped {
        return .scrollToTop
    }
    return .keepAnchor
}

enum ChatListScrollTarget: Equatable {
    case unchanged
    case top
    case row(index: Int, rowTopFromTop: Double)
}

struct ChatListScrollRequest: Equatable {
    var anchor: ChatListScrollAnchor?
    /// Visual order, index 0 at the top, including the header when the list has one.
    var nextRowIds: [ChatListScrollRowId]
    var command: ChatListScrollCommand
    /// The transition would otherwise scroll to row 0 because it treated the list as empty.
    var wouldScrollToFirstItem: Bool
    /// Deletes or inserts. An unread badge that stays on the same row is not structural.
    var structureChanged: Bool
    /// Row 0 is off screen, or more than a point below the top. False after the offset has already been clamped.
    var currentlyScrolledDown: Bool
}

struct ChatListScrollResolution: Equatable {
    var anchor: ChatListScrollAnchor?
    var target: ChatListScrollTarget
}

struct ChatListScrollRow: Equatable {
    var id: ChatListScrollRowId
    var height: Double
}

/// The row that crosses the viewport's top edge, or `.unavailable` when nothing is loaded.
func captureChatListScrollAnchor(rows: [ChatListScrollRow], contentOffset: Double) -> ChatListAnchorCapture {
    if rows.isEmpty {
        return .unavailable
    }
    var origin = 0.0
    for row in rows {
        let next = origin + row.height
        if next > contentOffset + 0.5 {
            let rowTop = origin - contentOffset
            if row.id == rows[0].id && contentOffset <= 1.0 && abs(rowTop) <= 1.0 {
                return .atTop
            }
            return .anchored(ChatListScrollAnchor(id: row.id, rowTopFromTop: rowTop))
        }
        origin = next
    }
    return .unavailable
}

func rememberChatListScrollAnchor(previous: ChatListScrollAnchor?, capture: ChatListAnchorCapture) -> ChatListScrollAnchor? {
    switch capture {
    case .atTop:
        return nil
    case let .anchored(anchor):
        return anchor
    case .unavailable:
        return previous
    }
}

/// Where the next frame should sit.
///
/// A saved anchor wins over "the list was empty, scroll to row 0". That scroll is what runs
/// after a clear has already clamped the offset to 0, and also what a full delete-and-insert
/// does when no row survives to anchor the layout. Folder switches and a second tap on Chats
/// are the two commands that drop the anchor and go to the top.
func resolveChatListScroll(_ request: ChatListScrollRequest) -> ChatListScrollResolution {
    switch request.command {
    case .scrollToTop:
        return ChatListScrollResolution(anchor: nil, target: .top)
    case .keepAnchor:
        guard let anchor = request.anchor else {
            if request.wouldScrollToFirstItem && !request.currentlyScrolledDown {
                return ChatListScrollResolution(anchor: nil, target: .top)
            }
            return ChatListScrollResolution(anchor: nil, target: .unchanged)
        }
        guard let index = request.nextRowIds.firstIndex(of: anchor.id) else {
            return ChatListScrollResolution(anchor: anchor, target: .unchanged)
        }
        let pin = request.wouldScrollToFirstItem || request.structureChanged || !request.currentlyScrolledDown
        if pin {
            return ChatListScrollResolution(anchor: anchor, target: .row(index: index, rowTopFromTop: anchor.rowTopFromTop))
        }
        return ChatListScrollResolution(anchor: anchor, target: .unchanged)
    }
}

/// Content offset that puts `target` where the anchor was. `.unchanged` keeps `fallback`.
func chatListContentOffset(rows: [ChatListScrollRow], target: ChatListScrollTarget, fallback: Double) -> Double {
    switch target {
    case .unchanged:
        return fallback
    case .top:
        return 0
    case let .row(index, rowTopFromTop):
        guard index >= 0 && index < rows.count else {
            return fallback
        }
        var origin = 0.0
        for row in rows.prefix(index) {
            origin += row.height
        }
        return origin - rowTopFromTop
    }
}
