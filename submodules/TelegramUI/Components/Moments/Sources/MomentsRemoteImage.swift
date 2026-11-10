import Foundation
import UIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import Display

/// HTTPS feed images go through `HttpReferenceMediaResource` and `MediaBox`, the same fetch
/// `UniversalVideoNode` already uses for Moments video. Bytes land in the account media cache.
/// The bitmap is an ImageIO thumbnail capped at the view size, never a full-size decode.
///
/// That is the same shape as:
/// - Apple Image I/O `kCGImageSourceThumbnailMaxPixelSize` (thumbnail without the full bitmap):
///   https://developer.apple.com/documentation/imageio/kcgimagesourcethumbnailmaxpixelsize
/// - Facebook Fresco, which resizes before decode: https://frescolib.org/docs/resizing.html
/// - Nuke's prefetch of upcoming items: https://kean-docs.github.io/nuke/documentation/nuke/prefetching/
/// Telegram's own list prefetch is `ChatListController`'s story resource disposables plus
/// `ListView.preloadPages`. This window is the next 8 rows in the scroll direction, then the
/// disposables for rows that left the window are dropped. `MediaBox` dedupes by URL hash.

func momentsDownsampleImage(path: String, maxPixel: CGFloat, scale: CGFloat) -> UIImage? {
    let sourceURL = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(sourceURL, nil) else {
        return nil
    }
    let pixels = Int(max(maxPixel, 1))
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: pixels,
        kCGImageSourceShouldCacheImmediately: true
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return nil
    }
    return UIImage(cgImage: cgImage, scale: scale > 0 ? scale : 1, orientation: .up)
}

private func momentsRemoteResource(url: String) -> HttpReferenceMediaResource {
    return HttpReferenceMediaResource(url: url, size: nil)
}

func momentsPrefetchRemoteImage(context: AccountContext, url: String) -> Signal<Never, NoError> {
    guard url.hasPrefix("https://") else {
        return .complete()
    }
    let resource = momentsRemoteResource(url: url)
    return context.engine.resources.fetch(reference: .standalone(resource: resource), userLocation: .other, userContentType: .image, statsCategory: .image)
    |> `catch` { _ -> Signal<FetchResourceSourceType, NoError> in
        return .complete()
    }
    |> ignoreValues
}

final class MomentsRemoteImageSlot {
    private var url: String?
    private var image: UIImage?
    private weak var imageView: UIImageView?
    private var disposable: Disposable?

    func bind(url: String?, imageView: UIImageView, context: AccountContext, maxSide: CGFloat) {
        self.imageView = imageView
        if url == self.url {
            imageView.image = self.image
            return
        }
        self.cancel()
        self.url = url
        self.imageView = imageView
        imageView.image = nil
        guard let url, url.hasPrefix("https://") else {
            return
        }
        let resource = momentsRemoteResource(url: url)
        let scale = UIScreen.main.scale
        let maxPixel = max(maxSide, 1) * (scale > 0 ? scale : 1)
        let expected = url
        let fetch = context.engine.resources.fetch(reference: .standalone(resource: resource), userLocation: .other, userContentType: .image, statsCategory: .image)
        |> `catch` { _ -> Signal<FetchResourceSourceType, NoError> in
            return .complete()
        }
        |> ignoreValues
        let data = context.account.postbox.mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: true))
        |> filter { $0.complete }
        |> take(1)
        |> deliverOn(Queue.concurrentDefaultQueue())
        |> map { resourceData -> UIImage? in
            return momentsDownsampleImage(path: resourceData.path, maxPixel: maxPixel, scale: scale)
        }
        |> deliverOnMainQueue
        let bag = DisposableSet()
        bag.add(fetch.start())
        bag.add(data.start(next: { [weak self] image in
            guard let self, self.url == expected, let image else {
                return
            }
            self.image = image
            self.imageView?.image = image
        }))
        self.disposable = bag
    }

    func cancel() {
        self.url = nil
        self.image = nil
        self.imageView = nil
        self.disposable?.dispose()
        self.disposable = nil
    }

    deinit {
        self.disposable?.dispose()
    }
}

public final class MomentsPrefetchManager {
    private let context: AccountContext
    private var inflight: [String: Disposable] = [:]
    public var lookahead = 8

    public init(context: AccountContext) {
        self.context = context
    }

    public func update(cards: [MomentsCard], firstIndex: Int, lastIndex: Int) {
        guard !cards.isEmpty else {
            self.reset()
            return
        }
        let start = min(max(0, firstIndex), cards.count)
        let end = min(cards.count, max(start, lastIndex + 1 + self.lookahead))
        guard start < end else {
            return
        }
        var urls: [String] = []
        for card in cards[start..<end] {
            if let avatar = card.author?.avatarKey, avatar.hasPrefix("https://") {
                urls.append(avatar)
            }
            for media in card.media where momentsPresentsAsImage(media.type) {
                if let remote = media.remoteURL, remote.hasPrefix("https://") {
                    urls.append(remote)
                }
            }
        }
        let keep = Set(urls)
        for url in self.inflight.keys where !keep.contains(url) {
            self.inflight[url]?.dispose()
            self.inflight.removeValue(forKey: url)
        }
        for url in keep where self.inflight[url] == nil {
            self.inflight[url] = momentsPrefetchRemoteImage(context: self.context, url: url).start()
        }
    }

    public func reset() {
        for disposable in self.inflight.values {
            disposable.dispose()
        }
        self.inflight.removeAll()
    }

    deinit {
        self.reset()
    }
}

func momentsTintedIcon(_ name: String, _ color: UIColor) -> UIImage? {
    return generateTintedImage(image: UIImage(bundleImageName: name), color: color)
}
