import Foundation

/// Image upload contract verified against content-engine `99fb6ce` on 2026-11-06.
///
/// Ten images is the `media_keys` maximum on `POST /v1/feed/posts`.
/// 20 MiB is `Tus-Max-Size: 20971520` from `OPTIONS /v1/feed/media/uploads`, and the per-image cap.
/// This file does not invent a public image host. A card image is shown from `media[].url` when
/// that URL is https, otherwise from `feed/config` `media_base_url` joined with the key.
public enum TellomiDiscoverImageContract {
    public static let maxCount = 10
    public static let maxBytes = 20_971_520
    public static let tusVersion = "1.0.0"
    public static let tusExtensions = "creation,termination"
    public static let maxEdge = 12_000
    public static let maxPixels = 50_000_000
    public static let uploadsPath = "/v1/feed/media/uploads"
    public static let retryAfterSeconds = 60
    public static let mediaUpload = "media_upload"
    public static let writeIdempotency = "write_idempotency"
}

public func tellomiDiscoverFeatureEnabled(_ capabilities: TellomiDiscoverCapabilities, _ feature: String) -> Bool {
    return capabilities.features.contains(feature)
}

/// `m/` plus a UUID. The returned key is lowercase. Empty and non-UUID keys are refused.
public func tellomiDiscoverMediaKey(_ raw: String) -> String? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.count == 38, value.lowercased().hasPrefix("m/") else {
        return nil
    }
    let parts = value.dropFirst(2).split(separator: "-")
    let counts = [8, 4, 4, 4, 12]
    guard parts.count == counts.count else {
        return nil
    }
    for (part, count) in zip(parts, counts) {
        guard part.count == count, part.allSatisfy(\.isHexDigit) else {
            return nil
        }
    }
    return "m/" + value.dropFirst(2).lowercased()
}

public func tellomiDiscoverImagePixelsAllowed(width: Int, height: Int) -> Bool {
    guard width > 0, height > 0, width <= TellomiDiscoverImageContract.maxEdge, height <= TellomiDiscoverImageContract.maxEdge else {
        return false
    }
    let pixels = Int64(width) * Int64(height)
    return pixels <= Int64(TellomiDiscoverImageContract.maxPixels)
}

public enum TellomiDiscoverImageBytes: Equatable {
    /// JPEG, PNG, or WebP that already fits the edge and pixel caps.
    case upload(kind: String, width: Int, height: Int)
    /// HEIC/HEIF. The app must transcode to JPEG and drop location metadata before upload.
    case convertHeic
    case rejected
}

public func tellomiDiscoverInspectImage(_ data: Data) -> TellomiDiscoverImageBytes {
    guard !data.isEmpty, data.count <= TellomiDiscoverImageContract.maxBytes else {
        return .rejected
    }
    if tellomiDiscoverImageIsHeic(data) {
        return .convertHeic
    }
    if let size = tellomiDiscoverPNGSize(data) ?? tellomiDiscoverJPEGSize(data) ?? tellomiDiscoverWebPSize(data) {
        guard tellomiDiscoverImagePixelsAllowed(width: size.width, height: size.height) else {
            return .rejected
        }
        return .upload(kind: size.kind, width: size.width, height: size.height)
    }
    return .rejected
}

public struct TellomiDiscoverImageMedia: Equatable {
    public var key: String
    public var width: Int
    public var height: Int
    /// Present only when the card supplied an https URL. Never synthesized from a public host.
    public var url: URL?

    public init(key: String, width: Int, height: Int, url: URL?) {
        self.key = key
        self.width = width
        self.height = height
        self.url = url
    }
}

public func tellomiDiscoverMediaBaseURL(_ raw: String) -> URL? {
    return tellomiDiscoverHTTPSURL(raw)
}

private func tellomiDiscoverHTTPSURL(_ raw: String) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let parts = URLComponents(string: trimmed), parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil, let host = parts.host, !host.isEmpty else {
        return nil
    }
    return parts.url
}

/// Prefer the card's signed or CDN `url`. Otherwise join `media_base_url` and the key.
/// An http URL, a URL with a user, or a missing base produces nil.
public func tellomiDiscoverImageURL(image: TellomiDiscoverImageMedia, mediaBaseURL: URL?) -> URL? {
    if let url = image.url, url.scheme?.lowercased() == "https", url.user == nil, url.host != nil {
        return url
    }
    guard let key = tellomiDiscoverMediaKey(image.key), let base = mediaBaseURL, base.scheme?.lowercased() == "https", base.user == nil, base.host != nil else {
        return nil
    }
    var text = base.absoluteString
    while text.hasSuffix("/") {
        text.removeLast()
    }
    guard let joined = URL(string: text + "/" + key), joined.scheme?.lowercased() == "https", joined.host?.caseInsensitiveCompare(base.host ?? "") == .orderedSame else {
        return nil
    }
    return joined
}

