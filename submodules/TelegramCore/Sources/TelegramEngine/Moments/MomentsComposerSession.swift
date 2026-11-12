import Foundation

/// What the composer is doing with media that is not on the post yet.
public enum MomentsComposerActivity: Equatable {
    case idle
    case recordingVoice
    case finishingVoice
    case uploadingMedia(count: Int)
}

public struct MomentsComposerPublishGate: Equatable {
    public var trimmedText: String
    public var completedMediaCount: Int
    public var activity: MomentsComposerActivity
    public var audienceChosen: Bool
    public var submitting: Bool
    /// A local file the post still needs is gone. Sending would drop that attachment.
    public var mediaBlocked: Bool

    public init(trimmedText: String, completedMediaCount: Int, activity: MomentsComposerActivity, audienceChosen: Bool, submitting: Bool, mediaBlocked: Bool = false) {
        self.trimmedText = trimmedText
        self.completedMediaCount = completedMediaCount
        self.activity = activity
        self.audienceChosen = audienceChosen
        self.submitting = submitting
        self.mediaBlocked = mediaBlocked
    }
}

public enum MomentsComposerPublishDenial: Equatable {
    case empty
    case audienceNotChosen
    case mediaNotReady
    case submitting
}

/// Upload and the tail of a voice recording close the send button, even when the text is already enough to post.
public func momentsComposerPublishDenial(_ gate: MomentsComposerPublishGate) -> MomentsComposerPublishDenial? {
    if gate.submitting {
        return .submitting
    }
    if gate.mediaBlocked || !momentsComposerActivityIsIdle(gate.activity) {
        return .mediaNotReady
    }
    if !gate.audienceChosen {
        return .audienceNotChosen
    }
    if gate.trimmedText.isEmpty && gate.completedMediaCount == 0 {
        return .empty
    }
    return nil
}

public func momentsComposerActivityIsIdle(_ activity: MomentsComposerActivity) -> Bool {
    if case .idle = activity {
        return true
    }
    return false
}

/// The wire payload that decides whether a retry is the same submission.
public struct MomentsPostFingerprint: Codable, Equatable {
    public var text: String
    public var mediaKeys: [String]
    public var audience: MomentsAudience
    public var allowNearby: Bool
    public var city: String?
    public var placeId: String?
    public var quoteOf: String?

    public init(text: String, mediaKeys: [String], audience: MomentsAudience, allowNearby: Bool, city: String? = nil, placeId: String? = nil, quoteOf: String? = nil) {
        self.text = text
        self.mediaKeys = mediaKeys
        self.audience = audience
        self.allowNearby = allowNearby
        self.city = city
        self.placeId = placeId
        self.quoteOf = quoteOf
    }
}

/// One submission keeps its nonce. A locked nonce stays put while uploads append keys. A different text, audience or quote mints a new one.
public func momentsClientNonceForSubmission(storedNonce: String?, storedFingerprint: MomentsPostFingerprint?, current: MomentsPostFingerprint, nonceLocked: Bool, make: () -> String = { UUID().uuidString }) -> String {
    if let storedNonce, momentsIsClientNonce(storedNonce), let storedFingerprint {
        if storedFingerprint == current || (nonceLocked && momentsSameSubmission(storedFingerprint, current)) {
            return storedNonce
        }
    }
    let minted = make()
    if momentsIsClientNonce(minted) {
        return minted
    }
    return UUID().uuidString
}

/// Text, audience and quote identify the submission. Media keys may grow while an upload finishes.
public func momentsSameSubmission(_ stored: MomentsPostFingerprint, _ current: MomentsPostFingerprint) -> Bool {
    if stored.text != current.text || stored.audience != current.audience || stored.allowNearby != current.allowNearby || stored.city != current.city || stored.placeId != current.placeId || stored.quoteOf != current.quoteOf {
        return false
    }
    if stored.mediaKeys == current.mediaKeys {
        return true
    }
    guard current.mediaKeys.count >= stored.mediaKeys.count else {
        return false
    }
    return Array(current.mediaKeys.prefix(stored.mediaKeys.count)) == stored.mediaKeys
}

public enum MomentsComposerLeaveSource: Equatable {
    case cancel
    case back
    case interactivePop
}

