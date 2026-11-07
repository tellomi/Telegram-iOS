import Foundation
import CryptoKit

/// Reports a secret view must not send. Opening the chat in this mode does not clear unread.
public enum TellomiSecretViewReport: String, Equatable, CaseIterable {
    case messagesReadHistory
    case channelsReadHistory
    case readMessageContents
    case readMentions
    case readReactions
    case clearUnread
    case online
    case typing
}

public func tellomiSecretViewAllows(_ report: TellomiSecretViewReport) -> Bool {
    return false
}

public func tellomiSecretViewKeepsUnreadAfterExit() -> Bool {
    return true
}

public func tellomiSecretViewBannerTitle(languageCode: String) -> String {
    return tellomiChatPrivacyUsesChinese(languageCode) ? "秘密查看中" : "Secret view"
}

public func tellomiSecretViewMenuTitle(languageCode: String) -> String {
    return tellomiChatPrivacyUsesChinese(languageCode) ? "秘密查看" : "Secret view"
}

public final class TellomiSecretViewSessions: @unchecked Sendable {
    public static let shared = TellomiSecretViewSessions()

    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    public init() {
    }

    public func begin(accountPeerId: Int64, chatPeerId: Int64) {
        self.lock.lock()
        let key = tellomiChatPrivacyKey(accountPeerId: accountPeerId, chatPeerId: chatPeerId)
        self.counts[key, default: 0] += 1
        self.lock.unlock()
    }

    public func end(accountPeerId: Int64, chatPeerId: Int64) {
        self.lock.lock()
        let key = tellomiChatPrivacyKey(accountPeerId: accountPeerId, chatPeerId: chatPeerId)
        if let count = self.counts[key] {
            if count <= 1 {
                self.counts.removeValue(forKey: key)
            } else {
                self.counts[key] = count - 1
            }
        }
        self.lock.unlock()
    }

    public func suppressesReports(accountPeerId: Int64, chatPeerId: Int64) -> Bool {
        self.lock.lock()
        let active = (self.counts[tellomiChatPrivacyKey(accountPeerId: accountPeerId, chatPeerId: chatPeerId)] ?? 0) > 0
        self.lock.unlock()
        return active
    }

    public func suppressesOnline(accountPeerId: Int64) -> Bool {
        let prefix = "\(accountPeerId):"
        self.lock.lock()
        let active = self.counts.contains { $0.key.hasPrefix(prefix) && $0.value > 0 }
        self.lock.unlock()
        return active
    }
}

public struct TellomiChatLockRecord: Equatable, Codable {
    public var salt: Data
    public var hash: Data
    public var biometricsEnabled: Bool

    public init(salt: Data, hash: Data, biometricsEnabled: Bool) {
        self.salt = salt
        self.hash = hash
        self.biometricsEnabled = biometricsEnabled
    }
}

public enum TellomiChatLockFailure: Error, Equatable {
    case pinNotNumeric
    case wrongPin
    case notLocked
}

public enum TellomiForgotChatLock: Equatable {
    /// The existing app passcode can authorize a new chat PIN. The chat stays locked until that PIN is saved.
    case resetAfterAppPasscode
    /// No app passcode. The chat stays locked. Nothing is sent to the server.
    case staysLocked
}

public let tellomiChatLockMinimumPinLength = 4
public let tellomiChatLockMaximumPinLength = 8

public func tellomiForgotChatLock(hasAppPasscode: Bool) -> TellomiForgotChatLock {
    return hasAppPasscode ? .resetAfterAppPasscode : .staysLocked
}

public func tellomiChatLockPinIsNumeric(_ pin: String) -> Bool {
    let count = pin.count
    guard count >= tellomiChatLockMinimumPinLength, count <= tellomiChatLockMaximumPinLength else {
        return false
    }
    return pin.allSatisfy { $0.isNumber }
}

public func tellomiChatLockHash(pin: String, salt: Data) -> Data {
    var material = Data(pin.utf8)
    material.append(salt)
    let digest = SHA256.hash(data: material)
    return Data(digest)
}

public func tellomiMakeChatLockRecord(pin: String, biometricsEnabled: Bool, salt: Data = tellomiChatLockRandomSalt()) -> Result<TellomiChatLockRecord, TellomiChatLockFailure> {
    guard tellomiChatLockPinIsNumeric(pin) else {
        return .failure(.pinNotNumeric)
    }
    return .success(TellomiChatLockRecord(salt: salt, hash: tellomiChatLockHash(pin: pin, salt: salt), biometricsEnabled: biometricsEnabled))
}

public func tellomiChatLockMatches(pin: String, record: TellomiChatLockRecord) -> Bool {
    return tellomiChatLockHash(pin: pin, salt: record.salt) == record.hash
}

public func tellomiChatLockRandomSalt() -> Data {
    var bytes = [UInt8](repeating: 0, count: 16)
    for index in bytes.indices {
        bytes[index] = UInt8.random(in: 0 ... 255)
    }
    return Data(bytes)
}

public enum TellomiChatLockSurface: Equatable, CaseIterable {
    case open
    case notificationPreview
    case listPreview
    case search
    case share
}

public func tellomiChatLockConcealedText(languageCode: String) -> String {
    return tellomiChatPrivacyUsesChinese(languageCode) ? "已锁定" : "Locked"
}

public func tellomiConcealedChatText(isLocked: Bool, text: String, languageCode: String) -> String {
    guard isLocked else {
        return text
    }
    return tellomiChatLockConcealedText(languageCode: languageCode)
}

