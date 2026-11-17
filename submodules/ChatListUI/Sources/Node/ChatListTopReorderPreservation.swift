import Foundation

/// Process-local switch for the chat list's top-insert preservation.
///
/// `enabled` defaults to true. It is not read from the server. A `ChatListNode`
/// created while this is false leaves `preservesTopDownInsert` false, and that
/// list keeps the upstream hint gate. The frame rule itself is
/// `listViewTopDownInsert` in Display, which `deleteAndInsertItemsTransaction` calls.
enum ChatListTopReorderPreservation {
    static var enabled = true
}
