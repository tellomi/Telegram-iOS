import Foundation
import CryptoKit
import Postbox
import SwiftSignalKit
internal import TelegramApi
import MtProtoKit

func tellomiDocumentByHashTraits(mimeType: String, attributes: [TelegramMediaFileAttribute], encrypted: Bool) -> TellomiDocumentByHashTraits {
    var fileName: String?
    var isAnimated = false
    var isSticker = false
    var isCustomEmoji = false
    var isVoice = false
    var hasNonVoiceAudio = false
    var isVideo = false
    var isInstantVideo = false
    for attribute in attributes {
        switch attribute {
        case let .FileName(name):
            fileName = name
        case .Animated:
            isAnimated = true
        case .Sticker:
            isSticker = true
        case .CustomEmoji:
            isCustomEmoji = true
        case .Audio(true, _, _, _, _):
            isVoice = true
        case .Audio(false, _, _, _, _):
            hasNonVoiceAudio = true
        case .Video(_, _, let flags, _, _, _):
            isVideo = true
            if flags.contains(.instantRoundVideo) {
                isInstantVideo = true
            }
        default:
            break
        }
    }
    return TellomiDocumentByHashTraits(
        mimeType: mimeType,
        encrypted: encrypted,
        isAnimated: isAnimated,
        isAnimatedSticker: fileName != nil && mimeType == "application/x-tgsticker",
        isVideoSticker: mimeType == "video/webm" && (isSticker || isCustomEmoji),
        isSticker: isSticker,
        isCustomEmoji: isCustomEmoji,
        isVoice: isVoice,
        isMusic: hasNonVoiceAudio && !isVideo,
        isVideo: isVideo,
        isInstantVideo: isInstantVideo
    )
}

func tellomiDocumentByHashTraits(file: TelegramMediaFile, encrypted: Bool) -> TellomiDocumentByHashTraits {
    return TellomiDocumentByHashTraits(
        mimeType: file.mimeType,
        encrypted: encrypted,
        isAnimated: file.isAnimated,
        isAnimatedSticker: file.isAnimatedSticker,
        isVideoSticker: file.isVideoSticker,
        isSticker: file.isSticker,
        isCustomEmoji: file.isCustomEmoji,
        isVoice: file.isVoice,
        isMusic: file.isMusic,
        isVideo: file.isVideo,
        isInstantVideo: file.isInstantVideo
    )
}

func tellomiSha256(data: Data) -> Data {
    return Data(SHA256.hash(data: data))
}

/// SHA-256 of the file at `path` when its length is exactly `expectedSize`.
/// Any short read or size mismatch returns nil so the caller uploads the bytes.
func tellomiSha256File(path: String, expectedSize: Int64) -> Data? {
    guard expectedSize > 0, let endOffset = UInt64(exactly: expectedSize) else {
        return nil
    }
    guard let handle = FileHandle(forReadingAtPath: path) else {
        return nil
    }
    defer {
        try? handle.close()
    }
    do {
        let end = try handle.seekToEnd()
        guard end == endOffset else {
            return nil
        }
        try handle.seek(toOffset: 0)
        var hasher = SHA256()
        var remaining = expectedSize
        while remaining > 0 {
            let count = Int(min(remaining, 1024 * 1024))
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else {
                return nil
            }
            hasher.update(data: chunk)
            remaining -= Int64(chunk.count)
        }
        return Data(hasher.finalize())
    } catch {
        return nil
    }
}

func tellomiReusableDocument(_ document: Api.Document, expectedSize: Int64, expectedMimeType: String) -> Api.Document? {
    switch document {
    case let .document(data):
        guard tellomiDocumentByHashIsReusable(id: data.id, dcId: data.dcId, size: data.size, mimeType: data.mimeType, expectedSize: expectedSize, expectedMimeType: expectedMimeType) else {
            return nil
        }
        return document
    case .documentEmpty:
        return nil
    }
}

func tellomiInputDocument(from document: Api.Document) -> Api.InputDocument? {
    guard case let .document(data) = document else {
        return nil
    }
    return .inputDocument(.init(id: data.id, accessHash: data.accessHash, fileReference: data.fileReference))
}

func tellomiLookupExistingDocument(network: Network, postbox: Postbox, resource: MediaResource, declaredSize: Int64?, mimeType: String, attributes: [TelegramMediaFileAttribute], encrypted: Bool) -> Signal<Api.Document?, NoError> {
    let traits = tellomiDocumentByHashTraits(mimeType: mimeType, attributes: attributes, encrypted: encrypted)
    guard case let .lookup(role) = tellomiDocumentByHashDecision(traits) else {
        return .single(nil)
    }
    if let declaredSize, !tellomiDocumentByHashSizeIsEligible(role: role, size: declaredSize) {
        return .single(nil)
    }
    return postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false), attemptSynchronously: true)
    |> take(1)
    |> mapToSignal { data -> Signal<Api.Document?, NoError> in
        guard data.complete else {
            return .single(nil)
        }
        if let declaredSize, declaredSize != data.size {
            return .single(nil)
        }
        guard tellomiDocumentByHashSizeIsEligible(role: role, size: data.size) else {
            return .single(nil)
        }
        let path = data.path
        let size = data.size
        return tellomiSha256Signal(path: path, expectedSize: size)
        |> mapToSignal { digest -> Signal<Api.Document?, NoError> in
            guard let digest else {
                return .single(nil)
            }
            return tellomiRequestDocumentByHash(network: network, sha256: digest, size: size, mimeType: mimeType)
        }
    }
}

