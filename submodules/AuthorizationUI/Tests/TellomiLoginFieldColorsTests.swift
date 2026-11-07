import XCTest

final class TellomiLoginFieldColorsTests: XCTestCase {
    func testTypedTextClearsBothFills() {
        for dark in [false, true] {
            let colors = tellomiLoginSurfaceColors(dark: dark)
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.fieldText, colors.fieldFill), 4.5, "text dark=\(dark)")
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.placeholder, colors.fieldFill), 4.5, "placeholder dark=\(dark)")
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.caret, colors.fieldFill), 3.0, "caret dark=\(dark)")
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.error, colors.page), 4.5, "error dark=\(dark)")
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.error, colors.fieldFill), 3.0, "error on field dark=\(dark)")
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.buttonForeground, colors.buttonBackground), 4.5, "button dark=\(dark)")
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.buttonDisabledForeground, colors.buttonDisabledBackground), 4.5, "disabled dark=\(dark)")
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.link, colors.page), 4.5, "link dark=\(dark)")
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.secondaryText, colors.page), 4.5, "secondary dark=\(dark)")
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.checkboxStroke, colors.page), 3.0, "checkbox dark=\(dark)")
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.checkboxTick, colors.checkboxFill), 4.5, "tick dark=\(dark)")
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.fieldBorder, colors.page), 3.0, "field border dark=\(dark)")
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.codeInactiveBorder, colors.fieldFill), 3.0, "code idle dark=\(dark)")
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.codeActiveBorder, colors.fieldFill), 3.0, "code focus dark=\(dark)")
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.rowText, colors.rowBackground), 4.5, "row dark=\(dark)")
            XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.rowBorder, colors.page), 3.0, "row border dark=\(dark)")
        }
    }

    func testLightFieldStaysTheUpstreamFillAndTheNightFieldSeparatesFromBlack() {
        let light = tellomiLoginSurfaceColors(dark: false)
        let night = tellomiLoginSurfaceColors(dark: true)
        XCTAssertEqual(light.fieldFill, 0xF2F2F7)
        XCTAssertEqual(light.fieldText, 0x000000)
        XCTAssertEqual(light.buttonBackground, 0x000000)
        XCTAssertEqual(light.buttonForeground, 0xFFFFFF)
        XCTAssertEqual(night.buttonBackground, 0xFFFFFF)
        XCTAssertGreaterThanOrEqual(tellomiContrastRatio(night.fieldFill, night.page), 1.45)
        XCTAssertLessThan(tellomiContrastRatio(night.fieldText, light.fieldFill), 2.0)
    }

    /// The pairs that were on screen: a gray ring on white, placeholder on the light fill,
    /// disabled label on the gray button, and the dark-theme placeholder on the dark fill.
    func testPreviousPairsFailAA() {
        XCTAssertLessThan(tellomiContrastRatio(0xC7C7CC, 0xFFFFFF), 3.0)
        XCTAssertLessThan(tellomiContrastRatio(0xB0B0B6, 0xF2F3F5), 3.0)
        XCTAssertLessThan(tellomiContrastRatio(0xB6B6BB, 0xF2F2F7), 3.0)
        XCTAssertLessThan(tellomiContrastRatio(0x8E8E93, 0xE5E5E5), 3.0)
        XCTAssertLessThan(tellomiContrastRatio(0x4D4D4D, 0x2C2C2E), 3.0)
        XCTAssertLessThan(tellomiContrastRatio(0xE5E5E5, 0xF2F2F7), 3.0)
        XCTAssertLessThan(tellomiContrastRatio(0x8E8E93, 0xFFFFFF), 4.5)
        XCTAssertLessThan(tellomiContrastRatio(0x3390EC, 0xFFFFFF), 4.5)
    }

    /// Default dark theme placeholder `0x4d4d4d` and the input fill `0x0f0f0f` are what
    /// `palette(theme:)` reads. Both are lifted.
    func testDarkThemeTokensAreLifted() {
        var tokens = tellomiDefaultLoginTokens(dark: true)
        tokens.fieldFill = 0x0F0F0F
        tokens.placeholder = 0x4D4D4D
        tokens.checkStroke = tellomiMix(0x000000, 0xFFFFFF, 0.3)
        let colors = tellomiLoginSurfaceColors(tokens)
        XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.fieldFill, colors.page), 1.45)
        XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.placeholder, colors.fieldFill), 4.5)
        XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.checkboxStroke, colors.page), 3.0)
        XCTAssertGreaterThanOrEqual(tellomiContrastRatio(colors.fieldText, colors.fieldFill), 4.5)
        XCTAssertNotEqual(colors.placeholder, 0x4D4D4D)
        XCTAssertNotEqual(colors.checkboxStroke, tokens.checkStroke)
    }

    func testLightAccentLinkIsDarkenedAndTheCheckStaysFilled() {
        let light = tellomiLoginSurfaceColors(dark: false)
        XCTAssertGreaterThanOrEqual(tellomiContrastRatio(light.link, light.page), 4.5)
        XCTAssertNotEqual(light.link, 0x3390EC)
        XCTAssertGreaterThanOrEqual(tellomiContrastRatio(light.checkboxTick, light.checkboxFill), 4.5)
        XCTAssertNotEqual(light.checkboxStroke, 0xC7C7CC)
    }
}
