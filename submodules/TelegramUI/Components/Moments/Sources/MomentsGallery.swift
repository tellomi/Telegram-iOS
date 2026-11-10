import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import Postbox

func momentsPresentGallery(context: AccountContext, card: MomentsCard, index: Int, controller: ViewController) {
    let slides = card.media.filter { momentsPresentsAsImage($0.type) || momentsPresentsAsVideo($0.type) }
    let peerId = context.account.peerId
    var messages: [EngineRawMessage] = []
    for (offset, media) in slides.enumerated() {
        // Gallery plays the original file. A relative key is joined onto the public media host.
        let url: String?
        if momentsPresentsAsVideo(media.type) {
            url = media.remoteURL.flatMap { $0.hasPrefix("https://") ? $0 : nil } ?? momentsMediaURL(base: momentsPublicMediaBaseURL, key: media.key)
        } else {
            url = momentsFeedImageURL(media, targetPixels: momentsSingleImagePixels) ?? momentsMediaURL(base: momentsPublicMediaBaseURL, key: media.key)
        }
        guard let url, url.hasPrefix("https://") else {
            continue
        }
        let attached: Media
        if momentsPresentsAsVideo(media.type) {
            attached = momentsGalleryFile(url: url, media: media)
        } else {
            attached = momentsGalleryImage(url: url, media: media, id: Int64(offset + 1))
        }
        let messageId = EngineMessage.Id(peerId: peerId, namespace: Namespaces.Message.Local, id: Int32(offset + 1))
        messages.append(EngineRawMessage(
            stableId: UInt32(offset + 1),
            stableVersion: 0,
            id: messageId,
            globallyUniqueId: nil,
            groupingKey: nil,
            groupInfo: nil,
            threadId: nil,
            timestamp: 0,
            flags: [],
            tags: [],
            globalTags: [],
            localTags: [],
            customTags: [],
            forwardInfo: nil,
            author: nil,
            text: "",
            attributes: [],
            media: [attached],
            peers: EngineSimpleDictionary(),
            associatedMessages: EngineSimpleDictionary(),
            associatedMessageIds: [],
            associatedMedia: [:],
            associatedThreadInfo: nil,
            associatedStories: [:]
        ))
    }
    guard !messages.isEmpty else {
        return
    }
    let tapped = min(max(0, index), messages.count - 1)
    let source: GalleryControllerItemSource = .custom(
        messages: .single((messages, Int32(tapped), false)),
        messageId: messages[tapped].id,
        loadMore: nil
    )
    let gallery = context.sharedContext.makeGalleryController(context: context, source: source, streamSingleVideo: true, isPreview: false)
    (controller.navigationController as? NavigationController)?.pushViewController(gallery)
}

private func momentsGalleryImage(url: String, media: MomentsMedia, id: Int64) -> TelegramMediaImage {
    let width = Int32(max(media.width, 1))
    let height = Int32(max(media.height, 1))
    let resource = HttpReferenceMediaResource(url: url, size: nil)
    let representation = TelegramMediaImageRepresentation(
        dimensions: PixelDimensions(width: width, height: height),
        resource: resource,
        progressiveSizes: [],
        immediateThumbnailData: nil,
        hasVideo: false,
        isPersonal: false
    )
    return TelegramMediaImage(
        imageId: EngineMedia.Id(namespace: Namespaces.Media.LocalImage, id: id),
        representations: [representation],
        immediateThumbnailData: nil,
        reference: nil,
        partialReference: nil,
        flags: []
    )
}

private func momentsGalleryFile(url: String, media: MomentsMedia) -> TelegramMediaFile {
    let width = Int32(max(media.width, 16))
    let height = Int32(max(media.height, 16))
    return TelegramMediaFile(
        fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: Int64(url.hashValue)),
        partialReference: nil,
        resource: HttpReferenceMediaResource(url: url, size: nil),
        previewRepresentations: [],
        videoThumbnails: [],
        immediateThumbnailData: nil,
        mimeType: momentsPlaybackMimeType(media.type),
        size: nil,
        attributes: [
            .FileName(fileName: momentsPlaybackFileName(media.type)),
            .Video(duration: Double(media.durationMs) / 1000.0, size: PixelDimensions(width: width, height: height), flags: TelegramMediaVideoFlags(), preloadSize: nil, coverTime: nil, videoCodec: nil)
        ],
        alternativeRepresentations: []
    )
}
