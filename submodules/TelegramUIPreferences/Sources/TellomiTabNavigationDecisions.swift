import Foundation
import TellomiLinks

public struct TellomiTabCopy: Equatable {
    public var feed: String
    public var chats: String
    /// Tab-bar label of the existing settings controller. Not `Settings_Title`, and not the page title.
    public var me: String
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
            chats: text("Tellomi.Tabs.Chats", "Chats", "聊天", "聊天"),
            me: text("Tellomi.Tabs.Me", "Me", "我", "我"),
            hideFeed: text("Tellomi.Discover.HideFeed", "Hide Discover", "隐藏发现", "隱藏發現"),
            hideContacts: text("Tellomi.Discover.HideContacts", "Hide Contacts", "隐藏联系人", "隱藏聯絡人"),
            navigationTitle: text("Tellomi.Discover.NavigationTitle", "Navigation Bar", "导航栏", "導覽列"),
            navigationFooter: text("Tellomi.Discover.NavigationFooter", "Discover, Chats, and Me always stay in the bar.", "发现、聊天和我始终显示，不能关闭。", "發現、聊天和我始終顯示，不能關閉。"),
            feedEmptyTitle: text("Tellomi.Discover.FeedEmptyTitle", "Nothing here yet", "还没有内容", "還沒有內容"),
            feedEmptyText: text("Tellomi.Discover.FeedEmptyText", "Posts will show up here.", "帖子会显示在这里。", "貼文會顯示在這裡。"),
            feedPostUnavailable: text("Tellomi.Discover.FeedPostUnavailable", "This post can't be opened yet.", "这条帖子暂时无法打开。", "這則貼文暫時無法打開。")
        )
    }
}

public enum TellomiRootTab: Equatable {
    case feed
    case chats
    case calls
    case contacts
    /// Upstream News. The product bar does not show it. The kill switch still can.
    case news
    case settings
}

/// The product bar is Discover, Chats, then the settings controller labeled Me.
/// The visibility flags do not add or remove items. The kill switch does not call this:
/// that path keeps the upstream controllers.
public func tellomiRootTabOrder(showFeedTab: Bool, showCallsTab: Bool, showContactsTab: Bool, showNewsTab: Bool) -> [TellomiRootTab] {
    let _ = (showFeedTab, showCallsTab, showContactsTab, showNewsTab)
    return [.feed, .chats, .settings]
}

/// Restoring an account switch still lands on the settings controller. Otherwise the bar opens on Chats.
public func tellomiStartupTabIndex(order: [TellomiRootTab], restoreSettings: Bool) -> Int {
    if restoreSettings, let index = order.lastIndex(of: .settings) {
        return index
    }
    return order.firstIndex(of: .chats) ?? 0
}

public enum TellomiTabControllerKind: Equatable {
    case feed
    case chats
    case calls
    case contacts
    case news
    case settings
}

/// Index of a controller in the built bar. Nil when that controller is not a tab.
/// Selection uses this kind, not a hard-coded upstream slot.
public func tellomiTabIndex(of kind: TellomiTabControllerKind, order: [TellomiRootTab]) -> Int? {
    let tab: TellomiRootTab
    switch kind {
    case .feed:
        tab = .feed
    case .chats:
        tab = .chats
    case .calls:
        tab = .calls
    case .contacts:
        tab = .contacts
    case .news:
        tab = .news
    case .settings:
        tab = .settings
    }
    return order.firstIndex(of: tab)
}

/// The settings controller's tab label. `pageTitle` is what the page already shows and is not replaced.
public func tellomiSettingsTabBarTitle(copy: TellomiTabCopy, pageTitle: String) -> String {
    let _ = pageTitle
    return copy.me
}

public func tellomiSettingsPageTitle(_ pageTitle: String) -> String {
    return pageTitle
}

/// VoiceOver reads the same string the tab draws.
public func tellomiTabBarAccessibilityLabel(title: String) -> String {
    return title
}

public func tellomiProductTabLabels(copy: TellomiTabCopy) -> [(title: String, accessibilityLabel: String)] {
    return [copy.feed, copy.chats, copy.me].map { title in
        return (title, tellomiTabBarAccessibilityLabel(title: title))
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
