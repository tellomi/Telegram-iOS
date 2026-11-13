import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi

/// Wires ADR-0083 B2 into a plaintext `upload.getFile` download.
///
/// The media box calls `beforeCompleteCommit` when a partial file is about to
/// become the finished file. This asks `upload.getFileHashes#9156982a`
/// (`location:InputFileLocation`, `offset:long`) and compares 128 KiB SHA-256
/// parts. A match links the file. A mismatched part, or a confirmed end shorter
/// than the file, deletes the partial and fails the download. An empty vector,
/// an RPC error, or no answer within `tellomiFileHashFailOpenSeconds` links the
/// file anyway.
///
/// CDN, web files, legacy `inputFileLocation`, secret-chat decryption, and a
/// download that never fills the file (preload, prefix, already on disk) do not
/// send the RPC. Local cache encryption is not used on iOS. `messages.getDocumentByHash`
/// is unchanged.

private let tellomiFileHashWatchLock = NSLock()
private var tellomiFileHashWatches: [String: [TellomiFileHashWatch]] = [:]

private final class TellomiFileHashWatch {
    weak var mediaBox: MediaBox?
    let resourceKey: String
    let postbox: Postbox
    let network: Network
    let datacenterId: Int
    let resolveLocation: (Data?) -> Api.InputFileLocation?
    let fileReference: Data?

    private let lock = NSLock()
    private var location: Api.InputFileLocation?
    private var cdn = false
    private var legacy = false
    private var checking = false
    private var retired = false

    init(mediaBox: MediaBox, resourceKey: String, postbox: Postbox, network: Network, datacenterId: Int, fileReference: Data?, resolveLocation: @escaping (Data?) -> Api.InputFileLocation?) {
        self.mediaBox = mediaBox
        self.resourceKey = resourceKey
        self.postbox = postbox
        self.network = network
        self.datacenterId = datacenterId
        self.fileReference = fileReference
        self.resolveLocation = resolveLocation
    }

    func noteLocation(_ location: Api.InputFileLocation) {
        self.lock.lock()
        self.location = location
        if case .inputFileLocation = location {
            self.legacy = true
        }
        self.lock.unlock()
    }

    func noteTransport(cdn: Bool) {
        self.lock.lock()
        self.cdn = cdn
        self.lock.unlock()
    }

    /// Snapshot for the commit hook. Sets `checking` so disposing the fetch does not drop the watch.
    func beginCommit() -> TellomiFileHashCommitPlan {
        self.lock.lock()
        if self.location == nil, let resolved = self.resolveLocation(self.fileReference) {
            self.location = resolved
            if case .inputFileLocation = resolved {
                self.legacy = true
            }
        }
        let location = self.location
        let cdn = self.cdn
        let legacy = self.legacy
        let retired = self.retired
        if !retired {
            self.checking = true
        }
        self.lock.unlock()
        if retired || cdn || legacy {
            return .skip
        }
        guard let location, tellomiFileHashLocationIsSupported(location) else {
            return .skip
        }
        return .verify(location: location, network: self.network, postbox: self.postbox, datacenterId: self.datacenterId)
    }

    func cancelIfIdle() {
        self.lock.lock()
        let drop = !self.checking
        if drop {
            self.retired = true
        }
        self.lock.unlock()
        if drop {
            tellomiFileHashRemove(self)
        }
    }

    func finish() {
        self.lock.lock()
        self.retired = true
        self.checking = false
        self.lock.unlock()
        tellomiFileHashRemove(self)
    }
}

private enum TellomiFileHashCommitPlan {
    case skip
    case verify(location: Api.InputFileLocation, network: Network, postbox: Postbox, datacenterId: Int)
}

func tellomiFileHashLocationIsSupported(_ location: Api.InputFileLocation) -> Bool {
    if case .inputFileLocation = location {
        return false
    }
    return true
}

/// Secret-chat decryption and web files are not plaintext `upload.getFile` results.
/// Local cache encryption is not used on iOS; callers pass `cacheEncrypted: false`.
func tellomiFileHashShouldObserve(webFile: Bool, secretEncrypted: Bool, cacheEncrypted: Bool) -> Bool {
    if webFile || secretEncrypted || cacheEncrypted {
        return false
    }
    return true
}

private func tellomiFileHashRemove(_ watch: TellomiFileHashWatch) {
    tellomiFileHashWatchLock.lock()
    var list = tellomiFileHashWatches[watch.resourceKey] ?? []
    list.removeAll { $0 === watch }
    if list.isEmpty {
        tellomiFileHashWatches.removeValue(forKey: watch.resourceKey)
    } else {
        tellomiFileHashWatches[watch.resourceKey] = list
    }
    tellomiFileHashWatchLock.unlock()
}

private func tellomiFileHashWatch(mediaBox: MediaBox, resourceKey: String) -> TellomiFileHashWatch? {
    tellomiFileHashWatchLock.lock()
    let list = tellomiFileHashWatches[resourceKey] ?? []
    let match = list.last(where: { $0.mediaBox === mediaBox })
    tellomiFileHashWatchLock.unlock()
    return match
}