public struct TellomiChatLockIndexEntry: Codable, Equatable {
    public var accountPeerId: Int64
    public var chatPeerId: Int64

    public init(accountPeerId: Int64, chatPeerId: Int64) {
        self.accountPeerId = accountPeerId
        self.chatPeerId = chatPeerId
    }
}

public struct TellomiChatLockIndex: Codable, Equatable {
    public var entries: [TellomiChatLockIndexEntry]

    public init(entries: [TellomiChatLockIndexEntry]) {
        self.entries = entries
    }
}

public func tellomiChatLockIndexPath(rootPath: String) -> String {
    return rootPath + "/tellomi-chat-locks.json"
}

public func tellomiChatPrivacyUsesChinese(_ languageCode: String) -> Bool {
    let language = languageCode.lowercased()
    if language.hasPrefix("zh-hant") || language.hasPrefix("zh-tw") || language.hasPrefix("zh-hk") || language.hasPrefix("zh-mo") {
        return false
    }
    return language == "zh" || language.hasPrefix("zh-hans") || language.hasPrefix("zh-cn") || language.hasPrefix("zh-")
}

public func tellomiChatPrivacyKey(accountPeerId: Int64, chatPeerId: Int64) -> String {
    return "\(accountPeerId):\(chatPeerId)"
}

public final class TellomiChatLockDirectory: @unchecked Sendable {
    public static let shared = TellomiChatLockDirectory()

    private let lock = NSLock()
    private var records: [String: TellomiChatLockRecord] = [:]
    private var indexPath: String?

    public init() {
    }

    public func setIndexPath(_ path: String?) {
        self.lock.lock()
        self.indexPath = path
        let entries = self.entriesLocked()
        let path = self.indexPath
        self.lock.unlock()
        self.writeIndex(entries, path: path)
    }

    public func isLocked(accountPeerId: Int64, chatPeerId: Int64) -> Bool {
        self.lock.lock()
        let locked = self.records[tellomiChatPrivacyKey(accountPeerId: accountPeerId, chatPeerId: chatPeerId)] != nil
        self.lock.unlock()
        return locked
    }

    public func record(accountPeerId: Int64, chatPeerId: Int64) -> TellomiChatLockRecord? {
        self.lock.lock()
        let record = self.records[tellomiChatPrivacyKey(accountPeerId: accountPeerId, chatPeerId: chatPeerId)]
        self.lock.unlock()
        return record
    }

    public func save(_ record: TellomiChatLockRecord, accountPeerId: Int64, chatPeerId: Int64) {
        self.lock.lock()
        self.records[tellomiChatPrivacyKey(accountPeerId: accountPeerId, chatPeerId: chatPeerId)] = record
        let entries = self.entriesLocked()
        let path = self.indexPath
        self.lock.unlock()
        self.writeIndex(entries, path: path)
    }

    public func remove(accountPeerId: Int64, chatPeerId: Int64) {
        self.lock.lock()
        self.records.removeValue(forKey: tellomiChatPrivacyKey(accountPeerId: accountPeerId, chatPeerId: chatPeerId))
        let entries = self.entriesLocked()
        let path = self.indexPath
        self.lock.unlock()
        self.writeIndex(entries, path: path)
    }

    public func replaceAll(_ records: [String: TellomiChatLockRecord]) {
        self.lock.lock()
        self.records = records
        let entries = self.entriesLocked()
        let path = self.indexPath
        self.lock.unlock()
        self.writeIndex(entries, path: path)
    }

    public func indexSnapshot() -> TellomiChatLockIndex {
        self.lock.lock()
        let entries = self.entriesLocked()
        self.lock.unlock()
        return TellomiChatLockIndex(entries: entries)
    }

    private func entriesLocked() -> [TellomiChatLockIndexEntry] {
        return self.records.keys.compactMap { key in
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let account = Int64(parts[0]), let chat = Int64(parts[1]) else {
                return nil
            }
            return TellomiChatLockIndexEntry(accountPeerId: account, chatPeerId: chat)
        }.sorted { lhs, rhs in
            if lhs.accountPeerId != rhs.accountPeerId {
                return lhs.accountPeerId < rhs.accountPeerId
            }
            return lhs.chatPeerId < rhs.chatPeerId
        }
    }

    private func writeIndex(_ entries: [TellomiChatLockIndexEntry], path: String?) {
        guard let path else {
            return
        }
        let index = TellomiChatLockIndex(entries: entries)
        guard let data = try? JSONEncoder().encode(index) else {
            return
        }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

public func tellomiChatLockIndex(at path: String) -> TellomiChatLockIndex {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let index = try? JSONDecoder().decode(TellomiChatLockIndex.self, from: data) else {
        return TellomiChatLockIndex(entries: [])
    }
    return index
}

public func tellomiChatLockIndexHides(index: TellomiChatLockIndex, accountPeerId: Int64, chatPeerId: Int64) -> Bool {
    return index.entries.contains { $0.accountPeerId == accountPeerId && $0.chatPeerId == chatPeerId }
}

/// Runtime hook for the app passcode. The chat PIN itself stays in this process's keychain.
public enum TellomiAppPasscodeBridge {
    public static var hasPasscode: () -> Bool = { false }
    public static var verify: (String) -> Bool = { _ in false }
}

public func tellomiChatLockMenuTitle(languageCode: String, isLocked: Bool) -> String {
    if tellomiChatPrivacyUsesChinese(languageCode) {
        return isLocked ? "聊天密码" : "设置密码"
    }
    return isLocked ? "Chat password" : "Set password"
}
