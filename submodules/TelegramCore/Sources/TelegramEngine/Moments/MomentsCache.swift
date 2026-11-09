import Foundation
import Postbox

private enum MomentsCacheKind: UInt8 {
    case feed = 1
    case drafts = 2
    case hides = 3
    case browse = 4
    case notifications = 5
    case outbox = 6
}

private func momentsCacheId(_ kind: MomentsCacheKind, extra: UInt8 = 0) -> ItemCacheEntryId {
    let key = ValueBoxKey(length: 2)
    key.setUInt8(0, value: kind.rawValue)
    key.setUInt8(1, value: extra)
    return ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.moments, key: key)
}

private func momentsFeedExtra(_ kind: MomentsFeedKind) -> UInt8 {
    switch kind {
    case .recommend:
        return 1
    case .following:
        return 2
    case .friends:
        return 3
    case .nearby:
        return 4
    }
}

struct MomentsCachedBlob: Codable, Equatable {
    var payload: String
}

func momentsReadBlob(transaction: Transaction, id: ItemCacheEntryId) -> String? {
    return transaction.retrieveItemCacheEntry(id: id)?.get(MomentsCachedBlob.self)?.payload
}

func momentsWriteBlob(transaction: Transaction, id: ItemCacheEntryId, payload: String?) {
    if let payload, let entry = CodableEntry(MomentsCachedBlob(payload: payload)) {
        transaction.putItemCacheEntry(id: id, entry: entry)
    } else {
        transaction.removeItemCacheEntry(id: id)
    }
}

func momentsFeedCacheId(_ kind: MomentsFeedKind) -> ItemCacheEntryId {
    return momentsCacheId(.feed, extra: momentsFeedExtra(kind))
}

func momentsDraftsCacheId() -> ItemCacheEntryId {
    return momentsCacheId(.drafts)
}

func momentsHidesCacheId() -> ItemCacheEntryId {
    return momentsCacheId(.hides)
}

func momentsBrowseCacheId() -> ItemCacheEntryId {
    return momentsCacheId(.browse)
}

func momentsNotificationsCacheId() -> ItemCacheEntryId {
    return momentsCacheId(.notifications)
}

func momentsOutboxCacheId() -> ItemCacheEntryId {
    return momentsCacheId(.outbox)
}
