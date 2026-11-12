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
    let personalized: (Bool) -> Void
    init(toggle: @escaping (String, Bool) -> Void, visibility: @escaping (Bool) -> Void, personalized: @escaping (Bool) -> Void) {
        self.toggle = toggle
        self.visibility = visibility
        self.personalized = personalized
    }
}

private final class MomentsSettingsHolder {
    var push = MomentsNotificationSettings.defaults
    var lists = MomentsListVisibilitySettings.defaults
    var personalized = true
    var showPersonalized = false
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
    case recommendationsHeader(String)
    case personalized(String, Bool)
    case personalizedInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .recommendationsHeader, .personalized, .personalizedInfo:
            return 1
        default:
            return 0
        }
    }

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
        case .recommendationsHeader: return 11
        case .personalized: return 12
        case .personalizedInfo: return 13
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
        case let .recommendationsHeader(text):
            if case .recommendationsHeader(text) = rhs { return true } else { return false }
        case let .personalized(title, value):
            if case .personalized(title, value) = rhs { return true } else { return false }
        case let .personalizedInfo(text):
            if case .personalizedInfo(text) = rhs { return true } else { return false }
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
        case let .footer(text), let .personalizedInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .recommendationsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .personalized(title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { updated in
                arguments.personalized(updated)
            })
        }
    }

    private func switchItem(_ presentationData: ItemListPresentationData, _ arguments: MomentsSettingsArguments, _ id: String, _ title: String, _ value: Bool) -> ListViewItem {
        return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { updated in
            arguments.toggle(id, updated)
        })
    }
}

public func momentsPrivacyController(context: AccountContext) -> ViewController {
    let holder = MomentsSettingsHolder()
    holder.personalized = context.engine.moments.recommendIsPersonalized()
    let state = Promise<(MomentsNotificationSettings, MomentsListVisibilitySettings, Bool, Bool)>()
    let publish = {
        state.set(.single((holder.push, holder.lists, holder.personalized, holder.showPersonalized)))
    }
    publish()
    let _ = (context.engine.moments.notificationSettings() |> deliverOnMainQueue).start(next: { value in
        holder.push = value
        publish()
    })
    let _ = (context.engine.moments.listVisibility() |> deliverOnMainQueue).start(next: { value in
        holder.lists = value
        publish()
    })
    let _ = (context.engine.moments.remoteConfig() |> deliverOnMainQueue).start(next: { config in
        holder.showPersonalized = config.personalizationToggleVisible
        publish()
    })
    let _ = (context.engine.moments.reloadPersonalizedRecommendations() |> deliverOnMainQueue).start(next: { value in
        holder.personalized = value
        publish()
    })
    let arguments = MomentsSettingsArguments(toggle: { id, value in
        switch id {
        case "comments": holder.push.comments = value
        case "replies": holder.push.replies = value
        case "mentions": holder.push.mentions = value
        case "follows": holder.push.follows = value
        case "likes": holder.push.likes = value
        case "reposts": holder.push.reposts = value
        case "new": holder.push.newPosts = value
        default: break
        }
        publish()
        let _ = context.engine.moments.updateNotificationSettings(holder.push).start()
    }, visibility: { _ in
        holder.lists.followingList = holder.lists.followingList == .everyone ? .onlyMe : .everyone
        holder.lists.followersList = holder.lists.followingList
        publish()
        let _ = context.engine.moments.updateListVisibility(holder.lists).start()
    }, personalized: { value in
        let previous = holder.personalized
        holder.personalized = value
        publish()
        let _ = (context.engine.moments.updatePersonalizedRecommendations(value) |> deliverOnMainQueue).start(error: { _ in
            guard holder.personalized == value else {
                return
            }
            holder.personalized = previous
            context.engine.moments.setPersonalizedRecommendations(previous)
            publish()
        })
    })
    let signal = combineLatest(context.sharedContext.presentationData, state.get())
    |> map { presentationData, values -> (ItemListControllerState, (ItemListNodeState, MomentsSettingsArguments)) in
        let (push, visibility, personalized, showPersonalized) = values
        let strings = presentationData.strings
        let who = visibility.followingList == .everyone ? strings.Moments_Settings_Public : strings.Moments_Settings_OnlyMe
        var entries: [MomentsSettingsEntry] = [
            .header(strings.Moments_Settings_Title),
            .following(strings.Moments_Settings_FollowingList, who),
            .followers(strings.Moments_Settings_FollowersList, who),
            .comments(strings.Moments_Push_Comments, push.comments),
            .replies(strings.Moments_Push_Replies, push.replies),
            .mentions(strings.Moments_Push_Mentions, push.mentions),
            .follows(strings.Moments_Push_Follows, push.follows),
            .likes(strings.Moments_Push_Likes, push.likes),
            .reposts(strings.Moments_Push_Reposts, push.reposts),
            .newPosts(strings.Moments_Push_NewPosts, push.newPosts),
            .footer(strings.Moments_FriendsHint)
        ]
        if showPersonalized {
            entries.append(.recommendationsHeader(strings.Moments_Settings_Recommendations))
            entries.append(.personalized(strings.Moments_Settings_Personalized, personalized))
            entries.append(.personalizedInfo(strings.Moments_Settings_PersonalizedInfo))
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(strings.Moments_Settings_Title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (listState, arguments))
    }
    return ItemListController(context: context, state: signal)
}
