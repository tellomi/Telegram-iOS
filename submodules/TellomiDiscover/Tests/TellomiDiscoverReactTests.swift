import XCTest

final class TellomiDiscoverReactTests: XCTestCase {
    private let base = URL(string: "https://feed.example")!
    private let postId = "post-9"
    private let nonce = "11111111-1111-4111-8111-111111111111"
    private let commentId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

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

    func testLikeMachineKeepsANewerTapAndRollsBackAPermanentFailure() {
        let like = TellomiDiscoverLike(postId: self.postId, liked: false, count: 2, hidden: false, surface: "following")
        let first = like.tap()
        XCTAssertEqual(first?.on, true)
        XCTAssertEqual(first?.surface, "following")
        XCTAssertEqual(like.view().count, 3)
        XCTAssertNil(like.tap())
        XCTAssertEqual(like.view().liked, false)
        XCTAssertEqual(like.view().count, 2)
        let follow = like.finish(generation: first!.generation, version: first!.version, error: .unavailable)
        XCTAssertEqual(follow?.on, false)
        XCTAssertEqual(follow?.automatic, true)
        _ = like.finish(generation: follow!.generation, version: follow!.version, error: .notFound)
        XCTAssertEqual(like.view().liked, false)
        XCTAssertEqual(like.view().count, 2)
        XCTAssertNil(like.finish(generation: like.generationValue() + 1, version: follow!.version, error: nil))
        like.close()
        XCTAssertNotEqual(like.generationValue(), first?.generation)
    }

    func testSignedOutResultRestoresTheConfirmedLike() {
        let like = TellomiDiscoverLike(postId: self.postId, liked: false, count: 4, hidden: false, surface: "recommend")
        let request = like.tap()
        XCTAssertEqual(like.view().count, 5)
        let next = tellomiDiscoverApplyLike(like, request: request, result: .failure(.signedOut))
        XCTAssertNil(next)
        XCTAssertEqual(like.view().count, 4)
        XCTAssertEqual(like.view().liked, false)
    }

