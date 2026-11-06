import Foundation

/// Local image selection for a Discover post.
///
/// The caps come from the 2026-11-06 content-engine contract (`99fb6ce`): `media_keys` allows
/// 10 keys, and `Tus-Max-Size` / the per-image cap is 20971520 bytes. `useVerifiedContract()`
/// applies those two numbers. Until it is called, selection stays closed, which is also how
/// the compose screen behaves when `media_upload` is absent.
///
/// This value stores no file URL, no image bytes, and no credential. Bytes and the tus session
/// live beside it. `posting` is `.textOnly` when nothing is selected, so a text, quote, or poll
/// post is unchanged. Selected images block send until every one is `.uploaded`, then `.ready`
/// carries the keys in selection order for `media_keys`.
public struct TellomiDiscoverImagePublish: Equatable {
    public enum LimitPolicy: Equatable {
        case unconfirmed
        case confirmed(maxCount: Int, maxBytesEach: Int)
    }

    public enum Phase: Equatable {
        case selected
        case uploading
        case failed
        case uploaded(key: String)
    }

    public struct Item: Equatable {
        public var localId: String
        public var byteCount: Int
        public var sent: Int
        public var phase: Phase

        public init(localId: String, byteCount: Int, sent: Int = 0, phase: Phase) {
            self.localId = localId
            self.byteCount = byteCount
            self.sent = sent
            self.phase = phase
        }
    }

    public enum Refusal: Equatable {
        case limitsUnconfirmed
        case limitInvalid
        case emptyId
        case byteCountInvalid
        case duplicate
        case overCount
        case overBytes
        case missing
        case notUploading
        case emptyKey
        case invalidKey
        case notFailed
    }

    public enum Posting: Equatable {
        case textOnly
        case blocked
        /// Upload keys in selection order. These are the `media_keys` to send.
        case ready([String])
    }

    public private(set) var limits: LimitPolicy
    public private(set) var items: [Item]

    public init(limits: LimitPolicy = .unconfirmed) {
        self.limits = limits
        self.items = []
    }

    public var posting: Posting {
        if self.items.isEmpty {
            return .textOnly
        }
        var keys: [String] = []
        keys.reserveCapacity(self.items.count)
        for item in self.items {
            guard case let .uploaded(key) = item.phase else {
                return .blocked
            }
            keys.append(key)
        }
        return .ready(keys)
    }

    /// Applies the verified 10-image and 20971520-byte caps. Does not open selection when the
    /// caller has not been told that `media_upload` is on; the compose screen gates that.
    public mutating func useVerifiedContract() -> Refusal? {
        return self.confirm(maxCount: TellomiDiscoverImageContract.maxCount, maxBytesEach: TellomiDiscoverImageContract.maxBytes)
    }

    public mutating func confirm(maxCount: Int, maxBytesEach: Int) -> Refusal? {
        guard maxCount > 0, maxBytesEach > 0 else {
            return .limitInvalid
        }
        if self.items.count > maxCount {
            return .overCount
        }
        if self.items.contains(where: { $0.byteCount > maxBytesEach }) {
            return .overBytes
        }
        self.limits = .confirmed(maxCount: maxCount, maxBytesEach: maxBytesEach)
        return nil
    }

    public mutating func select(localId: String, byteCount: Int) -> Refusal? {
        let trimmed = localId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .emptyId
        }
        guard byteCount > 0 else {
            return .byteCountInvalid
        }
        guard case let .confirmed(maxCount, maxBytesEach) = self.limits else {
            return .limitsUnconfirmed
        }
        if self.items.contains(where: { $0.localId == trimmed }) {
            return .duplicate
        }
        if self.items.count >= maxCount {
            return .overCount
        }
        if byteCount > maxBytesEach {
            return .overBytes
        }
        self.items.append(Item(localId: trimmed, byteCount: byteCount, phase: .selected))
        return nil
    }

    public mutating func beginUpload(localId: String) -> Refusal? {
        guard let index = self.index(of: localId) else {
            return .missing
        }
        switch self.items[index].phase {
        case .selected, .failed:
            self.items[index].sent = 0
            self.items[index].phase = .uploading
            return nil
        case .uploading, .uploaded:
            return .notFailed
        }
    }

    public mutating func fail(localId: String) -> Refusal? {
        guard let index = self.index(of: localId) else {
            return .missing
        }
        guard case .uploading = self.items[index].phase else {
            return .notUploading
        }
        self.items[index].phase = .failed
        return nil
    }

    public mutating func noteSent(localId: String, sent: Int) -> Refusal? {
        guard let index = self.index(of: localId) else {
            return .missing
        }
        guard case .uploading = self.items[index].phase else {
            return .notUploading
        }
        guard sent >= 0, sent <= self.items[index].byteCount else {
            return .byteCountInvalid
        }
        self.items[index].sent = sent
        return nil
    }

    /// Drops the selection. No key and no byte count remain.
    public mutating func cancel(localId: String) -> Refusal? {
        guard let index = self.index(of: localId) else {
            return .missing
        }
        self.items.remove(at: index)
        return nil
    }

    public mutating func retry(localId: String) -> Refusal? {
        guard let index = self.index(of: localId) else {
            return .missing
        }
        guard case .failed = self.items[index].phase else {
            return .notFailed
        }
        self.items[index].sent = 0
        self.items[index].phase = .uploading
        return nil
    }

    /// `key` must be the `Media-Key` from a finished upload (`m/` and a UUID).
    public mutating func complete(localId: String, key: String) -> Refusal? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .emptyKey
        }
        guard let key = tellomiDiscoverMediaKey(trimmed) else {
            return .invalidKey
        }
        guard let index = self.index(of: localId) else {
            return .missing
        }
        guard case .uploading = self.items[index].phase else {
            return .notUploading
        }
        self.items[index].sent = self.items[index].byteCount
        self.items[index].phase = .uploaded(key: key)
        return nil
    }

    private func index(of localId: String) -> Int? {
        return self.items.firstIndex(where: { $0.localId == localId })
    }
}

/// Image retry does not mint a new post nonce. The same `client_nonce` is what dedups the post.
public func tellomiDiscoverImageRetryNonce(current: String) -> String {
    return current
}
