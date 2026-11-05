import XCTest

final class TellomiDiscoverLinkTests: XCTestCase {
    private let nonce = "11111111-1111-4111-8111-111111111111"

    func testFirstUrlSkipsEmailAndTrailingPunctuation() {
        XCTAssertEqual(TellomiDiscoverLink.firstUrl("see https://example.com/a."), "https://example.com/a")
        XCTAssertEqual(TellomiDiscoverLink.firstUrl("看 https://example.com/a。"), "https://example.com/a")
        XCTAssertEqual(TellomiDiscoverLink.firstUrl("(https://example.com/a)"), "https://example.com/a")
        XCTAssertEqual(TellomiDiscoverLink.firstUrl("https://en.wikipedia.org/wiki/URL_(disambiguation)."), "https://en.wikipedia.org/wiki/URL_(disambiguation)")
        XCTAssertEqual(TellomiDiscoverLink.firstUrl("https://example.com/a and https://other.example/b"), "https://example.com/a")
        XCTAssertEqual(TellomiDiscoverLink.firstUrl("HTTPS://Example.COM/Path"), "HTTPS://Example.COM/Path")
        XCTAssertNil(TellomiDiscoverLink.firstUrl("mail a@b.com"))
        XCTAssertNil(TellomiDiscoverLink.firstUrl("www.example.com"))
        XCTAssertNil(TellomiDiscoverLink.firstUrl("nothttps://example.com"))
        XCTAssertNil(TellomiDiscoverLink.firstUrl("see @https://example.com"))
        XCTAssertNil(TellomiDiscoverLink.firstUrl("https://user:pass@example.com/a"))
    }

    func testFetchableRefusesPrivateTargets() {
        XCTAssertTrue(TellomiDiscoverLink.fetchable("https://example.com/a"))
        XCTAssertFalse(TellomiDiscoverLink.fetchable("http://127.0.0.1/secret"))
        XCTAssertFalse(TellomiDiscoverLink.fetchable("http://10.1.2.3/"))
        XCTAssertFalse(TellomiDiscoverLink.fetchable("http://192.168.0.8/a"))
        XCTAssertFalse(TellomiDiscoverLink.fetchable("http://169.254.1.1/"))
        XCTAssertFalse(TellomiDiscoverLink.fetchable("http://172.16.0.1/"))
        XCTAssertFalse(TellomiDiscoverLink.fetchable("http://100.64.0.1/"))
        XCTAssertFalse(TellomiDiscoverLink.fetchable("http://localhost/a"))
        XCTAssertFalse(TellomiDiscoverLink.fetchable("http://printer.local/a"))
        XCTAssertFalse(TellomiDiscoverLink.fetchable("https://[::1]/"))
        XCTAssertFalse(TellomiDiscoverLink.fetchable("javascript:alert(1)"))
        XCTAssertTrue(TellomiDiscoverLink.blockedLiteral("::1"))
        XCTAssertFalse(TellomiDiscoverLink.blockedLiteral("8.8.8.8"))
        XCTAssertTrue(TellomiDiscoverLink.blockedLiteral("::ffff:127.0.0.1"))
        XCTAssertFalse(TellomiDiscoverLink.blockedLiteral("::ffff:8.8.8.8"))
    }

