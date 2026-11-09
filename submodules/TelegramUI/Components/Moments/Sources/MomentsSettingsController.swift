import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import PresentationDataUtils

private final class MomentsSettingsArguments {
    let toggle: (String, Bool) -> Void
    let visibility: (Bool) -> Void
    init(toggle: @escaping (String, Bool) -> Void, visibility: @escaping (Bool) -> Void) {
        self.toggle = toggle
        self.visibility = visibility
    }
}

private enum MomentsSettingsEntry: ItemListNodeEntry {
    case header(String)
    case following(String, String)
    case followers(String, String)
    case comments(String, Bool)
    case replies(String, Bool)
    case mentions(String, Bool)
    case follows(String, Bool)
    case likes(String, Bool)
    case reposts(String, Bool)
    case newPosts(String, Bool)
    case footer(String)

    var section: ItemListSectionId { return 0 }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case .following: return 1
        case .followers: return 2
        case .comments: return 3
        case .replies: return 4
        case .mentions: return 5
        case .follows: return 6
        case .likes: return 7
        case .reposts: return 8
        case .newPosts: return 9
        case .footer: return 10
        }
    }

    static func <(lhs: MomentsSettingsEntry, rhs: MomentsSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    static func ==(lhs: MomentsSettingsEntry, rhs: MomentsSettingsEntry) -> Bool {
        switch lhs {
        case let .header(text):
            if case .header(text) = rhs { return true } else { return false }
        case let .following(title, value):
            if case .following(title, value) = rhs { return true } else { return false }
        case let .followers(title, value):
            if case .followers(title, value) = rhs { return true } else { return false }
        case let .comments(title, value):
            if case .comments(title, value) = rhs { return true } else { return false }
        case let .replies(title, value):
            if case .replies(title, value) = rhs { return true } else { return false }
        case let .mentions(title, value):
            if case .mentions(title, value) = rhs { return true } else { return false }
        case let .follows(title, value):
            if case .follows(title, value) = rhs { return true } else { return false }
        case let .likes(title, value):
            if case .likes(title, value) = rhs { return true } else { return false }
        case let .reposts(title, value):
            if case .reposts(title, value) = rhs { return true } else { return false }
        case let .newPosts(title, value):
            if case .newPosts(title, value) = rhs { return true } else { return false }
        case let .footer(text):
            if case .footer(text) = rhs { return true } else { return false }
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MomentsSettingsArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .following(title, value), let .followers(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.visibility(true)
            })
        case let .comments(title, value):
            return self.switchItem(presentationData, arguments, "comments", title, value)
        case let .replies(title, value):
            return self.switchItem(presentationData, arguments, "replies", title, value)
        case let .mentions(title, value):
            return self.switchItem(presentationData, arguments, "mentions", title, value)
        case let .follows(title, value):
            return self.switchItem(presentationData, arguments, "follows", title, value)
        case let .likes(title, value):
            return self.switchItem(presentationData, arguments, "likes", title, value)
        case let .reposts(title, value):
            return self.switchItem(presentationData, arguments, "reposts", title, value)
        case let .newPosts(title, value):
            return self.switchItem(presentationData, arguments, "new", title, value)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }

    private func switchItem(_ presentationData: ItemListPresentationData, _ arguments: MomentsSettingsArguments, _ id: String, _ title: String, _ value: Bool) -> ListViewItem {
        return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { updated in
            arguments.toggle(id, updated)
        })
    }
}

public func momentsPrivacyController(context: AccountContext) -> ViewController {
    var settings = MomentsNotificationSettings.defaults
    var lists = MomentsListVisibilitySettings.defaults
    let state = Promise<(MomentsNotificationSettings, MomentsListVisibilitySettings)>()
    state.set(.single((settings, lists)))
    let _ = (context.engine.moments.notificationSettings() |> deliverOnMainQueue).start(next: { value in
        settings = value
        state.set(.single((settings, lists)))
    })
    let _ = (context.engine.moments.listVisibility() |> deliverOnMainQueue).start(next: { value in
        lists = value
        state.set(.single((settings, lists)))
    })
    let arguments = MomentsSettingsArguments(toggle: { id, value in
        switch id {
        case "comments": settings.comments = value
        case "replies": settings.replies = value
        case "mentions": settings.mentions = value
        case "follows": settings.follows = value
        case "likes": settings.likes = value
        case "reposts": settings.reposts = value
        case "new": settings.newPosts = value
        default: break
        }
        state.set(.single((settings, lists)))
        let _ = context.engine.moments.updateNotificationSettings(settings).start()
    }, visibility: { _ in
        lists.followingList = lists.followingList == .everyone ? .onlyMe : .everyone
        lists.followersList = lists.followingList
        state.set(.single((settings, lists)))
        let _ = context.engine.moments.updateListVisibility(lists).start()
    })
    let signal = combineLatest(context.sharedContext.presentationData, state.get())
    |> map { presentationData, values -> (ItemListControllerState, (ItemListNodeState, MomentsSettingsArguments)) in
        let (push, visibility) = values
        let strings = presentationData.strings
        let who = visibility.followingList == .everyone ? momentsText(strings, .settingsPublic) : momentsText(strings, .settingsOnlyMe)
        let entries: [MomentsSettingsEntry] = [
            .header(momentsText(strings, .settingsTitle)),
            .following(momentsText(strings, .settingsFollowing), who),
            .followers(momentsText(strings, .settingsFollowers), who),
            .comments(momentsText(strings, .pushComments), push.comments),
            .replies(momentsText(strings, .pushReplies), push.replies),
            .mentions(momentsText(strings, .pushMentions), push.mentions),
            .follows(momentsText(strings, .pushFollows), push.follows),
            .likes(momentsText(strings, .pushLikes), push.likes),
            .reposts(momentsText(strings, .pushReposts), push.reposts),
            .newPosts(momentsText(strings, .pushNewPosts), push.newPosts),
            .footer(momentsText(strings, .friendsHint))
        ]
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(momentsText(strings, .settingsTitle)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (listState, arguments))
    }
    return ItemListController(context: context, state: signal)
}
