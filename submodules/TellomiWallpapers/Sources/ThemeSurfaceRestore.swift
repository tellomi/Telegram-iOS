import Foundation

/// Wallpaper solids and gradients from Telegram's theme color grid
/// (the lists in `ThemeColorsGridController` before the one-color replacement).
/// Light and dark are different sets. A preview of these values is a fill, not a download.
public enum ThemeWallpaperPalette {
    public static func solids(dark: Bool) -> [UInt32] {
        if dark {
            return [
                0x1D2D3C, 0x111B26, 0x0B141E,
                0x1F361F, 0x131F15, 0x0E1710,
                0x2F2E27, 0x2A261F, 0x191817,
                0x432E30, 0x2E1C1E, 0x1F1314,
                0x432E3C, 0x2E1C28, 0x1F131B,
                0x3C2E43, 0x291C2E, 0x1D1221,
                0x312E43, 0x1E1C2E, 0x141221,
                0x2F3F3F, 0x212D30, 0x141E20,
                0x272524, 0x191716, 0x000000,
            ]
        }
        return [
            0xD3DFEA, 0xA5C5DB, 0x6F99C8,
            0xD2E3A9, 0xA4D48E, 0x7DBB6E,
            0xE6DDAE, 0xD5BE91, 0xCBA479,
            0xEBC0B9, 0xE0A79D, 0xC97870,
            0xEBB9C8, 0xE09DB7, 0xD27593,
            0xDAC2ED, 0xD3A5E7, 0xB587D2,
            0xC2C2ED, 0xA5A5E7, 0x7F7FD0,
            0xC2E2ED, 0xA5D6E7, 0x7FBAD0,
            0xD6C2B9, 0x9C8882, 0x000000,
        ]
    }

    public static func gradients(dark: Bool) -> [[UInt32]] {
        if dark {
            return [
                [0x1e3557, 0x151a36, 0x1c4352, 0x2a4541],
                [0x1d223f, 0x1d1832, 0x1b2943, 0x141631],
                [0x203439, 0x102028, 0x1d3c3a, 0x172635],
                [0x1c2731, 0x1a1c25, 0x27303b, 0x1b1b21],
                [0x3a1c3a, 0x24193c, 0x392e3e, 0x1a1632],
                [0x2c211b, 0x44332a, 0x22191f, 0x3b2d36],
                [0x1e3557, 0x182036, 0x1c4352, 0x16263a],
                [0x111236, 0x14424f, 0x0b2334, 0x3b315d],
                [0x2d4836, 0x172b19, 0x364331, 0x103231],
            ]
        }
        return [
            [0xdbddbb, 0x6ba587, 0xd5d88d, 0x88b884],
            [0x8dc0eb, 0xb9d1ea, 0xc6b1ef, 0xebd7ef],
            [0x97beeb, 0xb1e9ea, 0xc6b1ef, 0xefb7dc],
            [0x8adbf2, 0x888dec, 0xe39fea, 0x679ced],
            [0xb0cdeb, 0x9fb0ea, 0xbbead5, 0xb2e3dd],
            [0xdaeac8, 0xa2b4ff, 0xeccbff, 0xb9e2ff],
            [0xdceb92, 0x8fe1d6, 0x67a3f2, 0x85d685],
            [0xeaa36e, 0xf0e486, 0xf29ebf, 0xe8c06e],
            [0xffc3b2, 0xe2c0ff, 0xffe7b2, 0xf8cece],
        ]
    }
}

/// Built-in theme row order from the theme picker before day/night were the only two.
public enum ThemePickerBuiltin: String, Equatable {
    case dayClassic
    case nightAccent
    case day
    case night
}

public func themePickerBuiltinOrder(autoNight: Bool) -> [ThemePickerBuiltin] {
    if autoNight {
        return [.nightAccent, .night]
    }
    return [.dayClassic, .nightAccent, .day, .night]
}

/// How `wallPaperNoFile` is painted and applied.
///
/// A solid from `account.getWallPapers` carries an id. Dropping that id and
/// sending `inputWallPaperNoFile` with id 0 makes install fail, and a file
/// stand-in with access hash 0 never finishes its preview. One color with an
/// id is painted as two stops of that color so the fill is visible and the id
/// is what gets saved.
public enum NofileWallpaperPaint: Equatable {
    case emoticon(String)
    case solid(UInt32)
    case fill(id: Int64, colors: [UInt32], rotation: Int32?)
    case missing
}

public func nofileWallpaperPaint(id: Int64, colors: [UInt32], rotation: Int32?, emoticon: String?) -> NofileWallpaperPaint {
    if id == 0, let emoticon, !emoticon.isEmpty {
        return .emoticon(emoticon)
    }
    if colors.isEmpty {
        return .missing
    }
    if colors.count == 1 && id == 0 {
        return .solid(colors[0])
    }
    if colors.count == 1 {
        return .fill(id: id, colors: [colors[0], colors[0]], rotation: rotation)
    }
    return .fill(id: id, colors: colors, rotation: rotation)
}

/// The wallpaper grid does not replace the built-in slot with a bundled file,
/// and it does not invent file wallpapers when the server list is empty or the
/// request fails. Colors and gradients above do not need that request.
public enum WallpaperGridSource: Equatable {
    case remoteAndBuiltin
    case builtinOnly
}

public func wallpaperGridSource(remoteCount: Int, fetchFailed: Bool) -> WallpaperGridSource {
    if fetchFailed || remoteCount == 0 {
        return .builtinOnly
    }
    return .remoteAndBuiltin
}

/// A chat theme whose sticker document is missing still shows its emoticon.
/// The server catalog has the emoticon and an accent, and no document.
public func chatThemeEmoticonLabel(hasEmojiFile: Bool, emoticon: String?) -> String? {
    guard !hasEmojiFile, let emoticon, !emoticon.isEmpty else {
        return nil
    }
    return emoticon
}

/// Accent used to paint a theme tile when the theme settings have no wallpaper file.
public func chatThemePreviewFill(accent: UInt32?, hasWallpaper: Bool) -> UInt32? {
    if hasWallpaper {
        return nil
    }
    return accent
}
