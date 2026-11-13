import Foundation
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
//import PhoneNumberFormat

private func tellomiIsOfficialServiceAccount(_ peerId: EnginePeer.Id) -> Bool {
    if peerId.isTelegramNotifications {
        return true
    }
    return peerId.namespace == Namespaces.Peer.CloudUser && peerId.id._internalGetInt64Value() == 333000
}

/// The service and notification accounts are client placeholders when they have no photo.
/// A server name that still says Telegram is shown as Tellomi. Any other name is kept.
private func tellomiServiceAccountTitle(peerId: EnginePeer.Id, name: String) -> String {
    guard tellomiIsOfficialServiceAccount(peerId) else {
        return name
    }
    let rewritten = tellomiRewriteBrand(name)
    return rewritten.isEmpty ? "Tellomi" : rewritten
}

public extension EnginePeer {
    var compactDisplayTitle: String {
        switch self {
        case let .user(user):
            let name: String
            if let firstName = user.firstName, !firstName.isEmpty {
                name = firstName
            } else if let lastName = user.lastName, !lastName.isEmpty {
                name = lastName
            } else if let _ = user.phone {
                name = "" //formatPhoneNumber("+\(phone)")
            } else if tellomiIsOfficialServiceAccount(user.id) {
                name = "Tellomi"
            } else {
                name = "Deleted Account"
            }
            return tellomiServiceAccountTitle(peerId: user.id, name: name)
        case let .legacyGroup(group):
            return group.title
        case let .channel(channel):
            return channel.title
        case let .community(community):
            return community.title
        case .secretChat:
            return ""
        }
    }

    func displayTitle(strings: PresentationStrings, displayOrder: PresentationPersonNameOrder) -> String {
        switch self {
        case let .user(user):
            if user.id.isReplies {
                return strings.DialogList_Replies
            }
            let name: String
            if let firstName = user.firstName, !firstName.isEmpty {
                if let lastName = user.lastName, !lastName.isEmpty {
                    switch displayOrder {
                    case .firstLast:
                        name = "\(firstName) \(lastName)"
                    case .lastFirst:
                        name = "\(lastName) \(firstName)"
                    }
                } else {
                    name = firstName
                }
            } else if let lastName = user.lastName, !lastName.isEmpty {
                name = lastName
            } else if let _ = user.phone {
                name = "" //formatPhoneNumber("+\(phone)")
            } else if tellomiIsOfficialServiceAccount(user.id) {
                name = "Tellomi"
            } else {
                name = strings.User_DeletedAccount
            }
            return tellomiServiceAccountTitle(peerId: user.id, name: name)
        case let .legacyGroup(group):
            return group.title
        case let .channel(channel):
            return channel.title
        case let .community(community):
            return community.title
        case .secretChat:
            return ""
        }
    }
}

public extension EnginePeer.IndexName {
    func isLessThan(other: EnginePeer.IndexName, ordering: PresentationPersonNameOrder) -> ComparisonResult {
        switch self {
        case let .title(lhsTitle, _):
            let rhsString: String
            switch other {
            case let .title(title, _):
                rhsString = title
            case let .personName(first, last, _, _):
                switch ordering {
                case .firstLast:
                    if first.isEmpty {
                        rhsString = last
                    } else {
                        rhsString = first + last
                    }
                case .lastFirst:
                    if last.isEmpty {
                        rhsString = first
                    } else {
                        rhsString = last + first
                    }
                }
            }
            return lhsTitle.caseInsensitiveCompare(rhsString)
        case let .personName(lhsFirst, lhsLast, _, _):
            let lhsString: String
            switch ordering {
            case .firstLast:
                if lhsFirst.isEmpty {
                    lhsString = lhsLast
                } else {
                    lhsString = lhsFirst + lhsLast
                }
            case .lastFirst:
                if lhsLast.isEmpty {
                    lhsString = lhsFirst
                } else {
                    lhsString = lhsLast + lhsFirst
                }
            }
            let rhsString: String
            switch other {
            case let .title(title, _):
                rhsString = title
            case let .personName(first, last, _, _):
                switch ordering {
                case .firstLast:
                    if first.isEmpty {
                        rhsString = last
                    } else {
                        rhsString = first + last
                    }
                case .lastFirst:
                    if last.isEmpty {
                        rhsString = first
                    } else {
                        rhsString = last + first
                    }
                }
            }
            return lhsString.caseInsensitiveCompare(rhsString)
        }
    }
}
