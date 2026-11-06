import XCTest

final class TellomiDiscoverImageWireTests: XCTestCase {
    private let base = URL(string: "https://feed.example")!
    private let key = "m/11111111-1111-4111-8111-111111111111"
    private let second = "m/22222222-2222-4222-8222-222222222222"
    private let nonce = "11111111-1111-4111-8111-111111111111"

    func testOptionsCreatePatchAndResumeStayOnTheFeedOrigin() {
        let bytes = Data([1, 2, 3, 4, 5, 6, 7, 8])
        var session = TellomiDiscoverImageUploadSession(length: bytes.count)
        session.chunkBytes = 3
        let options = session.call(base: self.base, bytes: bytes)
        XCTAssertEqual(options?.method, "OPTIONS")
        XCTAssertEqual(options?.authorizes, false)
        XCTAssertEqual(options?.url.path, "/v1/feed/media/uploads")
        XCTAssertNil(options?.headers["Authorization"])
        XCTAssertEqual(options?.headers["Tus-Resumable"], "1.0.0")
        session.receive(self.optionsResponse(), base: self.base)
        XCTAssertEqual(session.step, .create)

        let create = session.call(base: self.base, bytes: bytes)
        XCTAssertEqual(create?.method, "POST")
        XCTAssertEqual(create?.authorizes, true)
        XCTAssertEqual(create?.headers["Upload-Length"], "8")
        XCTAssertEqual(create?.headers["Tus-Resumable"], "1.0.0")
        session.receive(TellomiDiscoverHTTPResult(status: 201, body: Data("{\"id\":\"upload-1\",\"key\":\"\(self.key)\"}".utf8), headers: [
            "Location": "/v1/feed/media/uploads/upload-1",
            "Media-Key": self.key.uppercased()
        ]), base: self.base)
        XCTAssertEqual(session.step, .patch)
        XCTAssertEqual(session.mediaKey, self.key)
        XCTAssertEqual(session.location?.host, "feed.example")

        let first = session.call(base: self.base, bytes: bytes)
        XCTAssertEqual(first?.method, "PATCH")
        XCTAssertEqual(first?.headers["Content-Type"], "application/offset+octet-stream")
        XCTAssertEqual(first?.headers["Upload-Offset"], "0")
        XCTAssertEqual(first?.body, Data([1, 2, 3]))
        XCTAssertEqual(first?.authorizes, true)
        session.transportFailed()
        guard case .wait(let delay) = session.step else {
            return XCTFail("expected a backoff wait")
        }
        XCTAssertEqual(delay, 1)
        XCTAssertNil(session.call(base: self.base, bytes: bytes))
        session.waited()
        XCTAssertEqual(session.step, .head)
        let head = session.call(base: self.base, bytes: bytes)
        XCTAssertEqual(head?.method, "HEAD")
        XCTAssertEqual(head?.authorizes, true)
        session.receive(TellomiDiscoverHTTPResult(status: 200, body: Data(), headers: ["Upload-Offset": "3"]), base: self.base)
        XCTAssertEqual(session.offset, 3)
        let second = session.call(base: self.base, bytes: bytes)
        XCTAssertEqual(second?.body, Data([4, 5, 6]))
        XCTAssertEqual(second?.headers["Upload-Offset"], "3")
        session.receive(TellomiDiscoverHTTPResult(status: 409, body: Data(), headers: [:]), base: self.base)
        XCTAssertEqual(session.step, .head)
        session.receive(TellomiDiscoverHTTPResult(status: 204, body: Data(), headers: ["Upload-Offset": "6"]), base: self.base)
        let last = session.call(base: self.base, bytes: bytes)
        XCTAssertEqual(last?.body, Data([7, 8]))
        session.receive(TellomiDiscoverHTTPResult(status: 204, body: Data(), headers: ["Upload-Offset": "8"]), base: self.base)
        XCTAssertEqual(session.step, .done(key: self.key))
    }

