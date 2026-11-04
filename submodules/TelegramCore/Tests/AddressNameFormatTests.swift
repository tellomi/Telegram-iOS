import XCTest
@testable import TelegramCore

/// Public username length. Teamgram #182 accepts 4 characters; 3 stays invalid.
/// Settings, channel, and group public links all go through this check.
final class AddressNameFormatTests: XCTestCase {
    func testFourCharactersPass() {
        XCTAssertNil(_internal_checkAddressNameFormat("abcd"))
        XCTAssertNil(_internal_checkAddressNameFormat("ab1d"))
        XCTAssertNil(_internal_checkAddressNameFormat("ab_d"))
    }

    func testThreeCharactersAreTooShort() {
        XCTAssertEqual(_internal_checkAddressNameFormat("abc"), .tooShort)
        XCTAssertEqual(_internal_checkAddressNameFormat("ab1"), .tooShort)
        XCTAssertEqual(_internal_checkAddressNameFormat("a_b"), .tooShort)
    }

    func testATrailingUnderscoreOnThreeCharactersIsTooShort() {
        XCTAssertEqual(_internal_checkAddressNameFormat("ab_"), .tooShort)
    }

    func testATrailingUnderscoreOnFourCharactersIsNotTheLengthError() {
        XCTAssertEqual(_internal_checkAddressNameFormat("abc_"), .endsWithUnderscore)
    }
}