func tellomiLookupExistingDocument(network: Network, data: Data, mimeType: String, attributes: [TelegramMediaFileAttribute], encrypted: Bool) -> Signal<Api.Document?, NoError> {
    let traits = tellomiDocumentByHashTraits(mimeType: mimeType, attributes: attributes, encrypted: encrypted)
    guard case let .lookup(role) = tellomiDocumentByHashDecision(traits) else {
        return .single(nil)
    }
    let size = Int64(data.count)
    guard tellomiDocumentByHashSizeIsEligible(role: role, size: size) else {
        return .single(nil)
    }
    return Signal { subscriber in
        subscriber.putNext(tellomiSha256(data: data))
        subscriber.putCompletion()
        return EmptyDisposable
    }
    |> runOn(Queue.concurrentDefaultQueue())
    |> mapToSignal { digest -> Signal<Api.Document?, NoError> in
        return tellomiRequestDocumentByHash(network: network, sha256: digest, size: size, mimeType: mimeType)
    }
}

func tellomiLookupExistingDocument(network: Network, postbox: Postbox, source: MultipartUploadSource, mimeType: String, attributes: [TelegramMediaFileAttribute], encrypted: Bool) -> Signal<Api.Document?, NoError> {
    switch source {
    case let .resource(reference):
        return tellomiLookupExistingDocument(network: network, postbox: postbox, resource: reference.resource, declaredSize: nil, mimeType: mimeType, attributes: attributes, encrypted: encrypted)
    case let .data(data):
        return tellomiLookupExistingDocument(network: network, data: data, mimeType: mimeType, attributes: attributes, encrypted: encrypted)
    case let .tempFile(file):
        guard let size = tellomiFileByteCount(path: file.path) else {
            return .single(nil)
        }
        let traits = tellomiDocumentByHashTraits(mimeType: mimeType, attributes: attributes, encrypted: encrypted)
        guard case let .lookup(role) = tellomiDocumentByHashDecision(traits), tellomiDocumentByHashSizeIsEligible(role: role, size: size) else {
            return .single(nil)
        }
        return tellomiSha256Signal(path: file.path, expectedSize: size)
        |> mapToSignal { digest -> Signal<Api.Document?, NoError> in
            guard let digest else {
                return .single(nil)
            }
            return tellomiRequestDocumentByHash(network: network, sha256: digest, size: size, mimeType: mimeType)
        }
    case .custom:
        return .single(nil)
    }
}

func tellomiStoreReusedDocumentData(postbox: Postbox, source: MultipartUploadSource, cloud: TelegramMediaFile) {
    switch source {
    case let .resource(reference):
        postbox.mediaBox.copyResourceData(from: reference.resource.id, to: cloud.resource.id, synchronous: true)
    case let .data(data):
        postbox.mediaBox.storeResourceData(cloud.resource.id, data: data, synchronous: true)
    case let .tempFile(file):
        postbox.mediaBox.copyResourceData(cloud.resource.id, fromTempPath: file.path)
    case .custom:
        break
    }
}

private func tellomiFileByteCount(path: String) -> Int64? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path), let number = attributes[.size] as? NSNumber else {
        return nil
    }
    let size = number.int64Value
    if size <= 0 {
        return nil
    }
    return size
}

private func tellomiSha256Signal(path: String, expectedSize: Int64) -> Signal<Data?, NoError> {
    return Signal { subscriber in
        subscriber.putNext(tellomiSha256File(path: path, expectedSize: expectedSize))
        subscriber.putCompletion()
        return EmptyDisposable
    }
    |> runOn(Queue.concurrentDefaultQueue())
}

private func tellomiRequestDocumentByHash(network: Network, sha256: Data, size: Int64, mimeType: String) -> Signal<Api.Document?, NoError> {
    guard sha256.count == 32, size > 0, !mimeType.isEmpty else {
        return .single(nil)
    }
    return network.request(Api.functions.messages.getDocumentByHash(sha256: Buffer(data: sha256), size: size, mimeType: mimeType))
    |> map { document -> Api.Document? in
        let reusable = tellomiReusableDocument(document, expectedSize: size, expectedMimeType: mimeType)
        if reusable != nil {
            Logger.shared.log("TellomiDocumentByHash", "hit size=\(size) mime=\(mimeType)")
        } else {
            Logger.shared.log("TellomiDocumentByHash", "miss size=\(size) mime=\(mimeType)")
        }
        return reusable
    }
    |> `catch` { error -> Signal<Api.Document?, NoError> in
        Logger.shared.log("TellomiDocumentByHash", "fail-open \(error.errorDescription)")
        return .single(nil)
    }
}
