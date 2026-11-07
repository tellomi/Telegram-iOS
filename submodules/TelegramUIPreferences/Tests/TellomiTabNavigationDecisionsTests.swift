import XCTest

final class TellomiTabNavigationDecisionsTests: XCTestCase {
    func testDiscoverEmptyStateCopyIsTellomiTabCopy() {
        let chinese = TellomiTabCopy.resolve(languageCode: "zh-Hans")
        XCTAssertEqual(chinese.feed, "发现")
        XCTAssertEqual(chinese.chats, "聊天")
        XCTAssertEqual(chinese.me, "我")
        XCTAssertEqual(chinese.hideFeed, "隐藏发现")
        XCTAssertEqual(chinese.hideContacts, "隐藏联系人")
        XCTAssertEqual(chinese.navigationTitle, "导航栏")
        XCTAssertEqual(chinese.feedEmptyTitle, "还没有内容")
        XCTAssertEqual(chinese.feedEmptyText, "帖子会显示在这里。")
        XCTAssertEqual(chinese.feedPostUnavailable, "这条帖子暂时无法打开。")

        let english = TellomiTabCopy.resolve(languageCode: "en")
        XCTAssertEqual(english.feed, "Discover")
        XCTAssertEqual(english.chats, "Chats")
        XCTAssertEqual(english.me, "Me")
        XCTAssertEqual(english.hideFeed, "Hide Discover")
        XCTAssertEqual(english.hideContacts, "Hide Contacts")
        XCTAssertEqual(english.navigationTitle, "Navigation Bar")
        XCTAssertEqual(english.navigationFooter, "Chats and Settings always stay in the bar.")
        XCTAssertEqual(english.feedEmptyTitle, "Nothing here yet")
        XCTAssertEqual(english.feedEmptyText, "Posts will show up here.")
        XCTAssertEqual(english.feedPostUnavailable, "This post can't be opened yet.")

        XCTAssertEqual(TellomiTabCopy.resolve(languageCode: "ZH").feed, "发现")
        XCTAssertEqual(TellomiTabCopy.resolve(languageCode: "zh").feedEmptyTitle, "还没有内容")
        XCTAssertEqual(TellomiTabCopy.resolve(languageCode: "en-US").feed, "Discover")
        XCTAssertEqual(TellomiTabCopy.resolve(languageCode: "de").feedPostUnavailable, "This post can't be opened yet.")
        XCTAssertEqual(TellomiTabCopy.resolve(languageCode: "zh-Hant").feed, "發現")
        XCTAssertEqual(TellomiTabCopy.resolve(languageCode: "zh-Hant").chats, "聊天")
        XCTAssertEqual(TellomiTabCopy.resolve(languageCode: "zh-Hant").me, "我")
        XCTAssertEqual(TellomiTabCopy.resolve(languageCode: "zh-Hans").navigationFooter, "聊天和设置始终显示，不能关闭。")
        XCTAssertEqual(TellomiTabCopy.resolve(languageCode: "ja").feed, "Discover")
        let japanese = ["Tellomi.Discover.Feed": "発見"]
        XCTAssertEqual(TellomiTabCopy.resolve(languageCode: "ja", pack: japanese).feed, "発見")
        XCTAssertEqual(TellomiTabCopy.resolve(languageCode: "zh-Hans", pack: japanese).navigationTitle, "导航栏")
    }

