import Foundation
import CryptoKit
import Postbox

/// ADR-0083 B2. `upload.getFileHashes#9156982a` checks a finished plaintext
/// download against the SHA-256 parts Teamgram stores.
///
/// Parts are 128 KiB, the same split as `upload.getCdnFileHashes` and teamgram
/// `cdn.PartHashes` (`59922c63` / #215). `offset` drops parts that start before
/// it. The last part is shorter. A miss, an empty vector, an RPC error, or a
/// timeout leaves the download alone. A part whose bytes do not match fails it.
///
/// The request is the current `offset:long` method. `messages.getDocumentByHash`
/// is a different call and is not used here.
enum TellomiFileHashVerdict: Equatable {
    case match
    case mismatch
    case failOpen
}

struct TellomiFileHashPart: Equatable {
    var offset: Int64
    var limit: Int
    var hash: Data

    init(offset: Int64, limit: Int, hash: Data) {
        self.offset = offset
        self.limit = limit
        self.hash = Data(hash)
    }

    var wellFormed: Bool {
        if self.offset < 0 || self.limit <= 0 || self.limit > tellomiFileHashPartBytes {
            return false
        }
        if self.offset > Int64.max - Int64(self.limit) {
            return false
        }
        return self.hash.count == 32
    }
}

/// `upload.getFileHashes#9156982a location:InputFileLocation offset:long`.
let tellomiGetFileHashesConstructor: Int32 = Int32(bitPattern: 0x9156982a)

/// SHA-256 part size shared with `upload.getCdnFileHashes`.
let tellomiFileHashPartBytes: Int = 128 * 1024

/// After the bytes are on disk, give up waiting for hashes and keep the file.
/// The timer starts when the download is ready to finish, so a hung RPC cannot
/// hold the file.
let tellomiFileHashFailOpenSeconds: Double = 12

/// Account 0 `mainconfig` on Android (`MessagesController.getGlobalMainSettings()`).
/// iOS stores the same boolean in the account's persisted `help.getAppConfig`
/// (`AppConfiguration`). Missing or `true` runs the check. `false` skips the RPC.
/// Read when a download is about to ask; do not cache the value.
let tellomiGetFileHashesKey = "tellomi_get_file_hashes"

/// Enough parts for a multi-gigabyte file at `tellomiFileHashPartBytes`.
let tellomiFileHashMaxRequests: Int = 20_000

/// Tests only. `nil` reads `tellomiGetFileHashesKey`.
var tellomiGetFileHashesEnabledOverride: Bool?

/// The check is on unless the key is boolean `false`.
/// A missing key, an empty configuration, or a non-boolean stays on: Android's
/// `getBoolean(key, true)` does the same, and a prefs failure there stays on too.
func tellomiGetFileHashesEnabled(configuration: AppConfiguration) -> Bool {
    if let override = tellomiGetFileHashesEnabledOverride {
        return override
    }
    guard case let .dictionary(fields)? = configuration.data, let value = fields[tellomiGetFileHashesKey] else {
        return true
    }
    if case let .bool(enabled) = value {
        return enabled
    }
    return true
}

/// A full MTProto download whose stored bytes are the plaintext `upload.getFile`
/// returns. CDN downloads already check ciphertext hashes. Web files have no
/// `InputFileLocation`. Secret-chat decryption and local cache encryption store
/// different bytes. Preload, a prefix stop, and a file already on disk are not
/// this download. Legacy `inputFileLocation` is rejected by the server.
func tellomiFileHashDownloadApplies(enabled: Bool, hasLocation: Bool, locationIsLegacy: Bool, webFile: Bool, cdn: Bool, preload: Bool, alreadyOnDisk: Bool, secretEncrypted: Bool, cacheEncrypted: Bool, prefixOnly: Bool) -> Bool {
    if !enabled || !hasLocation || locationIsLegacy {
        return false
    }
    if webFile || cdn || preload || alreadyOnDisk || secretEncrypted || cacheEncrypted || prefixOnly {
        return false
    }
    return true
}

/// SHA-256 parts of `body`, using the same offset filter as teamgram `cdn.PartHashes`.
/// A negative offset yields nothing; the client does not send one.
func tellomiFileHashParts(of body: Data, requestOffset: Int64) -> [TellomiFileHashPart] {
    if requestOffset < 0 || body.isEmpty {
        return []
    }
    var out: [TellomiFileHashPart] = []
    var offset = 0
    while offset < body.count {
        if Int64(offset) < requestOffset {
            offset += tellomiFileHashPartBytes
            continue
        }
        let length = min(tellomiFileHashPartBytes, body.count - offset)
        let hash = tellomiFileHashSha256(body.subdata(in: offset ..< (offset + length)))
        out.append(TellomiFileHashPart(offset: Int64(offset), limit: length, hash: hash))
        offset += tellomiFileHashPartBytes
    }
    return out
}

func tellomiFileHashSha256(_ data: Data) -> Data {
    return Data(SHA256.hash(data: data))
}

/// Bytes from 0 covered by a contiguous run of well-formed parts.
func tellomiFileHashCoveredPrefix(_ parts: [TellomiFileHashPart]) -> Int64 {
    let sorted = parts.filter { $0.wellFormed }.sorted { $0.offset < $1.offset }
    var cursor: Int64 = 0
    for part in sorted {
        if part.offset > cursor {
            break
        }
        let end = part.offset + Int64(part.limit)
        if end > cursor {
            cursor = end
        }
    }
    return cursor
}

