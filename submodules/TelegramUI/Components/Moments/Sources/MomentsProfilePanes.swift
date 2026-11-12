import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import PeerInfoPaneNode

/// User profiles keep native Stories. Moments is inserted only when the profile
/// posts page is non-empty. Channels and groups are unchanged. A nil list stays nil.
public func momentsUserProfilePanes(_ panes: [PeerInfoPaneKey]?, isUserProfile: Bool, posts: MomentsProfilePostsPresence) -> [PeerInfoPaneKey]? {
    return momentsProfileTabs(panes, isUserProfile: isUserProfile, posts: posts, isStories: { $0 == .stories }, moments: .moments)
}

/// Emits `.unknown` immediately, then `.present` or `.empty` from
/// `GET /v1/feed/profiles/{id}/posts`. The first value lets the profile render
/// before this request returns. A failed request hides the pane.
public func momentsProfilePostsPresence(context: AccountContext, peerId: EnginePeer.Id) -> Signal<MomentsProfilePostsPresence, NoError> {
    let loaded = context.engine.moments.profilePosts(id: "\(peerId.toInt64())", filter: "posts", cursor: nil)
    |> map { page -> MomentsProfilePostsPresence in
        return momentsProfilePostsPresence(itemCount: page.items.count)
    }
    |> `catch` { _ -> Signal<MomentsProfilePostsPresence, NoError> in
        return .single(.empty)
    }
    return .single(.unknown)
    |> then(loaded)
}

/// Profile tab title for native Stories. Chinese shows 快拍 so it does not repeat Moments (动态).
public func momentsProfileStoriesTabTitle(_ strings: PresentationStrings) -> String {
    return momentsProfileStoriesTabTitle(resolved: strings.PeerInfo_PaneStories, languageCodes: [strings.primaryComponent.languageCode, strings.baseLanguageCode])
}