    func testPublicCommentReusesTheNonceAndKeepsHeldOutOfTheTotal() {
        let comments = TellomiDiscoverComments()
        let load = comments.open(postId: self.postId)
        let page = TellomiDiscoverCommentPage(comments: [
            TellomiDiscoverComment(id: self.commentId, text: "public", authorName: "Ada", own: true, postId: self.postId)
        ], cursor: "next")
        XCTAssertTrue(comments.accept(generation: load.generation, version: load.version, page: page))
        XCTAssertEqual(comments.publicCount(), 1)
        XCTAssertTrue(comments.hasMore())
        let more = comments.more()
        XCTAssertEqual(more?.cursor, "next")
        comments.failLoad(generation: more!.generation, version: more!.version)
        let first = comments.submit(text: " hello ", parentId: nil, freshNonce: self.nonce)
        XCTAssertEqual(first?.nonce, self.nonce)
        XCTAssertTrue(first?.ready() == true)
        comments.failSend(generation: first!.generation, version: first!.version)
        let retry = comments.submit(text: "hello", parentId: nil, freshNonce: "22222222-2222-4222-8222-222222222222")
        XCTAssertEqual(retry?.nonce, self.nonce)
        let held = TellomiDiscoverCommentCreated(id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", state: "held", version: 2, held: true)
        XCTAssertTrue(comments.finishSend(generation: retry!.generation, version: retry!.version, created: held))
        XCTAssertEqual(comments.publicCount(), 1)
        XCTAssertEqual(comments.pendingRows().count, 1)
        XCTAssertTrue(comments.canDelete(self.commentId))
        let cardSnapshot = ["old card"]
        func drawn() -> [String] {
            return tellomiDiscoverDetailCommentRows(bound: true, visible: comments.visibleRows(), pending: comments.pendingRows()).map { $0.text }
        }
        // Pending stays on screen and is not part of the public total.
        XCTAssertEqual(drawn(), ["public", "hello"])
        XCTAssertNotEqual(drawn(), cardSnapshot)
        XCTAssertEqual(comments.publicCount(), 1)
        comments.failLoad(generation: comments.generationValue(), version: 0)
        XCTAssertEqual(drawn(), ["public", "hello"])
        let remove = comments.delete(self.commentId)
        XCTAssertEqual(remove?.commentId, self.commentId)
        XCTAssertTrue(comments.finishDelete(generation: remove!.generation, version: remove!.version, commentId: self.commentId, ok: true))
        // The last public row is gone. The held row is still shown.
        XCTAssertEqual(comments.publicCount(), 0)
        XCTAssertEqual(drawn(), ["hello"])
        XCTAssertNotEqual(drawn(), cardSnapshot)
        XCTAssertEqual(tellomiDiscoverPublicCountAfterDelete(count: 3, wasVisible: true, deleted: true), 2)
        XCTAssertEqual(tellomiDiscoverPublicCountAfterDelete(count: 3, wasVisible: false, deleted: true), 3)
        let reload = comments.more()
        XCTAssertNotNil(reload)
        comments.failLoad(generation: reload!.generation, version: reload!.version)
        XCTAssertEqual(drawn(), ["hello"])
        XCTAssertNotEqual(drawn(), cardSnapshot)
        let heldId = comments.pendingRows()[0].id
        let dropHeld = comments.delete(heldId)
        XCTAssertEqual(dropHeld?.commentId, heldId)
        XCTAssertTrue(comments.finishDelete(generation: dropHeld!.generation, version: dropHeld!.version, commentId: heldId, ok: true))
        // Empty only after the pending row is deleted too.
        XCTAssertEqual(comments.pendingRows().count, 0)
        XCTAssertEqual(comments.publicCount(), 0)
        XCTAssertEqual(drawn(), [])
        XCTAssertNotEqual(drawn(), cardSnapshot)
        XCTAssertEqual(tellomiDiscoverPublicCountAfterDelete(count: 3, wasVisible: false, deleted: true), 3)
        let emptyReload = comments.more()
        XCTAssertNotNil(emptyReload)
        comments.failLoad(generation: emptyReload!.generation, version: emptyReload!.version)
        comments.failLoad(generation: comments.generationValue(), version: 0)
        XCTAssertEqual(drawn(), [])
        XCTAssertNotEqual(drawn(), cardSnapshot)
        comments.close()
        XCTAssertFalse(comments.accept(generation: load.generation, version: load.version, page: page))
        let body = tellomiDiscoverCommentBody(text: "hello", parentId: nil, nonce: self.nonce)
        let object = try! JSONSerialization.jsonObject(with: body!) as! [String: Any]
        XCTAssertNil(object["media_keys"])
        XCTAssertNil(object["operation_id"])
        let delete = tellomiDiscoverHTTPCall(base: self.base, operation: .deleteComment(self.commentId), token: "jwt")
        XCTAssertEqual(delete?.method, "DELETE")
        XCTAssertEqual(delete?.url.path, "/v1/feed/posts/\(self.commentId)")
    }

    #if os(Linux)
    static var allTests: [(String, (TellomiDiscoverReactTests) -> () throws -> Void)] {
        return [
            ("testLikeUsesTheEngineSurfaceAndNotAStoryCall", testLikeUsesTheEngineSurfaceAndNotAStoryCall),
            ("testLikeMachineKeepsANewerTapAndRollsBackAPermanentFailure", testLikeMachineKeepsANewerTapAndRollsBackAPermanentFailure),
            ("testSignedOutResultRestoresTheConfirmedLike", testSignedOutResultRestoresTheConfirmedLike),
            ("testPublicCommentReusesTheNonceAndKeepsHeldOutOfTheTotal", testPublicCommentReusesTheNonceAndKeepsHeldOutOfTheTotal)
        ]
    }
    #endif
}