func tellomiFileHashNoteLocation(resourceKey: String, location: Api.InputFileLocation) {
    tellomiFileHashWatchLock.lock()
    let list = tellomiFileHashWatches[resourceKey] ?? []
    tellomiFileHashWatchLock.unlock()
    for watch in list {
        watch.noteLocation(location)
    }
}

func tellomiFileHashNoteTransport(resourceKey: String, cdn: Bool) {
    tellomiFileHashWatchLock.lock()
    let list = tellomiFileHashWatches[resourceKey] ?? []
    tellomiFileHashWatchLock.unlock()
    for watch in list {
        watch.noteTransport(cdn: cdn)
    }
}

private func tellomiInstallFileHashHook(on mediaBox: MediaBox) {
    mediaBox.beforeCompleteCommit = { [weak mediaBox] resourceKey, partialPath, byteCount, decision in
        guard let mediaBox else {
            return false
        }
        return tellomiFileHashBeforeCommit(mediaBox: mediaBox, resourceKey: resourceKey, partialPath: partialPath, byteCount: byteCount, decision: decision)
    }
}

/// Observes one plaintext download. `nil` when this download must not send the RPC.
func tellomiObservePlaintextDownload(mediaBox: MediaBox, postbox: Postbox, network: Network, resource: MediaResource, datacenterId: Int, fileReference: Data?, webFile: Bool, secretEncrypted: Bool) -> Disposable? {
    if !tellomiFileHashShouldObserve(webFile: webFile, secretEncrypted: secretEncrypted, cacheEncrypted: false) {
        return nil
    }
    tellomiInstallFileHashHook(on: mediaBox)
    let resourceKey = resource.id.stringRepresentation
    let resolveLocation: (Data?) -> Api.InputFileLocation? = { reference in
        guard let cloud = resource as? TelegramCloudMediaResource else {
            return nil
        }
        return cloud.apiInputLocation(fileReference: reference)
    }
    let watch = TellomiFileHashWatch(mediaBox: mediaBox, resourceKey: resourceKey, postbox: postbox, network: network, datacenterId: datacenterId, fileReference: fileReference, resolveLocation: resolveLocation)
    tellomiFileHashWatchLock.lock()
    var list = tellomiFileHashWatches[resourceKey] ?? []
    list.append(watch)
    tellomiFileHashWatches[resourceKey] = list
    tellomiFileHashWatchLock.unlock()
    return ActionDisposable { [weak watch] in
        watch?.cancelIfIdle()
    }
}

func tellomiGatePlaintextFileDownload(mediaBox: MediaBox, postbox: Postbox, network: Network, resource: MediaResource, datacenterId: Int, parameters: MediaResourceFetchParameters?, webFile: Bool, secretEncrypted: Bool, fetch: Signal<MediaResourceDataFetchResult, MediaResourceDataFetchError>) -> Signal<MediaResourceDataFetchResult, MediaResourceDataFetchError> {
    let fileReference = (parameters?.info as? TelegramCloudMediaResourceFetchInfo)?.reference.apiFileReference
    return Signal { subscriber in
        let observation = tellomiObservePlaintextDownload(mediaBox: mediaBox, postbox: postbox, network: network, resource: resource, datacenterId: datacenterId, fileReference: fileReference, webFile: webFile, secretEncrypted: secretEncrypted)
        let disposable = fetch.start(next: { next in
            subscriber.putNext(next)
        }, error: { error in
            subscriber.putError(error)
        }, completed: {
            subscriber.putCompletion()
        })
        return ActionDisposable {
            observation?.dispose()
            disposable.dispose()
        }
    }
}

private func tellomiFileHashBeforeCommit(mediaBox: MediaBox, resourceKey: String, partialPath: String, byteCount: Int64, decision: @escaping (Bool) -> Void) -> Bool {
    guard let watch = tellomiFileHashWatch(mediaBox: mediaBox, resourceKey: resourceKey) else {
        return false
    }
    switch watch.beginCommit() {
    case .skip:
        watch.finish()
        return false
    case let .verify(location, network, postbox, datacenterId):
        if let override = tellomiGetFileHashesEnabledOverride, !override {
            Logger.shared.log("TellomiFileHashes", "kill switch off")
            watch.finish()
            return false
        }
        let holder = TellomiFileHashCheckHolder(network: network, postbox: postbox, datacenterId: datacenterId, location: location, partialPath: partialPath, fileSize: byteCount, decision: { allow in
            watch.finish()
            decision(allow)
        })
        holder.start()
        return true
    }
}

private enum TellomiFileHashPageError: Error {
    case rpc
}

private func tellomiRequestFileHashPage(network: Network, datacenterId: Int, location: Api.InputFileLocation, offset: Int64) -> Signal<[TellomiFileHashPart], TellomiFileHashPageError> {
    return network.download(datacenterId: datacenterId, isMedia: true, tag: nil)
    |> mapToSignalPromotingError { download -> Signal<[TellomiFileHashPart], TellomiFileHashPageError> in
        return download.requestWithAdditionalData(
            Api.functions.upload.getFileHashes(location: location, offset: offset),
            automaticFloodWait: false,
            failOnServerErrors: true
        )
        |> map { hashes, _ -> [TellomiFileHashPart] in
            return hashes.map { hash -> TellomiFileHashPart in
                switch hash {
                case let .fileHash(data):
                    return TellomiFileHashPart(offset: data.offset, limit: Int(data.limit), hash: data.hash.makeData())
                }
            }
        }
        |> mapError { _ -> TellomiFileHashPageError in
            return .rpc
        }
    }
}

