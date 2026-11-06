import Foundation

/// Local image selection for a Discover post (D-10), before any upload request exists.
///
/// `GET /v1/feed/config` as this client parses it (`TellomiDiscoverEngineConfig`) has no image
/// count or byte cap. Limits are applied only after `confirm(maxCount:maxBytesEach:)` is given
/// numbers from a confirmed server config. This value stores no file URL, no image bytes, and
/// no credential. Cancel drops the selection. A finished upload key is recorded only when the
/// caller passes one in; this type does not invent a wire field or an HTTP response.
///
/// `posting` is `.textOnly` when nothing is selected, so an existing text, quote, poll, or
/// visibility publish is unchanged. Selected images block send until every one has a key, and
/// even then the post stays held: the upload route's field names are not confirmed, so the
/// text body must not be sent as if the images were attached.
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
        public var phase: Phase

        public init(localId: String, byteCount: Int, phase: Phase) {
            self.localId = localId
            self.byteCount = byteCount
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
        case notFailed
    }

    public enum Posting: Equatable {
        case textOnly
        case blocked
        /// Keys are present, in selection order. The post is not sendable until the engine
        /// contract names the field that carries them.
        case heldUntilWireConfirmed([String])
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
        return .heldUntilWireConfirmed(keys)
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
        self.items[index].phase = .uploading
        return nil
    }

    /// `key` is whatever a confirmed upload response supplied. An empty key is refused.
    public mutating func complete(localId: String, key: String) -> Refusal? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .emptyKey
        }
        guard let index = self.index(of: localId) else {
            return .missing
        }
        guard case .uploading = self.items[index].phase else {
            return .notUploading
        }
        self.items[index].phase = .uploaded(key: trimmed)
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
