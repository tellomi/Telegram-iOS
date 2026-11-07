import XCTest
import TellomiWallpapers

/// Theme colors, chat themes, and wallpapers: the lists that can be previewed
/// without a document download, persistence of a no-file wallpaper id, light
/// and dark palettes, and a failed or empty wallpaper fetch.
final class ThemeSurfaceRestoreTests: XCTestCase {
    func testColorGridHasTheLightAndDarkPalettes() {
        let lightSolids = ThemeWallpaperPalette.solids(dark: false)
        let darkSolids = ThemeWallpaperPalette.solids(dark: true)
        XCTAssertEqual(lightSolids.count, 27)
        XCTAssertEqual(darkSolids.count, 27)
        XCTAssertNotEqual(lightSolids, darkSolids)
        XCTAssertEqual(Set(lightSolids).count, lightSolids.count)
        XCTAssertEqual(Set(darkSolids).count, darkSolids.count)
        XCTAssertEqual(lightSolids.last, 0x000000)
        XCTAssertEqual(darkSolids.last, 0x000000)

        let lightGradients = ThemeWallpaperPalette.gradients(dark: false)
        let darkGradients = ThemeWallpaperPalette.gradients(dark: true)
        XCTAssertEqual(lightGradients.count, 9)
        XCTAssertEqual(darkGradients.count, 9)
        XCTAssertNotEqual(lightGradients, darkGradients)
        for row in lightGradients + darkGradients {
            XCTAssertGreaterThanOrEqual(row.count, 2)
        }
    }

    func testPickerOffersClassicTintedDayAndNight() {
        XCTAssertEqual(themePickerBuiltinOrder(autoNight: false), [.dayClassic, .nightAccent, .day, .night])
        XCTAssertEqual(themePickerBuiltinOrder(autoNight: true), [.nightAccent, .night])
    }

    func testNofileSolidKeepsItsIdAndPaintsThatColor() {
        let paint = nofileWallpaperPaint(id: 9_100_000_001, colors: [0xF2F2F2], rotation: nil, emoticon: nil)
        XCTAssertEqual(paint, .fill(id: 9_100_000_001, colors: [0xF2F2F2, 0xF2F2F2], rotation: nil))
    }

    func testNofileGradientKeepsEveryStop() {
        let paint = nofileWallpaperPaint(id: 9_100_000_005, colors: [0x121212, 0x1E1E1E], rotation: 180, emoticon: nil)
        XCTAssertEqual(paint, .fill(id: 9_100_000_005, colors: [0x121212, 0x1E1E1E], rotation: 180))
    }

    func testPickedColorWithoutAnIdStaysASolid() {
        XCTAssertEqual(nofileWallpaperPaint(id: 0, colors: [0xD3DFEA], rotation: nil, emoticon: nil), .solid(0xD3DFEA))
    }

    func testEmoticonWallpaperAndMissingSettings() {
        XCTAssertEqual(nofileWallpaperPaint(id: 0, colors: [], rotation: nil, emoticon: "😀"), .emoticon("😀"))
        XCTAssertEqual(nofileWallpaperPaint(id: 4, colors: [], rotation: nil, emoticon: nil), .missing)
    }

    func testEmptyOrFailedWallpaperFetchDoesNotInventFileWallpapers() {
        XCTAssertEqual(wallpaperGridSource(remoteCount: 7, fetchFailed: false), .remoteAndBuiltin)
        XCTAssertEqual(wallpaperGridSource(remoteCount: 0, fetchFailed: false), .builtinOnly)
        XCTAssertEqual(wallpaperGridSource(remoteCount: 0, fetchFailed: true), .builtinOnly)
        XCTAssertEqual(wallpaperGridSource(remoteCount: 7, fetchFailed: true), .builtinOnly)
    }

    func testChatThemeWithoutAStickerStillShowsTheEmoticon() {
        XCTAssertEqual(chatThemeEmoticonLabel(hasEmojiFile: false, emoticon: "😀"), "😀")
        XCTAssertEqual(chatThemeEmoticonLabel(hasEmojiFile: false, emoticon: "❤️"), "❤️")
        XCTAssertNil(chatThemeEmoticonLabel(hasEmojiFile: true, emoticon: "😀"))
        XCTAssertNil(chatThemeEmoticonLabel(hasEmojiFile: false, emoticon: nil))
        XCTAssertNil(chatThemeEmoticonLabel(hasEmojiFile: false, emoticon: ""))
    }

    func testChatThemePreviewUsesTheAccentWhenThereIsNoWallpaper() {
        XCTAssertEqual(chatThemePreviewFill(accent: 0x3390EC, hasWallpaper: false), 0x3390EC)
        XCTAssertNil(chatThemePreviewFill(accent: 0x3390EC, hasWallpaper: true))
        XCTAssertNil(chatThemePreviewFill(accent: nil, hasWallpaper: false))
    }

    func testApplyingAPaletteColorRoundTripsTheSameBits() {
        let chosen = ThemeWallpaperPalette.solids(dark: false)[2]
        let stored = nofileWallpaperPaint(id: 0, colors: [chosen], rotation: nil, emoticon: nil)
        XCTAssertEqual(stored, .solid(chosen))
        let darkChosen = ThemeWallpaperPalette.solids(dark: true)[0]
        XCTAssertNotEqual(chosen, darkChosen)
    }
}
