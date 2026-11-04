import Foundation
import MtProtoKit
import Postbox
import SwiftSignalKit
import TellomiDiscover
internal import TelegramApi

public extension EnginePeer.Id {
    /// Teamgram user id for a cloud user. Groups, channels, and secret chats are nil.
    var tellomiCloudUserId: Int64? {
        guard self.namespace == Namespaces.Peer.CloudUser else {
            return nil
        }
        return self.id._internalGetInt64Value()
    }
}

public func tellomiDiscoverEngineCredential(account: Account) -> Signal<TellomiDiscoverCredential, MTRpcError> {
    return account.network.request(tellomiDiscoverEngineCredentialInvocation(constructorId: TellomiDiscoverTL.getEngineCredentialId))
    |> mapToSignal { data -> Signal<TellomiDiscoverCredential, MTRpcError> in
        guard let credential = TellomiDiscoverTL.decodeCredential(data) else {
            return .fail(MTRpcError(errorCode: 500, errorDescription: "TL_VERIFICATION_ERROR"))
        }
        return .single(credential)
    }
}

public func tellomiDiscoverAudienceToken(account: Account, kind: String, userIds: [Int64]) -> Signal<TellomiDiscoverAudienceToken, MTRpcError> {
    let payload = TellomiDiscoverTL.encodeAudienceRequest(kind: kind, userIds: userIds)
    return account.network.request(tellomiDiscoverBoxedInvocation(name: "discover.getAudienceToken", payload: payload))
    |> mapToSignal { data -> Signal<TellomiDiscoverAudienceToken, MTRpcError> in
        guard let token = TellomiDiscoverTL.decodeAudienceToken(data) else {
            return .fail(MTRpcError(errorCode: 500, errorDescription: "TL_VERIFICATION_ERROR"))
        }
        return .single(token)
    }
}

public func tellomiDiscoverClientError(for error: MTRpcError) -> TellomiDiscoverClientError {
    return tellomiDiscoverClientError(description: error.errorDescription, code: error.errorCode)
}
