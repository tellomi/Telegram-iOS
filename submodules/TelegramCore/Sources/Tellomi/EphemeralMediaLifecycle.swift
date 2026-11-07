import Foundation

/// `viewOnceTimeout` in `SyncCore_AutoremoveTimeoutMessageAttribute`. A media timer of this
/// value is view-once. It is not a duration.
public let ephemeralViewOnceTimeout: Int32 = 0x7fffffff

/// One minute. A cloud timer above this, other than view-once, is the conversation TTL.
/// `Message.containsSecretMedia` uses the same bound.
public let ephemeralSecretMediaTimeoutBound: Int32 = 60

public enum EphemeralMediaShape: Equatable {
    case photo
    case video
    case voice
    case roundVideo
    case other
}

public enum EphemeralChatKind: Equatable {
    case cloud
    case secret
}

/// View-once, a short media timer, one-play voice or round video, the conversation TTL,
/// and a secret chat are stored differently. Secret chats keep every timer as
/// `AutoremoveTimeoutMessageAttribute`. A cloud chat stores a media timer as
/// `AutoclearTimeoutMessageAttribute` and the conversation TTL as `AutoremoveTimeoutMessageAttribute`.
public enum EphemeralMediaKind: Equatable {
    case viewOncePhotoOrVideo
    case viewOnceVoice
    case viewOnceRoundVideo
    case mediaSelfDestruct
    case conversationTtl
    case secretChat
}

public enum EphemeralSide: Equatable {
    case sender
    case recipient
}

public enum EphemeralReadReport: Equatable {
    /// No `messages.readMessageContents` / `channels.readMessageContents` and no secret-chat read.
    case none
    /// Queued as `SynchronizeConsumeMessageContents`. A user or group sends
    /// `messages.readMessageContents`. A channel sends `channels.readMessageContents`.
    case cloudReadMessageContents
    /// `SecretChatOutgoingOperationContents.readMessagesContent`. Not the cloud RPC.
    case secretReadMessagesContent
}

public struct EphemeralOpenEffect: Equatable {
    public var startsCountdown: Bool
    public var readReport: EphemeralReadReport
    /// The interactive consume keeps the original media. The placeholder is a later step.
    public var replacesMediaWithPlaceholder: Bool
    public var removesCacheBytes: Bool

    public init(startsCountdown: Bool, readReport: EphemeralReadReport, replacesMediaWithPlaceholder: Bool, removesCacheBytes: Bool) {
        self.startsCountdown = startsCountdown
        self.readReport = readReport
        self.replacesMediaWithPlaceholder = replacesMediaWithPlaceholder
        self.removesCacheBytes = removesCacheBytes
    }
}

/// What the local timer does when it fires. Server access is not decided here.
public struct EphemeralExpiryEffect: Equatable {
    public var keepsMessageRow: Bool
    public var showsExpiredPlaceholder: Bool
    public var removesMessageRow: Bool
    /// `mediaBox.removeCachedResources`. Thumbnails are `previewRepresentations` and image
    /// representations. The video or audio bytes are `file.resource`.
    public var removesCacheBytes: Bool
    /// This path does not call `readMessageContents` and does not revoke a file id.
    public var invalidatesServerAccess: Bool

    public init(keepsMessageRow: Bool, showsExpiredPlaceholder: Bool, removesMessageRow: Bool, removesCacheBytes: Bool, invalidatesServerAccess: Bool) {
        self.keepsMessageRow = keepsMessageRow
        self.showsExpiredPlaceholder = showsExpiredPlaceholder
        self.removesMessageRow = removesMessageRow
        self.removesCacheBytes = removesCacheBytes
        self.invalidatesServerAccess = invalidatesServerAccess
    }
}

/// A holder that still has the resource id after the message stopped naming it.
public struct EphemeralStaleReference: Equatable {
    public var messageStillNamesResource: Bool
    public var cacheMayStillHoldBytes: Bool
    /// The expiry and consume paths do not mark the id invalid, so a normal fetch still
    /// reads the cache and, on a miss, asks the server.
    public var clientMarksResourceInvalid: Bool

    public init(messageStillNamesResource: Bool, cacheMayStillHoldBytes: Bool, clientMarksResourceInvalid: Bool) {
        self.messageStillNamesResource = messageStillNamesResource
        self.cacheMayStillHoldBytes = cacheMayStillHoldBytes
        self.clientMarksResourceInvalid = clientMarksResourceInvalid
    }
}

public func ephemeralMediaKind(chat: EphemeralChatKind, timeout: Int32, shape: EphemeralMediaShape) -> EphemeralMediaKind {
    if chat == .secret {
        return .secretChat
    }
    if timeout == ephemeralViewOnceTimeout {
        switch shape {
        case .voice:
            return .viewOnceVoice
        case .roundVideo:
            return .viewOnceRoundVideo
        case .photo, .video, .other:
            return .viewOncePhotoOrVideo
        }
    }
    if timeout > ephemeralSecretMediaTimeoutBound {
        return .conversationTtl
    }
    return .mediaSelfDestruct
}

/// `Message.containsSecretMedia`: view-once and a timer of at most one minute, and only for an
/// image or a video, animation, voice, or music file. Conversation TTL is not secret media.
public func ephemeralCountsAsSecretMedia(chat: EphemeralChatKind, timeout: Int32, shape: EphemeralMediaShape) -> Bool {
    if chat == .secret {
        return true
    }
    if timeout > ephemeralSecretMediaTimeoutBound && timeout != ephemeralViewOnceTimeout {
        return false
    }
    switch shape {
    case .photo, .video, .voice, .roundVideo:
        return true
    case .other:
        return false
    }
}

