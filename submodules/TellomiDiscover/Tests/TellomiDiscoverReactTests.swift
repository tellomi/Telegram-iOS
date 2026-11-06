import XCTest

final class TellomiDiscoverReactTests: XCTestCase {
    private let base = URL(string: "https://feed.example")!
    private let postId = "post-9"
    private let nonce = "11111111-1111-4111-8111-111111111111"

    func testLikeUsesTheEngineSurfaceAndNotAStoryCall() {
        let call = tellomiDiscoverHTTPCall(base: self.base, operation: .like(postId: self.postId, surface: "nearby"), token: "jwt")
        XCTAssertEqual(call?.method, "PUT")
        XCTAssertEqual(call?.url.path, "/v1/feed/posts/post-9/like")
        XCTAssertEqual(call?.url.query, "surface=recommend")
        let following = tellomiDiscoverHTTPCall(base: self.base, operation: .unlike(postId: self.postId, surface: "following"), token: "jwt")
        XCTAssertEqual(following?.method, "DELETE")
        XCTAssertEqual(following?.url.query, "surface=following")
        let acknowledged = tellomiDiscoverDecodeHTTP(operation: .like(postId: self.postId, surface: "recommend"), result: TellomiDiscoverHTTPResult(status: 204, body: Data()))
        guard case .success(.acknowledged) = acknowledged else {
            return XCTFail("like 204 was not acknowledged")
        }
        let wrong = tellomiDiscoverDecodeHTTP(operation: .like(postId: self.postId, surface: "recommend"), result: TellomiDiscoverHTTPResult(status: 200, body: Data()))
        guard case .failure(.unavailable) = wrong else {
            return XCTFail("like 200 was treated as success")
        }
    }

    func testStaleLikeResponseDoesNotMoveTheCount() {
        var state = TellomiDiscoverLikeState(postId: self.postId, liked: false, count: 2, hidden: false, surface: "recommend")
        let first = state.tap()
        XCTAssertEqual(first?.on, true)
        XCTAssertEqual(state.view().count, 3)
        let second = state.tap()
        XCTAssertEqual(second?.generation, 2)
        XCTAssertEqual(state.view().liked, false)
        _ = state.finish(generation: 1, success: true)
        XCTAssertEqual(state.view().count, 2)
        XCTAssertEqual(state.view().liked, false)
        _ = state.finish(generation: 2, success: false)
        XCTAssertEqual(state.confirmedLiked, false)
        XCTAssertEqual(state.view().count, 2)
        var hidden = TellomiDiscoverLikeState(postId: self.postId, liked: false, count: 0, hidden: true, surface: "recommend")
        XCTAssertNil(hidden.tap())
        XCTAssertTrue(hidden.view().hidden)
    }

    func testPublicCommentBodyHasNoMedia() {
        XCTAssertNil(tellomiDiscoverCommentBody(text: "  ", parentId: nil, nonce: self.nonce))
        XCTAssertNil(tellomiDiscoverCommentBody(text: "hi", parentId: "not-a-uuid", nonce: self.nonce))
        let body = tellomiDiscoverCommentBody(text: " hello ", parentId: nil, nonce: self.nonce)
        let object = try! JSONSerialization.jsonObject(with: body!) as! [String: Any]
        XCTAssertEqual(object["text"] as? String, "hello")
        XCTAssertEqual(object["client_nonce"] as? String, self.nonce)
        XCTAssertNil(object["media_keys"])
        XCTAssertNil(object["operation_id"])
        let call = tellomiDiscoverHTTPCall(base: self.base, operation: .comment(postId: self.postId, text: "hello", parentId: nil, clientNonce: self.nonce), token: "jwt")
        XCTAssertEqual(call?.method, "POST")
        XCTAssertEqual(call?.url.path, "/v1/feed/posts/post-9/comments")
        let created = tellomiDiscoverDecodeHTTP(operation: .comment(postId: self.postId, text: "hello", parentId: nil, clientNonce: self.nonce), result: TellomiDiscoverHTTPResult(status: 201, body: Data(#"{"id":"22222222-2222-4222-8222-222222222222","state":"ok","version":3}"#.utf8)))
        guard case let .success(.commentCreated(value)) = created else {
            return XCTFail("comment was not created")
        }
        XCTAssertEqual(value.version, 3)
        XCTAssertNil(value.held)
        let closed = tellomiDiscoverDecodeHTTP(operation: .comment(postId: self.postId, text: "hello", parentId: nil, clientNonce: self.nonce), result: TellomiDiscoverHTTPResult(status: 403, body: Data(#"{"error":"comments_closed"}"#.utf8)))
        guard case .failure(.commentsClosed) = closed else {
            return XCTFail("closed comments were accepted")
        }
    }

    func testCommentPageDropsPendingAndOtherPosts() {
        let page = #"""
        {"comments":[
          {"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","state":"ok","post_id":"post-9","card":{"text":"public","author":{"display_name":"Ada"}},"me":{"author":true}},
          {"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","state":"pending","post_id":"post-9","text":"held"},
          {"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","state":"ok","post_id":"other","text":"nope"}
        ],"cursor":"next"}
        """#
        let decoded = tellomiDiscoverDecodeHTTP(operation: .comments(postId: self.postId, cursor: nil), result: TellomiDiscoverHTTPResult(status: 200, body: Data(page.utf8)))
        guard case let .success(.commentPage(value)) = decoded else {
            return XCTFail("comment page was unreadable")
        }
        XCTAssertEqual(value.comments.count, 1)
        XCTAssertEqual(value.comments[0].text, "public")
        XCTAssertTrue(value.comments[0].own)
        XCTAssertEqual(value.cursor, "next")
        let delete = tellomiDiscoverHTTPCall(base: self.base, operation: .deleteComment("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"), token: "jwt")
        XCTAssertEqual(delete?.method, "DELETE")
        XCTAssertEqual(delete?.url.path, "/v1/feed/posts/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    }
}
