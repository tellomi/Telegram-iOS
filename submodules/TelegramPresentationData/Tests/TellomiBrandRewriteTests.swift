import XCTest

final class TellomiBrandRewriteTests: XCTestCase {
    func testShortLinksUseTellCc() {
        XCTAssertEqual(tellomiRewriteBrand("https://t.me/username"), "https://tell.cc/username")
        XCTAssertEqual(tellomiRewriteBrand("https://telegram.me/joinchat/abc"), "https://tell.cc/joinchat/abc")
        XCTAssertEqual(tellomiRewriteBrand("https://telegram.dog/+invite"), "https://tell.cc/+invite")
        XCTAssertEqual(tellomiRewriteBrand("tell.cc/addstickers/pack"), "tell.cc/addstickers/pack")
    }

    func testWebsiteLinksUsePagesThatExist() {
        XCTAssertEqual(tellomiRewriteBrand("https://telegram.org/faq#general"), "https://tellomi.cn/help#general")
        XCTAssertEqual(tellomiRewriteBrand("https://tellomi.cn/faq#general"), "https://tellomi.cn/help")
        XCTAssertEqual(tellomiRewriteBrand("https://tellomi.cn/faq#q-can-i-delete-my-messages"), "https://tellomi.cn/account/delete/")
        XCTAssertEqual(tellomiRewriteBrand("https://tellomi.cn/tos/stars"), "https://tellomi.cn/legal/terms/")
        XCTAssertEqual(tellomiRewriteBrand("https://tellomi.cn/terms"), "https://tellomi.cn/legal/terms/")
        XCTAssertEqual(tellomiRewriteBrand("https://tellomi.cn/tos/mini-apps"), "https://tellomi.cn/legal/terms/")
        XCTAssertEqual(tellomiRewriteBrand("https://tellomi.cn/privacy-tpa"), "https://tellomi.cn/legal/privacy/")
        XCTAssertEqual(tellomiRewriteBrand("https://tellomi.cn/apps"), "https://tellomi.cn/download/")
        XCTAssertEqual(tellomiRewriteBrand("https://telegram.org/privacy"), "https://tellomi.cn/legal/privacy/")
        XCTAssertEqual(tellomiRewriteBrand("https://telegram.org/tos"), "https://tellomi.cn/legal/terms/")
        XCTAssertEqual(tellomiRewriteBrand("https://telegram.org/terms"), "https://tellomi.cn/legal/terms/")
        XCTAssertEqual(tellomiRewriteBrand("https://www.telegram.org/"), "https://tellomi.cn/")
        XCTAssertEqual(tellomiRewriteBrand("https://telegram.org/update"), "https://tellomi.cn/help/install/update/")
        XCTAssertEqual(tellomiRewriteBrand("https://telegram.org/dl"), "https://tellomi.cn/download/")
        XCTAssertEqual(tellomiRewriteBrand("https://telegram.org/ads"), "https://tellomi.cn/legal/privacy/")
        XCTAssertEqual(tellomiRewriteBrand("https://telegram.org/blog/coronavirus"), "https://tellomi.cn/help")
        XCTAssertEqual(tellomiRewriteBrand("https://ads.telegram.org/guidelines"), "https://tellomi.cn/legal/community/")
        XCTAssertEqual(tellomiRewriteBrand("https://promote.telegram.org"), "https://tellomi.cn/support/")
        XCTAssertEqual(tellomiRewriteBrand("https://getdesktop.telegram.org"), "https://tellomi.cn/help/start/link-desktop/")
        XCTAssertEqual(tellomiRewriteBrand("https://web.telegram.org"), "https://tellomi.cn")
        XCTAssertEqual(tellomiRewriteBrand("https://translations.telegram.org"), "https://tellomi.cn/help")
        XCTAssertEqual(tellomiRewriteBrand("https://core.telegram.org/bots/webapps#launching-the-main-mini-app"), "https://tellomi.cn/help")
        XCTAssertEqual(tellomiRewriteBrand("recover@telegram.org"), "support@tellomi.app")
        XCTAssertEqual(tellomiRewriteBrand("sms@telegram.org"), "support@tellomi.app")
    }

    func testBugTrackerHostAndDeepLinkSchemeStay() {
        XCTAssertEqual(tellomiRewriteBrand("bugs.telegram.org/c/1"), "bugs.telegram.org/c/1")
        XCTAssertEqual(tellomiRewriteBrand("tg://resolve?domain=name"), "tg://resolve?domain=name")
    }
}
