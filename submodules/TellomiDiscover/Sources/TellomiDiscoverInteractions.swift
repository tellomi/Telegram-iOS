import Foundation

/// Direct repost is `PUT` / `DELETE /v1/feed/posts/{id}/repost` (content-engine #43).
/// A quote is the same `POST /v1/feed/posts` body with `quote_of`.
/// Sharing uses `https://tell.cc/m#<id>`. All four are only offered when the card is `shareable`.
public enum TellomiDiscoverShareAction: Equatable {
    case repost
    case unrepost
    case quote
    case shareInChat
    case shareExternal
}

public func tellomiDiscoverShareActions(shareable: Bool, reposted: Bool) -> [TellomiDiscoverShareAction] {
    guard shareable else {
        return []
    }
    if reposted {
        return [.unrepost, .quote, .shareInChat, .shareExternal]
    }
    return [.repost, .quote, .shareInChat, .shareExternal]
}

public func tellomiDiscoverShareURL(postId: String) -> URL? {
    guard let identifier = tellomiDiscoverPostId(postId) else {
        return nil
    }
    return URL(string: "https://tell.cc/m#\(identifier)")
}

public let tellomiDiscoverPollOptionMinimum = 2
public let tellomiDiscoverPollOptionLimit = 10
public let tellomiDiscoverPollOptionTextLimit = 100

public struct TellomiDiscoverPollOption: Equatable {
    public var text: String
    public var votes: Int

    public init(text: String, votes: Int) {
        self.text = text
        self.votes = votes
    }
}

public struct TellomiDiscoverPoll: Equatable {
    public var options: [TellomiDiscoverPollOption]
    /// Index into `options` after this account has voted. Missing means not voted.
    public var myVote: Int?

    public init(options: [TellomiDiscoverPollOption], myVote: Int?) {
        self.options = options
        self.myVote = myVote
    }
}

/// Trimmed options, in order. Fewer than 2, more than 10, a blank, a newline,
/// or an option over 100 characters is not a poll.
public func tellomiDiscoverNormalizedPollOptions(_ raw: [String]) -> [String]? {
    var options: [String] = []
    for value in raw {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            continue
        }
        guard text.count <= tellomiDiscoverPollOptionTextLimit, !text.contains(where: { $0.isNewline }) else {
            return nil
        }
        options.append(text)
    }
    guard options.count >= tellomiDiscoverPollOptionMinimum, options.count <= tellomiDiscoverPollOptionLimit else {
        return nil
    }
    return options
}

public func tellomiDiscoverVoteBody(option: Int) -> Data? {
    guard option >= 0, option < tellomiDiscoverPollOptionLimit else {
        return nil
    }
    return try? JSONSerialization.data(withJSONObject: ["option": option], options: [])
}

/// teamgram `push.DiscoverNotifyUserID` (@faxian). `account.updateNotifySettings`
/// on this user is the discover push switch. `mute_until <= 0` sends; a future
/// time, including `Int32.max`, does not. Muting private chats does not.
public let tellomiDiscoverNotifyUserId: Int64 = 777005

public func tellomiDiscoverNotificationsEnabled(muteUntil: Int32?, now: Int64) -> Bool {
    guard let muteUntil, muteUntil > 0 else {
        return true
    }
    return Int64(muteUntil) <= now
}
