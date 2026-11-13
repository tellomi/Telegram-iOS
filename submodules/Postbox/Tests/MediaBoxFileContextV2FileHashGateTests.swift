import Foundation
import XCTest
import SwiftSignalKit
@testable import Postbox

/// A commit hook can hold the partial-to-complete link. Allowing it links the file.
/// Refusing it deletes the partial bytes and fails the fetch.
final class MediaBoxFileContextV2FileHashGateTests: XCTestCase {
    private var queue: Queue!
    private var basePath: String!
    private var manager: MediaBoxFileManager!
    private var context: MediaBoxFileContextV2Impl!
    private var hook: MediaBoxBeforeCompleteCommit?
    private var fetchDisposable: Disposable?

    private var fullPath: String { return self.basePath + "/resource" }
    private var partialPath: String { return self.basePath + "/resource_partial" }

    override func setUp() {
        super.setUp()
        self.queue = Queue(name: "MediaBoxFileContextV2FileHashGateTests")
        self.basePath = NSTemporaryDirectory() + "MediaBoxFileContextV2FileHashGateTests-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: self.basePath, withIntermediateDirectories: true)
        self.manager = MediaBoxFileManager(queue: self.queue)
        self.queue.sync {
            self.context = MediaBoxFileContextV2Impl(
                queue: self.queue,
                manager: self.manager,
                storageBox: nil,
                resourceId: "resource".data(using: .utf8)!,
                path: self.fullPath,
                partialPath: self.partialPath,
                metaPath: self.partialPath + ".meta",
                beforeCompleteCommit: { [weak self] in
                    return self?.hook
                }
            )
        }
        XCTAssertNotNil(self.context)
    }

    override func tearDown() {
        self.fetchDisposable?.dispose()
        self.fetchDisposable = nil
        self.queue.sync {
            self.context = nil
        }
        self.manager = nil
        let _ = try? FileManager.default.removeItem(atPath: self.basePath)
        super.tearDown()
    }

    func testNoHookLinksTheFile() {
        self.hook = nil
        let completed = self.expectation(description: "completed")
        self.fetch(payload: Data([1, 2, 3, 4]), completed: {
            completed.fulfill()
        }, error: {
            XCTFail("unexpected error")
        })
        self.wait(for: [completed], timeout: 5.0)
        XCTAssertEqual(self.bytes(at: self.fullPath), Data([1, 2, 3, 4]))
    }

    func testHookCanLinkOrReject() {
        self.hook = { resourceKey, _, _, decision in
            XCTAssertEqual(resourceKey, "resource")
            decision(true)
            return true
        }
        let completed = self.expectation(description: "allowed")
        self.fetch(payload: Data([9, 8, 7]), completed: {
            completed.fulfill()
        }, error: {
            XCTFail("allow must not fail the fetch")
        })
        self.wait(for: [completed], timeout: 5.0)
        XCTAssertEqual(self.bytes(at: self.fullPath), Data([9, 8, 7]))
        self.fetchDisposable?.dispose()
        self.fetchDisposable = nil

        self.queue.sync {
            self.context = nil
        }
        let _ = try? FileManager.default.removeItem(atPath: self.fullPath)
        let _ = try? FileManager.default.removeItem(atPath: self.partialPath)
        self.queue.sync {
            self.context = MediaBoxFileContextV2Impl(
                queue: self.queue,
                manager: self.manager,
                storageBox: nil,
                resourceId: "resource".data(using: .utf8)!,
                path: self.fullPath,
                partialPath: self.partialPath,
                metaPath: self.partialPath + ".meta",
                beforeCompleteCommit: { [weak self] in
                    return self?.hook
                }
            )
        }
        self.hook = { _, _, _, decision in
            decision(false)
            return true
        }
        let failed = self.expectation(description: "rejected")
        self.fetch(payload: Data([1, 2, 3, 4]), completed: {
            XCTFail("reject must not complete the fetch")
        }, error: {
            failed.fulfill()
        })
        self.wait(for: [failed], timeout: 5.0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: self.fullPath))
        XCTAssertNotEqual(self.bytes(at: self.partialPath), Data([1, 2, 3, 4]))
    }

    func testHookThatReturnsFalseLinksImmediately() {
        self.hook = { _, _, _, _ in
            return false
        }
        let completed = self.expectation(description: "completed")
        self.fetch(payload: Data([5]), completed: {
            completed.fulfill()
        }, error: {
            XCTFail("unexpected error")
        })
        self.wait(for: [completed], timeout: 5.0)
        XCTAssertEqual(self.bytes(at: self.fullPath), Data([5]))
    }

    private func fetch(payload: Data, completed: @escaping () -> Void, error: @escaping () -> Void) {
        self.fetchDisposable?.dispose()
        self.queue.sync {
            self.fetchDisposable = self.context.fetchedFullRange(fetch: { _ in
                return Signal { subscriber in
                    subscriber.putNext(.dataPart(resourceOffset: 0, data: payload, range: 0 ..< Int64(payload.count), complete: false))
                    subscriber.putNext(.resourceSizeUpdated(Int64(payload.count)))
                    subscriber.putCompletion()
                    return EmptyDisposable
                }
            }, error: { _ in
                error()
            }, completed: {
                completed()
            })
        }
    }

    private func bytes(at path: String) -> Data? {
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }
}