public enum MomentsComposerLeave: Equatable {
    case dismiss
    case confirm
}

public func momentsComposerIsDirty(text: String, mediaCount: Int, localMediaCount: Int, audienceChosen: Bool, quoteId: String?, activity: MomentsComposerActivity, hasPendingSend: Bool) -> Bool {
    if !text.isEmpty || mediaCount > 0 || localMediaCount > 0 || audienceChosen || hasPendingSend {
        return true
    }
    if let quoteId, !quoteId.isEmpty {
        return true
    }
    return !momentsComposerActivityIsIdle(activity)
}

/// Cancel, the back button and swipe-back ask the same question.
public func momentsComposerLeave(source: MomentsComposerLeaveSource, dirty: Bool) -> MomentsComposerLeave {
    switch source {
    case .cancel, .back, .interactivePop:
        return dirty ? .confirm : .dismiss
    }
}

/// An explicit quote wins. Otherwise the saved draft's quote is the one the composer reopens with.
public func momentsRestoredQuote(openedWith: String?, stored: String?) -> String? {
    if let openedWith {
        let trimmed = openedWith.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
    }
    if let stored {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
    }
    return nil
}

public enum MomentsPendingPostPhase: String, Codable, Equatable {
    case uploading
    case sending
    case failed
}

/// A send that has left the composer. `clientNonce` is the `client_nonce` field on `POST /v1/feed/posts`.
public struct MomentsPendingPost: Codable, Equatable {
    public var clientNonce: String
    public var fingerprint: MomentsPostFingerprint
    public var text: String
    public var audience: MomentsAudience
    public var media: [MomentsMedia]
    public var localMedia: [MomentsComposerLocalMedia]
    public var allowNearby: Bool
    public var city: String?
    public var placeId: String?
    public var quoteOf: String?
    public var phase: MomentsPendingPostPhase
    /// The person already tapped Post. An upload that has not been submitted is only restored into the draft.
    public var submitted: Bool
    /// Set once `POST /v1/feed/posts` has been attempted. Retries keep `clientNonce`.
    public var nonceLocked: Bool
    public var audienceToken: String?
    public var audienceTokenExpiresAt: Int64?
    public var audienceTokenKind: String?
    public var audienceTokenUserIds: [Int64]

    public init(clientNonce: String, fingerprint: MomentsPostFingerprint, text: String, audience: MomentsAudience, media: [MomentsMedia], localMedia: [MomentsComposerLocalMedia], allowNearby: Bool, city: String? = nil, placeId: String? = nil, quoteOf: String? = nil, phase: MomentsPendingPostPhase, submitted: Bool, nonceLocked: Bool = false, audienceToken: String? = nil, audienceTokenExpiresAt: Int64? = nil, audienceTokenKind: String? = nil, audienceTokenUserIds: [Int64] = []) {
        self.clientNonce = clientNonce
        self.fingerprint = fingerprint
        self.text = text
        self.audience = audience
        self.media = media
        self.localMedia = localMedia
        self.allowNearby = allowNearby
        self.city = city
        self.placeId = placeId
        self.quoteOf = quoteOf
        self.phase = phase
        self.submitted = submitted
        self.nonceLocked = nonceLocked
        self.audienceToken = audienceToken
        self.audienceTokenExpiresAt = audienceTokenExpiresAt
        self.audienceTokenKind = audienceTokenKind
        self.audienceTokenUserIds = audienceTokenUserIds
    }

    public func postDraft() -> MomentsPostDraft {
        return MomentsPostDraft(text: self.text, audience: self.audience, mediaKeys: self.media.sorted { $0.order < $1.order }.map(\.key).filter { !$0.isEmpty }, allowNearby: self.allowNearby, city: self.city, placeId: self.placeId, quoteOf: self.quoteOf, clientNonce: self.clientNonce)
    }
}

public enum MomentsPendingDisposition: Equatable {
    /// The request may already have reached the server. Wait for the person to retry with the same nonce.
    case offerRetry
    /// Local files are still on disk and the person has not tapped Post.
    case resumeUpload
    /// The person tapped Post and files are still on disk. Upload them, then send the same nonce.
    case resumeThenSend
    /// A file the post needs is gone. Do not send it without that attachment.
    case holdIncomplete
    case idle
}

