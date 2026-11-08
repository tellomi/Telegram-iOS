import Foundation

/// Chat link cards. Internal hosts stay on `messages.getWebPage`. Everything
/// else is fetched on the phone and submitted with `inputMediaWebPage` flags 3–6.
public enum TellomiChatLinkRoute: Equatable {
    case server
    case client
    case refused
}

public struct TellomiChatLinkFields: Equatable {
    public var title: String?
    public var text: String?
    public var siteName: String?
    /// Bits 3–6. Bits 0–2 stay with the caller.
    public var flags: Int32

    public init(title: String?, text: String?, siteName: String?, flags: Int32) {
        self.title = title
        self.text = text
        self.siteName = siteName
        self.flags = flags
    }
}

public func tellomiChatLinkRoute(_ raw: String) -> TellomiChatLinkRoute {
    guard TellomiDiscoverLink.fetchable(raw) else {
        return .refused
    }
    if tellomiChatLinkIsInternal(raw) {
        return .server
    }
    return .client
}

public func tellomiChatLinkIsInternal(_ raw: String) -> Bool {
    guard let host = TellomiDiscoverLink.host(raw) else {
        return false
    }
    let internalHosts: Set<String> = [
        "tell.cc",
        "www.tell.cc",
        "t.me",
        "www.t.me",
        "telegram.me",
        "www.telegram.me",
        "telegram.dog",
        "www.telegram.dog"
    ]
    return internalHosts.contains(host)
}

/// `author` from a client-submitted card. The bubble must not draw it.
public func tellomiDisplayedWebpageAuthor(_ author: String?) -> String? {
    guard let author else {
        return nil
    }
    if author.caseInsensitiveCompare("unverified") == .orderedSame {
        return nil
    }
    return author
}

/// Clip to the stored lengths. A field whose UTF-8 form is over 16 KiB is omitted.
public func tellomiChatLinkFields(title: String?, text: String?, siteName: String?, hasPhoto: Bool) -> TellomiChatLinkFields {
    let title = tellomiChatLinkField(title, limit: 128)
    let text = tellomiChatLinkField(text, limit: 400)
    let siteName = tellomiChatLinkField(siteName, limit: 64)
    var flags: Int32 = 0
    if title != nil {
        flags |= 1 << 3
    }
    if text != nil {
        flags |= 1 << 4
    }
    if siteName != nil {
        flags |= 1 << 5
    }
    if hasPhoto {
        flags |= 1 << 6
    }
    return TellomiChatLinkFields(title: title, text: text, siteName: siteName, flags: flags)
}

private func tellomiChatLinkField(_ raw: String?, limit: Int) -> String? {
    guard let raw else {
        return nil
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return nil
    }
    if trimmed.utf8.count > 16 * 1024 {
        return nil
    }
    if trimmed.count <= limit {
        return trimmed
    }
    return String(trimmed.prefix(limit))
}