public enum TellomiDiscoverImagePreviewSource: Equatable {
    case remote([URL])
    case local
    case none
}

/// Before review, cards are not `ok` and carry no displayable media. The author's local bytes stay.
/// After review, an `ok` card uses its remote URLs and the local bytes are no longer the source.
public func tellomiDiscoverImagePreviewSource(cardState: String, remoteURLs: [URL], hasLocalBytes: Bool) -> TellomiDiscoverImagePreviewSource {
    if cardState == "ok" {
        return remoteURLs.isEmpty ? .none : .remote(remoteURLs)
    }
    return hasLocalBytes ? .local : .none
}

public final class TellomiDiscoverLocalPreviewBook {
    private var stored: [String: [Data]] = [:]

    public init() {
    }

    public func keep(postId: String, images: [Data]) {
        let id = postId.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = images.filter { !$0.isEmpty }
        guard !id.isEmpty, !images.isEmpty else {
            return
        }
        self.stored[id] = images
    }

    public func images(for postId: String) -> [Data] {
        return self.stored[postId] ?? []
    }

    public func drop(postId: String) {
        self.stored.removeValue(forKey: postId)
    }
}

public struct TellomiDiscoverImageWireCall: Equatable {
    public var method: String
    public var url: URL
    public var body: Data?
    public var authorizes: Bool
    public var headers: [String: String]

    public init(method: String, url: URL, body: Data?, authorizes: Bool, headers: [String: String]) {
        self.method = method
        self.url = url
        self.body = body
        self.authorizes = authorizes
        self.headers = headers
    }
}

public func tellomiDiscoverMediaUploadsURL(base: URL) -> URL? {
    guard var parts = URLComponents(url: base, resolvingAgainstBaseURL: false), parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil, parts.host != nil else {
        return nil
    }
    parts.path = TellomiDiscoverImageContract.uploadsPath
    parts.query = nil
    parts.fragment = nil
    return parts.url
}

/// Absolute or origin-relative Location is accepted only for this host and `/v1/feed/media/uploads/{id}`.
public func tellomiDiscoverAllowedMediaLocation(_ location: String, base: URL) -> URL? {
    guard let baseParts = URLComponents(url: base, resolvingAgainstBaseURL: false), baseParts.scheme?.lowercased() == "https", baseParts.user == nil, baseParts.password == nil, let host = baseParts.host, !host.isEmpty else {
        return nil
    }
    let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.lowercased().hasPrefix("javascript:"), !trimmed.contains("\\"), !trimmed.contains("@") else {
        return nil
    }
    let resolved: URLComponents?
    if trimmed.hasPrefix("/") {
        var parts = baseParts
        parts.query = nil
        parts.fragment = nil
        parts.percentEncodedPath = trimmed
        resolved = parts
    } else {
        resolved = URLComponents(string: trimmed)
    }
    guard var parts = resolved, parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil, let locationHost = parts.host, locationHost.caseInsensitiveCompare(host) == .orderedSame else {
        return nil
    }
    let basePort = baseParts.port ?? 443
    let locationPort = parts.port ?? 443
    guard basePort == locationPort, parts.fragment == nil, parts.query == nil else {
        return nil
    }
    let path = parts.percentEncodedPath
    let prefix = TellomiDiscoverImageContract.uploadsPath + "/"
    guard path.hasPrefix(prefix) else {
        return nil
    }
    let rest = path.dropFirst(prefix.count)
    let segments = rest.split(separator: "/", omittingEmptySubsequences: false)
    guard !segments.isEmpty, segments.allSatisfy({ segment in
        !segment.isEmpty && segment != "." && segment != ".." && !segment.contains("%") && !segment.contains(":")
    }) else {
        return nil
    }
    parts.percentEncodedPath = path
    return parts.url
}

public func tellomiDiscoverImageWireTarget(_ call: TellomiDiscoverImageWireCall, base: URL) -> Bool {
    guard call.url.scheme?.lowercased() == "https", call.url.user == nil else {
        return false
    }
    guard let uploads = tellomiDiscoverMediaUploadsURL(base: base), call.url.host?.caseInsensitiveCompare(uploads.host ?? "") == .orderedSame else {
        return false
    }
    if !call.authorizes {
        return call.method == "OPTIONS" && call.url.path == TellomiDiscoverImageContract.uploadsPath
    }
    if call.url.path == TellomiDiscoverImageContract.uploadsPath {
        return call.method == "POST" || call.method == "OPTIONS"
    }
    return tellomiDiscoverAllowedMediaLocation(call.url.absoluteString, base: base) != nil
}