    func testRejectedLocationNeverReceivesTheCredential() {
        var session = TellomiDiscoverImageUploadSession(length: 4)
        let bytes = Data([9, 9, 9, 9])
        _ = session.call(base: self.base, bytes: bytes)
        session.receive(self.optionsResponse(), base: self.base)
        _ = session.call(base: self.base, bytes: bytes)
        session.receive(TellomiDiscoverHTTPResult(status: 201, body: Data("{\"id\":\"x\",\"key\":\"\(self.key)\"}".utf8), headers: [
            "Location": "https://evil.example/v1/feed/media/uploads/x",
            "Media-Key": self.key
        ]), base: self.base)
        XCTAssertEqual(session.step, .failed(.locationRejected))
        XCTAssertNil(session.location)
        XCTAssertNil(session.call(base: self.base, bytes: bytes))
        XCTAssertNil(tellomiDiscoverAllowedMediaLocation("https://user:jwt@feed.example/v1/feed/media/uploads/x", base: self.base))
        XCTAssertNil(tellomiDiscoverAllowedMediaLocation("http://feed.example/v1/feed/media/uploads/x", base: self.base))
        XCTAssertNil(tellomiDiscoverAllowedMediaLocation("/v1/feed/media/uploads/../secret", base: self.base))
        XCTAssertNil(tellomiDiscoverAllowedMediaLocation("javascript:alert(1)", base: self.base))
        let allowed = tellomiDiscoverAllowedMediaLocation("/v1/feed/media/uploads/upload-1", base: self.base)
        XCTAssertEqual(allowed?.absoluteString, "https://feed.example/v1/feed/media/uploads/upload-1")
    }

    func testTooManyFormatAndCancel() {
        var session = TellomiDiscoverImageUploadSession(length: 2)
        let bytes = Data([1, 2])
        _ = session.call(base: self.base, bytes: bytes)
        session.receive(self.optionsResponse(), base: self.base)
        _ = session.call(base: self.base, bytes: bytes)
        session.receive(TellomiDiscoverHTTPResult(status: 429, body: Data(), headers: ["Retry-After": "60"]), base: self.base)
        XCTAssertEqual(session.step, .wait(seconds: 60))
        XCTAssertNil(session.call(base: self.base, bytes: bytes))
        session.waited()
        XCTAssertEqual(session.step, .create)
        session.receive(TellomiDiscoverHTTPResult(status: 415, body: Data(), headers: [:]), base: self.base)
        XCTAssertEqual(session.step, .voided)
        session.retry()
        XCTAssertEqual(session.step, .create)
        session.receive(self.created(self.key), base: self.base)
        XCTAssertEqual(session.step, .patch)
        session.cancel()
        let delete = session.call(base: self.base, bytes: bytes)
        XCTAssertEqual(delete?.method, "DELETE")
        XCTAssertEqual(delete?.authorizes, true)
        session.receive(TellomiDiscoverHTTPResult(status: 404, body: Data(), headers: [:]), base: self.base)
        XCTAssertEqual(session.step, .cancelled)

        var fresh = TellomiDiscoverImageUploadSession(length: 2)
        fresh.cancel()
        XCTAssertEqual(fresh.step, .cancelled)
        XCTAssertNil(fresh.call(base: self.base, bytes: bytes))
    }

    func testDeleteOfAnUnattachedUploadAndHiddenFeed() {
        var session = TellomiDiscoverImageUploadSession(length: 2)
        let bytes = Data([1, 2])
        _ = session.call(base: self.base, bytes: bytes)
        session.receive(self.optionsResponse(), base: self.base)
        session.receive(self.created(self.key), base: self.base)
        session.cancel()
        _ = session.call(base: self.base, bytes: bytes)
        session.receive(TellomiDiscoverHTTPResult(status: 204, body: Data(), headers: [:]), base: self.base)
        XCTAssertEqual(session.step, .cancelled)

        var hidden = TellomiDiscoverImageUploadSession(length: 2)
        _ = hidden.call(base: self.base, bytes: bytes)
        hidden.receive(TellomiDiscoverHTTPResult(status: 404, body: Data("{\"error\":\"feed_hidden\"}".utf8), headers: [:]), base: self.base)
        XCTAssertEqual(hidden.step, .failed(.hidden))
    }

