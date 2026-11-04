import Foundation
import TelegramCore
import TelegramUIPreferences
import TellomiWallpapers

let tellomiAccentPresets: [PresentationThemeAccentColor] = TellomiAccentColors.all.enumerated().map { offset, color in
    return PresentationThemeAccentColor(index: 101 + Int32(offset), baseColor: .preset, accentColor: color.rgb, bubbleColors: [], wallpaper: nil)
}
