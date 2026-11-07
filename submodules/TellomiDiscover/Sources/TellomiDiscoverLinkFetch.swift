import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// The same GET the Discover composer uses: 8 seconds, 512 KiB, no cookies,
/// redirects checked one hop at a time so a public page cannot land on a
/// private address.
public enum TellomiDiscoverLinkFetch {
    public static let timeout: TimeInterval = 8
    public static let maxBytes = 512 * 1024
    private static let maxHops = 5
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) TellomiLinkPreview/1.0"

    public struct Page: Equatable {
        public var url: String
        public var html: String
        public var preview: TellomiDiscoverLink.Preview
    }

    public static func loadPage(_ pageURL: String) -> Page? {
        var current = pageURL
        for _ in 0 ... self.maxHops {
            if !self.reachablePublic(current) {
                return nil
            }
            guard let exchange = self.get(current, stopAtHead: true) else {
                return nil
            }
            let status = exchange.response.statusCode
            if status >= 300 && status < 400 {
                guard let next = self.redirect(current: current, location: exchange.response.value(forHTTPHeaderField: "Location")) else {
                    return nil
                }
                current = next
                continue
            }
            if status < 200 || status >= 300 {
                return nil
            }
            let type = exchange.response.value(forHTTPHeaderField: "Content-Type")
            if let type {
                let lower = type.lowercased()
                if lower.hasPrefix("image/") {
                    return nil
                }
                if !lower.contains("html") && !lower.contains("xml") && !lower.contains("text/") {
                    return nil
                }
            }
            let html = self.text(exchange.data, contentType: type)
            guard let preview = TellomiDiscoverLink.parseHtml(html, pageUrl: current) else {
                return nil
            }
            return Page(url: current, html: html, preview: preview)
        }
        return nil
    }

    public static func loadData(_ url: String, hop: Int = 0) -> Data? {
        guard hop <= self.maxHops, self.reachablePublic(url), let exchange = self.get(url, stopAtHead: false) else {
            return nil
        }
        let status = exchange.response.statusCode
        if status >= 300 && status < 400 {
            guard let next = self.redirect(current: url, location: exchange.response.value(forHTTPHeaderField: "Location")) else {
                return nil
            }
            return self.loadData(next, hop: hop + 1)
        }
        guard status >= 200, status < 300 else {
            return nil
        }
        if let type = exchange.response.value(forHTTPHeaderField: "Content-Type"), !type.lowercased().hasPrefix("image/") {
            return nil
        }
        return exchange.data
    }

    /// DNS answers must all be public. A lookup failure refuses the host.
    public static func reachablePublic(_ raw: String) -> Bool {
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
        let reader = TellomiDiscoverLinkHeadReader(stopAtHead: stopAtHead, limit: self.maxBytes)
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

private final class TellomiDiscoverLinkHeadReader: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
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
