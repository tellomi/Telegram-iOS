import Foundation
import MtProtoKit
import SwiftSignalKit
import TellomiDiscover
internal import TelegramApi

public func tellomiDiscoverEngineCredential(account: Account) -> Signal<TellomiDiscoverCredential, MTRpcError> {
    return account.network.request(tellomiDiscoverEngineCredentialInvocation(constructorId: TellomiDiscoverTL.getEngineCredentialId))
    |> mapToSignal { data -> Signal<TellomiDiscoverCredential, MTRpcError> in
        guard let credential = TellomiDiscoverTL.decodeCredential(data) else {
            return .fail(MTRpcError(errorCode: 500, errorDescription: "TL_VERIFICATION_ERROR"))
        }
        return .single(credential)
    }
}

public func tellomiDiscoverClientError(for error: MTRpcError) -> TellomiDiscoverClientError {
    if error.errorCode == 401 || error.errorDescription.contains("AUTH_KEY_UNREGISTERED") {
        return .signedOut
    }
    if error.errorDescription.contains("DISCOVER_DISABLED") || error.errorDescription.contains("USER_ID_INVALID") {
        return .disabled
    }
    return .unavailable
}
