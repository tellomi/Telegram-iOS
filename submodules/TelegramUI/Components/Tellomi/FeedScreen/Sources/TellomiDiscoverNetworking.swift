import Foundation
import MtProtoKit
import SwiftSignalKit
import TelegramCore
import TellomiDiscover

func tellomiDiscoverMakeLoader(account: Account) -> TellomiDiscoverLoader {
    let transport = TellomiDiscoverHTTPS()
    return TellomiDiscoverLoader(now: {
        return Int64(Date().timeIntervalSince1970)
    }, fetchCredential: { completion in
        let _ = (tellomiDiscoverEngineCredential(account: account)
        |> deliverOnMainQueue).start(next: { credential in
            completion(.success(credential))
        }, error: { error in
            completion(.failure(tellomiDiscoverClientError(for: error)))
        })
    }, http: { call, completion in
        transport.perform(call, completion: completion)
    })
}

private final class TellomiDiscoverRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let _ = (session, task, response)
        if request.url?.scheme?.lowercased() == "https" {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}

private final class TellomiDiscoverHTTPS {
    private let session: URLSession
    private let redirect = TellomiDiscoverRedirect()

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        self.session = URLSession(configuration: configuration, delegate: self.redirect, delegateQueue: nil)
    }

    func perform(_ call: TellomiDiscoverHTTPCall, completion: @escaping (Result<TellomiDiscoverHTTPResult, TellomiDiscoverClientError>) -> Void) {
        guard call.url.scheme?.lowercased() == "https" else {
            completion(.failure(.unavailable))
            return
        }
        var request = URLRequest(url: call.url)
        request.httpMethod = call.method
        request.httpBody = call.body
        if call.authorizes {
            request.setValue("Bearer \(call.token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType = call.contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        let task = self.session.dataTask(with: request) { data, response, error in
            let result: Result<TellomiDiscoverHTTPResult, TellomiDiscoverClientError>
            if error != nil || response == nil {
                result = .failure(.unavailable)
            } else if let http = response as? HTTPURLResponse {
                let body = data ?? Data()
                if body.count > 2_000_000 {
                    result = .failure(.unreadable)
                } else {
                    result = .success(TellomiDiscoverHTTPResult(status: http.statusCode, body: body))
                }
            } else {
                result = .failure(.unavailable)
            }
            Queue.mainQueue().async {
                completion(result)
            }
        }
        task.resume()
    }
}
