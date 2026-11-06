import Foundation
import XCTest
import TellomiWallpapers

final class TellomiWallpapersTests: XCTestCase {
    func testAccentColorTableMatchesThePlan() {
        let expected: [(String, UInt32)] = [
            ("蓝", 0x3390EC),
            ("天青", 0x2AABEE),
            ("青", 0x00A8A8),
            ("绿", 0x31B545),
            ("薄荷", 0x25D366),
            ("黄", 0xF5A623),
            ("橙", 0xFF8A3D),
            ("红", 0xE5484D),
            ("粉", 0xEC4899),
            ("紫", 0x8B5CF6),
            ("靛", 0x5B5BD6),
            ("石墨", 0x5F6B7A),
        ]
        XCTAssertEqual(TellomiAccentColors.all.count, 12)
        XCTAssertEqual(TellomiAccentColors.all.map { ($0.name, $0.rgb) }, expected)
        XCTAssertEqual(TellomiAccentColors.defaultColor, 0x3390EC)
        XCTAssertEqual(Set(TellomiAccentColors.all.map(\.rgb)).count, 12)
    }

    func testDefaultWallpapers() {
        let light = TellomiWallpaperCatalog.defaultEntry(dark: false)
        XCTAssertEqual(light.id, "tm_doodle_light")
        XCTAssertEqual(light.pattern, "doodle")
        XCTAssertEqual(light.colors, [0xEFE7DD])
        XCTAssertEqual(light.intensity, 12)
        XCTAssertFalse(light.isDark)
        XCTAssertEqual(light.patternResourceSlug, "tm_doodle")

        let dark = TellomiWallpaperCatalog.defaultEntry(dark: true)
        XCTAssertEqual(dark.id, "tm_doodle_dark")
        XCTAssertEqual(dark.pattern, "doodle")
        XCTAssertEqual(dark.colors, [0x0B141A, 0x16232B])
        XCTAssertEqual(dark.intensity, -8)
        XCTAssertTrue(dark.isDark)
    }

    func testStockWallpaperListIsTheTenBuiltInsAndOneSeparateSolid() {
        XCTAssertEqual(TellomiWallpaperCatalog.stockEntries.count, 10)
        XCTAssertEqual(TellomiWallpaperCatalog.entries.map(\.id), [
            "tm_doodle_light",
            "tm_doodle_dark",
            "tm_mint",
            "tm_sky",
            "tm_peach",
            "tm_lavender",
            "tm_sunset",
            "tm_forest_dark",
            "tm_ocean_dark",
            "tm_aurora_dark",
        ])
        let patterned = TellomiWallpaperCatalog.stockEntries.filter { $0.pattern != nil }
        XCTAssertEqual(patterned.map(\.patternResourceSlug), [
            "tm_doodle", "tm_doodle", "tm_doodle", "tm_doodle", "tm_dots", "tm_waves", "tm_doodle", "tm_waves",
        ])
        XCTAssertEqual(TellomiWallpaperCatalog.patternResourceSlugs, ["tm_doodle", "tm_dots", "tm_waves"])

        XCTAssertNil(TellomiWallpaperCatalog.entry(id: "tm_sunset")?.pattern)
        XCTAssertNil(TellomiWallpaperCatalog.entry(id: "tm_aurora_dark")?.pattern)
        XCTAssertEqual(TellomiWallpaperCatalog.entry(id: "tm_sunset")?.colors, [0xFAD0C4, 0xFFD1FF, 0xFBC2EB, 0xA6C1EE])
        XCTAssertEqual(TellomiWallpaperCatalog.entry(id: "tm_mint")?.colors, [0xDBEED9, 0xB8DCC8, 0xE6F2D8, 0xC2E3D1])
        XCTAssertEqual(TellomiWallpaperCatalog.entry(id: "tm_forest_dark")?.intensity, -10)
        XCTAssertEqual(TellomiWallpaperCatalog.entry(id: "tm_ocean_dark")?.colors, [0x141E30, 0x243B55])

        XCTAssertEqual(TellomiWallpaperPresets.lightSolid, 0xF0F2F5)
        XCTAssertEqual(TellomiWallpaperPresets.darkSolid, 0x101418)
        XCTAssertEqual(TellomiWallpaperPresets.solidColor(dark: false), 0xF0F2F5)
        XCTAssertEqual(TellomiWallpaperPresets.solidColor(dark: true), 0x101418)
        XCTAssertNotEqual(TellomiWallpaperPresets.lightSolid, TellomiWallpaperPresets.legacyLightSolid)
        XCTAssertNotEqual(TellomiWallpaperPresets.darkSolid, TellomiWallpaperPresets.legacyDarkSolid)
    }

