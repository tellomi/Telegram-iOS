# Upstream patches

The client tree on `release/ios` is Telegram-iOS `279f89e4`. Changes below are Tellomi
patches on top of that tree.

## Chat list scroll anchor

Opening a chat marks it read. That refresh, and a pagination hole that used to replace
the sampled window with a single hole entry, was sending the chat list back to the first
row. A clear drops every row, `UIScrollView` clamps the offset to 0, and the next frame's
offset is `.none` or `.known(0)`. A delete-and-insert that leaves no surviving row is laid
out from index 0. Both happen while the chat is still open.

The Postbox view keeps the dialogs at and newer than a hole, and appends the hole after
them. The list remembers the row at the viewport edge and that row's distance from the
top. A refresh, an unread update, or a reorder of the same folder scrolls to that row.
An empty frame does not replace the memory with the clamped 0. The first population of
an empty list, a folder change, and a second tap on the Chats tab (or the user's own
scroll-to-top) still go to the top.

| File | Change |
| --- | --- |
| `submodules/Postbox/Sources/ChatListView.swift` | Keep dialogs above a hole instead of replacing the sampled window with the hole. |
| `submodules/Postbox/Tests/ChatListHoleKeepsLoadedDialogsTests.swift` | Hole at the oldest dialog keeps that page; a hole newer than every dialog drops it. |
| `submodules/TelegramCore/Sources/TelegramEngine/Messages/ChatList.swift` | A hole after loaded dialogs does not mark the list as an empty loading page. |
| `submodules/ChatListUI/Sources/Node/ChatListViewTransition.swift` | A same-folder refresh is not an empty view, so it does not request a scroll to row 0. |
| `submodules/ChatListUI/Sources/Node/ChatListScrollAnchor.swift` | Anchor capture and the keep-or-top decision. |
| `submodules/ChatListUI/Sources/Node/ChatListNode.swift` | Saves the row from the visible nodes. Applies the decision instead of always scrolling to row 0. Folder changes and `scrollToPosition` (the Chats tab and scroll-to-top) clear it. |
| `submodules/ChatListUI/Tests/ChatListScrollAnchorTests.swift` | Scrolled list, open chat, unread reorder, clamped offset, delete-and-reinsert, badge-only update, sort, refresh, folder, Chats tab, first population. |
| `submodules/ChatListUI/BUILD` | Host `swift_test` `ChatListScrollAnchorTests`. The anchor test is excluded from the UIKit `ios_unit_test` sources. |

Tests:

```sh
bazel test //submodules/ChatListUI:ChatListScrollAnchorTests
bazel test //submodules/Postbox:PostboxTests --test_filter=ChatListHoleKeepsLoadedDialogsTests
```