public enum TellomiDiscoverImageUploadFailure: Equatable {
    case transport
    case unauthorized
    case hidden
    case conflict
    case rejectedFormat
    case tooLarge
    case tooMany
    case locationRejected
    case keyMismatch
    case gone
    case unexpected
}

public struct TellomiDiscoverImageUploadSession: Equatable {
    public enum Step: Equatable {
        case options
        case create
        case patch
        case head
        case delete
        case wait(seconds: Int)
        case done(key: String)
        case failed(TellomiDiscoverImageUploadFailure)
        case voided
        case cancelled
    }

    public private(set) var step: Step
    public private(set) var offset: Int
    public private(set) var location: URL?
    public private(set) var mediaKey: String?
    public let length: Int
    public var chunkBytes: Int
    private var optionsAccepted: Bool
    private var lastSent: Int
    private var transportStrikes: Int
    private var discarding: Bool

    public init(length: Int) {
        self.step = .options
        self.offset = 0
        self.location = nil
        self.mediaKey = nil
        self.length = length
        self.chunkBytes = Int.max
        self.optionsAccepted = false
        self.lastSent = 0
        self.transportStrikes = 0
        self.discarding = false
    }

    public mutating func call(base: URL, bytes: Data) -> TellomiDiscoverImageWireCall? {
        guard bytes.count == self.length, self.length > 0, self.length <= TellomiDiscoverImageContract.maxBytes else {
            return nil
        }
        let tus = ["Tus-Resumable": TellomiDiscoverImageContract.tusVersion]
        switch self.step {
        case .options:
            guard let url = tellomiDiscoverMediaUploadsURL(base: base) else {
                return nil
            }
            return self.sending(TellomiDiscoverImageWireCall(method: "OPTIONS", url: url, body: nil, authorizes: false, headers: tus))
        case .create:
            guard let url = tellomiDiscoverMediaUploadsURL(base: base) else {
                return nil
            }
            var headers = tus
            headers["Upload-Length"] = String(self.length)
            return self.sending(TellomiDiscoverImageWireCall(method: "POST", url: url, body: nil, authorizes: true, headers: headers))
        case .patch:
            guard let url = self.location, self.offset < self.length, self.offset <= bytes.count else {
                return nil
            }
            let end = min(self.length, self.offset + max(1, self.chunkBytes))
            var headers = tus
            headers["Content-Type"] = "application/offset+octet-stream"
            headers["Upload-Offset"] = String(self.offset)
            return self.sending(TellomiDiscoverImageWireCall(method: "PATCH", url: url, body: bytes.subdata(in: self.offset ..< end), authorizes: true, headers: headers))
        case .head:
            guard let url = self.location else {
                return nil
            }
            return self.sending(TellomiDiscoverImageWireCall(method: "HEAD", url: url, body: nil, authorizes: true, headers: tus))
        case .delete:
            guard let url = self.location else {
                return nil
            }
            return self.sending(TellomiDiscoverImageWireCall(method: "DELETE", url: url, body: nil, authorizes: true, headers: tus))
        case .wait, .done, .failed, .voided, .cancelled:
            return nil
        }
    }

    private mutating func sending(_ call: TellomiDiscoverImageWireCall) -> TellomiDiscoverImageWireCall {
        self.lastSent = call.body?.count ?? 0
        return call
    }

    public mutating func receive(_ result: TellomiDiscoverHTTPResult, base: URL) {
        self.transportStrikes = 0
        if result.status == 401 || result.status == 403 {
            self.step = .failed(.unauthorized)
            return
        }
        if result.status == 404, tellomiDiscoverErrorCode(result.body) == "feed_hidden" {
            self.step = .failed(.hidden)
            return
        }
        switch self.step {
        case .options:
            self.receiveOptions(result)
        case .create:
            self.receiveCreate(result, base: base)
        case .patch:
            self.receivePatch(result)
        case .head:
            self.receiveHead(result)
        case .delete:
            if result.status == 204 || result.status == 404 {
                let discard = self.discarding
                self.location = nil
                self.discarding = false
                self.step = discard ? .failed(.keyMismatch) : .cancelled
            } else {
                self.step = .failed(.unexpected)
            }
        case .wait, .done, .failed, .voided, .cancelled:
            break
        }
    }

