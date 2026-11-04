import Foundation

public struct TellomiAccentColor: Equatable {
    public let name: String
    public let rgb: UInt32

    public init(name: String, rgb: UInt32) {
        self.name = name
        self.rgb = rgb
    }
}

public enum TellomiAccentColors {
    public static let all: [TellomiAccentColor] = [
        TellomiAccentColor(name: "蓝", rgb: 0x3390EC),
        TellomiAccentColor(name: "天青", rgb: 0x2AABEE),
        TellomiAccentColor(name: "青", rgb: 0x00A8A8),
        TellomiAccentColor(name: "绿", rgb: 0x31B545),
        TellomiAccentColor(name: "薄荷", rgb: 0x25D366),
        TellomiAccentColor(name: "黄", rgb: 0xF5A623),
        TellomiAccentColor(name: "橙", rgb: 0xFF8A3D),
        TellomiAccentColor(name: "红", rgb: 0xE5484D),
        TellomiAccentColor(name: "粉", rgb: 0xEC4899),
        TellomiAccentColor(name: "紫", rgb: 0x8B5CF6),
        TellomiAccentColor(name: "靛", rgb: 0x5B5BD6),
        TellomiAccentColor(name: "石墨", rgb: 0x5F6B7A),
    ]

    public static var defaultColor: UInt32 {
        return self.all[0].rgb
    }
}

public enum TellomiWallpaperPresets {
    public static let lightSolid: UInt32 = 0xF0F2F5
    public static let darkSolid: UInt32 = 0x101418
    public static let legacyLightSolid: UInt32 = 0xF2F2F2
    public static let legacyDarkSolid: UInt32 = 0x000000

    public static func solidColor(dark: Bool) -> UInt32 {
        return dark ? self.darkSolid : self.lightSolid
    }
}

public enum TellomiBubbleColors {
    public static let incomingLight: UInt32 = 0xFFFFFF
    public static let incomingDark: UInt32 = 0x202C33
}

public enum TellomiBubbleShadowSpec {
    public static let radius: Double = 0.5
    public static let verticalOffset: Double = 0.5
    public static let alpha: Double = 0.18
}

public struct TellomiWallpaperEntry: Equatable {
    public let id: String
    public let name: String
    public let pattern: String?
    public let colors: [UInt32]
    public let intensity: Int32?
    public let isDark: Bool
    public let isDefaultLight: Bool
    public let isDefaultDark: Bool
    public let fileId: Int64

    public init(id: String, name: String, pattern: String?, colors: [UInt32], intensity: Int32?, isDark: Bool, isDefaultLight: Bool, isDefaultDark: Bool, fileId: Int64) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.colors = colors
        self.intensity = intensity
        self.isDark = isDark
        self.isDefaultLight = isDefaultLight
        self.isDefaultDark = isDefaultDark
        self.fileId = fileId
    }

    public var patternResourceSlug: String? {
        guard let pattern = self.pattern else {
            return nil
        }
        return "tm_\(pattern)"
    }
}

public enum TellomiWallpaperCatalog {
    // intensity is Telegram's signed pattern strength: positive draws the
    // pattern dark, negative draws it light. Percents in the plan are the
    // absolute value; "浅色" on a dark wallpaper is the negative sign.
    public static let entries: [TellomiWallpaperEntry] = [
        TellomiWallpaperEntry(id: "tm_doodle_light", name: "米色涂鸦", pattern: "doodle", colors: [0xEFE7DD], intensity: 12, isDark: false, isDefaultLight: true, isDefaultDark: false, fileId: 910001),
        TellomiWallpaperEntry(id: "tm_doodle_dark", name: "夜间涂鸦", pattern: "doodle", colors: [0x0B141A, 0x16232B], intensity: -8, isDark: true, isDefaultLight: false, isDefaultDark: true, fileId: 910002),
        TellomiWallpaperEntry(id: "tm_mint", name: "薄荷涂鸦", pattern: "doodle", colors: [0xDBEED9, 0xB8DCC8, 0xE6F2D8, 0xC2E3D1], intensity: 15, isDark: false, isDefaultLight: false, isDefaultDark: false, fileId: 910003),
        TellomiWallpaperEntry(id: "tm_sky", name: "天空涂鸦", pattern: "doodle", colors: [0xD6E8F7, 0xB9D3EE, 0xE3DDF5, 0xC8E0F4], intensity: 15, isDark: false, isDefaultLight: false, isDefaultDark: false, fileId: 910004),
        TellomiWallpaperEntry(id: "tm_peach", name: "蜜桃", pattern: "dots", colors: [0xFCE3D6, 0xF8CFC4, 0xFDEBD0, 0xF6D6DE], intensity: 15, isDark: false, isDefaultLight: false, isDefaultDark: false, fileId: 910005),
        TellomiWallpaperEntry(id: "tm_lavender", name: "薰衣草", pattern: "waves", colors: [0xE6DDF7, 0xD3C8F0, 0xF1E3F5, 0xDCD6F6], intensity: 15, isDark: false, isDefaultLight: false, isDefaultDark: false, fileId: 910006),
        TellomiWallpaperEntry(id: "tm_sunset", name: "日落渐变", pattern: nil, colors: [0xFAD0C4, 0xFFD1FF, 0xFBC2EB, 0xA6C1EE], intensity: nil, isDark: false, isDefaultLight: false, isDefaultDark: false, fileId: 910007),
        TellomiWallpaperEntry(id: "tm_forest_dark", name: "森林夜", pattern: "doodle", colors: [0x0F2027, 0x203A43, 0x2C5364], intensity: -10, isDark: true, isDefaultLight: false, isDefaultDark: false, fileId: 910008),
        TellomiWallpaperEntry(id: "tm_ocean_dark", name: "深海", pattern: "waves", colors: [0x141E30, 0x243B55], intensity: -10, isDark: true, isDefaultLight: false, isDefaultDark: false, fileId: 910009),
        TellomiWallpaperEntry(id: "tm_aurora_dark", name: "极光", pattern: nil, colors: [0x1A2A6C, 0x3B2667, 0x0F3443, 0x2D1B4E], intensity: nil, isDark: true, isDefaultLight: false, isDefaultDark: false, fileId: 910010),
    ]

    public static var stockEntries: [TellomiWallpaperEntry] {
        return self.entries
    }

    public static let patternResourceSlugs: [String] = ["tm_doodle", "tm_dots", "tm_waves"]

    public static func entry(id: String) -> TellomiWallpaperEntry? {
        return self.entries.first(where: { $0.id == id })
    }

    public static func defaultEntry(dark: Bool) -> TellomiWallpaperEntry {
        let match = self.entries.first(where: { dark ? $0.isDefaultDark : $0.isDefaultLight })
        return match ?? self.entries[0]
    }
}

public enum TellomiOpenSourceNotices {
    public static let text = """
    Chat wallpaper patterns shipped in this app:

    Tabler Icons — MIT License. Copyright (c) 2020-2026 Paweł Kuna. https://github.com/tabler/tabler-icons

    Lucide — ISC License. Copyright (c) Lucide Contributors. Portions of the icons come from Feather (MIT). https://github.com/lucide-icons/lucide

    Hero Patterns — CC BY 4.0. Copyright Steve Schoger. https://heropatterns.com
    "Topography" is the wave tile (tm_waves). "Polka Dots" is the dot tile (tm_dots).

    These tiles were composed for Tellomi. They are not WhatsApp or Telegram artwork.
    """
}
