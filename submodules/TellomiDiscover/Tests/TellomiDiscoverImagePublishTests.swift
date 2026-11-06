import XCTest

final class TellomiDiscoverImagePublishTests: XCTestCase {
    private let nonce = "11111111-1111-4111-8111-111111111111"

    func testUnconfirmedLimitsRejectSelection() {
        var images = TellomiDiscoverImagePublish()
        XCTAssertEqual(images.select(localId: "a", byteCount: 10), .limitsUnconfirmed)
        XCTAssertEqual(images.posting, .textOnly)
        XCTAssertEqual(images.confirm(maxCount: 0, maxBytesEach: 10), .limitInvalid)
        XCTAssertEqual(images.confirm(maxCount: 2, maxBytesEach: 0), .limitInvalid)
    }

    func testSelectionHonorsConfirmedCaps() {
        var images = TellomiDiscoverImagePublish()
        XCTAssertNil(images.confirm(maxCount: 2, maxBytesEach: 100))
        XCTAssertEqual(images.select(localId: " ", byteCount: 10), .emptyId)
        XCTAssertEqual(images.select(localId: "a", byteCount: 0), .byteCountInvalid)
        XCTAssertEqual(images.select(localId: "big", byteCount: 101), .overBytes)
        XCTAssertNil(images.select(localId: "a", byteCount: 10))
        XCTAssertEqual(images.select(localId: "a", byteCount: 10), .duplicate)
        XCTAssertNil(images.select(localId: "b", byteCount: 20))
        XCTAssertEqual(images.select(localId: "c", byteCount: 20), .overCount)
        XCTAssertEqual(images.items.map { $0.localId }, ["a", "b"])
    }

    func testIncompleteUploadBlocksPublishAndCancelDropsIt() {
        var images = self.readyPair()
        XCTAssertEqual(images.posting, .blocked)
        XCTAssertNil(images.beginUpload(localId: "a"))
        XCTAssertEqual(images.posting, .blocked)
        XCTAssertNil(images.fail(localId: "a"))
        XCTAssertEqual(images.posting, .blocked)
        XCTAssertEqual(images.retry(localId: "b"), .notFailed)
        XCTAssertNil(images.retry(localId: "a"))
        XCTAssertEqual(images.complete(localId: "a", key: " "), .emptyKey)
        XCTAssertEqual(images.complete(localId: "a", key: "key-a"), .invalidKey)
        XCTAssertNil(images.complete(localId: "a", key: "m/11111111-1111-4111-8111-111111111111"))
        XCTAssertEqual(images.posting, .blocked)
        XCTAssertNil(images.cancel(localId: "b"))
        XCTAssertFalse(images.items.contains(where: { $0.localId == "b" }))
        guard case let .ready(keys) = images.posting else {
            return XCTFail("expected ready keys")
        }
        XCTAssertEqual(keys, ["m/11111111-1111-4111-8111-111111111111"])
    }

    func testRetryKeepsThePostNonce() {
        var images = self.readyPair()
        XCTAssertNil(images.beginUpload(localId: "a"))
        XCTAssertNil(images.fail(localId: "a"))
        let again = tellomiDiscoverImageRetryNonce(current: self.nonce)
        XCTAssertNil(images.retry(localId: "a"))
        XCTAssertEqual(again, self.nonce)
        XCTAssertTrue(tellomiDiscoverClientNonce(again))
    }

