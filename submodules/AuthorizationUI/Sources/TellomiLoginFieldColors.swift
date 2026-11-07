import Foundation

/// Login field colors shared by the chrome and the contrast test.
/// Values are the upstream authorization theme, lifted only when a pair misses WCAG AA.
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

/// Upstream authorization tokens. `0xRRGGBB`, opaque.
public struct TellomiLoginThemeTokens: Equatable {
    public var page: UInt32
    public var fieldFill: UInt32
    public var primaryText: UInt32
    public var accent: UInt32
    public var secondaryText: UInt32
    public var placeholder: UInt32
    public var destructive: UInt32
    public var separator: UInt32
    public var disabledText: UInt32
    public var checkFill: UInt32
    public var checkStroke: UInt32
    public var checkTick: UInt32
    public var buttonBackground: UInt32
    public var buttonForeground: UInt32
    public var rowBackground: UInt32

    public init(page: UInt32, fieldFill: UInt32, primaryText: UInt32, accent: UInt32, secondaryText: UInt32, placeholder: UInt32, destructive: UInt32, separator: UInt32, disabledText: UInt32, checkFill: UInt32, checkStroke: UInt32, checkTick: UInt32, buttonBackground: UInt32, buttonForeground: UInt32, rowBackground: UInt32) {
        self.page = page
        self.fieldFill = fieldFill
        self.primaryText = primaryText
        self.accent = accent
        self.secondaryText = secondaryText
        self.placeholder = placeholder
        self.destructive = destructive
        self.separator = separator
        self.disabledText = disabledText
        self.checkFill = checkFill
        self.checkStroke = checkStroke
        self.checkTick = checkTick
        self.buttonBackground = buttonBackground
        self.buttonForeground = buttonForeground
        self.rowBackground = rowBackground
    }
}

/// Colors actually drawn. Text is at least 4.5:1. Strokes and the checkbox are at least 3:1.
public struct TellomiLoginSurfaceColors: Equatable {
    public var page: UInt32
    public var fieldFill: UInt32
    public var fieldText: UInt32
    public var fieldBorder: UInt32
    public var placeholder: UInt32
    public var caret: UInt32
    public var error: UInt32
    public var buttonBackground: UInt32
    public var buttonForeground: UInt32
    public var buttonDisabledBackground: UInt32
    public var buttonDisabledForeground: UInt32
    public var link: UInt32
    public var secondaryText: UInt32
    public var checkboxFill: UInt32
    public var checkboxTick: UInt32
    public var checkboxStroke: UInt32
    public var codeInactiveBorder: UInt32
    public var codeActiveBorder: UInt32
    public var rowBorder: UInt32
    public var rowBackground: UInt32
    public var rowText: UInt32

    public init(page: UInt32, fieldFill: UInt32, fieldText: UInt32, fieldBorder: UInt32, placeholder: UInt32, caret: UInt32, error: UInt32, buttonBackground: UInt32, buttonForeground: UInt32, buttonDisabledBackground: UInt32, buttonDisabledForeground: UInt32, link: UInt32, secondaryText: UInt32, checkboxFill: UInt32, checkboxTick: UInt32, checkboxStroke: UInt32, codeInactiveBorder: UInt32, codeActiveBorder: UInt32, rowBorder: UInt32, rowBackground: UInt32, rowText: UInt32) {
        self.page = page
        self.fieldFill = fieldFill
        self.fieldText = fieldText
        self.fieldBorder = fieldBorder
        self.placeholder = placeholder
        self.caret = caret
        self.error = error
        self.buttonBackground = buttonBackground
        self.buttonForeground = buttonForeground
        self.buttonDisabledBackground = buttonDisabledBackground
        self.buttonDisabledForeground = buttonDisabledForeground
        self.link = link
        self.secondaryText = secondaryText
        self.checkboxFill = checkboxFill
        self.checkboxTick = checkboxTick
        self.checkboxStroke = checkboxStroke
        self.codeInactiveBorder = codeInactiveBorder
        self.codeActiveBorder = codeActiveBorder
        self.rowBorder = rowBorder
        self.rowBackground = rowBackground
        self.rowText = rowText
    }