    public mutating func transportFailed() {
        self.transportStrikes += 1
        if self.transportStrikes >= 3 {
            self.step = .failed(.transport)
            return
        }
        if self.location != nil, self.step == .patch || self.step == .head {
            self.step = .head
            return
        }
        self.step = .failed(.transport)
    }

    public mutating func waited() {
        guard case .wait = self.step else {
            return
        }
        self.step = .create
    }

    /// Continue an authorized upload after a new credential, or start a replacement after 415.
    public mutating func retry() {
        self.transportStrikes = 0
        switch self.step {
        case .failed(.rejectedFormat), .voided:
            self.location = nil
            self.mediaKey = nil
            self.offset = 0
            self.step = self.optionsAccepted ? .create : .options
        case .failed, .cancelled:
            if let _ = self.location {
                self.step = .head
            } else {
                self.step = self.optionsAccepted ? .create : .options
            }
        case .wait:
            self.step = .create
        default:
            break
        }
    }

    public mutating func cancel() {
        switch self.step {
        case .done, .cancelled, .voided:
            return
        default:
            break
        }
        if self.location == nil {
            self.step = .cancelled
        } else {
            self.step = .delete
        }
    }

    private mutating func receiveOptions(_ result: TellomiDiscoverHTTPResult) {
        guard result.status == 200 || result.status == 204 else {
            self.step = .failed(.unexpected)
            return
        }
        let version = tellomiDiscoverHeader(result.headers, "Tus-Version") ?? ""
        let extensions = tellomiDiscoverHeader(result.headers, "Tus-Extension") ?? ""
        guard version.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).contains(TellomiDiscoverImageContract.tusVersion) else {
            self.step = .failed(.unexpected)
            return
        }
        let names = extensions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard names.contains("creation"), names.contains("termination") else {
            self.step = .failed(.unexpected)
            return
        }
        guard let maxText = tellomiDiscoverHeader(result.headers, "Tus-Max-Size"), let maxBytes = Int(maxText), maxBytes > 0 else {
            self.step = .failed(.unexpected)
            return
        }
        guard self.length <= maxBytes, self.length <= TellomiDiscoverImageContract.maxBytes else {
            self.step = .failed(.tooLarge)
            return
        }
        self.optionsAccepted = true
        self.step = .create
    }

    private mutating func receiveCreate(_ result: TellomiDiscoverHTTPResult, base: URL) {
        if result.status == 429 {
            let header = tellomiDiscoverHeader(result.headers, "Retry-After").flatMap(Int.init)
            let seconds = header.flatMap { $0 > 0 ? $0 : nil } ?? TellomiDiscoverImageContract.retryAfterSeconds
            self.step = .wait(seconds: seconds)
            return
        }
        if result.status == 415 {
            self.location = nil
            self.step = .voided
            return
        }
        guard result.status == 201 else {
            self.step = .failed(.unexpected)
            return
        }
        guard let headerLocation = tellomiDiscoverHeader(result.headers, "Location"), let location = tellomiDiscoverAllowedMediaLocation(headerLocation, base: base) else {
            self.location = nil
            self.step = .failed(.locationRejected)
            return
        }
        guard let headerKey = tellomiDiscoverHeader(result.headers, "Media-Key").flatMap(tellomiDiscoverMediaKey), let bodyKey = tellomiDiscoverCreatedMediaKey(result.body), headerKey == bodyKey else {
            self.location = location
            self.discarding = true
            self.step = .delete
            return
        }
        self.location = location
        self.mediaKey = headerKey
        self.offset = 0
        self.step = .patch
    }

    private mutating func receivePatch(_ result: TellomiDiscoverHTTPResult) {
        if result.status == 409 {
            self.step = .head
            return
        }
        if result.status == 415 {
            self.location = nil
            self.mediaKey = nil
            self.step = .voided
            return
        }
        if result.status == 404 {
            self.step = .failed(.gone)
            return
        }
        guard result.status == 204, let reported = tellomiDiscoverHeader(result.headers, "Upload-Offset").flatMap(Int.init) else {
            self.step = .failed(.unexpected)
            return
        }
        let sent = self.lastSent
        guard reported >= self.offset, reported <= self.offset + sent, reported <= self.length else {
            self.step = .head
            return
        }
        self.offset = reported
        if self.offset == self.length, let key = self.mediaKey {
            self.step = .done(key: key)
        } else {
            self.step = .patch
        }
    }

    private mutating func receiveHead(_ result: TellomiDiscoverHTTPResult) {
        if result.status == 404 {
            self.location = nil
            self.step = .failed(.gone)
            return
        }
        guard (result.status == 200 || result.status == 204), let reported = tellomiDiscoverHeader(result.headers, "Upload-Offset").flatMap(Int.init), reported >= 0, reported <= self.length else {
            self.step = .failed(.conflict)
            return
        }
        self.offset = reported
        if reported == self.length, let key = self.mediaKey {
            self.step = .done(key: key)
        } else {
            self.step = .patch
        }
    }
}

