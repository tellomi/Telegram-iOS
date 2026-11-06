import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One completion for one transport start. `close` is the cancel/deregister:
/// the first caller wins, and a later URLSession callback is dropped.
final class TellomiDiscoverTransportCallback: @unchecked Sendable {
    private let body: (Result<TellomiDiscoverHTTPResult, TellomiDiscoverClientError>) -> Void

    init(_ body: @escaping (Result<TellomiDiscoverHTTPResult, TellomiDiscoverClientError>) -> Void) {
        self.body = body
    }

    func call(_ result: Result<TellomiDiscoverHTTPResult, TellomiDiscoverClientError>) {
        self.body(result)
    }
}

public final class TellomiDiscoverTransportSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false

    public func close() -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.closed {
            return false
        }
        self.closed = true
        return true
    }
}

/// The app transport calls this and only this to start one request.
/// `http` is refused before a task exists. Cancel closes the slot, then
/// cancels the task, so a redirect that arrives afterwards is not delivered.
public func tellomiDiscoverBeginTransport(call: TellomiDiscoverHTTPCall, session: URLSession, completion: @escaping (Result<TellomiDiscoverHTTPResult, TellomiDiscoverClientError>) -> Void) -> () -> Void {
    guard call.url.scheme?.lowercased() == "https" else {
        completion(.failure(.unavailable))
        return {}
    }
    var request = URLRequest(url: call.url)
    request.httpMethod = call.method
    request.httpBody = call.body
    if let body = call.body, body.count > 1_000_000 {
        request.timeoutInterval = 120
    }
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let contentType = call.contentType {
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    }
    for (name, value) in call.extraHeaders {
        if name.caseInsensitiveCompare("Authorization") == .orderedSame {
            continue
        }
        request.setValue(value, forHTTPHeaderField: name)
    }
    if call.authorizes {
        request.setValue("Bearer \(call.token)", forHTTPHeaderField: "Authorization")
    }
    let slot = TellomiDiscoverTransportSlot()
    let callback = TellomiDiscoverTransportCallback(completion)
    let task = session.dataTask(with: request) { data, response, error in
        let result: Result<TellomiDiscoverHTTPResult, TellomiDiscoverClientError>
        if error != nil || response == nil {
            result = .failure(.unavailable)
        } else if let http = response as? HTTPURLResponse {
            let body = data ?? Data()
            if body.count > 2_000_000 {
                result = .failure(.unreadable)
            } else {
                var headers: [String: String] = [:]
                for (key, value) in http.allHeaderFields {
                    if let name = key as? String, let text = value as? String {
                        headers[name] = text
                    }
                }
                result = .success(TellomiDiscoverHTTPResult(status: http.statusCode, body: body, headers: headers))
            }
        } else {
            result = .failure(.unavailable)
        }
        if slot.close() {
            callback.call(result)
        }
    }
    task.resume()
    return {
        _ = slot.close()
        task.cancel()
    }
}
