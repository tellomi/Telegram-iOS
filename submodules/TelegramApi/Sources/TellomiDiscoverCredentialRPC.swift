import Foundation

/// `discover.getEngineCredential#a80a7f76` has no arguments. The constructor id is the one
/// teamgram registers; it is not part of the generated Telegram schema. The bytes are checked
/// by `TellomiDiscoverTL.encodeRequest`.
public func tellomiDiscoverEngineCredentialInvocation(constructorId: Int32) -> (FunctionDescription, Buffer, DeserializeFunctionResponse<Data>) {
    let buffer = Buffer()
    buffer.appendInt32(constructorId)
    let description = FunctionDescription(name: "discover.getEngineCredential", parameters: [])
    return (description, buffer, DeserializeFunctionResponse { raw in
        let data = raw.makeData()
        guard !data.isEmpty else {
            return nil
        }
        return data
    })
}