public func tellomiDiscoverHeader(_ headers: [String: String], _ name: String) -> String? {
    for (key, value) in headers where key.caseInsensitiveCompare(name) == .orderedSame {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
    }
    return nil
}

private struct TellomiDiscoverImageSize {
    var kind: String
    var width: Int
    var height: Int
}

private func tellomiDiscoverImageIsHeic(_ data: Data) -> Bool {
    guard data.count >= 12 else {
        return false
    }
    let bytes = [UInt8](data.prefix(32))
    guard bytes.count >= 12, String(bytes: bytes[4 ..< 8], encoding: .ascii) == "ftyp" else {
        return false
    }
    let brand = String(bytes: bytes[8 ..< 12], encoding: .ascii)?.lowercased() ?? ""
    return ["heic", "heix", "hevc", "heif", "mif1", "msf1"].contains(brand)
}

private func tellomiDiscoverPNGSize(_ data: Data) -> TellomiDiscoverImageSize? {
    let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    let bytes = [UInt8](data.prefix(24))
    guard bytes.count >= 24, Array(bytes.prefix(8)) == signature else {
        return nil
    }
    guard String(bytes: bytes[12 ..< 16], encoding: .ascii) == "IHDR" else {
        return nil
    }
    let width = tellomiDiscoverBigEndian(bytes, 16)
    let height = tellomiDiscoverBigEndian(bytes, 20)
    return TellomiDiscoverImageSize(kind: "png", width: width, height: height)
}

private func tellomiDiscoverJPEGSize(_ data: Data) -> TellomiDiscoverImageSize? {
    let bytes = [UInt8](data)
    guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else {
        return nil
    }
    var index = 2
    while index + 3 < bytes.count {
        if bytes[index] != 0xFF {
            index += 1
            continue
        }
        while index < bytes.count, bytes[index] == 0xFF {
            index += 1
        }
        guard index < bytes.count else {
            return nil
        }
        let marker = bytes[index]
        index += 1
        if marker == 0xD9 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7) {
            continue
        }
        guard index + 1 < bytes.count else {
            return nil
        }
        let length = (Int(bytes[index]) << 8) + Int(bytes[index + 1])
        guard length >= 2, index + length <= bytes.count else {
            return nil
        }
        let sof = [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF].contains(Int(marker))
        if sof, length >= 7 {
            let height = (Int(bytes[index + 3]) << 8) + Int(bytes[index + 4])
            let width = (Int(bytes[index + 5]) << 8) + Int(bytes[index + 6])
            return TellomiDiscoverImageSize(kind: "jpeg", width: width, height: height)
        }
        index += length
    }
    return nil
}

private func tellomiDiscoverWebPSize(_ data: Data) -> TellomiDiscoverImageSize? {
    let bytes = [UInt8](data.prefix(30))
    guard bytes.count >= 30, String(bytes: bytes[0 ..< 4], encoding: .ascii) == "RIFF", String(bytes: bytes[8 ..< 12], encoding: .ascii) == "WEBP", String(bytes: bytes[12 ..< 16], encoding: .ascii) == "VP8X" else {
        return nil
    }
    let width = 1 + Int(bytes[24]) + (Int(bytes[25]) << 8) + (Int(bytes[26]) << 16)
    let height = 1 + Int(bytes[27]) + (Int(bytes[28]) << 8) + (Int(bytes[29]) << 16)
    return TellomiDiscoverImageSize(kind: "webp", width: width, height: height)
}

private func tellomiDiscoverBigEndian(_ bytes: [UInt8], _ offset: Int) -> Int {
    return (Int(bytes[offset]) << 24) + (Int(bytes[offset + 1]) << 16) + (Int(bytes[offset + 2]) << 8) + Int(bytes[offset + 3])
}

private func tellomiDiscoverCreatedMediaKey(_ data: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    guard let id = object["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
    }
    guard let key = object["key"] as? String else {
        return nil
    }
    return tellomiDiscoverMediaKey(key)
}