/// Keeps the config read and the hash RPC alive until one decision is delivered.
private final class TellomiFileHashCheckHolder {
    private let network: Network
    private let postbox: Postbox
    private let datacenterId: Int
    private let location: Api.InputFileLocation
    private let partialPath: String
    private let fileSize: Int64
    private let decision: (Bool) -> Void
    private let configDisposable = MetaDisposable()
    private let pageDisposable = MetaDisposable()
    private let lock = NSLock()
    private var session = TellomiFileHashSession()
    private var decided = false
    private var hashing = false
    private var retained: TellomiFileHashCheckHolder?

    init(network: Network, postbox: Postbox, datacenterId: Int, location: Api.InputFileLocation, partialPath: String, fileSize: Int64, decision: @escaping (Bool) -> Void) {
        self.network = network
        self.postbox = postbox
        self.datacenterId = datacenterId
        self.location = location
        self.partialPath = partialPath
        self.fileSize = fileSize
        self.decision = decision
    }

    func start() {
        if self.fileSize <= 0 {
            self.decision(true)
            return
        }
        self.retained = self
        Queue.concurrentDefaultQueue().after(tellomiFileHashFailOpenSeconds) { [weak self] in
            self?.timeout()
        }
        let enabled = self.postbox.transaction { transaction -> Bool in
            return tellomiGetFileHashesEnabled(configuration: currentAppConfiguration(transaction: transaction))
        }
        self.configDisposable.set((enabled |> take(1)).start(next: { [weak self] enabled in
            guard let self else {
                return
            }
            if !enabled {
                Logger.shared.log("TellomiFileHashes", "kill switch off")
                self.complete(allow: true)
                return
            }
            self.lock.lock()
            if self.decided {
                self.lock.unlock()
                return
            }
            let offset = self.session.open()
            self.lock.unlock()
            self.request(offset: offset)
        }))
    }

    private func timeout() {
        self.lock.lock()
        if self.decided || self.hashing {
            self.lock.unlock()
            return
        }
        self.session.stop()
        self.lock.unlock()
        Logger.shared.log("TellomiFileHashes", "fail-open timeout")
        self.complete(allow: true)
    }

    private func request(offset: Int64) {
        self.lock.lock()
        if self.decided {
            self.lock.unlock()
            return
        }
        self.lock.unlock()
        let signal = tellomiRequestFileHashPage(network: self.network, datacenterId: self.datacenterId, location: self.location, offset: offset)
        self.pageDisposable.set(signal.start(next: { [weak self] page in
            self?.accept(page: page)
        }, error: { [weak self] _ in
            self?.fail(reason: "rpc")
        }))
    }

    private func accept(page: [TellomiFileHashPart]) {
        self.lock.lock()
        if self.decided {
            self.lock.unlock()
            return
        }
        let next = self.session.accept(fileSize: self.fileSize, page: page)
        if next >= 0 {
            self.lock.unlock()
            self.request(offset: next)
            return
        }
        let parts = self.session.parts
        let confirmedEnd = self.session.confirmedEnd
        let hasParts = self.session.hasParts
        self.hashing = true
        self.lock.unlock()
        if !hasParts {
            Logger.shared.log("TellomiFileHashes", "fail-open miss")
            self.complete(allow: true)
            return
        }
        let path = self.partialPath
        let fileSize = self.fileSize
        Queue.concurrentDefaultQueue().async { [weak self] in
            let verdict = tellomiFileHashCheck(path: path, fileSize: fileSize, parts: parts, confirmedEnd: confirmedEnd)
            self?.apply(verdict)
        }
    }

    private func apply(_ verdict: TellomiFileHashVerdict) {
        switch verdict {
        case .match:
            Logger.shared.log("TellomiFileHashes", "ok")
            self.complete(allow: true)
        case .failOpen:
            Logger.shared.log("TellomiFileHashes", "fail-open check")
            self.complete(allow: true)
        case .mismatch:
            Logger.shared.log("TellomiFileHashes", "mismatch")
            self.complete(allow: false)
        }
    }

    private func fail(reason: String) {
        self.lock.lock()
        if self.decided || self.hashing {
            self.lock.unlock()
            return
        }
        self.session.stop()
        self.lock.unlock()
        Logger.shared.log("TellomiFileHashes", "fail-open \(reason)")
        self.complete(allow: true)
    }

    private func complete(allow: Bool) {
        self.lock.lock()
        if self.decided {
            self.lock.unlock()
            return
        }
        self.decided = true
        self.lock.unlock()
        self.configDisposable.dispose()
        self.pageDisposable.dispose()
        let decision = self.decision
        self.retained = nil
        decision(allow)
    }
}
