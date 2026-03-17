import SwiftUI

// MARK: - Adaptive Color Helper

extension Color {
    /// Creates a color that adapts between dark and light mode
    static func adaptive(dark: Color, light: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}

// MARK: - Brand Colors (Studio — Zinc + Blue)

extension Color {
    /// Near-black — primary background (dark mode) — zinc-950
    static let twilight = Color(red: 0x09/255, green: 0x09/255, blue: 0x0B/255)
    /// Off-white — primary background (light mode) — zinc-50
    static let mist = Color(red: 0xFA/255, green: 0xFA/255, blue: 0xFA/255)
    /// Primary accent — confident blue — blue-500
    static let coral = Color(red: 0x3B/255, green: 0x82/255, blue: 0xF6/255)
    /// Secondary accent — same as primary for consistency
    static let skyBlue = Color(red: 0x3B/255, green: 0x82/255, blue: 0xF6/255)
    /// Warm accent — amber for notifications/badges — amber-500
    static let glow = Color(red: 0xF5/255, green: 0x9E/255, blue: 0x0B/255)
    /// Clean white — dark mode text primary — zinc-50
    static let moonlight = Color(red: 0xFA/255, green: 0xFA/255, blue: 0xFA/255)
    /// Neutral grey — secondary text — zinc-400
    static let dusk = Color(red: 0xA1/255, green: 0xA1/255, blue: 0xAA/255)
    /// Light neutral — zinc-200
    static let cream = Color(red: 0xE4/255, green: 0xE4/255, blue: 0xE7/255)

    /// User bubble background — blue tint
    static let userBubble = Color.adaptive(
        dark: Color(red: 0x3B/255, green: 0x82/255, blue: 0xF6/255),
        light: Color(red: 0x3B/255, green: 0x82/255, blue: 0xF6/255)
    )

    /// Shimmer accent — blue glow
    static let shimmerAccent = Color.adaptive(
        dark: Color(red: 0x3B/255, green: 0x82/255, blue: 0xF6/255).opacity(0.15),
        light: Color(red: 0x3B/255, green: 0x82/255, blue: 0xF6/255).opacity(0.08)
    )
    /// Tinted surface — subtle blue tint
    static let tintedSurface = Color.adaptive(
        dark: Color(red: 0x18/255, green: 0x18/255, blue: 0x1B/255),
        light: Color(red: 0xF4/255, green: 0xF4/255, blue: 0xF5/255)
    )
}

// MARK: - Legacy Brand Color Aliases (map old names → new palette values)

extension Color {
    static let heart = Color.coral
    static let amethyst = Color.coral
    static let lavender = Color.skyBlue
    static let causticHighlight = Color.shimmerAccent
    static let waterSurface = Color.tintedSurface
    static let deepInk = Color.twilight
    static let soul = Color.mist
    static let trust = Color.dusk
}

// MARK: - Functional Colors

extension Color {
    /// Success — connected, completed — green-500
    static let success = Color(red: 0x22/255, green: 0xC5/255, blue: 0x5E/255)
    /// Warning — loading, connecting — yellow-500
    static let warning = Color(red: 0xEA/255, green: 0xB3/255, blue: 0x08/255)
    /// Error — errors, disconnected — red-500
    static let error = Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255)
    /// Info — running tools, active — blue-500
    static let info = Color(red: 0x3B/255, green: 0x82/255, blue: 0xF6/255)

    static let codeBg = Color.adaptive(
        dark: Color(red: 0x18/255, green: 0x18/255, blue: 0x1B/255),
        light: Color(red: 0xF4/255, green: 0xF4/255, blue: 0xF5/255)
    )
}

// MARK: - Legacy Functional Color Aliases

extension Color {
    static let sageGreen = Color.success
    static let amberGlow = Color.warning
    static let softRed = Color.error
    static let electricBlue = Color.info
}

// MARK: - Adaptive Surface Colors

extension Color {
    static let appBackground = Color.adaptive(
        dark: Color.twilight,
        light: Color.mist
    )

    /// Surface — cards, panels — zinc-900 / white
    static let surface = Color.adaptive(
        dark: Color(red: 0x18/255, green: 0x18/255, blue: 0x1B/255),
        light: Color.white
    )

