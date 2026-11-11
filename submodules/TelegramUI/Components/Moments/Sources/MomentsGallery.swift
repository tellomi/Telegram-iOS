import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import AccountContext
import Postbox
import GalleryUI

/// The row that was tapped. The gallery asks again for whichever page is on screen, including after
/// a horizontal swipe, the same way a chat asks the visible bubble.
public final class MomentsGallerySource {
    let aspects: [Int: Double]
    private let transition: (Int) -> MomentsGalleryTransition?
    private let viewsToHide: (Int) -> [UIView]
    private var hidden: [UIView] = []

    init(aspects: [Int: Double], transition: @escaping (Int) -> MomentsGalleryTransition?, viewsToHide: @escaping (Int) -> [UIView]) {
        self.aspects = aspects
        self.transition = transition
        self.viewsToHide = viewsToHide
    }

    func transition(for slide: Int) -> MomentsGalleryTransition? {
        assert(Queue.mainQueue().isCurrent())
        return self.transition(slide)
    }

    func hide(_ views: [UIView]) {
        assert(Queue.mainQueue().isCurrent())
        for view in views {
            if self.hidden.contains(where: { $0 === view }) {
                view.isHidden = true
                continue
            }
            view.isHidden = true
            self.hidden.append(view)
        }
    }

    /// The page that is central in the gallery stays hidden. The others show again, matching
    /// `GalleryController`'s hidden-media update when the pager moves.
    func focus(slide: Int) {
        assert(Queue.mainQueue().isCurrent())
        let keep = self.viewsToHide(slide)
        self.hidden.removeAll { view in
            if keep.contains(where: { $0 === view }) {
                return false
            }
            view.isHidden = false
            return true
        }
        self.hide(keep)
    }

    deinit {
        let views = self.hidden
        momentsOnMainQueue {
            for view in views {
                view.isHidden = false
            }
        }
    }
}

struct MomentsGalleryTransition {
    let node: (ASDisplayNode, CGRect, () -> (UIView?, UIView?))
    let views: [UIView]
}

func momentsPresentGallery(context: AccountContext, card: MomentsCard, index: Int, controller: ViewController, source: MomentsGallerySource?) {
    assert(Queue.mainQueue().isCurrent())
    let entries = momentsGalleryEntries(from: card.media, visibleAspectBySlide: source?.aspects ?? [:])
    guard let position = momentsGalleryEntryPosition(entries: entries, tappedSlide: index) else {
        return
    }
    let slides = card.media.filter { momentsPresentsAsImage($0.type) || momentsPresentsAsVideo($0.type) }
    let peerId = context.account.peerId
    let grouped = entries.count > 1
    var messages: [Message] = []
    for entry in entries {
        let media = slides[entry.slideIndex]
        let attached: Media
        let width = Int32(entry.pixels.width)
        let height = Int32(entry.pixels.height)
        if entry.isVideo {
            attached = momentsGalleryFile(url: entry.url, media: media, width: width, height: height)
        } else {
            attached = momentsGalleryImage(url: entry.url, width: width, height: height, id: Int64(entry.slideIndex + 1))
        }
        let messageId = MessageId(peerId: peerId, namespace: Namespaces.Message.Local, id: Int32(entry.slideIndex + 1))
        messages.append(Message(
            stableId: UInt32(entry.slideIndex + 1),
            stableVersion: 0,
            id: messageId,
            globallyUniqueId: nil,
            groupingKey: grouped ? 1 : nil,
            groupInfo: grouped ? MessageGroupInfo(stableId: 1) : nil,
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
            peers: SimpleDictionary(),
            associatedMessages: SimpleDictionary(),
            associatedMessageIds: [],
            associatedMedia: [:],
            associatedThreadInfo: nil,
            associatedStories: [:]
        ))
    }
    guard !messages.isEmpty else {
        return
    }
    let central = messages[position]
    // `.custom` builds its history from the end of the array, the same order as a chat history.
    // Hand it the reversed list so the pager runs in the post's own order. The central page is
    // chosen by message id, not by that array position.
    let sourceSignal: GalleryControllerItemSource = .custom(
        messages: .single((Array(messages.reversed()), Int32(messages.count), false)),
        messageId: central.id,
        loadMore: nil
    )
    let gallery = GalleryController(context: context, source: sourceSignal, streamSingleVideo: true, replaceRootController: { _, _ in
    }, baseNavigationController: controller.navigationController as? NavigationController)
    if let source {
        gallery.centralItemUpdated = { messageId in
            assert(Queue.mainQueue().isCurrent())
            source.focus(slide: Int(messageId.id) - 1)
        }
    }
    let arguments = GalleryControllerPresentationArguments(transitionArguments: { [weak controller] messageId, _ in
        guard let source, let transition = source.transition(for: Int(messageId.id) - 1) else {
            return nil
        }
        source.hide(transition.views)
        return GalleryTransitionArguments(transitionNode: transition.node, addToTransitionSurface: { view in
            assert(Queue.mainQueue().isCurrent())
            controller?.view.addSubview(view)
        })
    })
    controller.present(gallery, in: .window(.root), with: arguments, blockInteraction: true)
}

func momentsGallerySnapshot(of view: UIView?) -> UIView {
    if let view, let snapshot = view.snapshotContentTree(unhide: true) {
        return snapshot
    }
    if let imageView = view as? UIImageView, let image = imageView.image {
        let copy = UIImageView(image: image)
        copy.frame = CGRect(origin: CGPoint(), size: imageView.bounds.size)
        copy.contentMode = imageView.contentMode
        copy.clipsToBounds = true
        copy.layer.cornerRadius = imageView.layer.cornerRadius
        return copy
    }
    let size = view?.bounds.size ?? CGSize(width: 1, height: 1)
    let placeholder = UIView(frame: CGRect(origin: CGPoint(), size: size))
    placeholder.backgroundColor = view?.backgroundColor
    return placeholder
}

private func momentsGalleryImage(url: String, width: Int32, height: Int32, id: Int64) -> TelegramMediaImage {
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

private func momentsGalleryFile(url: String, media: MomentsMedia, width: Int32, height: Int32) -> TelegramMediaFile {
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
            .Video(duration: Double(media.durationMs) / 1000.0, size: PixelDimensions(width: max(width, 16), height: max(height, 16)), flags: TelegramMediaVideoFlags(), preloadSize: nil, coverTime: nil, videoCodec: nil)
        ],
        alternativeRepresentations: []
    )
}
