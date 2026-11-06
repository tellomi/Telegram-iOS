import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class TellomiRedirectHost: @unchecked Sendable {
    var value: String?
    var error: String?
}

final class TellomiDiscoverImageClosureTests: XCTestCase {
    private let base = URL(string: "https://feed.example")!
    private var redirectProcess: Process?
    private let location = URL(string: "https://feed.example/v1/feed/media/uploads/upload-1")!

    func testTenImagesStayReachableWithoutCoveringTextPollOrLink() {
        var pieces: [TellomiDiscoverDetailPiece] = [.text(80)]
        for _ in 0 ..< 10 {
            pieces.append(.image(160))
        }
        pieces.append(.link(50))
        pieces.append(.poll(40))
        pieces.append(.comment(44))
        let viewport = 640.0
        let layout = tellomiDiscoverDetailLayout(contentWidth: 390, viewportHeight: viewport, pieces: pieces, bottom: 34)
        XCTAssertEqual(layout.frames.count, 14)
        XCTAssertGreaterThan(layout.contentHeight, viewport)
        let images = Array(layout.frames[1 ..< 11])
        XCTAssertEqual(images.count, 10)
        for frame in images {
            XCTAssertTrue(layout.reachable(frame))
            XCTAssertLessThanOrEqual(frame.width, layout.frames[0].width)
        }
        XCTAssertGreaterThan(images.last?.y ?? 0, viewport - 160)
        XCTAssertLessThanOrEqual(layout.frames[0].maxY, images[0].y)
        XCTAssertLessThanOrEqual(images.last?.maxY ?? 0, layout.frames[11].y)
        XCTAssertEqual(layout.frames[11].height, 50)
        XCTAssertEqual(layout.frames[12].height, 40)
        XCTAssertEqual(layout.frames[0].width, layout.frames[11].width)
        XCTAssertEqual(layout.frames[0].width, layout.frames[12].width)
        for pair in zip(layout.frames, layout.frames.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.maxY, pair.1.y)
        }
    }

    func testJPEGPNGandWebPDropLocationWithoutReencodingPixels() {
        let clean = self.jpeg(tiff: self.tiff(gps: false), xmp: nil)
        let cleanStripped = tellomiDiscoverStripImageLocation(clean)
        XCTAssertEqual(cleanStripped, clean)
        XCTAssertEqual(tellomiDiscoverImageOrientation(clean), 6)
        XCTAssertFalse(tellomiDiscoverImageHasLocation(clean))

        let xmp = "<x:xmpmeta xmlns:exif=\"x\" xmlns:tiff=\"y\"><rdf:Description tiff:Orientation=\"6\" exif:GPSLatitude=\"30,15.0N\" exif:GPSLongitude=\"104,4.0E\"/></x:xmpmeta>"
        let located = self.jpeg(tiff: self.tiff(gps: true), xmp: xmp)
        XCTAssertTrue(tellomiDiscoverImageHasLocation(located))
        XCTAssertTrue(located.contains(self.sentinel))
        let stripped = tellomiDiscoverStripImageLocation(located)
        XCTAssertNotNil(stripped)
        XCTAssertFalse(tellomiDiscoverImageHasLocation(stripped!))
        XCTAssertFalse(stripped!.contains(self.sentinel))
        XCTAssertNil(stripped!.range(of: Data("GPSLatitude".utf8)))
        XCTAssertNotNil(stripped!.range(of: Data("tiff:Orientation=\"6\"".utf8)))
        XCTAssertEqual(tellomiDiscoverImageOrientation(stripped!), 6)
        XCTAssertEqual(tellomiDiscoverInspectImage(stripped!), .upload(kind: "jpeg", width: 1, height: 1))
        XCTAssertEqual(self.entropy(stripped!), self.entropy(located))
        XCTAssertEqual(self.segment(stripped!, marker: 0xC0), self.segment(located, marker: 0xC0))
        XCTAssertLessThan(stripped!.count, located.count)
        XCTAssertEqual(stripped!.prefix(2), Data([0xFF, 0xD8]))

        let png = self.png(exif: self.tiff(gps: true))
        let pngStripped = tellomiDiscoverStripImageLocation(png)
        XCTAssertNotNil(pngStripped)
        XCTAssertFalse(tellomiDiscoverImageHasLocation(pngStripped!))
        XCTAssertFalse(pngStripped!.contains(self.sentinel))
        XCTAssertEqual(tellomiDiscoverImageOrientation(pngStripped!), 6)
        XCTAssertEqual(tellomiDiscoverInspectImage(pngStripped!), .upload(kind: "png", width: 1, height: 1))
        XCTAssertEqual(self.pngChunk(pngStripped!, type: "IDAT"), self.pngChunk(png, type: "IDAT"))
        XCTAssertEqual(self.pngChunk(pngStripped!, type: "IHDR"), self.pngChunk(png, type: "IHDR"))
        XCTAssertEqual(pngStripped!.prefix(8), Data([137, 80, 78, 71, 13, 10, 26, 10]))

        let cleanPNG = self.png(exif: self.tiff(gps: false))
        XCTAssertEqual(tellomiDiscoverStripImageLocation(cleanPNG), cleanPNG)

        let webp = self.webp(exif: self.tiff(gps: true))
        let webpStripped = tellomiDiscoverStripImageLocation(webp)
        XCTAssertNotNil(webpStripped)
        XCTAssertFalse(tellomiDiscoverImageHasLocation(webpStripped!))
        XCTAssertFalse(webpStripped!.contains(self.sentinel))
        XCTAssertEqual(tellomiDiscoverImageOrientation(webpStripped!), 6)
        XCTAssertEqual(tellomiDiscoverInspectImage(webpStripped!), .upload(kind: "webp", width: 1, height: 1))
        XCTAssertEqual(self.webpChunk(webpStripped!, type: "VP8 "), self.webpChunk(webp, type: "VP8 "))
        XCTAssertEqual(webpStripped!.prefix(4), Data("RIFF".utf8))
    }

    func testCloseBackgroundAndLostCreateDoNotKeepBytesOrInventALocation() {
        var created = TellomiDiscoverImageUploadSession(length: 4)
        let bytes = Data([1, 2, 3, 4])
        _ = created.call(base: self.base, bytes: bytes)
        created.receive(TellomiDiscoverHTTPResult(status: 204, body: Data(), headers: [
            "Tus-Version": "1.0.0",
            "Tus-Extension": "creation,termination",
            "Tus-Max-Size": "20971520"
        ]), base: self.base)
        _ = created.call(base: self.base, bytes: bytes)
        XCTAssertTrue(created.createSent)
        created.transportFailed()
        XCTAssertTrue(created.mayBeOrphaned)
        XCTAssertEqual(tellomiDiscoverImageResidue(session: created, attached: false), .possibleOrphan)
        XCTAssertNil(created.location)
        XCTAssertEqual(tellomiDiscoverImageByteCount(after: .close, current: bytes.count), 0)
        XCTAssertEqual(tellomiDiscoverImageByteCount(after: .background, current: bytes.count), bytes.count)
        XCTAssertFalse(tellomiDiscoverImageShouldResume(created))

        var uploading = TellomiDiscoverImageUploadSession(length: 4)
        _ = uploading.call(base: self.base, bytes: bytes)
        uploading.receive(TellomiDiscoverHTTPResult(status: 204, body: Data(), headers: [
            "Tus-Version": "1.0.0",
            "Tus-Extension": "creation,termination",
            "Tus-Max-Size": "20971520"
        ]), base: self.base)
        uploading.receive(TellomiDiscoverHTTPResult(status: 201, body: Data("{\"id\":\"upload-1\",\"key\":\"m/11111111-1111-4111-8111-111111111111\"}".utf8), headers: [
            "Location": self.location.absoluteString,
            "Media-Key": "m/11111111-1111-4111-8111-111111111111"
        ]), base: self.base)
        XCTAssertEqual(tellomiDiscoverImageEnterBackground(&uploading), .resumeFromOffset)
        guard case .wait(let delay) = uploading.step else {
            return XCTFail("expected backoff before resume")
        }
        XCTAssertEqual(delay, tellomiDiscoverImageRetryDelay(strike: 1))
        uploading.waited()
        XCTAssertTrue(tellomiDiscoverImageShouldResume(uploading))
        XCTAssertEqual(tellomiDiscoverImageResidue(session: uploading, attached: false), .delete(self.location))
        XCTAssertEqual(tellomiDiscoverImageResidue(session: uploading, attached: true), .none)
        let delete = tellomiDiscoverImageDeleteCall(location: self.location, base: self.base)
        XCTAssertEqual(delete?.method, "DELETE")
        XCTAssertEqual(delete?.authorizes, true)
        XCTAssertNil(tellomiDiscoverImageDeleteCall(location: URL(string: "https://evil.example/v1/feed/media/uploads/x")!, base: self.base))
        XCTAssertEqual(tellomiDiscoverImageByteCount(after: .cancel, current: 4), 0)
        XCTAssertEqual(tellomiDiscoverImageByteCount(after: .foreground, current: 4), 4)
        var finished = uploading
        finished.waited()
        _ = finished.call(base: self.base, bytes: bytes)
        finished.receive(TellomiDiscoverHTTPResult(status: 204, body: Data(), headers: ["Upload-Offset": "4"]), base: self.base)
        XCTAssertEqual(finished.step, .done(key: "m/11111111-1111-4111-8111-111111111111"))
        finished.cancel()
        XCTAssertEqual(finished.step, .delete)
        XCTAssertEqual(tellomiDiscoverImageResidue(session: finished, attached: true), .none)
        XCTAssertEqual(tellomiDiscoverImageResidue(session: finished, attached: false, publishUncertain: true), .none)
    }

    func testSignOutStopsImageRequestsAndRedirectKeepsBearerOnTheOrigin() {
        var calls = 0
        let loader = TellomiDiscoverLoader(now: { 0 }, credential: TellomiDiscoverCredential(token: "jwt", expires: 10_000, region: "cn"), fetchCredential: { completion in
            completion(.success(TellomiDiscoverCredential(token: "jwt", expires: 10_000, region: "cn")))
        }, http: { _, completion in
            calls += 1
            completion(.success(TellomiDiscoverHTTPResult(status: 204, body: Data(), headers: [:])))
        })
        loader.signOut()
        let blocked = expectation(description: "blocked")
        _ = loader.performImage(loggedIn: true, configuration: TellomiDiscoverConfiguration(enabled: true, baseURL: self.base), call: TellomiDiscoverImageWireCall(method: "POST", url: URL(string: "https://feed.example/v1/feed/media/uploads")!, body: nil, authorizes: true, headers: [:])) { result in
            guard case .failure(.signedOut) = result else {
                return XCTFail("expected sign-out to stop the upload")
            }
            blocked.fulfill()
        }
        wait(for: [blocked], timeout: 1)
        XCTAssertEqual(calls, 0)

        let origin = URL(string: "https://feed.example/v1/feed/media/uploads")!
        switch tellomiDiscoverRedirect(original: origin, proposed: URL(string: "https://evil.example/v1/feed/media/uploads/x")!, authorizes: true) {
        case .refuse:
            break
        case .follow:
            XCTFail("bearer would leave the origin")
        }
        switch tellomiDiscoverRedirect(original: origin, proposed: URL(string: "https://feed.example/v1/other")!, authorizes: true) {
        case .refuse:
            break
        case .follow:
            XCTFail("path left the upload prefix")
        }
        switch tellomiDiscoverRedirect(original: origin, proposed: URL(string: "https://feed.example/v1/feed/media/uploads/upload-1")!, authorizes: true) {
        case let .follow(url, attachBearer):
            XCTAssertEqual(url.path, "/v1/feed/media/uploads/upload-1")
            XCTAssertTrue(attachBearer)
        case .refuse:
            XCTFail("same-origin upload redirect should be followed")
        }
        let webp = self.plainVP8()
        XCTAssertEqual(tellomiDiscoverInspectImage(webp), .upload(kind: "webp", width: 1, height: 1))
    }

    func testRedirectGateIsTheURLSessionDelegate() {
        let gate = TellomiDiscoverRedirectGate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: configuration, delegate: gate, delegateQueue: nil)
        let port = self.bindRedirect(to: "https://evil.example/steal")
        XCTAssertGreaterThan(port, 0)
        let expectation = expectation(description: "redirect")
        let host = TellomiRedirectHost()
        let task = session.dataTask(with: URL(string: "http://127.0.0.1:\(port)/v1/feed/media/uploads")!) { _, response, error in
            host.value = response?.url?.host
            host.error = error?.localizedDescription
            expectation.fulfill()
        }
        task.resume()
        wait(for: [expectation], timeout: 4)
        XCTAssertGreaterThan(port, 0)
        XCTAssertEqual(host.value, "127.0.0.1", host.error ?? "")
        session.invalidateAndCancel()
        self.redirectProcess?.terminate()
    }

    func testSignedOutDetailCannotReopenTheLoader() {
        var calls = 0
        let loader = TellomiDiscoverLoader(now: { 0 }, credential: TellomiDiscoverCredential(token: "jwt-a", expires: 10_000, region: "cn"), fetchCredential: { completion in
            completion(.success(TellomiDiscoverCredential(token: "jwt-b", expires: 10_000, region: "cn")))
        }, http: { _, completion in
            calls += 1
            completion(.success(TellomiDiscoverHTTPResult(status: 204, body: Data(), headers: [:])))
        })
        let configuration = TellomiDiscoverConfiguration(enabled: true, baseURL: self.base)
        let upload = TellomiDiscoverImageWireCall(method: "POST", url: URL(string: "https://feed.example/v1/feed/media/uploads")!, body: nil, authorizes: true, headers: [:])
        loader.noteSignedIn(account: "account-a")
        let opened = expectation(description: "opened")
        _ = loader.performImage(loggedIn: true, configuration: configuration, call: upload) { result in
            guard case .success = result else {
                return XCTFail("expected the signed-in upload")
            }
            opened.fulfill()
        }
        wait(for: [opened], timeout: 1)
        XCTAssertEqual(calls, 1)
        let staleLoggedIn = true
        loader.signOut()
        let blockedRun = expectation(description: "blocked-run")
        loader.run(loggedIn: staleLoggedIn, configuration: configuration, operation: .status) { result in
            guard case .failure(.signedOut) = result else {
                return XCTFail("a stale detail must not clear sign-out")
            }
            blockedRun.fulfill()
        }
        wait(for: [blockedRun], timeout: 1)
        let blockedImage = expectation(description: "blocked-image")
        _ = loader.performImage(loggedIn: staleLoggedIn, configuration: configuration, call: upload) { result in
            guard case .failure(.signedOut) = result else {
                return XCTFail("image upload stayed open after sign-out")
            }
            blockedImage.fulfill()
        }
        wait(for: [blockedImage], timeout: 1)
        XCTAssertEqual(calls, 1)
        loader.noteSignedIn(account: "account-b")
        let switched = expectation(description: "switched")
        _ = loader.performImage(loggedIn: true, configuration: configuration, call: upload) { result in
            guard case .success = result else {
                return XCTFail("a new account login should allow upload")
            }
            switched.fulfill()
        }
        wait(for: [switched], timeout: 1)
        XCTAssertEqual(calls, 2)
    }

    func testCyclicAndDeepExifIsRejected() {
        let started = Date()
        XCTAssertNil(tellomiDiscoverStripImageLocation(self.jpeg(tiff: self.cyclicTIFF(), xmp: nil)))
        XCTAssertNil(tellomiDiscoverStripImageLocation(self.jpeg(tiff: self.deepTIFF(links: 40), xmp: nil)))
        XCTAssertNil(tellomiDiscoverStripImageLocation(self.jpeg(tiff: self.hugeCountTIFF(), xmp: nil)))
        XCTAssertNil(tellomiDiscoverStripImageLocation(self.jpeg(tiff: self.offsetPastEndTIFF(), xmp: nil)))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        let clean = tellomiDiscoverStripImageLocation(self.jpeg(tiff: self.tiff(gps: false), xmp: nil))
        XCTAssertEqual(clean, self.jpeg(tiff: self.tiff(gps: false), xmp: nil))
    }

    #if os(Linux)
    static var allTests: [(String, (TellomiDiscoverImageClosureTests) -> () throws -> Void)] {
        return [
            ("testTenImagesStayReachableWithoutCoveringTextPollOrLink", testTenImagesStayReachableWithoutCoveringTextPollOrLink),
            ("testJPEGPNGandWebPDropLocationWithoutReencodingPixels", testJPEGPNGandWebPDropLocationWithoutReencodingPixels),
            ("testCloseBackgroundAndLostCreateDoNotKeepBytesOrInventALocation", testCloseBackgroundAndLostCreateDoNotKeepBytesOrInventALocation),
            ("testSignOutStopsImageRequestsAndRedirectKeepsBearerOnTheOrigin", testSignOutStopsImageRequestsAndRedirectKeepsBearerOnTheOrigin),
            ("testRedirectGateIsTheURLSessionDelegate", testRedirectGateIsTheURLSessionDelegate),
            ("testSignedOutDetailCannotReopenTheLoader", testSignedOutDetailCannotReopenTheLoader),
            ("testCyclicAndDeepExifIsRejected", testCyclicAndDeepExifIsRejected)
        ]
    }
    #endif

    private let sentinel = Data([0x01, 0x02, 0x03, 0x04])

    private func plainVP8() -> Data {
        let payload = Data([0x00, 0x00, 0x00, 0x9D, 0x01, 0x2A, 0x01, 0x00, 0x01, 0x00])
        var body = Data("WEBP".utf8)
        body.append(self.webpChunk("VP8 ", payload))
        var file = Data("RIFF".utf8)
        let size = UInt32(body.count)
        file.append(contentsOf: [UInt8(size & 0xFF), UInt8((size >> 8) & 0xFF), UInt8((size >> 16) & 0xFF), UInt8((size >> 24) & 0xFF)])
        file.append(body)
        return file
    }

    private func bindRedirect(to location: String) -> UInt16 {
        let script = """
import socket
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 0))
s.listen(1)
print(s.getsockname()[1], flush=True)
c, _ = s.accept()
c.settimeout(3)
try:
    c.recv(4096)
except Exception:
    pass
c.sendall(b"HTTP/1.1 302 Found\\r\\nLocation: \(location)\\r\\nContent-Length: 0\\r\\nConnection: close\\r\\n\\r\\n")
c.close()
"""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return 0
        }
        self.redirectProcess = process
        var collected = Data()
        let handle = output.fileHandleForReading
        while collected.count < 16 {
            let byte = handle.readData(ofLength: 1)
            if byte.isEmpty {
                break
            }
            collected.append(byte)
            if byte == Data([0x0A]) {
                break
            }
        }
        let text = String(data: collected, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return UInt16(text) ?? 0
    }

    private func cyclicTIFF() -> Data {
        var data = Data([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00])
        data.append(contentsOf: [0x00, 0x00])
        data.append(contentsOf: [0x08, 0x00, 0x00, 0x00])
        return data
    }

    private func deepTIFF(links: Int) -> Data {
        var data = Data([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00])
        for index in 0 ..< links {
            data.append(contentsOf: [0x00, 0x00])
            let next = index + 1 < links ? 8 + (index + 1) * 6 : 0
            data.append(contentsOf: [UInt8(next & 0xFF), UInt8((next >> 8) & 0xFF), UInt8((next >> 16) & 0xFF), UInt8((next >> 24) & 0xFF)])
        }
        return data
    }

    private func hugeCountTIFF() -> Data {
        var data = Data([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00])
        data.append(contentsOf: [0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00])
        return data
    }

    private func offsetPastEndTIFF() -> Data {
        return Data([0x49, 0x49, 0x2A, 0x00, 0xFF, 0xFF, 0x00, 0x00])
    }

    private func tiff(gps: Bool) -> Data {
        var data = Data([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00])
        if gps {
            data.append(contentsOf: [0x02, 0x00])
            data.append(contentsOf: [0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00])
            data.append(contentsOf: [0x25, 0x88, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 38, 0x00, 0x00, 0x00])
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
            data.append(contentsOf: [0x02, 0x00])
            data.append(contentsOf: [0x01, 0x00, 0x02, 0x00, 0x02, 0x00, 0x00, 0x00, 0x4E, 0x00, 0x00, 0x00])
            data.append(contentsOf: [0x02, 0x00, 0x05, 0x00, 0x03, 0x00, 0x00, 0x00, 68, 0x00, 0x00, 0x00])
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
            data.append(self.sentinel)
            data.append(contentsOf: [0x01, 0x00, 0x00, 0x00])
            data.append(contentsOf: [30, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])
        } else {
            data.append(contentsOf: [0x01, 0x00])
            data.append(contentsOf: [0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00])
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        }
        return data
    }

    private func jpeg(tiff: Data, xmp: String?) -> Data {
        var data = Data([0xFF, 0xD8])
        data.append(self.app1(Data("Exif\0\0".utf8) + tiff))
        if let xmp {
            data.append(self.app1(Data("http://ns.adobe.com/xap/1.0/\0".utf8) + Data(xmp.utf8)))
        }
        data.append(contentsOf: [0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00, 0x01, 0x01, 0x11, 0x00, 0x00])
        data.append(contentsOf: [0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0xA5, 0x5A, 0x11, 0x22, 0xFF, 0xD9])
        return data
    }

    private func app1(_ payload: Data) -> Data {
        var segment = Data([0xFF, 0xE1])
        let length = payload.count + 2
        segment.append(UInt8((length >> 8) & 0xFF))
        segment.append(UInt8(length & 0xFF))
        segment.append(payload)
        return segment
    }

    private func png(exif: Data) -> Data {
        var data = Data([137, 80, 78, 71, 13, 10, 26, 10])
        let ihdr = Data([0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00])
        data.append(self.pngChunk("IHDR", ihdr))
        data.append(self.pngChunk("eXIf", exif))
        data.append(self.pngChunk("IDAT", Data("PAY1".utf8)))
        data.append(self.pngChunk("IEND", Data()))
        return data
    }

    private func pngChunk(_ type: String, _ payload: Data) -> Data {
        var chunk = Data()
        let length = UInt32(payload.count)
        chunk.append(contentsOf: [UInt8((length >> 24) & 0xFF), UInt8((length >> 16) & 0xFF), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)])
        chunk.append(Data(type.utf8))
        chunk.append(payload)
        chunk.append(contentsOf: [0, 0, 0, 0])
        return chunk
    }

    private func webp(exif: Data) -> Data {
        var body = Data("WEBP".utf8)
        let vp8x = Data([0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        body.append(self.webpChunk("VP8X", vp8x))
        body.append(self.webpChunk("EXIF", Data("Exif\0\0".utf8) + exif))
        body.append(self.webpChunk("VP8 ", Data("PIXL".utf8)))
        var file = Data("RIFF".utf8)
        let size = UInt32(body.count)
        file.append(contentsOf: [UInt8(size & 0xFF), UInt8((size >> 8) & 0xFF), UInt8((size >> 16) & 0xFF), UInt8((size >> 24) & 0xFF)])
        file.append(body)
        return file
    }

    private func webpChunk(_ type: String, _ payload: Data) -> Data {
        var chunk = Data(type.utf8)
        let size = UInt32(payload.count)
        chunk.append(contentsOf: [UInt8(size & 0xFF), UInt8((size >> 8) & 0xFF), UInt8((size >> 16) & 0xFF), UInt8((size >> 24) & 0xFF)])
        chunk.append(payload)
        if payload.count % 2 == 1 {
            chunk.append(0)
        }
        return chunk
    }

    private func entropy(_ data: Data?) -> Data {
        guard let data else {
            return Data()
        }
        let bytes = [UInt8](data)
        guard let start = self.markerEnd(bytes, 0xDA) else {
            return Data()
        }
        return Data(bytes[start...])
    }

    private func segment(_ data: Data?, marker: UInt8) -> Data {
        guard let data else {
            return Data()
        }
        let bytes = [UInt8](data)
        var index = 2
        while index + 3 < bytes.count, bytes[index] == 0xFF {
            let found = bytes[index + 1]
            let length = (Int(bytes[index + 2]) << 8) + Int(bytes[index + 3])
            let end = index + 2 + length
            guard end <= bytes.count else {
                return Data()
            }
            if found == marker {
                return Data(bytes[index ..< end])
            }
            if found == 0xDA {
                return Data()
            }
            index = end
        }
        return Data()
    }

    private func markerEnd(_ bytes: [UInt8], _ marker: UInt8) -> Int? {
        var index = 2
        while index + 3 < bytes.count, bytes[index] == 0xFF {
            let found = bytes[index + 1]
            let length = (Int(bytes[index + 2]) << 8) + Int(bytes[index + 3])
            let end = index + 2 + length
            if found == marker {
                return end
            }
            if found == 0xDA || end > bytes.count {
                return nil
            }
            index = end
        }
        return nil
    }

    private func pngChunk(_ data: Data?, type: String) -> Data {
        guard let data else {
            return Data()
        }
        let bytes = [UInt8](data)
        let name = [UInt8](type.utf8)
        var index = 8
        while index + 8 <= bytes.count {
            let length = (Int(bytes[index]) << 24) + (Int(bytes[index + 1]) << 16) + (Int(bytes[index + 2]) << 8) + Int(bytes[index + 3])
            let start = index + 8
            let end = start + length
            guard end <= bytes.count else {
                return Data()
            }
            if Array(bytes[(index + 4) ..< (index + 8)]) == name {
                return Data(bytes[start ..< end])
            }
            index = end + 4
        }
        return Data()
    }

    private func webpChunk(_ data: Data?, type: String) -> Data {
        guard let data else {
            return Data()
        }
        let bytes = [UInt8](data)
        let name = [UInt8](type.utf8)
        var index = 12
        while index + 8 <= bytes.count {
            let size = Int(bytes[index + 4]) + (Int(bytes[index + 5]) << 8) + (Int(bytes[index + 6]) << 16) + (Int(bytes[index + 7]) << 24)
            let start = index + 8
            let end = start + size
            guard end <= bytes.count else {
                return Data()
            }
            if Array(bytes[index ..< index + 4]) == name {
                return Data(bytes[start ..< end])
            }
            index = end + (size % 2)
        }
        return Data()
    }
}