    /// Surface Elevated — modals, popovers — zinc-800 / zinc-100
    static let surfaceElevated = Color.adaptive(
        dark: Color(red: 0x27/255, green: 0x27/255, blue: 0x2A/255),
        light: Color(red: 0xF4/255, green: 0xF4/255, blue: 0xF5/255)
    )

    /// Input — input fields — zinc-900 / white
    static let inputBg = Color.adaptive(
        dark: Color(red: 0x18/255, green: 0x18/255, blue: 0x1B/255),
        light: Color.white
    )

    /// Text Primary — zinc-50 / zinc-900
    static let textPrimary = Color.adaptive(
        dark: Color(red: 0xFA/255, green: 0xFA/255, blue: 0xFA/255),
        light: Color(red: 0x18/255, green: 0x18/255, blue: 0x1B/255)
    )

    /// Text Secondary — zinc-400 / zinc-500
    static let textSecondary = Color.adaptive(
        dark: Color(red: 0xA1/255, green: 0xA1/255, blue: 0xAA/255),
        light: Color(red: 0x71/255, green: 0x71/255, blue: 0x7A/255)
    )

    /// Divider — zinc-800 / zinc-200
    static let divider = Color.adaptive(
        dark: Color(red: 0x27/255, green: 0x27/255, blue: 0x2A/255),
        light: Color(red: 0xE4/255, green: 0xE4/255, blue: 0xE7/255)
    )

    /// Assistant bubble border — zinc-800 / zinc-200
    static let assistantBubbleBorder = Color.adaptive(
        dark: Color(red: 0x27/255, green: 0x27/255, blue: 0x2A/255),
        light: Color(red: 0xE4/255, green: 0xE4/255, blue: 0xE7/255)
    )
}

// MARK: - ShapeStyle Extensions (enables .colorName in .foregroundStyle/.background)

extension ShapeStyle where Self == Color {
    // Brand colors
    static var coral: Color { Color.coral }
    static var skyBlue: Color { Color.skyBlue }
    static var twilight: Color { Color.twilight }
    static var mist: Color { Color.mist }
    static var glow: Color { Color.glow }
    static var moonlight: Color { Color.moonlight }
    static var dusk: Color { Color.dusk }
    static var cream: Color { Color.cream }
    static var userBubble: Color { Color.userBubble }
    static var shimmerAccent: Color { Color.shimmerAccent }
    static var tintedSurface: Color { Color.tintedSurface }

    // Legacy aliases
    static var amethyst: Color { Color.coral }
    static var lavender: Color { Color.skyBlue }
    static var causticHighlight: Color { Color.shimmerAccent }
    static var waterSurface: Color { Color.tintedSurface }
    static var heart: Color { Color.coral }
    static var deepInk: Color { Color.twilight }
    static var soul: Color { Color.mist }
    static var trust: Color { Color.dusk }

    // Functional colors
    static var success: Color { Color.success }
    static var warning: Color { Color.warning }
    static var error: Color { Color.error }
    static var info: Color { Color.info }

    // Legacy functional aliases
    static var sageGreen: Color { Color.success }
    static var amberGlow: Color { Color.warning }
    static var softRed: Color { Color.error }
    static var electricBlue: Color { Color.info }

    // Surfaces
    static var codeBg: Color { Color.codeBg }
    static var appBackground: Color { Color.appBackground }
    static var surface: Color { Color.surface }
    static var surfaceElevated: Color { Color.surfaceElevated }
    static var inputBg: Color { Color.inputBg }
    static var textPrimary: Color { Color.textPrimary }
    static var textSecondary: Color { Color.textSecondary }
    static var divider: Color { Color.divider }
    static var assistantBubbleBorder: Color { Color.assistantBubbleBorder }
}

// MARK: - Font Extensions

extension Font {
    // Helpers for custom fonts with system fallback
    static func spaceGrotesk(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .semibold: name = "SpaceGrotesk-Bold"
        default: name = "SpaceGrotesk-Medium"
        }
        return .custom(name, size: size, relativeTo: .body)
    }

    static func inter(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .semibold: name = "Inter-Bold"
        case .medium: name = "Inter-Medium"
        default: name = "Inter-Regular"
        }
        return .custom(name, size: size, relativeTo: .body)
    }

    static func playfair(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // Kept for compatibility — maps to system serif
        return .system(size: size, weight: weight == .bold ? .bold : weight == .semibold ? .semibold : weight == .medium ? .medium : .regular, design: .serif)
    }
}

