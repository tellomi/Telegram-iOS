import Foundation
import TellomiDiscover
import UIKit
#if canImport(Darwin)
import Darwin
#endif

/// Open Graph and cover images, fetched on this phone's own network.
///
/// This does not call Chengdu, `account.getWebPagePreview`, port 8801, or
/// `POST /internal/v1/link-preview`. The maps below are a short in-memory cache
/// for this process. They are not written to disk and they are not a shared
/// URL cache.
enum TellomiDiscoverLinkClient {
    static let maxBytes = 512 * 1024
    private static let maxHops = 5
    private static let timeout: TimeInterval = 8
    private static let previewLimit = 16
    private static let imageLimit = 8
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) TellomiLinkPreview/1.0"

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

    /// DNS check before a connection. Any private, loopback, link-local, or
    /// reserved answer refuses the hop. A lookup failure refuses it too.
    static func reachablePublic(_ raw: String) -> Bool {
        guard TellomiDiscoverLink.fetchable(raw), let host = TellomiDiscoverLink.host(raw) else {
            return false
        }
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        hints.ai_family = AF_UNSPEC
        var info: UnsafeMutablePointer<addrinfo>?
        let code = host.withCString { pointer in
            getaddrinfo(pointer, nil, &hints, &info)
        }
        guard code == 0, let info else {
            return false
        }
        defer { freeaddrinfo(info) }
        var cursor: UnsafeMutablePointer<addrinfo>? = info
        var saw = false
        while let node = cursor {
            saw = true
            if !self.publicAddress(node.pointee) {
                return false
            }
            cursor = node.pointee.ai_next
        }
        return saw
    }

    private static func fetch(_ pageURL: String) -> TellomiDiscoverLink.Preview? {
        var current = pageURL
        for _ in 0 ... self.maxHops {
            if !self.reachablePublic(current) {
                return TellomiDiscoverLink.urlOnly(pageURL)
            }
            guard let exchange = self.get(current, stopAtHead: true) else {
                return TellomiDiscoverLink.urlOnly(pageURL)
            }
            let status = exchange.response.statusCode
            if status >= 300 && status < 400 {
                guard let next = self.redirect(current: current, location: exchange.response.value(forHTTPHeaderField: "Location")) else {
                    return TellomiDiscoverLink.urlOnly(pageURL)
                }
                current = next
                continue
            }
            if status < 200 || status >= 300 {
                return TellomiDiscoverLink.urlOnly(pageURL)
            }
            let type = exchange.response.value(forHTTPHeaderField: "Content-Type")
            if let type, type.lowercased().hasPrefix("image/"), TellomiDiscoverLink.fetchable(current) {
                return TellomiDiscoverLink.Preview(url: current, title: nil, description: nil, image: current)
            }
            if let type {
                let lower = type.lowercased()
                if !lower.contains("html") && !lower.contains("xml") && !lower.contains("text/") {
                    return TellomiDiscoverLink.urlOnly(pageURL)
                }
            }
            let html = self.text(exchange.data, contentType: type)
            return TellomiDiscoverLink.parseHtml(html, pageUrl: current)
        }
        return TellomiDiscoverLink.urlOnly(pageURL)
    }

    private static func fetchImage(_ url: String, hop: Int = 0) -> UIImage? {
        guard hop <= self.maxHops, self.reachablePublic(url), let exchange = self.get(url, stopAtHead: false) else {
            return nil
        }
        let status = exchange.response.statusCode
        if status >= 300 && status < 400 {
            guard let next = self.redirect(current: url, location: exchange.response.value(forHTTPHeaderField: "Location")) else {
                return nil
            }
            return self.fetchImage(next, hop: hop + 1)
        }
        guard status >= 200, status < 300 else {
            return nil
        }
        if let type = exchange.response.value(forHTTPHeaderField: "Content-Type"), !type.lowercased().hasPrefix("image/") {
            return nil
        }
        return UIImage(data: exchange.data)
    }

    private static func redirect(current: String, location: String?) -> String? {
        guard let location, !location.isEmpty, let base = URL(string: current) else {
            return nil
        }
        guard let next = URL(string: location, relativeTo: base)?.absoluteURL.absoluteString, TellomiDiscoverLink.fetchable(next) else {
            return nil
        }
        return next
    }

    private static func get(_ urlString: String, stopAtHead: Bool) -> (response: HTTPURLResponse, data: Data)? {
        guard let url = URL(string: urlString) else {
            return nil
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: self.timeout)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.1", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(self.userAgent, forHTTPHeaderField: "User-Agent")
        let reader = HeadReader(stopAtHead: stopAtHead, limit: self.maxBytes)
        return reader.start(request)
    }

    private static func text(_ data: Data, contentType: String?) -> String {
        let name = TellomiDiscoverLink.charsetName(data, contentType: contentType)
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        if cf != kCFStringEncodingInvalidId {
            let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func touch(_ order: inout [String], _ key: String) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
    }

    /// Darwin lays `sin_addr` at byte 4 of `sockaddr_in` and `sin6_addr` at byte 8 of `sockaddr_in6`.
    private static func publicAddress(_ info: addrinfo) -> Bool {
        guard let addr = info.ai_addr else {
            return false
        }
        let raw = UnsafeRawPointer(addr)
        if info.ai_family == AF_INET {
            var bytes = [UInt8](repeating: 0, count: 4)
            bytes.withUnsafeMutableBytes { dest in
                if let base = dest.baseAddress {
                    _ = memcpy(base, raw.advanced(by: 4), 4)
                }
            }
            return !TellomiDiscoverLink.blockedBytes(bytes)
        }
        if info.ai_family == AF_INET6 {
            var bytes = [UInt8](repeating: 0, count: 16)
            bytes.withUnsafeMutableBytes { dest in
                if let base = dest.baseAddress {
                    _ = memcpy(base, raw.advanced(by: 8), 16)
                }
            }
            return !TellomiDiscoverLink.blockedBytes(bytes)
        }
        return false
    }
}

/// One GET. Redirects are not followed. Reading stops at 512 KiB, and an HTML
/// fetch also stops once `</head>` has arrived.
private final class HeadReader: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    private let stopAtHead: Bool
    private let limit: Int
    private var data = Data()
    private var response: HTTPURLResponse?
    private var failed = false
    private let semaphore = DispatchSemaphore(value: 0)
    private var session: URLSession?

    init(stopAtHead: Bool, limit: Int) {
        self.stopAtHead = stopAtHead
        self.limit = limit
    }

    func start(_ request: URLRequest) -> (response: HTTPURLResponse, data: Data)? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        session.dataTask(with: request).resume()
        self.semaphore.wait()
        session.invalidateAndCancel()
        guard let response = self.response, !self.failed else {
            return nil
        }
        return (response, self.data)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response as? HTTPURLResponse
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if self.data.count >= self.limit {
            dataTask.cancel()
            return
        }
        let room = self.limit - self.data.count
        self.data.append(data.prefix(room))
        if self.data.count >= self.limit || (self.stopAtHead && self.headEnded()) {
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        self.response = response
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as NSError?, error.code != NSURLErrorCancelled {
            self.failed = true
        }
        self.semaphore.signal()
    }

    private func headEnded() -> Bool {
        let ascii = String(data: self.data, encoding: .isoLatin1)?.lowercased() ?? ""
        return ascii.contains("</head>")
    }
}
