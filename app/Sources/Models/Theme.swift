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

// MARK: - Brand Colors (Serene Pastel Wellness Palette)

extension Color {
    /// Warm near-black — primary background (dark mode)
    static let twilight = Color(red: 0x1C/255, green: 0x1B/255, blue: 0x1F/255)
    /// Warm off-white — primary background (light mode)
    static let mist = Color(red: 0xFA/255, green: 0xF7/255, blue: 0xF5/255)
    /// Vivid purple — primary action color, buttons, highlights
    static let coral = Color(red: 0x7C/255, green: 0x5C/255, blue: 0xFC/255)
    /// Sage green — secondary accent, tags, badges
    static let skyBlue = Color(red: 0x9B/255, green: 0xC5/255, blue: 0xA3/255)
    /// Soft rose — warm accent, notifications, active states
    static let glow = Color(red: 0xD4/255, green: 0xA0/255, blue: 0xB0/255)
    /// Soft warm white — dark mode text primary
    static let moonlight = Color(red: 0xF0/255, green: 0xED/255, blue: 0xEB/255)
    /// Soft grey — secondary text
    static let dusk = Color(red: 0x8E/255, green: 0x8E/255, blue: 0x93/255)
    /// Warm cream — warm accent
    static let cream = Color(red: 0xF0/255, green: 0xDC/255, blue: 0xC8/255)

    /// User bubble background — adaptive (purple dark / purple light)
    static let userBubble = Color.adaptive(
        dark: Color(red: 0x3D/255, green: 0x2E/255, blue: 0x7C/255),
        light: Color(red: 0x7C/255, green: 0x5C/255, blue: 0xFC/255)
    )

