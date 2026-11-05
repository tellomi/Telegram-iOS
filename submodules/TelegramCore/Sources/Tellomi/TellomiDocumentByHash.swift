import Foundation

/// Which outgoing file may skip its byte upload via `messages.getDocumentByHash`.
///
/// TDLib sets this for animations and documents (`MessageContent.cpp`, `allow_get_by_hash`)
/// and restarts the normal upload when the lookup fails (`FileManager::on_upload_error`).
/// Videos are included only up to `tellomiDocumentByHashVideoByteLimit`: a miss reads the
/// file again for the upload, so a long video starts uploading immediately. The server
/// still deduplicates those bytes after the upload.
enum TellomiDocumentByHashRole: Equatable {
    case gif
    case document
    case video
}

struct TellomiDocumentByHashTraits: Equatable {
    var mimeType: String
    var encrypted: Bool
    var isAnimated: Bool
    var isAnimatedSticker: Bool
    var isVideoSticker: Bool
    var isSticker: Bool
    var isCustomEmoji: Bool
    var isVoice: Bool
    var isMusic: Bool
    var isVideo: Bool
    var isInstantVideo: Bool
}

enum TellomiDocumentByHashDecision: Equatable {
    case lookup(TellomiDocumentByHashRole)
    case skip
}

/// Inclusive upper bound for a video hash probe. GIFs and ordinary documents are not capped.
let tellomiDocumentByHashVideoByteLimit: Int64 = 100 * 1024 * 1024

/// Account 0 `mainconfig` on Android (`MessagesController.getGlobalMainSettings()`).
/// iOS stores the same boolean in the sending account's persisted `help.getAppConfig`
/// (`AppConfiguration`). Missing or `true` keeps the lookup. `false` skips it.
/// Read on each send; do not cache the value.
let tellomiGetDocumentByHashKey = "tellomi_get_document_by_hash"

/// Tests only. `nil` reads `tellomiGetDocumentByHashKey` from the persisted configuration.
var tellomiGetDocumentByHashEnabledOverride: Bool?

/// Lookup stays on unless the key is boolean `false`.
/// A missing key, an empty configuration, or a non-boolean stays on: Android's
/// `getBoolean(key, true)` does the same, and a prefs failure there stays on too.
func tellomiGetDocumentByHashEnabled(configuration: AppConfiguration) -> Bool {
    if let override = tellomiGetDocumentByHashEnabledOverride {
        return override
    }
    guard case let .dictionary(fields)? = configuration.data, let value = fields[tellomiGetDocumentByHashKey] else {
        return true
    }
    if case let .bool(enabled) = value {
        return enabled
    }
    return true
}

func tellomiDocumentByHashDecision(_ traits: TellomiDocumentByHashTraits) -> TellomiDocumentByHashDecision {
    if traits.encrypted || traits.mimeType.isEmpty {
        return .skip
    }
    if traits.isSticker || traits.isCustomEmoji || traits.isAnimatedSticker || traits.isVideoSticker {
        return .skip
    }
    if traits.isVoice || traits.isMusic || traits.isInstantVideo {
        return .skip
    }
    if traits.isAnimated || traits.mimeType == "image/gif" {
        return .lookup(.gif)
    }
    if traits.isVideo {
        return .lookup(.video)
    }
    return .lookup(.document)
}

func tellomiDocumentByHashSizeIsEligible(role: TellomiDocumentByHashRole, size: Int64) -> Bool {
    if size <= 0 {
        return false
    }
    if role == .video && size > tellomiDocumentByHashVideoByteLimit {
        return false
    }
    return true
}

/// A hit is a real document whose size and mime are the ones we hashed.
/// `documentEmpty`, a zero id, or a dc the client cannot download from is a miss.
func tellomiDocumentByHashIsReusable(id: Int64, dcId: Int32, size: Int64, mimeType: String, expectedSize: Int64, expectedMimeType: String) -> Bool {
    if id == 0 || dcId <= 0 {
        return false
    }
    if expectedSize <= 0 || expectedMimeType.isEmpty {
        return false
    }
    return size == expectedSize && mimeType == expectedMimeType
}