    func testSavedWallpaperIncludingPureBlackIsKept() {
        let chosen = [
            TellomiWallpaperPresets.legacyDarkSolid,
            TellomiWallpaperPresets.legacyLightSolid,
            TellomiWallpaperPresets.darkSolid,
            TellomiWallpaperPresets.lightSolid,
            0x112233 as UInt32,
        ]
        for color in chosen {
            XCTAssertFalse(TellomiWallpaperMigration.replacesSavedColor(color), String(format: "%06X", color))
            XCTAssertFalse(TellomiWallpaperMigration.replacesWithBundledDefault(hasSavedWallpaper: true, isBuiltinToken: false))
        }
    }

    func testUnsavedWallpaperUsesTheBundledDefault() {
        XCTAssertTrue(TellomiWallpaperMigration.replacesWithBundledDefault(hasSavedWallpaper: false, isBuiltinToken: false))
        XCTAssertTrue(TellomiWallpaperMigration.replacesWithBundledDefault(hasSavedWallpaper: false, isBuiltinToken: true))
    }

    func testBuiltinTokenMigratesBecauseItIsNotAChosenColor() {
        XCTAssertTrue(TellomiWallpaperMigration.replacesWithBundledDefault(hasSavedWallpaper: true, isBuiltinToken: true))
    }

    func testBubbleColorsAndSolidShadow() {
        XCTAssertEqual(TellomiBubbleColors.incomingLight, 0xFFFFFF)
        XCTAssertEqual(TellomiBubbleColors.incomingDark, 0x202C33)
        XCTAssertEqual(TellomiBubbleShadowSpec.radius, 0.5)
        XCTAssertEqual(TellomiBubbleShadowSpec.verticalOffset, 0.5)
        XCTAssertEqual(TellomiBubbleShadowSpec.alpha, 0.18)
    }

    func testBubbleShadowDrawsForEveryWallpaper() {
        XCTAssertTrue(TellomiBubbleChrome.drawsShadow(hasWallpaper: true))
        XCTAssertFalse(TellomiBubbleChrome.drawsShadow(hasWallpaper: false))
    }

    func testReactionCapsuleBackgroundsMatchUpstream() {
        XCTAssertEqual(TellomiReactionCapsules.classicOutgoingInactive, TellomiReactionCapsuleBackground(rgb: 0x3FC33B, alpha: 0.12))
        XCTAssertEqual(TellomiReactionCapsules.classicOutgoingActive, TellomiReactionCapsuleBackground(rgb: 0x3FC33B, alpha: 1))
        XCTAssertNotEqual(TellomiReactionCapsules.classicOutgoingActive.rgb, 0x000000)

        XCTAssertEqual(TellomiReactionCapsules.dayOutgoingInactive, TellomiReactionCapsuleBackground(rgb: 0xFFFFFF, alpha: 0.12))
        XCTAssertEqual(TellomiReactionCapsules.dayOutgoingActive, TellomiReactionCapsuleBackground(rgb: 0xFFFFFF, alpha: 1))
        XCTAssertNotEqual(TellomiReactionCapsules.dayOutgoingActive.rgb, 0x000000)

        XCTAssertEqual(TellomiReactionCapsules.darkIncomingInactive, TellomiReactionCapsuleBackground(rgb: 0xFFFFFF, alpha: 0.07))
        XCTAssertEqual(TellomiReactionCapsules.darkOutgoingInactive, TellomiReactionCapsuleBackground(rgb: 0xFFFFFF, alpha: 0.1))
        XCTAssertEqual(TellomiReactionCapsules.darkAccentedOutgoingInactive, TellomiReactionCapsuleBackground(rgb: 0xFFFFFF, alpha: 0.12))
        XCTAssertEqual(TellomiReactionCapsules.darkActive, TellomiReactionCapsuleBackground(rgb: 0xFFFFFF, alpha: 1))

        XCTAssertEqual(TellomiAccentColors.defaultColor, 0x3390EC)
    }

    func testOpenSourceNoticeNamesThePatternSources() {
        let text = TellomiOpenSourceNotices.text
        XCTAssertTrue(text.contains("Tabler Icons"))
        XCTAssertTrue(text.contains("MIT"))
        XCTAssertTrue(text.contains("Lucide"))
        XCTAssertTrue(text.contains("ISC"))
        XCTAssertTrue(text.contains("Steve Schoger"))
        XCTAssertTrue(text.contains("CC BY 4.0"))
        XCTAssertTrue(text.contains("Topography"))
        XCTAssertTrue(text.contains("Polka Dots"))
    }
}