extension Font {
    // Display — SF Pro, weight contrast for hierarchy
    static let displayLarge = Font.system(size: 28, weight: .bold)
    static let displayTitle = Font.system(size: 22, weight: .semibold)
    static let displaySubtitle = Font.system(size: 18, weight: .medium)
    static let navTitle = Font.system(size: 17, weight: .semibold)

    // Body
    static let chatMessage = Font.system(size: 15)
    static let bodyMedium = Font.system(size: 15, weight: .medium)
    static let bodySmall = Font.system(size: 14)
    static let bodySmallMedium = Font.system(size: 14, weight: .medium)
    static let caption = Font.system(size: 13)
    static let captionMedium = Font.system(size: 13, weight: .medium)
    static let captionSmall = Font.system(size: 12)
    static let small = Font.system(size: 11, weight: .medium)
    static let tiny = Font.system(size: 10, weight: .semibold)
    static let micro = Font.system(size: 9, weight: .bold)

    // Semantic
    static let rowTitle = Font.system(size: 15, weight: .semibold)
    static let cardTitle = Font.system(size: 17, weight: .semibold)

    // Code
    static let codeFont = Font.system(size: 14, design: .monospaced)
    static let codeSm = Font.system(size: 12, design: .monospaced)

    // Mapped legacy tokens
    static let thinking = Font.system(size: 13, design: .monospaced)
    static let toolTitle = Font.system(size: 14, weight: .medium)
    static let toolDetail = Font.system(size: 12, design: .monospaced)
    static let timestamp = Font.system(size: 11)
    static let sectionHeader = Font.system(size: 12, weight: .semibold)
    static let sectionHeaderSerif = Font.system(size: 13, weight: .semibold)
    static let emptyStateTitle = Font.system(size: 28, weight: .bold)
}

// MARK: - Theme Constants

struct SolaceTheme {
    // Spacing (4px base unit — tighter for professional density)
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28

    // Chat
    static let chatHorizontalPadding: CGFloat = 16
    static let bubbleMaxWidthRatio: CGFloat = 0.85
    static let sameAuthorSpacing: CGFloat = 6
    static let differentAuthorSpacing: CGFloat = 14

    // Radius (clean, professional)
    static let bubbleRadius: CGFloat = 14
    static let bubbleTailRadius: CGFloat = 4
    static let inputFieldRadius: CGFloat = 20
    static let cardRadius: CGFloat = 12

    // Sizes
    static let connectionDotSize: CGFloat = 6
    static let sendButtonSize: CGFloat = 32
    static let inputFieldHeight: CGFloat = 44
    static let minTouchTarget: CGFloat = 44
    static let toolCardCollapsedHeight: CGFloat = 40
    static let thinkingCollapsedHeight: CGFloat = 34
    static let thinkingMaxExpandedHeight: CGFloat = 300
    static let toolCardLeftBorderWidth: CGFloat = 2

    // Conversation Blocks
    static let conversationBlockPadding: CGFloat = 16
    static let conversationBlockSpacing: CGFloat = 20
    static let conversationBlockRadius: CGFloat = 14
    static let blockTextMaxWidthRatio: CGFloat = 0.95
    static let blockUserAccentWidth: CGFloat = 2
    static let blockDividerInset: CGFloat = 12
    static let inlineGuideSize: CGFloat = 18
    static let blockEntranceScale: CGFloat = 0.98
    static let blockEntranceDuration: Double = 0.4

    // Particle System
    static let particleLifetime: Double = 2.0
    static let particleMaxCount: Int = 8

    // Animation Durations
    static let springDuration: Double = 0.35
    static let appearDuration: Double = 0.25
    static let breatheDuration: Double = 5.0
    static let thinkingPulseDuration: Double = 2.0

    // Shimmer Effects
    static let shimmerFrameRate: Double = 30.0
    static let shimmerDuration: Double = 2.5
    static let rippleDuration: Double = 0.6
    static let shimmerOpacitySubtle: Double = 0.04
    static let shimmerOpacityStandard: Double = 0.06
    static let shimmerOpacityProminent: Double = 0.10
    static let rippleMaxRadius: CGFloat = 100
}

// MARK: - Z-Layer

enum ZLayer: CGFloat {
    case background = 0
    case content = 1
    case overlay = 10
    case banner = 20
    case modal = 30
}