    func testAPostLinkIsNotHandledWhenTheBarIsOff() {
        let post = URL(string: "https://tell.cc/m#example")!
        XCTAssertEqual(tellomiFeedPostId(in: post), "example")
        XCTAssertNil(tellomiFeedPostIdIfHandled(in: post, navigationEnabled: false))
        XCTAssertEqual(tellomiFeedPostIdIfHandled(in: post, navigationEnabled: true), "example")

        let upperHost = URL(string: "https://TELL.CC/m#example")!
        XCTAssertEqual(tellomiFeedPostIdIfHandled(in: upperHost, navigationEnabled: true), "example")
        XCTAssertNil(tellomiFeedPostIdIfHandled(in: upperHost, navigationEnabled: false))

        let www = URL(string: "https://www.tell.cc/m/#example%20id")!
        XCTAssertEqual(tellomiFeedPostIdIfHandled(in: www, navigationEnabled: true), "example id")
        XCTAssertNil(tellomiFeedPostIdIfHandled(in: www, navigationEnabled: false))

        let withQuery = URL(string: "https://tell.cc/m?x=1#example")!
        XCTAssertEqual(tellomiFeedPostIdIfHandled(in: withQuery, navigationEnabled: true), "example")

        let slug = URL(string: "https://tell.cc/m/some-slug")!
        XCTAssertNil(tellomiFeedPostId(in: slug))
        XCTAssertNil(tellomiFeedPostIdIfHandled(in: slug, navigationEnabled: true))
        XCTAssertNil(tellomiFeedPostIdIfHandled(in: slug, navigationEnabled: false))

        XCTAssertNil(tellomiFeedPostIdIfHandled(in: URL(string: "https://t.me/m#example")!, navigationEnabled: true))
        XCTAssertNil(tellomiFeedPostIdIfHandled(in: URL(string: "https://tell.cc/m")!, navigationEnabled: true))
        XCTAssertNil(tellomiFeedPostIdIfHandled(in: URL(string: "https://tell.cc/m#")!, navigationEnabled: true))
        XCTAssertNil(tellomiFeedPostIdIfHandled(in: URL(string: "https://tell.cc/m#%20")!, navigationEnabled: true))
        XCTAssertNil(tellomiFeedPostIdIfHandled(in: URL(string: "https://tell.cc/m/extra#example")!, navigationEnabled: true))
    }

    func testAChatTapOnAPostLinkDoesNotResolveAsTheUserM() {
        XCTAssertTrue(tellomiFeedPostLinkEscapesPeerResolution("https://tell.cc/m#example", navigationEnabled: true))
        XCTAssertTrue(tellomiFeedPostLinkEscapesPeerResolution("https://TELL.CC/m#example", navigationEnabled: true))
        XCTAssertTrue(tellomiFeedPostLinkEscapesPeerResolution("http://tell.cc/m/#example%20id", navigationEnabled: true))
        XCTAssertFalse(tellomiFeedPostLinkEscapesPeerResolution("https://tell.cc/m#example", navigationEnabled: false))
        XCTAssertFalse(tellomiFeedPostLinkEscapesPeerResolution("https://tell.cc/m/some-slug", navigationEnabled: true))
        XCTAssertFalse(tellomiFeedPostLinkEscapesPeerResolution("https://t.me/m#example", navigationEnabled: true))
        XCTAssertFalse(tellomiFeedPostLinkEscapesPeerResolution("https://tell.cc/m", navigationEnabled: true))
        XCTAssertFalse(tellomiFeedPostLinkEscapesPeerResolution("not a url", navigationEnabled: true))
    }

    func testTheContactsGetterDoesNotPush() {
        XCTAssertEqual(
            tellomiContactsControllerRead(navigationEnabled: true, tabBarReady: true, tabVisible: false, pushedPageExists: false),
            .none
        )
        XCTAssertEqual(
            tellomiContactsControllerRead(navigationEnabled: true, tabBarReady: true, tabVisible: false, pushedPageExists: true),
            .pushed
        )
        XCTAssertEqual(
            tellomiContactsControllerRead(navigationEnabled: true, tabBarReady: true, tabVisible: true, pushedPageExists: false),
            .tab
        )
        XCTAssertEqual(
            tellomiContactsControllerRead(navigationEnabled: true, tabBarReady: true, tabVisible: true, pushedPageExists: true),
            .tab
        )
        XCTAssertEqual(
            tellomiContactsControllerRead(navigationEnabled: false, tabBarReady: true, tabVisible: false, pushedPageExists: false),
            .owned
        )
        XCTAssertEqual(
            tellomiContactsControllerRead(navigationEnabled: false, tabBarReady: true, tabVisible: true, pushedPageExists: true),
            .owned
        )
        XCTAssertEqual(
            tellomiContactsControllerRead(navigationEnabled: true, tabBarReady: false, tabVisible: false, pushedPageExists: true),
            .owned
        )
    }

