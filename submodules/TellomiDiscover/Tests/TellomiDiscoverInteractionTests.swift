import XCTest

final class TellomiDiscoverInteractionTests: XCTestCase {
    private let nonce = "11111111-1111-4111-8111-111111111111"

    func testShareMenuIsOnlyTheShareablePost() {
        XCTAssertEqual(tellomiDiscoverShareActions(shareable: false, reposted: false), [])
        XCTAssertEqual(tellomiDiscoverShareActions(shareable: false, reposted: true), [])
        XCTAssertEqual(tellomiDiscoverShareActions(shareable: true, reposted: false), [.repost, .quote, .shareInChat, .shareExternal])
        XCTAssertEqual(tellomiDiscoverShareActions(shareable: true, reposted: true), [.unrepost, .quote, .shareInChat, .shareExternal])
        XCTAssertEqual(tellomiDiscoverShareURL(postId: "post-9")?.absoluteString, "https://tell.cc/m#post-9")
        XCTAssertNil(tellomiDiscoverShareURL(postId: "../x"))
        XCTAssertEqual(tellomiDiscoverNotifyUserId, 777005)
    }

    func testRepostAndVoteRequests() {
        let base = URL(string: "https://feed.example")!
        let repost = tellomiDiscoverHTTPCall(base: base, operation: .repost("post-9"), token: "jwt")
        XCTAssertEqual(repost?.method, "PUT")
        XCTAssertEqual(repost?.url.absoluteString, "https://feed.example/v1/feed/posts/post-9/repost")
        XCTAssertNil(repost?.body)
        let undo = tellomiDiscoverHTTPCall(base: base, operation: .unrepost("post-9"), token: "jwt")
        XCTAssertEqual(undo?.method, "DELETE")
        XCTAssertEqual(undo?.url.path, "/v1/feed/posts/post-9/repost")
        XCTAssertNil(tellomiDiscoverHTTPCall(base: base, operation: .repost("../x"), token: "jwt"))

        let vote = tellomiDiscoverHTTPCall(base: base, operation: .vote(postId: "post-9", option: 1), token: "jwt")
        XCTAssertEqual(vote?.method, "PUT")
        XCTAssertEqual(vote?.url.path, "/v1/feed/posts/post-9/vote")
        let voteJSON = try! JSONSerialization.jsonObject(with: vote!.body!) as! [String: Any]
        XCTAssertEqual((voteJSON["option"] as? NSNumber)?.intValue, 1)
        XCTAssertNil(tellomiDiscoverVoteBody(option: -1))
        XCTAssertNil(tellomiDiscoverVoteBody(option: 10))

        let acknowledged = tellomiDiscoverDecodeHTTP(operation: .repost("post-9"), result: TellomiDiscoverHTTPResult(status: 204, body: Data()))
        XCTAssertEqual(acknowledged, .success(.acknowledged))
        let voted = tellomiDiscoverDecodeHTTP(operation: .vote(postId: "post-9", option: 0), result: TellomiDiscoverHTTPResult(status: 200, body: Data("{}".utf8)))
        XCTAssertEqual(voted, .success(.acknowledged))
    }

    func testQuoteAndPollPublishBodies() {
        let quote = tellomiDiscoverPublishBody(text: "加上一句", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, quoteOf: "post-9")
        let quoteJSON = try! JSONSerialization.jsonObject(with: quote!) as! [String: Any]
        XCTAssertEqual(quoteJSON["quote_of"] as? String, "post-9")
        XCTAssertNil(quoteJSON["poll"])
        XCTAssertNil(tellomiDiscoverPublishBody(text: "x", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, quoteOf: "../x"))

        XCTAssertNil(tellomiDiscoverNormalizedPollOptions(["only one"]))
        XCTAssertNil(tellomiDiscoverNormalizedPollOptions(["", "  "]))
        XCTAssertEqual(tellomiDiscoverNormalizedPollOptions(["  是 ", "否"]), ["是", "否"])

        let poll = tellomiDiscoverPublishBody(text: "今天吃什么", visibility: .contacts, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, pollOptions: ["面", "饭"])
        let pollJSON = try! JSONSerialization.jsonObject(with: poll!) as! [String: Any]
        XCTAssertEqual(pollJSON["text"] as? String, "今天吃什么")
        XCTAssertEqual(pollJSON["visibility"] as? String, "contacts")
        let options = (pollJSON["poll"] as? [String: Any])?["options"] as? [String]
        XCTAssertEqual(options, ["面", "饭"])
        XCTAssertNil(pollJSON["quote_of"])
        XCTAssertNil(tellomiDiscoverPublishBody(text: "x", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, quoteOf: "post-9", pollOptions: ["a", "b"]))
        XCTAssertEqual(tellomiDiscoverPublishStep(text: "x", visibility: .everyone, userIds: [], selfUserId: 1, clientNonce: self.nonce, textLimit: 500, token: nil, now: 1, pollOptions: ["only"]), .rejected(.notPublishable))
    }

    func testPollRoundTripOnACard() {
        let cards = #"{"cards":[{"id":"post-9","state":"ok","card":{"text":"选","poll":{"options":[{"text":"甲","votes":2},{"text":"乙","votes":0}],"my_vote":0}},"me":{"reposted":true},"shareable":true}]}"#.data(using: .utf8)!
        let card = tellomiDiscoverParseCards(cards)?.first
        XCTAssertEqual(card?.shareable, true)
        XCTAssertEqual(card?.reposted, true)
        XCTAssertEqual(card?.poll, TellomiDiscoverPoll(options: [
            TellomiDiscoverPollOption(text: "甲", votes: 2),
            TellomiDiscoverPollOption(text: "乙", votes: 0)
        ], myVote: 0))
        let post = tellomiDiscoverDisplayPost(card!)
        XCTAssertEqual(post.shareable, true)
        XCTAssertEqual(post.reposted, true)
        let summary = tellomiDiscoverPostSummary(post: post, copy: .resolve(languageCode: "zh"), list: false)
        XCTAssertTrue(summary.body.contains("甲 · 2 票"))
        let hidden = tellomiDiscoverPostSummary(post: post, copy: .resolve(languageCode: "zh"), list: false, includePoll: false)
        XCTAssertFalse(hidden.body.contains("甲"))
    }

    func testDiscoverNotificationMuteMatchesThePushRule() {
        XCTAssertTrue(tellomiDiscoverNotificationsEnabled(muteUntil: nil, now: 1_700_000_000))
        XCTAssertTrue(tellomiDiscoverNotificationsEnabled(muteUntil: 0, now: 1_700_000_000))
        XCTAssertTrue(tellomiDiscoverNotificationsEnabled(muteUntil: -1, now: 1_700_000_000))
        XCTAssertTrue(tellomiDiscoverNotificationsEnabled(muteUntil: 1_600_000_000, now: 1_700_000_000))
        XCTAssertFalse(tellomiDiscoverNotificationsEnabled(muteUntil: 1_800_000_000, now: 1_700_000_000))
        XCTAssertFalse(tellomiDiscoverNotificationsEnabled(muteUntil: Int32.max, now: 1_700_000_000))
    }
}