/// Interactive consume extends an `AutoremoveTimeout` by the media duration. An `AutoclearTimeout`
/// is extended the same way except view-once, which stays the sentinel.
public func ephemeralCountdownTimeout(storedTimeout: Int32, mediaDuration: Int32?, attributeIsAutoclear: Bool) -> Int32 {
    if attributeIsAutoclear && storedTimeout == ephemeralViewOnceTimeout {
        return storedTimeout
    }
    guard let mediaDuration else {
        return storedTimeout
    }
    return max(storedTimeout, mediaDuration)
}

/// View-once schedules tag 1 at the countdown begin time, so the placeholder is due immediately.
/// Any other autoclear or autoremove timer is due at begin + timeout.
public func ephemeralDueTimestamp(timeout: Int32, countdownBegin: Int32) -> Int32 {
    if timeout == ephemeralViewOnceTimeout {
        return countdownBegin
    }
    let (sum, overflow) = countdownBegin.addingReportingOverflow(timeout)
    return overflow ? Int32.max : sum
}

/// Opening or starting playback. Recipient only. The gallery calls this when a secret photo or
/// video preview is ready. The playlist calls it when voice or round-video playback starts.
/// The sender's copy does not enter this function: the implementation returns unless the message
/// is incoming.
public func ephemeralOpenEffect(kind: EphemeralMediaKind, side: EphemeralSide, countdownAlreadyStarted: Bool) -> EphemeralOpenEffect {
    guard side == .recipient, !countdownAlreadyStarted else {
        return EphemeralOpenEffect(startsCountdown: false, readReport: .none, replacesMediaWithPlaceholder: false, removesCacheBytes: false)
    }
    switch kind {
    case .viewOncePhotoOrVideo, .viewOnceVoice, .viewOnceRoundVideo, .mediaSelfDestruct:
        return EphemeralOpenEffect(startsCountdown: true, readReport: .cloudReadMessageContents, replacesMediaWithPlaceholder: false, removesCacheBytes: false)
    case .secretChat:
        return EphemeralOpenEffect(startsCountdown: true, readReport: .secretReadMessagesContent, replacesMediaWithPlaceholder: false, removesCacheBytes: false)
    case .conversationTtl:
        // A nil begin time is filled in. Incoming cloud messages already store the message date,
        // so opening one does not start it again. This does not report `readMessageContents`
        // and does not hide the media.
        return EphemeralOpenEffect(startsCountdown: true, readReport: .none, replacesMediaWithPlaceholder: false, removesCacheBytes: false)
    }
}

/// Local timer. Cloud autoclear (view-once and media TTL) swaps in `TelegramMediaExpiredContent`
/// and leaves the cache. Cloud autoremove deletes the row and leaves the cache. A secret chat
/// deletes the row and force-removes the cache. None of these call `readMessageContents`.
public func ephemeralExpiryEffect(kind: EphemeralMediaKind) -> EphemeralExpiryEffect {
    switch kind {
    case .viewOncePhotoOrVideo, .viewOnceVoice, .viewOnceRoundVideo, .mediaSelfDestruct:
        return EphemeralExpiryEffect(keepsMessageRow: true, showsExpiredPlaceholder: true, removesMessageRow: false, removesCacheBytes: false, invalidatesServerAccess: false)
    case .conversationTtl:
        return EphemeralExpiryEffect(keepsMessageRow: false, showsExpiredPlaceholder: false, removesMessageRow: true, removesCacheBytes: false, invalidatesServerAccess: false)
    case .secretChat:
        return EphemeralExpiryEffect(keepsMessageRow: false, showsExpiredPlaceholder: false, removesMessageRow: true, removesCacheBytes: true, invalidatesServerAccess: false)
    }
}

/// Another device, or this device after reconnect, applies a remote consume. View-once replaces
/// the media immediately. A media timer replaces it only once the local clock is past the due
/// time. A secret chat starts the countdown and does not insert the placeholder here. The cache
/// is not removed. `readMessageContents` was the other device's report; this apply does not send one.
public func ephemeralRemoteConsumeReplacesMedia(kind: EphemeralMediaKind, timeout: Int32, now: Int32, countdownBegin: Int32) -> Bool {
    switch kind {
    case .viewOncePhotoOrVideo, .viewOnceVoice, .viewOnceRoundVideo:
        return true
    case .mediaSelfDestruct:
        return now >= ephemeralDueTimestamp(timeout: timeout, countdownBegin: countdownBegin)
    case .conversationTtl, .secretChat:
        return false
    }
}

/// `synchronizeConsumeMessageContents` catches an RPC error and completes. The worker then
/// removes the operation log entry. A failed cloud report is not retried. A request that the
/// network layer has not finished is still in that layer; this function does not keep its own copy.
public func ephemeralCloudReadReportRetriedAfterError() -> Bool {
    return false
}

public func ephemeralStaleReference(after effect: EphemeralExpiryEffect) -> EphemeralStaleReference {
    return EphemeralStaleReference(
        messageStillNamesResource: false,
        cacheMayStillHoldBytes: !effect.removesCacheBytes,
        clientMarksResourceInvalid: false
    )
}
