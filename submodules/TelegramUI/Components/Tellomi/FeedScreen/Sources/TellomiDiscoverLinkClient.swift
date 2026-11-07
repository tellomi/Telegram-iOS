import Foundation
import TellomiDiscover
import UIKit

/// Open Graph and cover images, fetched on this phone's own network.
///
/// This does not call Chengdu, `account.getWebPagePreview`, port 8801, or
/// `POST /internal/v1/link-preview`. The maps below are a short in-memory cache
/// for this process. They are not written to disk and they are not a shared
/// URL cache.
enum TellomiDiscoverLinkClient {
    private static let previewLimit = 16
    private static let imageLimit = 8

    private static let lock = NSLock()
    private static var previews: [String: TellomiDiscoverLink.Preview] = [:]
    private static var previewOrder: [String] = []
    private static var waiters: [String: [(TellomiDiscoverLink.Preview?) -> Void]] = [:]
    private static var images: [String: UIImage] = [:]
    private static var imageOrder: [String] = []

    static func peek(_ url: String) -> TellomiDiscoverLink.Preview? {
        guard TellomiDiscoverLink.fetchable(url) else {
            return nil
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let value = self.previews[url] else {
            return nil
        }
        self.touch(&self.previewOrder, url)
        return value
    }

    static func load(_ url: String, completion: @escaping (TellomiDiscoverLink.Preview?) -> Void) {
        guard TellomiDiscoverLink.fetchable(url) else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }
        if let hit = self.peek(url) {
            DispatchQueue.main.async {
                completion(hit)
            }
            return
        }
        var start = false
        self.lock.lock()
        if self.waiters[url] != nil {
            self.waiters[url]?.append(completion)
        } else {
            self.waiters[url] = [completion]
            start = true
        }
        self.lock.unlock()
        guard start else {
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let fetched = self.fetch(url) ?? TellomiDiscoverLink.urlOnly(url)
            self.lock.lock()
            if let fetched, fetched.title != nil || fetched.description != nil || fetched.image != nil {
                self.previews[url] = fetched
                self.touch(&self.previewOrder, url)
                while self.previewOrder.count > self.previewLimit {
                    let oldest = self.previewOrder.removeFirst()
                    self.previews.removeValue(forKey: oldest)
                }
            }
            let callbacks = self.waiters.removeValue(forKey: url) ?? []
            self.lock.unlock()
            DispatchQueue.main.async {
                for callback in callbacks {
                    callback(fetched)
                }
            }
        }
    }

    static func loadImage(_ url: String?, completion: @escaping (UIImage?) -> Void) {
        guard let url, TellomiDiscoverLink.fetchable(url) else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }
        self.lock.lock()
        let cached = self.images[url]
        if cached != nil {
            self.touch(&self.imageOrder, url)
        }
        self.lock.unlock()
        if let cached {
            DispatchQueue.main.async {
                completion(cached)
            }
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let image = self.fetchImage(url)
            if let image {
                self.lock.lock()
                self.images[url] = image
                self.touch(&self.imageOrder, url)
                while self.imageOrder.count > self.imageLimit {
                    let oldest = self.imageOrder.removeFirst()
                    self.images.removeValue(forKey: oldest)
                }
                self.lock.unlock()
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    private static func touch(_ order: inout [String], _ key: String) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
    }

    private static func fetch(_ pageURL: String) -> TellomiDiscoverLink.Preview? {
        if let page = TellomiDiscoverLinkFetch.loadPage(pageURL) {
            return page.preview
        }
        return TellomiDiscoverLink.urlOnly(pageURL)
    }

    private static func fetchImage(_ url: String, hop: Int = 0) -> UIImage? {
        let _ = hop
        guard let data = TellomiDiscoverLinkFetch.loadData(url) else {
            return nil
        }
        return UIImage(data: data)
    }
}
