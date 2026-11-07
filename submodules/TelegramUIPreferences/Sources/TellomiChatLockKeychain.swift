import Foundation
import Security

/// The chat PIN hash lives in the app's data-protection keychain. This is not the macOS login keychain.
public enum TellomiChatLockKeychain {
    public static let service = "app.tellomi.chat.chat-lock"

    public static func load(into directory: TellomiChatLockDirectory = .shared) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let rows = result as? [[String: Any]] else {
            directory.replaceAll([:])
            return
        }
        var records: [String: TellomiChatLockRecord] = [:]
        for row in rows {
            guard let account = row[kSecAttrAccount as String] as? String, let data = row[kSecValueData as String] as? Data, let record = try? JSONDecoder().decode(TellomiChatLockRecord.self, from: data) else {
                continue
            }
            records[account] = record
        }
        directory.replaceAll(records)
    }

    public static func save(_ record: TellomiChatLockRecord, accountPeerId: Int64, chatPeerId: Int64, directory: TellomiChatLockDirectory = .shared) {
        let account = tellomiChatPrivacyKey(accountPeerId: accountPeerId, chatPeerId: chatPeerId)
        guard let data = try? JSONEncoder().encode(record) else {
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        if status == errSecSuccess {
            directory.save(record, accountPeerId: accountPeerId, chatPeerId: chatPeerId)
        }
    }

    public static func remove(accountPeerId: Int64, chatPeerId: Int64, directory: TellomiChatLockDirectory = .shared) {
        let account = tellomiChatPrivacyKey(accountPeerId: accountPeerId, chatPeerId: chatPeerId)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(query as CFDictionary)
        directory.remove(accountPeerId: accountPeerId, chatPeerId: chatPeerId)
    }
}