    /// Adaptive light purple — shimmer accent spots
    static let shimmerAccent = Color.adaptive(
        dark: Color(red: 0xB0/255, green: 0x97/255, blue: 0xFC/255),
        light: Color(red: 0xB0/255, green: 0x97/255, blue: 0xFC/255)
    )
    /// Warm tinted overlay for card surfaces
    static let tintedSurface = Color.adaptive(
        dark: Color(red: 0x26/255, green: 0x25/255, blue: 0x29/255),
        light: Color(red: 0xFA/255, green: 0xF7/255, blue: 0xF5/255)
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
    /// Success — connected, completed (muted sage)
    static let success = Color(red: 0x7C/255, green: 0xB6/255, blue: 0x86/255)
    /// Warning — loading, connecting (warm amber)
    static let warning = Color(red: 0xD4/255, green: 0xA9/255, blue: 0x6A/255)
    /// Error — errors, disconnected (dusty rose)
    static let error = Color(red: 0xC4/255, green: 0x7E/255, blue: 0x7E/255)
    /// Info — running tools, active (soft blue)
    static let info = Color(red: 0x7E/255, green: 0xA8/255, blue: 0xC4/255)

    static let codeBg = Color.adaptive(
        dark: Color(red: 0x1E/255, green: 0x1D/255, blue: 0x21/255),
        light: Color(red: 0xF5/255, green: 0xF0/255, blue: 0xEB/255)
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

    /// Surface — cards, bubbles
    static let surface = Color.adaptive(
        dark: Color(red: 0x26/255, green: 0x25/255, blue: 0x29/255),
        light: Color.white
    )

    /// Surface Elevated — modals, popovers
    static let surfaceElevated = Color.adaptive(
        dark: Color(red: 0x30/255, green: 0x2E/255, blue: 0x33/255),
        light: Color(red: 0xFA/255, green: 0xF7/255, blue: 0xF5/255)
    )

    /// Input — input fields
    static let inputBg = Color.adaptive(
        dark: Color(red: 0x1A/255, green: 0x1A/255, blue: 0x1A/255),
        light: Color.white
    )

    static let textPrimary = Color.adaptive(
        dark: Color.moonlight,
        light: Color(red: 0x2C/255, green: 0x2C/255, blue: 0x2C/255)
    )

    static let textSecondary = Color.dusk

    static let divider = Color.adaptive(
        dark: Color(red: 0x3A/255, green: 0x38/255, blue: 0x40/255),
        light: Color(red: 0xE8/255, green: 0xE5/255, blue: 0xE1/255)
    )

    static let assistantBubbleBorder = Color.adaptive(
        dark: Color(red: 0x3A/255, green: 0x38/255, blue: 0x40/255),
        light: Color(red: 0xE8/255, green: 0xE5/255, blue: 0xE1/255)
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
        let name: String
        switch weight {
        case .bold: name = "PlayfairDisplay-Bold"
        case .semibold: name = "PlayfairDisplay-SemiBold"
        case .medium: name = "PlayfairDisplay-Medium"
        default: name = "PlayfairDisplay-Regular"
        }
        return .custom(name, size: size, relativeTo: .body)
    }
}

extension Font {
    // Display (Playfair Display — elegant serif for emotional headings)
    static let displayLarge = Font.playfair(size: 44, weight: .medium)
    static let displayTitle = Font.playfair(size: 28, weight: .semibold)
    static let displaySubtitle = Font.playfair(size: 22, weight: .medium)
    static let navTitle = Font.inter(size: 18, weight: .semibold)

    // Body (Inter)
    static let chatMessage = Font.inter(size: 16)
    static let bodyMedium = Font.inter(size: 16, weight: .medium)
    static let bodySmall = Font.inter(size: 14)
    static let bodySmallMedium = Font.inter(size: 14, weight: .medium)
    static let caption = Font.inter(size: 13)
    static let captionMedium = Font.inter(size: 13, weight: .medium)
    static let captionSmall = Font.inter(size: 12)
    static let small = Font.inter(size: 11, weight: .medium)
    static let tiny = Font.inter(size: 10, weight: .semibold)
    static let micro = Font.inter(size: 9, weight: .bold)

    // Semantic
    static let rowTitle = Font.inter(size: 15, weight: .semibold)
    static let cardTitle = Font.inter(size: 17, weight: .semibold)

    // Code (System Mono — keep)
    static let codeFont = Font.system(size: 14, design: .monospaced)
    static let codeSm = Font.system(size: 12, design: .monospaced)

    // Mapped legacy tokens
    static let thinking = Font.system(size: 13, design: .monospaced)
    static let toolTitle = Font.inter(size: 14, weight: .medium)
    static let toolDetail = Font.system(size: 12, design: .monospaced)
    static let timestamp = Font.inter(size: 11)
    static let sectionHeader = Font.inter(size: 12, weight: .semibold)
    static let sectionHeaderSerif = Font.playfair(size: 14, weight: .medium)
    static let emptyStateTitle = Font.playfair(size: 28, weight: .medium)
}

// MARK: - Theme Constants

struct SolaceTheme {
    // Spacing (4px base unit)
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    // Chat
    static let chatHorizontalPadding: CGFloat = 20
    static let bubbleMaxWidthRatio: CGFloat = 0.80
    static let sameAuthorSpacing: CGFloat = 8
    static let differentAuthorSpacing: CGFloat = 16

    // Radius (softer, rounder for wellness feel)
    static let bubbleRadius: CGFloat = 22
    static let bubbleTailRadius: CGFloat = 4
    static let inputFieldRadius: CGFloat = 24
    static let cardRadius: CGFloat = 20

    // Sizes
    static let connectionDotSize: CGFloat = 6
    static let sendButtonSize: CGFloat = 36
    static let inputFieldHeight: CGFloat = 36
    static let minTouchTarget: CGFloat = 44
    static let toolCardCollapsedHeight: CGFloat = 44
    static let thinkingCollapsedHeight: CGFloat = 36
    static let thinkingMaxExpandedHeight: CGFloat = 350
    static let toolCardLeftBorderWidth: CGFloat = 3

    // Conversation Blocks
    static let conversationBlockPadding: CGFloat = 24
    static let conversationBlockSpacing: CGFloat = 32
    static let conversationBlockRadius: CGFloat = 24
    static let blockTextMaxWidthRatio: CGFloat = 0.95
    static let blockUserAccentWidth: CGFloat = 3
    static let blockDividerInset: CGFloat = 16
    static let inlineGuideSize: CGFloat = 20
    static let blockEntranceScale: CGFloat = 0.98
    static let blockEntranceDuration: Double = 0.55

    // Particle System
    static let particleLifetime: Double = 2.0
    static let particleMaxCount: Int = 12

    // Animation Durations
    static let springDuration: Double = 0.5
    static let appearDuration: Double = 0.35
    static let breatheDuration: Double = 7.0
    static let thinkingPulseDuration: Double = 2.5

    // Shimmer Effects
    static let shimmerFrameRate: Double = 30.0
    static let shimmerDuration: Double = 3.0
    static let rippleDuration: Double = 0.8
    static let shimmerOpacitySubtle: Double = 0.05
    static let shimmerOpacityStandard: Double = 0.07
    static let shimmerOpacityProminent: Double = 0.11
    static let rippleMaxRadius: CGFloat = 120
}

// MARK: - Z-Layer

enum ZLayer: CGFloat {
    case background = 0
    case content = 1
    case overlay = 10
    case banner = 20
    case modal = 30
}
