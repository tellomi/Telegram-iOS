import XCTest

final class TellomiLoginFieldColorsTests: XCTestCase {
    func testTypedTextClearsBothFills() {
        for dark in [false, true] {
            let colors = tellomiLoginFieldColors(dark: dark)
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.text, colors.fill), 4.5, "dark=\(dark)")
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.caret, colors.fill), 3.0, "dark=\(dark)")
        }
    }

    func testDarkDigitsAreNotDrawnOnTheLightFill() {
        let dark = tellomiLoginFieldColors(dark: true)
        let light = tellomiLoginFieldColors(dark: false)
        XCTAssertLessThan(tellomiContrastRatio(dark.text, light.fill), 2.0)
        XCTAssertEqual(dark.fill, 0x2C2C2E)
        XCTAssertEqual(dark.text, 0xFFFFFF)
        XCTAssertEqual(light.fill, 0xF2F3F5)
        XCTAssertEqual(light.text, 0x111111)
    }

    /// Default dark theme placeholder `0x4d4d4d` on the dark field fill.
    func testDarkThemePlaceholderGrayFailsOnTheDarkField() {
        XCTAssertLessThan(tellomiContrastRatio(0x4D4D4D, tellomiLoginFieldColors(dark: true).fill), 3.0)
        XCTAssertGreaterThanOrEqual(
            tellomiContrastRatio(tellomiLoginFieldColors(dark: true).placeholder, tellomiLoginFieldColors(dark: true).fill),
            3.0
        )
    }
}