    func testLoaderWithholdsTheCredentialAndRetriesExpiry() {
        var seen: [TellomiDiscoverHTTPCall] = []
        var posts = 0
        let loader = TellomiDiscoverLoader(now: { 0 }, credential: TellomiDiscoverCredential(token: "jwt-1", expires: 10_000, region: "cn"), fetchCredential: { completion in
            completion(.success(TellomiDiscoverCredential(token: "jwt-2", expires: 10_000, region: "cn")))
        }, http: { call, completion in
            seen.append(call)
            if call.method == "OPTIONS" {
                completion(.success(TellomiDiscoverHTTPResult(status: 204, body: Data(), headers: [
                    "Tus-Version": "1.0.0",
                    "Tus-Extension": "creation,termination",
                    "Tus-Max-Size": "20971520"
                ])))
                return
            }
            posts += 1
            if posts == 1 {
                completion(.success(TellomiDiscoverHTTPResult(status: 401, body: Data("{\"error\":\"credential_expired\"}".utf8))))
            } else {
                completion(.success(TellomiDiscoverHTTPResult(status: 201, body: Data("{\"id\":\"upload-1\",\"key\":\"\(self.key)\"}".utf8), headers: [
                    "Location": "https://feed.example/v1/feed/media/uploads/upload-1",
                    "Media-Key": self.key
                ])))
            }
        })
        let configuration = TellomiDiscoverConfiguration(enabled: true, baseURL: self.base)
        var session = TellomiDiscoverImageUploadSession(length: 1)
        let bytes = Data([7])
        let options = session.call(base: self.base, bytes: bytes)!
        let optionsDone = expectation(description: "options")
        loader.performImage(loggedIn: true, configuration: configuration, call: options) { result in
            guard case let .success(response) = result else {
                return XCTFail("expected options")
            }
            session.receive(response, base: self.base)
            optionsDone.fulfill()
        }
        wait(for: [optionsDone], timeout: 1)
        XCTAssertEqual(seen.first?.authorizes, false)
        XCTAssertEqual(seen.first?.token, "")

        let evil = TellomiDiscoverImageWireCall(method: "PATCH", url: URL(string: "https://evil.example/v1/feed/media/uploads/x")!, body: Data([1]), authorizes: true, headers: [:])
        let blocked = expectation(description: "blocked")
        loader.performImage(loggedIn: true, configuration: configuration, call: evil) { result in
            guard case .failure(.unavailable) = result else {
                return XCTFail("expected the off-origin upload to be refused")
            }
            blocked.fulfill()
        }
        wait(for: [blocked], timeout: 1)
        XCTAssertEqual(seen.count, 1)

        let create = session.call(base: self.base, bytes: bytes)!
        let created = expectation(description: "created")
        loader.performImage(loggedIn: true, configuration: configuration, call: create) { result in
            guard case let .success(response) = result else {
                return XCTFail("expected create")
            }
            session.receive(response, base: self.base)
            created.fulfill()
        }
        wait(for: [created], timeout: 1)
        XCTAssertEqual(seen.map(\.token), ["", "jwt-1", "jwt-2"])
        XCTAssertEqual(seen.dropFirst().map(\.authorizes), [true, true])
        XCTAssertEqual(session.step, .patch)
        let decoded = tellomiDiscoverDecodeHTTP(operation: .publish(text: "hi", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, city: nil, quoteOf: nil, pollOptions: nil, linkPreview: nil, mediaKeys: nil), result: TellomiDiscoverHTTPResult(status: 401, body: Data("{\"error\":\"credential_expired\"}".utf8)))
        guard case .failure(.unauthorized) = decoded else {
            return XCTFail("expected credential_expired to refresh")
        }
    }

    func testMediaKeysOrderEmptyTextAndInvalidMedia() {
        let keys = [self.second, self.key]
        let body = tellomiDiscoverPublishBody(text: "", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, mediaKeys: keys)
        let object = try? JSONSerialization.jsonObject(with: body ?? Data()) as? [String: Any]
        XCTAssertEqual(object?["media_keys"] as? [String], keys)
        XCTAssertEqual(object?["text"] as? String, "")
        XCTAssertNil(object?["operation_id"])
        XCTAssertNil(tellomiDiscoverPublishBody(text: "", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, mediaKeys: nil))
        var tooMany = Array(repeating: self.key, count: 11)
        tooMany[1] = self.second
        XCTAssertNil(tellomiDiscoverPublishBody(text: "hi", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, mediaKeys: tooMany))
        XCTAssertNil(tellomiDiscoverPublishBody(text: "hi", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, mediaKeys: [self.key, self.key]))
        let features = TellomiDiscoverCapabilities(version: 1, features: [TellomiDiscoverImageContract.mediaUpload, TellomiDiscoverImageContract.writeIdempotency])
        XCTAssertTrue(tellomiDiscoverFeatureEnabled(features, TellomiDiscoverImageContract.mediaUpload))
        XCTAssertFalse(tellomiDiscoverFeatureEnabled(TellomiDiscoverCapabilities(version: 1, features: ["feed"]), TellomiDiscoverImageContract.mediaUpload))
        let rejected = tellomiDiscoverDecodeHTTP(operation: .publish(text: "", visibility: .everyone, audienceToken: nil, clientNonce: self.nonce, textLimit: 500, city: nil, quoteOf: nil, pollOptions: nil, linkPreview: nil, mediaKeys: keys), result: TellomiDiscoverHTTPResult(status: 400, body: Data("{\"error\":\"invalid_media\"}".utf8)))
        guard case .failure(.invalidMedia) = rejected else {
            return XCTFail("expected invalid_media")
        }
        XCTAssertEqual(tellomiDiscoverImageRetryNonce(current: self.nonce), self.nonce)
        XCTAssertEqual(TellomiDiscoverVisibility.contacts.rawValue, "contacts")
        XCTAssertEqual(TellomiDiscoverVisibility.closeFriends.rawValue, "close_friends")
    }

