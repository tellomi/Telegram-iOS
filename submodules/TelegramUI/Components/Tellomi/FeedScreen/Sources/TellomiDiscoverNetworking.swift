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
            let mapped = tellomiDiscoverClientError(for: error)
            // This RPC's USER_ID_INVALID means the signed-in account is deleted.
            // The same code on getAudienceToken means one id in the list.
            completion(.failure(mapped == .userInvalid ? .disabled : mapped))
        })
    }, http: { call, completion in
        transport.perform(call, completion: completion)
    }, startHTTP: { call, completion in
        return transport.start(call, completion: completion)
    })
}

private final class TellomiDiscoverHTTPS {
    private let session: URLSession
    private let redirect = TellomiDiscoverRedirectGate()

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        self.session = URLSession(configuration: configuration, delegate: self.redirect, delegateQueue: nil)
    }

    func perform(_ call: TellomiDiscoverHTTPCall, completion: @escaping (Result<TellomiDiscoverHTTPResult, TellomiDiscoverClientError>) -> Void) {
        _ = self.start(call, completion: completion)
    }

    func start(_ call: TellomiDiscoverHTTPCall, completion: @escaping (Result<TellomiDiscoverHTTPResult, TellomiDiscoverClientError>) -> Void) -> () -> Void {
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
        let task = self.session.dataTask(with: request) { data, response, error in
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
            Queue.mainQueue().async {
                completion(result)
            }
        }
        task.resume()
        return { task.cancel() }
    }
}
