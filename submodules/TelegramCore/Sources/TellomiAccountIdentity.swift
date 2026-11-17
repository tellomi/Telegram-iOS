import Foundation
import Postbox

/// An address `auth.sendCode` can carry in `phone_number`. One `@`, a dotted domain, no whitespace.
public func tellomiNormalizedLoginEmail(_ raw: String) -> String {
    return raw.trimmingCharacters(in: .whitespacesAndNewlines)
}

public func tellomiIsLoginEmail(_ raw: String) -> Bool {
    return tellomiAccountIdentifierIsEmail(raw)
}

public func tellomiAccountIdentifierIsEmail(_ raw: String) -> Bool {
    let value = tellomiNormalizedLoginEmail(raw)
    if value.count < 3 || value.count > 254 {
        return false
    }
    if value.contains(where: { $0.isWhitespace }) {
        return false
    }
    let parts = value.split(separator: "@", omittingEmptySubsequences: false)
    if parts.count != 2 {
        return false
    }
    let local = parts[0]
    let domain = parts[1]
    if local.isEmpty || local.count > 64 {
        return false
    }
    if domain.count < 3 || !domain.contains(".") || domain.hasPrefix(".") || domain.hasSuffix(".") || domain.contains("..") {
        return false
    }
    return true
}

/// `alice@x.com` → `a***@x.com`. The domain stays so the account is still recognizable.
public func tellomiMaskedEmail(_ raw: String) -> String {
    let value = tellomiNormalizedLoginEmail(raw)
    let parts = value.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 2, let first = parts[0].first else {
        return value
    }
    return "\(first)***@\(parts[1])"
}

private func tellomiLoginEmailDefaultsKey(_ peerId: PeerId) -> String {
    return "TellomiLoginEmail.\(peerId.toInt64())"
}

/// The login address is not a user field. Remember it on this device so Settings can show it.
public func tellomiRememberLoginEmail(peerId: PeerId, login: String) {
    let email = tellomiNormalizedLoginEmail(login)
    guard tellomiAccountIdentifierIsEmail(email) else {
        return
    }
    UserDefaults.standard.set(email, forKey: tellomiLoginEmailDefaultsKey(peerId))
}

public func tellomiStoredAccountLoginEmail(peerId: PeerId) -> String? {
    guard let stored = UserDefaults.standard.string(forKey: tellomiLoginEmailDefaultsKey(peerId)) else {
        return nil
    }
    let email = tellomiNormalizedLoginEmail(stored)
    return tellomiAccountIdentifierIsEmail(email) ? email : nil
}

public struct TellomiAccountContact: Equatable {
    public let phone: String?
    public let email: String?

    public init(phone: String?, email: String?) {
        self.phone = phone
        self.email = email
    }
}

/// Phone and email are separate. A phone field that is an address is the email, not a number.
public func tellomiAccountContact(phone: String?, peerId: PeerId) -> TellomiAccountContact {
    let trimmed = phone?.trimmingCharacters(in: .whitespacesAndNewlines)
    let fieldEmail = trimmed.flatMap { tellomiAccountIdentifierIsEmail($0) ? tellomiNormalizedLoginEmail($0) : nil }
    let fieldPhone: String?
    if let trimmed, !trimmed.isEmpty, fieldEmail == nil {
        fieldPhone = trimmed
    } else {
        fieldPhone = nil
    }
    let email = fieldEmail ?? tellomiStoredAccountLoginEmail(peerId: peerId)
    return TellomiAccountContact(phone: fieldPhone, email: email)
}

/// Account switcher subtitle. A number is preferred; otherwise the masked address.
public func tellomiAccountSwitcherLabel(phone: String?, peerId: PeerId) -> String? {
    let contact = tellomiAccountContact(phone: phone, peerId: peerId)
    if let phone = contact.phone, !phone.isEmpty {
        return phone
    }
    if let email = contact.email {
        return tellomiMaskedEmail(email)
    }
    return nil
}

/// Same account already on this device. Emails compare case-insensitively; numbers compare digits.
public func tellomiLoginIdentifiersMatch(_ stored: String, _ entered: String) -> Bool {
    let left = stored.trimmingCharacters(in: .whitespacesAndNewlines)
    let right = entered.trimmingCharacters(in: .whitespacesAndNewlines)
    if left.isEmpty || right.isEmpty {
        return false
    }
    if tellomiAccountIdentifierIsEmail(left) || tellomiAccountIdentifierIsEmail(right) {
        guard tellomiAccountIdentifierIsEmail(left), tellomiAccountIdentifierIsEmail(right) else {
            return false
        }
        return tellomiNormalizedLoginEmail(left).lowercased() == tellomiNormalizedLoginEmail(right).lowercased()
    }
    let leftDigits = left.filter { $0 >= "0" && $0 <= "9" }
    let rightDigits = right.filter { $0 >= "0" && $0 <= "9" }
    return !leftDigits.isEmpty && leftDigits == rightDigits
}

/// Welcome is only the signed-out root. Adding an account never uses it.
public func tellomiAuthorizationShowsWelcome(existingAccountCount: Int) -> Bool {
    return existingAccountCount == 0
}

/// Server langpack for the first preferred language. Nil for every language other than Chinese.
/// `zh-Hant` / `zh-TW` / `zh-HK` / `zh-MO` are `zh-hant`. Other `zh*` values are `zh-hans`.
public func tellomiLangPackCode(preferredLanguages: [String]) -> String? {
    guard let language = preferredLanguages.first?.lowercased(), !language.isEmpty else {
        return nil
    }
    if language.hasPrefix("zh-hant") || language.hasPrefix("zh-tw") || language.hasPrefix("zh-hk") || language.hasPrefix("zh-mo") {
        return "zh-hant"
    }
    if language == "zh" || language.hasPrefix("zh-hans") || language.hasPrefix("zh-cn") || language.hasPrefix("zh-") {
        return "zh-hans"
    }
    return nil
}