    func testTextQuotePollBodyIsUnchangedWhenNoImagesAreSelected() {
        let images = TellomiDiscoverImagePublish()
        XCTAssertEqual(images.posting, .textOnly)
        let body = tellomiDiscoverPublishBody(
            text: "hello",
            visibility: .contacts,
            audienceToken: nil,
            clientNonce: self.nonce,
            textLimit: 500,
            quoteOf: "post_1",
            pollOptions: nil,
            linkPreview: nil
        )
        let object = try? JSONSerialization.jsonObject(with: body ?? Data()) as? [String: Any]
        XCTAssertEqual(object?["visibility"] as? String, "contacts")
        XCTAssertEqual(object?["quote_of"] as? String, "post_1")
        XCTAssertEqual(object?["client_nonce"] as? String, self.nonce)
        XCTAssertNil(object?["poll"])
        XCTAssertEqual(Set(object?.keys ?? [String: Any]().keys), Set(["kind", "text", "visibility", "client_nonce", "quote_of"]))
        let poll = tellomiDiscoverPublishBody(
            text: "hello",
            visibility: .everyone,
            audienceToken: nil,
            clientNonce: self.nonce,
            textLimit: 500,
            pollOptions: ["yes", "no"]
        )
        let pollObject = try? JSONSerialization.jsonObject(with: poll ?? Data()) as? [String: Any]
        let pollBody = pollObject?["poll"] as? [String: Any]
        XCTAssertEqual(pollBody?["options"] as? [String], ["yes", "no"])
        XCTAssertNil(pollObject?["quote_of"])
    }

    func testReadyKeysArePostedInOrderAndTextOnlyStaysBare() {
        var images = TellomiDiscoverImagePublish()
        XCTAssertNil(images.useVerifiedContract())
        XCTAssertEqual(TellomiDiscoverImageContract.maxCount, 10)
        XCTAssertEqual(TellomiDiscoverImageContract.maxBytes, 20_971_520)
        XCTAssertNil(images.select(localId: "a", byteCount: TellomiDiscoverImageContract.maxBytes))
        XCTAssertEqual(images.select(localId: "big", byteCount: TellomiDiscoverImageContract.maxBytes + 1), .overBytes)
        XCTAssertNil(images.beginUpload(localId: "a"))
        XCTAssertNil(images.complete(localId: "a", key: "m/11111111-1111-4111-8111-111111111111"))
        guard case let .ready(keys) = images.posting else {
            return XCTFail("expected ready keys")
        }
        XCTAssertEqual(keys, ["m/11111111-1111-4111-8111-111111111111"])
        let bare = tellomiDiscoverPublishBody(text: "hello", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500)
        let bareObject = try? JSONSerialization.jsonObject(with: bare ?? Data()) as? [String: Any]
        XCTAssertNil(bareObject?["media_keys"])
        XCTAssertNil(bareObject?["operation_id"])
        let posted = tellomiDiscoverPublishBody(text: "  ", visibility: .contacts, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, mediaKeys: keys)
        let object = try? JSONSerialization.jsonObject(with: posted ?? Data()) as? [String: Any]
        XCTAssertEqual(object?["text"] as? String, "")
        XCTAssertEqual(object?["visibility"] as? String, "contacts")
        XCTAssertEqual(object?["media_keys"] as? [String], keys)
        XCTAssertNil(object?["operation_id"])
        XCTAssertNotEqual(TellomiDiscoverVisibility.contacts.rawValue, "friends")
        XCTAssertNotEqual(TellomiDiscoverVisibility.closeFriends.rawValue, "only_me")
    }

    #if os(Linux)
    static var allTests: [(String, (TellomiDiscoverImagePublishTests) -> () throws -> Void)] {
        return [
            ("testUnconfirmedLimitsRejectSelection", testUnconfirmedLimitsRejectSelection),
            ("testSelectionHonorsConfirmedCaps", testSelectionHonorsConfirmedCaps),
            ("testIncompleteUploadBlocksPublishAndCancelDropsIt", testIncompleteUploadBlocksPublishAndCancelDropsIt),
            ("testRetryKeepsThePostNonce", testRetryKeepsThePostNonce),
            ("testTextQuotePollBodyIsUnchangedWhenNoImagesAreSelected", testTextQuotePollBodyIsUnchangedWhenNoImagesAreSelected),
            ("testReadyKeysArePostedInOrderAndTextOnlyStaysBare", testReadyKeysArePostedInOrderAndTextOnlyStaysBare)
        ]
    }
    #endif

    private func readyPair() -> TellomiDiscoverImagePublish {
        var images = TellomiDiscoverImagePublish()
        XCTAssertNil(images.confirm(maxCount: 2, maxBytesEach: 100))
        XCTAssertNil(images.select(localId: "a", byteCount: 10))
        XCTAssertNil(images.select(localId: "b", byteCount: 20))
        return images
    }
}
