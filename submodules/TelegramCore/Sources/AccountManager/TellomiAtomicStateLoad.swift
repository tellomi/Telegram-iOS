import Foundation

/// Bytes an extension can treat as account-manager atomic state.
///
/// Missing, empty, or non-JSON bytes are unusable. `getCurrentRecords` then
/// returns no records instead of trapping. The file is absent on a fresh
/// install, and the main app replaces it atomically while `auth.checkPassword`
/// moves the record from the auth slot to a signed-in account. A reader that
/// hits that window used to `preconditionFailure` inside the Siri intents process.
public func tellomiAtomicStatePayload(_ data: Data?) -> Data? {
    guard let data, !data.isEmpty else {
        return nil
    }
    guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
        return nil
    }
    return data
}
