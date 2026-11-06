import Foundation

/// Login field colors shared by the chrome and the contrast test.
/// Light values are the owner palette. Dark values keep typed text off the light fill.
public struct TellomiLoginFieldColors: Equatable {
    public let fill: UInt32
    public let text: UInt32
    public let placeholder: UInt32
    public let caret: UInt32
    public let error: UInt32

    public init(fill: UInt32, text: UInt32, placeholder: UInt32, caret: UInt32, error: UInt32) {
        self.fill = fill
        self.text = text
        self.placeholder = placeholder
        self.caret = caret
        self.error = error
    }
}

public func tellomiLoginFieldColors(dark: Bool) -> TellomiLoginFieldColors {
    if dark {
        return TellomiLoginFieldColors(fill: 0x2C2C2E, text: 0xFFFFFF, placeholder: 0x8E8E93, caret: 0xFFFFFF, error: 0xFF453A)
    }
    return TellomiLoginFieldColors(fill: 0xF2F3F5, text: 0x111111, placeholder: 0xB0B0B6, caret: 0x111111, error: 0xFF3B30)
}

func tellomiSrgbChannel(_ byte: UInt32) -> Double {
    let channel = Double(byte) / 255.0
    if channel <= 0.04045 {
        return channel / 12.92
    }
    return pow((channel + 0.055) / 1.055, 2.4)
}

public func tellomiRelativeLuminance(_ rgb: UInt32) -> Double {
    let red = tellomiSrgbChannel((rgb >> 16) & 0xFF)
    let green = tellomiSrgbChannel((rgb >> 8) & 0xFF)
    let blue = tellomiSrgbChannel(rgb & 0xFF)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue
}

public func tellomiContrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
    let lighter = max(tellomiRelativeLuminance(first), tellomiRelativeLuminance(second))
    let darker = min(tellomiRelativeLuminance(first), tellomiRelativeLuminance(second))
    return (lighter + 0.05) / (darker + 0.05)
}
