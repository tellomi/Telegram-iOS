import Foundation

import Display

/// Process-local switch for the chat list's top-insert preservation.
///
/// `enabled` defaults to true. It is not read from the server. `ChatListNode.init`
/// calls `install(on:)`. A node created while this is false does not opt in, and
/// `deleteAndInsertItemsTransaction` keeps the upstream hint gate.
enum ChatListTopReorderPreservation {
    static var enabled = true

    /// The list test sets this so `ChatListNode.init` can return after `install(on:)`.
    /// Production leaves it false, and the rest of `init` runs.
    static var returnAfterInstall = false

    static func install(on list: ListViewImpl) {
        list.preservesTopDownInsert = enabled
    }
}
