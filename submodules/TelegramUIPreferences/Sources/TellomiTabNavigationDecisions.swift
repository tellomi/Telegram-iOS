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

    public static func resolve(languageCode: String, pack: [String: String] = [:]) -> TellomiTabCopy {
        func text(_ key: String, _ english: String, _ simplified: String, _ traditional: String) -> String {
            return tellomiTabPackString(languageCode: languageCode, pack: pack, key: key, english: english, simplified: simplified, traditional: traditional)
        }
        return TellomiTabCopy(
            feed: text("Tellomi.Discover.Feed", "Discover", "发现", "發現"),
            hideFeed: text("Tellomi.Discover.HideFeed", "Hide Discover", "隐藏发现", "隱藏發現"),
            hideContacts: text("Tellomi.Discover.HideContacts", "Hide Contacts", "隐藏联系人", "隱藏聯絡人"),
            navigationTitle: text("Tellomi.Discover.NavigationTitle", "Navigation Bar", "导航栏", "導覽列"),
            navigationFooter: text("Tellomi.Discover.NavigationFooter", "Chats and Settings always stay in the bar.", "聊天和设置始终显示，不能关闭。", "聊天和設定始終顯示，不能關閉。"),
            feedEmptyTitle: text("Tellomi.Discover.FeedEmptyTitle", "Nothing here yet", "还没有内容", "還沒有內容"),
            feedEmptyText: text("Tellomi.Discover.FeedEmptyText", "Posts will show up here.", "帖子会显示在这里。", "貼文會顯示在這裡。"),
            feedPostUnavailable: text("Tellomi.Discover.FeedPostUnavailable", "This post can't be opened yet.", "这条帖子暂时无法打开。", "這則貼文暫時無法打開。")
        )
    }
}

func tellomiTabPackString(languageCode: String, pack: [String: String], key: String, english: String, simplified: String, traditional: String) -> String {
    if let value = pack[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, value != key {
        return value
    }
    let code = languageCode.lowercased()
    if code == "zh-hant" || code.hasPrefix("zh-hant") || code == "zh-tw" || code.hasPrefix("zh-tw") || code == "zh-hk" || code.hasPrefix("zh-hk") || code == "zh-mo" || code.hasPrefix("zh-mo") {
        return traditional
    }
    if code == "zh" || code.hasPrefix("zh") {
        return simplified
    }
    return english
}

public func tellomiStringPack(primary: [String: String], secondary: [String: String]?) -> [String: String] {
    var pack: [String: String] = [:]
    if let secondary {
        for (key, value) in secondary {
            pack[key] = value
        }
    }
    for (key, value) in primary {
        pack[key] = value
    }
    return pack
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

/// A chat tap resolves `tell.cc/<name>` as a username. `tell.cc/m#<id>` would
/// become the user `m` and never reopen Discover (D-57). True means `resolveUrl`
/// must hand the address to the external opener, which turns Discover back on
/// and opens the post. The kill switch stays on the username path.
public func tellomiFeedPostLinkEscapesPeerResolution(_ url: String, navigationEnabled: Bool) -> Bool {
    guard let parsed = URL(string: url) else {
        return false
    }
    return tellomiFeedPostIdIfHandled(in: parsed, navigationEnabled: navigationEnabled) != nil
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