public func momentsPendingDisposition(_ post: MomentsPendingPost, fileExists: (String) -> Bool) -> MomentsPendingDisposition {
    let locals = post.localMedia.filter { !$0.path.isEmpty }
    if locals.contains(where: { !fileExists($0.path) }) {
        return .holdIncomplete
    }
    if !locals.isEmpty {
        return post.submitted ? .resumeThenSend : .resumeUpload
    }
    if post.submitted {
        return .offerRetry
    }
    return .idle
}

/// A submitted task is the one a killed app has to offer. Otherwise the upload still in progress.
public func momentsSelectPendingPost(_ posts: [MomentsPendingPost]) -> MomentsPendingPost? {
    if let submitted = posts.last(where: { $0.submitted }) {
        return submitted
    }
    return posts.last
}

public func momentsPendingMediaDirectory(accountPath: String) -> String {
    return accountPath + "/moments-pending"
}

/// Copies one attachment into the account directory so a killed app can upload it again.
public func momentsCopyPendingFile(from sourcePath: String, accountPath: String, name: String) -> String? {
    let trimmed = sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, FileManager.default.fileExists(atPath: trimmed) else {
        return nil
    }
    let directory = momentsPendingMediaDirectory(accountPath: accountPath)
    do {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    } catch {
        return nil
    }
    let safeName = momentsPendingFileName(name)
    let destination = directory + "/" + safeName
    if destination == trimmed {
        return destination
    }
    if FileManager.default.fileExists(atPath: destination) {
        try? FileManager.default.removeItem(atPath: destination)
    }
    do {
        try FileManager.default.copyItem(atPath: trimmed, toPath: destination)
    } catch {
        return nil
    }
    return destination
}

public func momentsRemovePendingFiles(accountPath: String) {
    let directory = momentsPendingMediaDirectory(accountPath: accountPath)
    if FileManager.default.fileExists(atPath: directory) {
        try? FileManager.default.removeItem(atPath: directory)
    }
}

struct MomentsOutboxBlob: Codable, Equatable {
    var posts: [MomentsPendingPost]
}

/// `POST /v1/feed/posts` answers 200 with the original post. A repeated `client_nonce` returns that same post, not a second one.
public struct MomentsPublishReceipt: Equatable {
    public var id: String
    public var state: String
    public var version: Int64

    public init(id: String, state: String, version: Int64) {
        self.id = id
        self.state = state
        self.version = version
    }
}

public func momentsPublishReceipt(status: Int, json: [String: Any]) -> MomentsPublishReceipt? {
    guard status == 200, let id = momentsString(json, "id"), !id.isEmpty else {
        return nil
    }
    return MomentsPublishReceipt(id: id, state: momentsString(json, "state") ?? "", version: momentsInt64(json, "version"))
}

/// The nonce that just posted is no longer waiting. Any other task stays.
public func momentsOutboxAfterPosted(_ posts: [MomentsPendingPost], nonce: String) -> [MomentsPendingPost] {
    return posts.filter { $0.clientNonce != nonce }
}

/// The row the feed shows for a post the server accepted, including a replay of an earlier nonce.
public func momentsPostedCard(receipt: MomentsPublishReceipt, text: String, media: [MomentsMedia]) -> MomentsCard {
    let state = receipt.state.isEmpty ? "published" : receipt.state
    return MomentsCard(id: receipt.id, version: receipt.version, state: state, text: text, media: media)
}

/// A refresh that does not yet contain the post still shows it. Once the server page has that id, the server row wins.
public func momentsFeedWithPosted(items: [MomentsCard], posted: MomentsCard) -> [MomentsCard] {
    if items.contains(where: { $0.id == posted.id }) {
        return items
    }
    return [posted] + items
}

func momentsPendingFileName(_ name: String) -> String {
    let base = (name as NSString).lastPathComponent
    let filtered = base.unicodeScalars.filter { scalar in
        if CharacterSet.alphanumerics.contains(scalar) {
            return true
        }
        return scalar == "." || scalar == "-" || scalar == "_"
    }
    let built = String(String.UnicodeScalarView(filtered))
    if built.isEmpty || built == "." || built == ".." {
        return "file"
    }
    return built
}
