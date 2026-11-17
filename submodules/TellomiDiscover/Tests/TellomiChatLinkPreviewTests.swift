import XCTest

final class TellomiChatLinkPreviewTests: XCTestCase {
    func testInternalHostsStayOnTheServer() {
        XCTAssertEqual(tellomiChatLinkRoute("https://tell.cc/addstickers/erelpack"), .server)
        XCTAssertEqual(tellomiChatLinkRoute("https://www.tell.cc/username"), .server)
        XCTAssertEqual(tellomiChatLinkRoute("https://t.me/somechannel/3"), .server)
        XCTAssertEqual(tellomiChatLinkRoute("https://telegram.me/+invite"), .server)
        XCTAssertEqual(tellomiChatLinkRoute("https://www.telegram.me/name"), .server)
        XCTAssertEqual(tellomiChatLinkRoute("https://telegram.dog/+abc"), .server)
        XCTAssertEqual(tellomiChatLinkRoute("https://tellomi.cn/help"), .client)
    }

    func testExternalLinksAreFetchedOnThePhone() {
        XCTAssertEqual(tellomiChatLinkRoute("https://www.apple.com/iphone"), .client)
        XCTAssertEqual(tellomiChatLinkRoute("http://127.0.0.1/secret"), .refused)
        XCTAssertEqual(tellomiChatLinkRoute("http://10.1.2.3/"), .refused)
        XCTAssertEqual(tellomiChatLinkRoute("http://localhost/a"), .refused)
        XCTAssertEqual(tellomiChatLinkRoute("javascript:alert(1)"), .refused)
    }

    func testFieldsMatchTheStoredLimitsAndFlagBits() {
        let fields = tellomiChatLinkFields(title: String(repeating: "a", count: 200), text: "hello", siteName: "Apple", hasPhoto: true)
        XCTAssertEqual(fields.title?.count, 128)
        XCTAssertEqual(fields.text, "hello")
        XCTAssertEqual(fields.siteName, "Apple")
        XCTAssertEqual(fields.flags, (1 << 3) | (1 << 4) | (1 << 5) | (1 << 6))
    }

    func testOversizedFieldIsOmitted() {
        let huge = String(repeating: "字", count: 9000)
        XCTAssertGreaterThan(huge.utf8.count, 16 * 1024)
        let fields = tellomiChatLinkFields(title: huge, text: nil, siteName: nil, hasPhoto: false)
        XCTAssertNil(fields.title)
        XCTAssertEqual(fields.flags, 0)
    }

    func testUnverifiedAuthorIsNotShown() {
        XCTAssertNil(tellomiDisplayedWebpageAuthor("unverified"))
        XCTAssertNil(tellomiDisplayedWebpageAuthor("Unverified"))
        XCTAssertEqual(tellomiDisplayedWebpageAuthor("Ada"), "Ada")
        XCTAssertNil(tellomiDisplayedWebpageAuthor(nil))
    }

    func testOpenGraphSiteName() {
        let html = "<meta property=\"og:site_name\" content=\"Apple\">"
        XCTAssertEqual(TellomiDiscoverLink.openGraphSiteName(html), "Apple")
    }
}
