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

/// The shared profile opening. A known snapshot is emitted as it is, so a second
/// visit does not drop the tab while the same request is replayed. The first visit
/// emits `.unknown` before the cache and the network, and does not hold the page.
public func momentsProfilePostsPresence(context: AccountContext, peerId: EnginePeer.Id) -> Signal<MomentsProfilePostsPresence, NoError> {
    let id = "\(peerId.toInt64())"
    let opened = context.engine.moments.openProfilePosts(id: id)
    |> map { snapshot -> MomentsProfilePostsPresence in
        return snapshot.presence
    }
    if context.engine.moments.latestProfilePosts(id: id) != nil {
        return opened |> distinctUntilChanged
    }
    return .single(.unknown)
    |> then(opened)
    |> distinctUntilChanged
}

/// Profile tab title for native Stories. Chinese shows 快拍 so it does not repeat Moments (动态).
public func momentsProfileStoriesTabTitle(_ strings: PresentationStrings) -> String {
    return momentsProfileStoriesTabTitle(resolved: strings.PeerInfo_PaneStories, languageCodes: [strings.primaryComponent.languageCode, strings.baseLanguageCode])
}
