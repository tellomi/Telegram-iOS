import AccountContext
import Foundation
import SwiftSignalKit
import TelegramCore
import TellomiDiscover

func tellomiRunDiscoverPublish(context: AccountContext, loader: TellomiDiscoverLoader, configuration: TellomiDiscoverConfiguration, loggedIn: Bool, city: String?, textLimit: Int, request: TellomiDiscoverComposeRequest, retainAudience: @escaping (Disposable?) -> Void, completion: @escaping (Result<TellomiDiscoverDecoded, TellomiDiscoverClientError>) -> Void) {
    guard let selfUserId = context.account.peerId.tellomiCloudUserId else {
        completion(.failure(.signedOut))
        return
    }
    guard loggedIn, configuration.enabled else {
        completion(.failure(loggedIn ? .disabled : .signedOut))
        return
    }
    let step = tellomiDiscoverPublishStep(text: request.text, visibility: request.visibility, userIds: request.userIds, selfUserId: selfUserId, clientNonce: request.nonce, textLimit: textLimit, token: nil, now: Int64(Date().timeIntervalSince1970), city: city, quoteOf: request.quoteOf, pollOptions: request.pollOptions)
    switch step {
    case .ready:
        loader.run(loggedIn: true, configuration: configuration, operation: .publish(text: request.text, visibility: request.visibility, audienceToken: nil, clientNonce: request.nonce, textLimit: textLimit, city: city, quoteOf: request.quoteOf, pollOptions: request.pollOptions), completion: completion)
    case let .needsAudienceToken(kind, ids):
        let disposable = (tellomiDiscoverAudienceToken(account: context.account, kind: kind, userIds: ids)
        |> deliverOnMainQueue).start(next: { token in
            loader.run(loggedIn: true, configuration: configuration, operation: .publish(text: request.text, visibility: request.visibility, audienceToken: token.token, clientNonce: request.nonce, textLimit: textLimit, city: city, quoteOf: request.quoteOf, pollOptions: request.pollOptions), completion: completion)
        }, error: { error in
            completion(.failure(tellomiDiscoverClientError(for: error)))
        })
        retainAudience(disposable)
    case let .rejected(error):
        completion(.failure(error))
    }
}