/// Next `offset` so the parts cover `fileSize`. `-1` when the size is unknown
/// or the prefix already covers it.
func tellomiFileHashNextOffset(fileSize: Int64, parts: [TellomiFileHashPart]) -> Int64 {
    if fileSize <= 0 {
        return -1
    }
    let cursor = tellomiFileHashCoveredPrefix(parts)
    if cursor >= fileSize {
        return -1
    }
    return cursor
}

func tellomiFileHashHasWellFormed(_ parts: [TellomiFileHashPart]) -> Bool {
    return parts.contains(where: { $0.wellFormed })
}

/// Compare well-formed parts to `body`. No well-formed part is a miss.
/// A part that runs past the body, or whose SHA-256 differs, is a mismatch.
/// When `confirmedEnd` is set, a body longer than the contiguous prefix is a
/// mismatch too: the server said the file ends there.
func tellomiFileHashCheck(body: Data, parts: [TellomiFileHashPart], confirmedEnd: Bool) -> TellomiFileHashVerdict {
    if !tellomiFileHashHasWellFormed(parts) {
        return .failOpen
    }
    if confirmedEnd {
        let cursor = tellomiFileHashCoveredPrefix(parts)
        if cursor > 0 && Int64(body.count) > cursor {
            return .mismatch
        }
    }
    for part in parts where part.wellFormed {
        if part.offset > Int64(body.count) || Int64(part.limit) > Int64(body.count) - part.offset {
            return .mismatch
        }
        let start = Int(part.offset)
        let digest = tellomiFileHashSha256(body.subdata(in: start ..< (start + part.limit)))
        if digest != part.hash {
            return .mismatch
        }
    }
    return .match
}

/// Same rules as `tellomiFileHashCheck(body:parts:confirmedEnd:)` for a file on disk.
/// A file that cannot be read is fail-open so a local read error does not block the download.
func tellomiFileHashCheck(path: String, fileSize: Int64, parts: [TellomiFileHashPart], confirmedEnd: Bool) -> TellomiFileHashVerdict {
    if !tellomiFileHashHasWellFormed(parts) {
        return .failOpen
    }
    if confirmedEnd {
        let cursor = tellomiFileHashCoveredPrefix(parts)
        if cursor > 0 && fileSize > cursor {
            return .mismatch
        }
    }
    guard FileManager.default.fileExists(atPath: path), let handle = FileHandle(forReadingAtPath: path) else {
        return .failOpen
    }
    defer {
        try? handle.close()
    }
    for part in parts where part.wellFormed {
        if part.offset > fileSize || Int64(part.limit) > fileSize - part.offset {
            return .mismatch
        }
        do {
            try handle.seek(toOffset: UInt64(part.offset))
            guard let bytes = try tellomiFileHashRead(handle, count: part.limit) else {
                return .mismatch
            }
            if tellomiFileHashSha256(bytes) != part.hash {
                return .mismatch
            }
        } catch {
            return .failOpen
        }
    }
    return .match
}

private func tellomiFileHashRead(_ handle: FileHandle, count: Int) throws -> Data? {
    var data = Data()
    while data.count < count {
        guard let chunk = try handle.read(upToCount: count - data.count) else {
            return nil
        }
        if chunk.isEmpty {
            return nil
        }
        data.append(chunk)
    }
    return data
}

/// One download's hash pages. The caller serializes access.
/// An empty page means the server has no further parts (`confirmedEnd`).
/// An error or a timeout is `stop()` and does not confirm the length.
struct TellomiFileHashSession {
    private(set) var parts: [TellomiFileHashPart] = []
    private var asked: Set<Int64> = []
    private(set) var started = false
    private(set) var stopped = false
    private(set) var confirmedEnd = false

    var hasParts: Bool {
        return tellomiFileHashHasWellFormed(self.parts)
    }

    /// First request is offset 0. Further calls return `-1`.
    mutating func open() -> Int64 {
        if self.started {
            return -1
        }
        self.started = true
        self.asked.insert(0)
        return 0
    }

    /// RPC error or timeout. Keep any parts already stored.
    mutating func stop() {
        self.stopped = true
    }

    /// Merge one page. Returns the next offset, or `-1` when no further request should be sent.
    mutating func accept(fileSize: Int64, page: [TellomiFileHashPart]) -> Int64 {
        if self.stopped {
            return -1
        }
        if page.isEmpty {
            self.confirmedEnd = true
            self.stopped = true
            return -1
        }
        var added = 0
        for part in page where part.wellFormed {
            self.parts.append(part)
            added += 1
        }
        if added == 0 {
            self.stopped = true
            return -1
        }
        return self.requestNext(fileSize: fileSize)
    }

    /// Next page for a file whose length is now known. `-1` when the file is covered,
    /// the offset is already in flight, or the session has stopped.
    mutating func requestNext(fileSize: Int64) -> Int64 {
        if self.stopped {
            return -1
        }
        if self.asked.count >= tellomiFileHashMaxRequests {
            self.stopped = true
            return -1
        }
        let next = tellomiFileHashNextOffset(fileSize: fileSize, parts: self.parts)
        if next < 0 || self.asked.contains(next) {
            return -1
        }
        self.asked.insert(next)
        return next
    }
}
