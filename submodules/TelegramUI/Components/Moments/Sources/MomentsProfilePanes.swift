import Foundation
import TelegramCore
import TelegramPresentationData
import PeerInfoPaneNode

/// User profiles keep native Stories and put Moments first. Channels and groups
/// are unchanged. A nil list is still loading and stays nil.
public func momentsUserProfilePanes(_ panes: [PeerInfoPaneKey]?, isUserProfile: Bool) -> [PeerInfoPaneKey]? {
    return momentsProfileTabs(panes, isUserProfile: isUserProfile, moments: .moments)
}

/// Profile tab title for native Stories. Chinese shows 快拍 so it does not repeat Moments (动态).
public func momentsProfileStoriesTabTitle(_ strings: PresentationStrings) -> String {
    return momentsProfileStoriesTabTitle(resolved: strings.PeerInfo_PaneStories, languageCodes: [strings.primaryComponent.languageCode, strings.baseLanguageCode])
}
