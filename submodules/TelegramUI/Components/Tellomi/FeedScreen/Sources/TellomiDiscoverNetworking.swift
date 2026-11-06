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
        return tellomiDiscoverBeginTransport(call: call, session: self.session) { result in
            Queue.mainQueue().async {
                completion(result)
            }
        }
    }
}
