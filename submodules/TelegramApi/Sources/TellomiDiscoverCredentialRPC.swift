import Foundation

/// `discover.getEngineCredential` and `discover.getAudienceToken` are not in the generated
/// schema. `payload` is the full boxed query, including the constructor id.
public func tellomiDiscoverBoxedInvocation(name: String, payload: Data) -> (FunctionDescription, Buffer, DeserializeFunctionResponse<Data>) {
    let buffer = Buffer(data: payload)
    let description = FunctionDescription(name: name, parameters: [])
    return (description, buffer, DeserializeFunctionResponse { raw in
        let data = raw.makeData()
        guard !data.isEmpty else {
            return nil
        }
        return data
    })
}

public func tellomiDiscoverEngineCredentialInvocation(constructorId: Int32) -> (FunctionDescription, Buffer, DeserializeFunctionResponse<Data>) {
    var payload = Data()
    var little = constructorId.littleEndian
    withUnsafeBytes(of: &little) { bytes in
        payload.append(contentsOf: bytes)
    }
    return tellomiDiscoverBoxedInvocation(name: "discover.getEngineCredential", payload: payload)
}