    func testHtmlUsesOpenGraphThenFallbacks() {
        let html = "<html><head>"
            + "<meta content=\"Hello &amp; co\" property=\"og:title\">"
            + "<meta name=\"description\" content=\"plain\">"
            + "<meta property=\"og:description\" content=\"From the page\">"
            + "<meta property=\"og:image\" content=\"/cover.jpg\">"
            + "<title>Ignored</title>"
            + "</head></html>"
        let preview = TellomiDiscoverLink.parseHtml(html, pageUrl: "https://example.com/post")
        XCTAssertEqual(preview?.url, "https://example.com/post")
        XCTAssertEqual(preview?.title, "Hello & co")
        XCTAssertEqual(preview?.description, "From the page")
        XCTAssertEqual(preview?.image, "https://example.com/cover.jpg")
        XCTAssertEqual(preview?.siteLine(), "example.com")

        let bare = "<title>Only title</title><meta name=\"description\" content=\"About\">"
        let fallback = TellomiDiscoverLink.parseHtml(bare, pageUrl: "https://example.com/post")
        XCTAssertEqual(fallback?.title, "Only title")
        XCTAssertEqual(fallback?.description, "About")
        XCTAssertNil(fallback?.image)

        let hostile = "<meta property=\"og:image\" content=\"javascript:alert(1)\">"
            + "<meta property=\"og:image\" content=\"https://127.0.0.1/a.jpg\">"
            + "<meta property=\"og:image\" content=\"https://cdn.example/ok.jpg\">"
            + "<meta property=\"og:title\" content=\"Hi\">"
        let dropped = TellomiDiscoverLink.parseHtml(hostile, pageUrl: "https://example.com/post")
        XCTAssertEqual(dropped?.title, "Hi")
        XCTAssertEqual(dropped?.image, "https://cdn.example/ok.jpg")

        let relative = "<meta property=\"og:image\" content=\"//cdn.example/a.jpg\">"
        XCTAssertEqual(TellomiDiscoverLink.parseHtml(relative, pageUrl: "https://example.com/post")?.image, "https://cdn.example/a.jpg")
        XCTAssertNil(TellomiDiscoverLink.parseHtml(html, pageUrl: "http://127.0.0.1/"))
    }

    func testPublishFieldsStayMinimal() {
        let preview = TellomiDiscoverLink.Preview(url: "https://example.com/a", title: "Hello", description: "From the page", image: "https://cdn.example/pic.jpg")
        let fields = TellomiDiscoverLink.publishFields(preview)
        XCTAssertEqual(fields?.orderedKeys, ["url", "title", "description", "image"])
        XCTAssertEqual(fields?.title, "Hello")
        XCTAssertNil(TellomiDiscoverLink.publishFields(TellomiDiscoverLink.Preview(url: "http://10.0.0.1/x", title: "No", description: nil, image: nil)))
        let noImage = TellomiDiscoverLink.publishFields(TellomiDiscoverLink.Preview(url: "https://example.com/a", title: "Hello", description: nil, image: "https://127.0.0.1/a.jpg"))
        XCTAssertEqual(noImage?.orderedKeys, ["url", "title"])
        let urlOnly = TellomiDiscoverLink.publishFields(TellomiDiscoverLink.urlOnly("https://example.com/a"))
        XCTAssertEqual(urlOnly?.orderedKeys, ["url"])
    }

    func testPublishBodyAddsLinkPreviewWithoutChangingTheOtherKeys() {
        let plain = tellomiDiscoverPublishBody(text: "see https://example.com/a", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500)
        let without = try! JSONSerialization.jsonObject(with: plain!) as! [String: Any]
        XCTAssertEqual(Set(without.keys), Set(["kind", "text", "visibility", "client_nonce"]))
        XCTAssertNil(without["link_preview"])
        XCTAssertNil(without["mentions"])
        XCTAssertNil(without["entities"])
        XCTAssertNil(without["media"])

        let preview = TellomiDiscoverLink.Preview(url: "https://example.com/a", title: "Hello", description: "From the page", image: "https://cdn.example/pic.jpg")
        let posted = tellomiDiscoverPublishBody(text: "see https://example.com/a", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, linkPreview: preview)
        let object = try! JSONSerialization.jsonObject(with: posted!) as! [String: Any]
        XCTAssertEqual(Set(object.keys), Set(["kind", "text", "visibility", "client_nonce", "link_preview"]))
        XCTAssertEqual(object["text"] as? String, "see https://example.com/a")
        let card = object["link_preview"] as! [String: String]
        XCTAssertEqual(Set(card.keys), Set(["url", "title", "description", "image"]))
        XCTAssertEqual(card["url"], "https://example.com/a")
        XCTAssertEqual(card["title"], "Hello")
        XCTAssertEqual(card["description"], "From the page")
        XCTAssertEqual(card["image"], "https://cdn.example/pic.jpg")
        XCTAssertNil(card["site_name"])

        let refused = tellomiDiscoverPublishBody(text: "hi", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, linkPreview: TellomiDiscoverLink.Preview(url: "http://192.168.0.1/", title: "Lan", description: nil, image: nil))
        let refusedText = String(data: refused!, encoding: .utf8)!
        XCTAssertFalse(refusedText.contains("link_preview"))
        XCTAssertFalse(refusedText.contains("mentions"))
    }

