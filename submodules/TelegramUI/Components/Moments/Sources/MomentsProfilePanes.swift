import Foundation
import TelegramCore
import PeerInfoPaneNode

/// User profiles: Moments is the first tab, and the native Stories tab is omitted.
/// Channels and groups keep Stories. A nil list is still loading and stays nil.
public func momentsUserProfilePanes(_ panes: [PeerInfoPaneKey]?, isUserProfile: Bool) -> [PeerInfoPaneKey]? {
    return momentsProfileTabs(panes, isUserProfile: isUserProfile, isStories: { $0 == .stories }, moments: .moments)
}