    func testImageBytesLimitsAndCardURLs() {
        XCTAssertEqual(tellomiDiscoverInspectImage(self.png(width: 1, height: 1)), .upload(kind: "png", width: 1, height: 1))
        XCTAssertEqual(tellomiDiscoverInspectImage(self.jpeg(width: 12, height: 8)), .upload(kind: "jpeg", width: 12, height: 8))
        XCTAssertEqual(tellomiDiscoverInspectImage(self.webp(width: 2, height: 3)), .upload(kind: "webp", width: 2, height: 3))
        XCTAssertEqual(tellomiDiscoverInspectImage(self.heic()), .convertHeic)
        XCTAssertEqual(tellomiDiscoverInspectImage(self.png(width: 12_001, height: 1)), .rejected)
        XCTAssertEqual(tellomiDiscoverInspectImage(self.png(width: 10_000, height: 5_001)), .rejected)
        XCTAssertEqual(tellomiDiscoverInspectImage(Data(repeating: 0, count: TellomiDiscoverImageContract.maxBytes + 1)), .rejected)

        let cards = tellomiDiscoverParseCards(Data("""
        {"cards":[{"id":"post-1","state":"ok","card":{"text":"hi","media":[{"type":"image","key":"\(self.key)","w":640,"h":480,"url":"https://cdn.example/signed"},{"type":"image","key":"m/not-a-uuid","w":1,"h":1}]}}]}
        """.utf8))
        XCTAssertEqual(cards?.first?.imageCount, 2)
        XCTAssertEqual(cards?.first?.images.count, 1)
        let image = cards!.first!.images[0]
        let base = tellomiDiscoverMediaBaseURL("https://cdn.example/media")
        XCTAssertEqual(tellomiDiscoverImageURL(image: image, mediaBaseURL: base)?.absoluteString, "https://cdn.example/signed")
        let withoutURL = TellomiDiscoverImageMedia(key: self.key, width: 1, height: 1, url: nil)
        XCTAssertEqual(tellomiDiscoverImageURL(image: withoutURL, mediaBaseURL: base)?.absoluteString, "https://cdn.example/media/\(self.key)")
        XCTAssertNil(tellomiDiscoverImageURL(image: withoutURL, mediaBaseURL: nil))
        XCTAssertNil(tellomiDiscoverMediaBaseURL("http://cdn.example/media"))
        let config = tellomiDiscoverParseEngineConfig(Data("{\"enabled\":true,\"media_base_url\":\"https://cdn.example/media\"}".utf8))
        XCTAssertEqual(config?.mediaBaseURL, base)
        let ignored = tellomiDiscoverParseEngineConfig(Data("{\"enabled\":true,\"media_base_url\":\"http://cdn.example/media\"}".utf8))
        XCTAssertEqual(ignored?.enabled, true)
        XCTAssertNil(ignored?.mediaBaseURL)
        let remote = [tellomiDiscoverImageURL(image: image, mediaBaseURL: base)!]
        XCTAssertEqual(tellomiDiscoverImagePreviewSource(moderation: .pending, remoteURLs: remote, hasLocalBytes: true), .local)
        XCTAssertEqual(tellomiDiscoverImagePreviewSource(moderation: .hidden, remoteURLs: remote, hasLocalBytes: true), .none)
        XCTAssertEqual(tellomiDiscoverImagePreviewSource(moderation: .unknown, remoteURLs: remote, hasLocalBytes: true), .none)
        XCTAssertEqual(tellomiDiscoverImagePreviewSource(moderation: .published, remoteURLs: remote, hasLocalBytes: true), .remote(remote))
        let missing = tellomiDiscoverParseCards(Data("{\"cards\":[{\"id\":\"post-1\"}]}".utf8))
        XCTAssertEqual(missing?.first?.state, "")
        XCTAssertEqual(tellomiDiscoverDisplayPost(missing!.first!).moderation, .unknown)
        XCTAssertEqual(tellomiDiscoverDisplayPost(missing!.first!).unavailable, true)
        let pending = tellomiDiscoverParseCards(Data("{\"cards\":[{\"id\":\"post-1\",\"state\":\"pending\",\"card\":{\"text\":\"hi\",\"media\":[{\"type\":\"image\",\"key\":\"\(self.key)\",\"w\":1,\"h\":1,\"url\":\"https://cdn.example/a\"}]}}]}".utf8))
        let pendingPost = tellomiDiscoverDisplayPost(pending!.first!)
        XCTAssertEqual(pendingPost.moderation, .pending)
        XCTAssertFalse(pendingPost.unavailable)
        XCTAssertEqual(tellomiDiscoverPostSummary(post: pendingPost, copy: .resolve(languageCode: "zh"), list: false).body, "hi")
        let book = TellomiDiscoverLocalPreviewBook()
        book.keep(account: "a", postId: "post-1", images: [Data([1])])
        book.keep(account: "b", postId: "post-1", images: [Data([2])])
        XCTAssertEqual(book.images(account: "a", postId: "post-1"), [Data([1])])
        XCTAssertEqual(book.images(account: "b", postId: "post-1"), [Data([2])])
        book.dropAll()
        XCTAssertTrue(book.images(account: "a", postId: "post-1").isEmpty)
    }