    func testDefaultTabsAreDiscoverChatsThenSettingsAndSwitchesStillInsertTabs() {
        let fresh = tellomiRootTabOrder(showFeedTab: true, showCallsTab: false, showContactsTab: false, showNewsTab: false)
        XCTAssertEqual(fresh, [.feed, .chats, .settings])
        XCTAssertEqual(tellomiTabIndex(of: .feed, order: fresh), 0)
        XCTAssertEqual(tellomiTabIndex(of: .chats, order: fresh), 1)
        XCTAssertEqual(tellomiTabIndex(of: .settings, order: fresh), 2)
        XCTAssertNil(tellomiTabIndex(of: .calls, order: fresh))
        XCTAssertNil(tellomiTabIndex(of: .contacts, order: fresh))
        XCTAssertNil(tellomiTabIndex(of: .news, order: fresh))
        XCTAssertEqual(tellomiStartupTabIndex(order: fresh, restoreSettings: false), 1)
        XCTAssertEqual(tellomiStartupTabIndex(order: fresh, restoreSettings: true), 2)

        let hiddenFeed = tellomiRootTabOrder(showFeedTab: false, showCallsTab: false, showContactsTab: false, showNewsTab: false)
        XCTAssertEqual(hiddenFeed, [.chats, .settings])
        XCTAssertNil(tellomiTabIndex(of: .feed, order: hiddenFeed))
        XCTAssertEqual(tellomiTabIndex(of: .chats, order: hiddenFeed), 0)
        XCTAssertEqual(tellomiTabIndex(of: .settings, order: hiddenFeed), 1)

        let withOptionalTabs = tellomiRootTabOrder(showFeedTab: true, showCallsTab: true, showContactsTab: true, showNewsTab: true)
        XCTAssertEqual(withOptionalTabs, [.feed, .chats, .calls, .contacts, .news, .settings])
        XCTAssertEqual(tellomiTabIndex(of: .calls, order: withOptionalTabs), 2)
        XCTAssertEqual(tellomiTabIndex(of: .contacts, order: withOptionalTabs), 3)
        XCTAssertEqual(tellomiTabIndex(of: .news, order: withOptionalTabs), 4)
        XCTAssertEqual(tellomiTabIndex(of: .settings, order: withOptionalTabs), 5)
        XCTAssertEqual(tellomiStartupTabIndex(order: withOptionalTabs, restoreSettings: false), 1)
        XCTAssertEqual(tellomiStartupTabIndex(order: withOptionalTabs, restoreSettings: true), 5)
    }

    func testTheSettingsTabLabelDoesNotReplaceThePageTitle() {
        let chinese = TellomiTabCopy.resolve(languageCode: "zh-Hans")
        XCTAssertEqual(tellomiSettingsTabBarTitle(copy: chinese, pageTitle: "设置"), "我")
        XCTAssertEqual(tellomiSettingsPageTitle("设置"), "设置")
        XCTAssertNotEqual(tellomiSettingsTabBarTitle(copy: chinese, pageTitle: "设置"), tellomiSettingsPageTitle("设置"))

        let english = TellomiTabCopy.resolve(languageCode: "en")
        XCTAssertEqual(tellomiSettingsTabBarTitle(copy: english, pageTitle: "Settings"), "Me")
        XCTAssertEqual(tellomiSettingsPageTitle("Settings"), "Settings")

        let labels = tellomiProductTabLabels(copy: chinese)
        XCTAssertEqual(labels.map(\.title), ["发现", "聊天", "我"])
        XCTAssertEqual(labels.map(\.accessibilityLabel), labels.map(\.title))
        XCTAssertEqual(tellomiTabBarAccessibilityLabel(title: "我"), "我")
    }

    func testMeTabAvatarDoesNotWaitForAnotherAccountOrAMiss() {
        XCTAssertTrue(tellomiMeTabShowsAccountAvatar(hasAccountPeer: true))
        XCTAssertFalse(tellomiMeTabShowsAccountAvatar(hasAccountPeer: false))
        XCTAssertEqual(tellomiMeTabAvatar(shown: "photo", incoming: nil as String?), "photo")
        XCTAssertEqual(tellomiMeTabAvatar(shown: "photo", incoming: "next"), "next")
        XCTAssertNil(tellomiMeTabAvatar(shown: nil as String?, incoming: nil))
    }
}
