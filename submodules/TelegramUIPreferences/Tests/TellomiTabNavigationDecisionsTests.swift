import XCTest

final class TellomiTabNavigationDecisionsTests: XCTestCase {
    func testDiscoverEmptyStateCopyIsTellomiTabCopy() {
        let chinese = TellomiTabCopy.resolve(languageCode: "zh-Hans")
        XCTAssertEqual(chinese.feed, "发现")
        XCTAssertEqual(chinese.hideFeed, "隐藏发现")
        XCTAssertEqual(chinese.hideContacts, "隐藏联系人")
        XCTAssertEqual(chinese.navigationTitle, "导航栏")
        XCTAssertEqual(chinese.feedEmptyTitle, "还没有内容")
        XCTAssertEqual(chinese.feedEmptyText, "帖子会显示在这里。")
        XCTAssertEqual(chinese.feedPostUnavailable, "这条帖子暂时无法打开。")

        let english = TellomiTabCopy.resolve(languageCode: "en")
        XCTAssertEqual(english.feed, "Discover")
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
}