    #if os(Linux)
    static var allTests: [(String, (TellomiDiscoverImageWireTests) -> () throws -> Void)] {
        return [
            ("testOptionsCreatePatchAndResumeStayOnTheFeedOrigin", testOptionsCreatePatchAndResumeStayOnTheFeedOrigin),
            ("testRejectedLocationNeverReceivesTheCredential", testRejectedLocationNeverReceivesTheCredential),
            ("testTooManyFormatAndCancel", testTooManyFormatAndCancel),
            ("testDeleteOfAnUnattachedUploadAndHiddenFeed", testDeleteOfAnUnattachedUploadAndHiddenFeed),
            ("testLoaderWithholdsTheCredentialAndRetriesExpiry", testLoaderWithholdsTheCredentialAndRetriesExpiry),
            ("testMediaKeysOrderEmptyTextAndInvalidMedia", testMediaKeysOrderEmptyTextAndInvalidMedia),
            ("testImageBytesLimitsAndCardURLs", testImageBytesLimitsAndCardURLs)
        ]
    }
    #endif

    private func optionsResponse() -> TellomiDiscoverHTTPResult {
        return TellomiDiscoverHTTPResult(status: 204, body: Data(), headers: [
            "Tus-Version": "1.0.0",
            "Tus-Extension": "creation,termination",
            "Tus-Max-Size": "20971520"
        ])
    }

    private func created(_ key: String) -> TellomiDiscoverHTTPResult {
        return TellomiDiscoverHTTPResult(status: 201, body: Data("{\"id\":\"upload-1\",\"key\":\"\(key)\"}".utf8), headers: [
            "Location": "https://feed.example/v1/feed/media/uploads/upload-1",
            "Media-Key": key
        ])
    }

    private func png(width: Int, height: Int) -> Data {
        var data = Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13])
        data.append(contentsOf: [73, 72, 68, 82])
        data.append(self.big(width))
        data.append(self.big(height))
        data.append(contentsOf: [8, 2, 0, 0, 0])
        return data
    }

    private func jpeg(width: Int, height: Int) -> Data {
        var data = Data([0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x0B, 0x08])
        data.append(UInt8((height >> 8) & 0xFF))
        data.append(UInt8(height & 0xFF))
        data.append(UInt8((width >> 8) & 0xFF))
        data.append(UInt8(width & 0xFF))
        data.append(contentsOf: [1, 0x11, 0x00, 0xFF, 0xD9])
        return data
    }

    private func webp(width: Int, height: Int) -> Data {
        var data = Data([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x58, 10, 0, 0, 0, 0, 0, 0, 0])
        let canvasWidth = width - 1
        let canvasHeight = height - 1
        data.append(UInt8(canvasWidth & 0xFF))
        data.append(UInt8((canvasWidth >> 8) & 0xFF))
        data.append(UInt8((canvasWidth >> 16) & 0xFF))
        data.append(UInt8(canvasHeight & 0xFF))
        data.append(UInt8((canvasHeight >> 8) & 0xFF))
        data.append(UInt8((canvasHeight >> 16) & 0xFF))
        return data
    }

    private func heic() -> Data {
        return Data([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63, 0, 0, 0, 0])
    }

    private func big(_ value: Int) -> Data {
        return Data([UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }
}