    public var fieldColors: TellomiLoginFieldColors {
        return TellomiLoginFieldColors(fill: self.fieldFill, text: self.fieldText, placeholder: self.placeholder, caret: self.caret, error: self.error)
    }
}

/// Day and night defaults from `makeDefaultDayPresentationTheme` / `makeDefaultDarkPresentationTheme`.
/// The dark field is the elevated `2C2C2E` block, not `itemInputField` `0F0F0F`, which sits on black at 1.1:1.
public func tellomiDefaultLoginTokens(dark: Bool) -> TellomiLoginThemeTokens {
    if dark {
        return TellomiLoginThemeTokens(
            page: 0x000000,
            fieldFill: 0x2C2C2E,
            primaryText: 0xFFFFFF,
            accent: 0xFFFFFF,
            secondaryText: 0x98989E,
            placeholder: 0x8F8F8F,
            destructive: 0xEB5545,
            separator: 0x545458,
            disabledText: 0x8F8F8F,
            checkFill: 0xFFFFFF,
            checkStroke: 0x8E8E93,
            checkTick: 0x000000,
            buttonBackground: 0xFFFFFF,
            buttonForeground: 0x111111,
            rowBackground: 0x1C1C1E
        )
    }
    return TellomiLoginThemeTokens(
        page: 0xFFFFFF,
        fieldFill: 0xF2F2F7,
        primaryText: 0x000000,
        accent: 0x3390EC,
        secondaryText: 0x8E8E93,
        placeholder: 0xB6B6BB,
        destructive: 0xFF3B30,
        separator: 0xC8C7CC,
        disabledText: 0x8E8E93,
        checkFill: 0x3390EC,
        checkStroke: 0xC7C7CC,
        checkTick: 0xFFFFFF,
        buttonBackground: 0x000000,
        buttonForeground: 0xFFFFFF,
        rowBackground: 0xFFFFFF
    )
}

public func tellomiLoginSurfaceColors(_ tokens: TellomiLoginThemeTokens) -> TellomiLoginSurfaceColors {
    let night = tellomiRelativeLuminance(tokens.page) < 0.2
    let fieldFill = tellomiSeparatedFill(tokens.fieldFill, against: tokens.page, toward: tokens.primaryText, minimum: night ? 1.45 : 1.0)
    let rowBackground = tellomiSeparatedFill(tokens.rowBackground, against: tokens.page, toward: tokens.primaryText, minimum: night ? 1.3 : 1.0)
    let fieldText = tellomiInk(tokens.primaryText, on: fieldFill, minimum: 4.5)
    let placeholder = tellomiInk(tokens.placeholder, on: fieldFill, minimum: 4.5)
    let link = tellomiInk(tokens.accent, on: tokens.page, minimum: 4.5)
    let caret = tellomiInk(link, on: fieldFill, minimum: 3.0)
    var error = tellomiInk(tokens.destructive, on: tokens.page, minimum: 4.5)
    if tellomiContrastRatio(error, fieldFill) < 3.0 {
        error = tellomiInk(error, on: fieldFill, minimum: 3.0)
    }
    let secondary = tellomiInk(tokens.secondaryText, on: tokens.page, minimum: 4.5)
    let fieldBorder = tellomiInk(tokens.separator, on: tokens.page, minimum: 3.0)
    let codeInactive = tellomiInk(tokens.separator, on: fieldFill, minimum: 3.0)
    let codeActive = tellomiInk(tokens.accent, on: fieldFill, minimum: 3.0)
    let checkboxStroke = tellomiInk(tokens.checkStroke, on: tokens.page, minimum: 3.0)
    let checked = tellomiButtonPair(background: tokens.checkFill, foreground: tokens.checkTick)
    let button = tellomiButtonPair(background: tokens.buttonBackground, foreground: tokens.buttonForeground)
    let disabledBackground = tellomiMix(tokens.page, tokens.disabledText, 0.38)
    let disabledForeground = tellomiInk(tokens.disabledText, on: disabledBackground, minimum: 4.5)
    let rowText = tellomiInk(tokens.primaryText, on: rowBackground, minimum: 4.5)
    return TellomiLoginSurfaceColors(
        page: tokens.page,
        fieldFill: fieldFill,
        fieldText: fieldText,
        fieldBorder: fieldBorder,
        placeholder: placeholder,
        caret: caret,
        error: error,
        buttonBackground: button.background,
        buttonForeground: button.foreground,
        buttonDisabledBackground: disabledBackground,
        buttonDisabledForeground: disabledForeground,
        link: link,
        secondaryText: secondary,
        checkboxFill: checked.background,
        checkboxTick: checked.foreground,
        checkboxStroke: checkboxStroke,
        codeInactiveBorder: codeInactive,
        codeActiveBorder: codeActive,
        rowBorder: fieldBorder,
        rowBackground: rowBackground,
        rowText: rowText
    )
}

