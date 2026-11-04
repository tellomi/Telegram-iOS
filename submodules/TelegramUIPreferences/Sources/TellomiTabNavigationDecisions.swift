import Foundation
import TellomiLinks

public struct TellomiTabCopy: Equatable {
    public var feed: String
    public var hideFeed: String
    public var hideContacts: String
    public var navigationTitle: String
    public var navigationFooter: String
    public var feedEmptyTitle: String
    public var feedEmptyText: String
    public var feedPostUnavailable: String

    public static func resolve(languageCode: String) -> TellomiTabCopy {
        if tellomiTabLanguageIsChinese(languageCode) {
            return TellomiTabCopy(
                feed: "发现",
                hideFeed: "隐藏发现",
                hideContacts: "隐藏联系人",
                navigationTitle: "导航栏",
                navigationFooter: "聊天和设置始终显示，不能关闭。",
                feedEmptyTitle: "还没有内容",
                feedEmptyText: "帖子会显示在这里。",
                feedPostUnavailable: "这条帖子暂时无法打开。"
            )
        }
        return TellomiTabCopy(
            feed: "Discover",
            hideFeed: "Hide Discover",
            hideContacts: "Hide Contacts",
            navigationTitle: "Navigation Bar",
            navigationFooter: "Chats and Settings always stay in the bar.",
            feedEmptyTitle: "Nothing here yet",
            feedEmptyText: "Posts will show up here.",
            feedPostUnavailable: "This post can't be opened yet."
        )
    }
}

private func tellomiTabLanguageIsChinese(_ code: String) -> Bool {
    let value = code.lowercased()
    return value == "zh" || value.hasPrefix("zh-")
}

/// `https://tell.cc/m#<id>` (D-57). `https://tell.cc/m/<slug>` stays a message link.
public func tellomiFeedPostId(in url: URL) -> String? {
    guard let host = url.host?.lowercased() else {
        return nil
    }
    guard host == TellomiLinks.host || host == "www.\(TellomiLinks.host)" else {
        return nil
    }
    guard url.path == "/m" || url.path == "/m/" else {
        return nil
    }
    guard let fragment = url.fragment else {
        return nil
    }
    let identifier = (fragment.removingPercentEncoding ?? fragment).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !identifier.isEmpty else {
        return nil
    }
    return identifier
}

/// The post id the bar should open. Nil means the normal opener keeps the link.
/// The kill switch (`navigationEnabled == false`) must not swallow a post link.
public func tellomiFeedPostIdIfHandled(in url: URL, navigationEnabled: Bool) -> String? {
    guard navigationEnabled else {
        return nil
    }
    return tellomiFeedPostId(in: url)
}

/// What `getContactsController` may return. None of these create or push a page.
/// Opening Contacts while the tab is hidden is `openContacts`.
public enum TellomiContactsControllerRead: Equatable {
    /// The bar is off, or it is not built yet. The getter keeps the controller it already holds.
    case owned
    /// The contacts tab is in the bar.
    case tab
    /// The tab is hidden and a contacts page is already on the stack.
    case pushed
    /// The tab is hidden and nothing is pushed. The getter must not create a page.
    case none
}

public func tellomiContactsControllerRead(navigationEnabled: Bool, tabBarReady: Bool, tabVisible: Bool, pushedPageExists: Bool) -> TellomiContactsControllerRead {
    guard navigationEnabled else {
        return .owned
    }
    guard tabBarReady else {
        return .owned
    }
    if tabVisible {
        return .tab
    }
    if pushedPageExists {
        return .pushed
    }
    return .none
}
