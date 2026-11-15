import Foundation
import XCTest

final class TellomiAtomicStateLoadTests: XCTestCase {
    func testMissingOrUnreadableAtomicStateIsNotUsable() {
        XCTAssertNil(tellomiAtomicStatePayload(nil))
        XCTAssertNil(tellomiAtomicStatePayload(Data()))
        XCTAssertNil(tellomiAtomicStatePayload(Data("not-json".utf8)))
        XCTAssertNil(tellomiAtomicStatePayload(Data("{".utf8)))
    }

    func testAJsonObjectCanBeDecoded() {
        let bytes = Data("{\"records\":[]}".utf8)
        XCTAssertEqual(tellomiAtomicStatePayload(bytes), bytes)
    }
}