public func tellomiLoginSurfaceColors(dark: Bool) -> TellomiLoginSurfaceColors {
    return tellomiLoginSurfaceColors(tellomiDefaultLoginTokens(dark: dark))
}

public func tellomiLoginFieldColors(dark: Bool) -> TellomiLoginFieldColors {
    return tellomiLoginSurfaceColors(dark: dark).fieldColors
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

public func tellomiMix(_ first: UInt32, _ second: UInt32, _ amount: Double) -> UInt32 {
    let clamped = min(1.0, max(0.0, amount))
    func channel(_ shift: UInt32) -> UInt32 {
        let start = Double((first >> shift) & 0xFF)
        let end = Double((second >> shift) & 0xFF)
        let mixed = start * (1.0 - clamped) + end * clamped
        return UInt32(min(255, max(0, Int(mixed.rounded()))))
    }
    return (channel(16) << 16) | (channel(8) << 8) | channel(0)
}

/// Moves `color` toward black or white, whichever raises contrast, until `minimum`.
public func tellomiInk(_ color: UInt32, on background: UInt32, minimum: Double) -> UInt32 {
    if tellomiContrastRatio(color, background) >= minimum {
        return color
    }
    let toward: UInt32 = tellomiRelativeLuminance(background) > 0.4 ? 0x000000 : 0xFFFFFF
    var best = toward
    var low = 1
    var high = 100
    while low <= high {
        let mid = (low + high) / 2
        let mixed = tellomiMix(color, toward, Double(mid) / 100.0)
        if tellomiContrastRatio(mixed, background) >= minimum {
            best = mixed
            high = mid - 1
        } else {
            low = mid + 1
        }
    }
    return best
}

/// Keeps `foreground` and moves the fill until the pair clears 4.5:1.
/// If the opposite ink already clears 4.5:1, that ink is used and the fill stays.
public func tellomiButtonPair(background: UInt32, foreground: UInt32) -> (background: UInt32, foreground: UInt32) {
    if tellomiContrastRatio(foreground, background) >= 4.5 {
        return (background, foreground)
    }
    let opposite: UInt32 = tellomiRelativeLuminance(background) > 0.4 ? 0x000000 : 0xFFFFFF
    if opposite != foreground && tellomiContrastRatio(opposite, background) >= 4.5 {
        return (background, opposite)
    }
    let toward: UInt32 = tellomiRelativeLuminance(foreground) > 0.5 ? 0x000000 : 0xFFFFFF
    var best = toward
    var low = 1
    var high = 100
    while low <= high {
        let mid = (low + high) / 2
        let mixed = tellomiMix(background, toward, Double(mid) / 100.0)
        if tellomiContrastRatio(foreground, mixed) >= 4.5 {
            best = mixed
            high = mid - 1
        } else {
            low = mid + 1
        }
    }
    return (best, foreground)
}

func tellomiSeparatedFill(_ fill: UInt32, against page: UInt32, toward ink: UInt32, minimum: Double) -> UInt32 {
    if tellomiContrastRatio(fill, page) >= minimum {
        return fill
    }
    var best = tellomiMix(fill, ink, 1.0)
    var low = 1
    var high = 100
    while low <= high {
        let mid = (low + high) / 2
        let mixed = tellomiMix(fill, ink, Double(mid) / 100.0)
        if tellomiContrastRatio(mixed, page) >= minimum {
            best = mixed
            high = mid - 1
        } else {
            low = mid + 1
        }
    }
    return best
}
