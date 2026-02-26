import SwiftUI

// MARK: - Adaptive Color Helper

extension Color {
    /// Creates a color that adapts between dark and light mode
    static func adaptive(dark: Color, light: Color) -> Color {
        // We use UIColor to get automatic trait adaptation
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}

// MARK: - Brand Colors (fixed, non-adaptive)

extension Color {
    static let heart = Color(red: 232/255, green: 69/255, blue: 107/255)
    static let deepInk = Color(red: 26/255, green: 26/255, blue: 46/255)
    static let soul = Color(red: 250/255, green: 247/255, blue: 242/255)
    static let trust = Color(red: 107/255, green: 123/255, blue: 141/255)
}

// MARK: - Functional Colors (fixed)

extension Color {
    static let amberGlow = Color(red: 244/255, green: 166/255, blue: 35/255)
    static let electricBlue = Color(red: 59/255, green: 130/255, blue: 246/255)
    static let sageGreen = Color(red: 52/255, green: 211/255, blue: 153/255)
    static let softRed = Color(red: 239/255, green: 68/255, blue: 68/255)
    static let codeBg = Color(red: 55/255, green: 65/255, blue: 81/255)
}

// MARK: - Adaptive Surface Colors

extension Color {
    static let appBackground = Color.adaptive(
        dark: Color(red: 26/255, green: 26/255, blue: 46/255),
        light: Color(red: 250/255, green: 247/255, blue: 242/255)
    )

    static let surface = Color.adaptive(
        dark: Color(red: 22/255, green: 33/255, blue: 62/255),
        light: .white
    )

    static let surfaceElevated = Color.adaptive(
        dark: Color(red: 31/255, green: 46/255, blue: 77/255),
        light: Color(red: 245/255, green: 240/255, blue: 235/255)
    )

    static let inputBg = Color.adaptive(
        dark: Color(red: 15/255, green: 23/255, blue: 41/255),
        light: .white
    )

    static let textPrimary = Color.adaptive(
        dark: Color(red: 241/255, green: 241/255, blue: 244/255),
        light: Color(red: 26/255, green: 26/255, blue: 46/255)
    )

    static let textSecondary = Color.trust

    static let divider = Color.adaptive(
        dark: .white.opacity(0.06),
        light: Color(red: 232/255, green: 228/255, blue: 223/255)
    )

    static let assistantBubbleBorder = Color.adaptive(
        dark: .clear,
        light: Color(red: 232/255, green: 228/255, blue: 223/255)
    )
}

// MARK: - ShapeStyle Extensions (enables .colorName in .foregroundStyle/.background)

extension ShapeStyle where Self == Color {
    static var heart: Color { Color.heart }
    static var deepInk: Color { Color.deepInk }
    static var soul: Color { Color.soul }
    static var trust: Color { Color.trust }
    static var amberGlow: Color { Color.amberGlow }
    static var electricBlue: Color { Color.electricBlue }
    static var sageGreen: Color { Color.sageGreen }
    static var softRed: Color { Color.softRed }
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
    static let chatMessage = Font.system(size: 16)
    static let thinking = Font.system(size: 13, design: .monospaced)
    static let toolTitle = Font.system(size: 14, weight: .medium)
    static let toolDetail = Font.system(size: 12, design: .monospaced)
    static let timestamp = Font.system(size: 11)
    static let sectionHeader = Font.system(size: 12, weight: .bold)
    static let emptyStateTitle = Font.system(size: 28, weight: .light)
    static let navTitle = Font.system(size: 20, weight: .semibold)
    static let codeFont = Font.system(size: 14, design: .monospaced)
}

// MARK: - Theme Constants

struct LoveMeTheme {
    // Spacing (4px base unit)
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    // Chat
    static let chatHorizontalPadding: CGFloat = 16
    static let bubbleMaxWidthRatio: CGFloat = 0.80
    static let sameAuthorSpacing: CGFloat = 8
    static let differentAuthorSpacing: CGFloat = 16

    // Radius
    static let bubbleRadius: CGFloat = 16
    static let bubbleTailRadius: CGFloat = 4
    static let inputFieldRadius: CGFloat = 18

    // Sizes
    static let connectionDotSize: CGFloat = 6
    static let sendButtonSize: CGFloat = 36
    static let inputFieldHeight: CGFloat = 36
    static let minTouchTarget: CGFloat = 44
    static let toolCardCollapsedHeight: CGFloat = 44
    static let thinkingCollapsedHeight: CGFloat = 36
    static let thinkingMaxExpandedHeight: CGFloat = 200
    static let toolCardLeftBorderWidth: CGFloat = 3

    // Animation Durations
    static let springDuration: Double = 0.3
    static let appearDuration: Double = 0.2
    static let breatheDuration: Double = 3.0
    static let thinkingPulseDuration: Double = 1.5
}

// MARK: - Z-Layer

enum ZLayer: CGFloat {
    case background = 0
    case content = 1
    case overlay = 10
    case banner = 20
    case modal = 30
}