    func testCardsReadStoredPreviewAndIgnoreAMissingOne() {
        let json = "{\"cards\":[{\"id\":\"post-9\",\"state\":\"ok\",\"card\":{\"text\":\"see https://example.com/a\","
            + "\"link_preview\":{\"url\":\"https://example.com/a\",\"title\":\"Hello\",\"description\":\"From the page\","
            + "\"image\":\"https://cdn.example/pic.jpg\",\"site_name\":\"Example\"}}}]}"
        let card = tellomiDiscoverParseCards(json.data(using: .utf8)!)?.first
        XCTAssertEqual(card?.linkPreview?.title, "Hello")
        XCTAssertEqual(card?.linkPreview?.image, "https://cdn.example/pic.jpg")
        XCTAssertEqual(card?.linkPreview?.siteLine(), "example.com")
        let post = tellomiDiscoverDisplayPost(card!)
        XCTAssertEqual(post.linkPreview?.title, "Hello")

        let beside = "{\"cards\":[{\"id\":\"post-2\",\"state\":\"ok\",\"link_preview\":{\"url\":\"https://example.com/b\",\"title\":\"Side\"},\"card\":{\"text\":\"x\"}}]}"
        XCTAssertEqual(tellomiDiscoverParseCards(beside.data(using: .utf8)!)?.first?.linkPreview?.title, "Side")

        let dropped = "{\"cards\":[{\"id\":\"post-3\",\"state\":\"ok\",\"card\":{\"text\":\"x\",\"link_preview\":{\"url\":\"https://example.com/c\",\"title\":\"Keep\",\"image\":\"http://10.0.0.5/a.jpg\"}}}]}"
        let kept = tellomiDiscoverParseCards(dropped.data(using: .utf8)!)?.first
        XCTAssertEqual(kept?.linkPreview?.title, "Keep")
        XCTAssertNil(kept?.linkPreview?.image)

        let absent = "{\"cards\":[{\"id\":\"post-4\",\"state\":\"ok\",\"card\":{\"text\":\"x\",\"source_url\":\"\"}}]}"
        XCTAssertNil(tellomiDiscoverParseCards(absent.data(using: .utf8)!)?.first?.linkPreview)

        let junk = "{\"cards\":[{\"id\":\"post-5\",\"state\":\"ok\",\"card\":{\"text\":\"x\",\"link_preview\":\"nope\"}}]}"
        XCTAssertNil(tellomiDiscoverParseCards(junk.data(using: .utf8)!)?.first?.linkPreview)

        let hidden = "{\"cards\":[{\"id\":\"post-6\",\"state\":\"ok\",\"card\":{\"text\":\"x\",\"link_preview\":{\"url\":\"http://127.0.0.1/a\",\"title\":\"No\"}}}]}"
        XCTAssertNil(tellomiDiscoverParseCards(hidden.data(using: .utf8)!)?.first?.linkPreview)
    }

    func testCharsetComesFromTheHeaderOrTheMetaTag() {
        XCTAssertEqual(TellomiDiscoverLink.charsetName(Data(), contentType: "text/html; charset=gbk"), "GBK")
        let meta = "<meta charset=\"gb18030\">".data(using: .ascii)!
        XCTAssertEqual(TellomiDiscoverLink.charsetName(meta, contentType: "text/html"), "GB18030")
        XCTAssertEqual(TellomiDiscoverLink.charsetName(meta, contentType: nil), "GB18030")
        XCTAssertEqual(TellomiDiscoverLink.charsetName(Data([UInt8(ascii: "x")]), contentType: "text/plain"), "UTF-8")
    }
}
