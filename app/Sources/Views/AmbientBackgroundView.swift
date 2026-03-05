import SwiftUI

// MARK: - Shimmer Intensity

enum ShimmerIntensity {
    case subtle     // Chat — barely perceptible
    case standard   // Empty state — gentle shimmer
    case prominent  // Welcome — eye-catching

    var opacity: Double {
        switch self {
        case .subtle: return SolaceTheme.shimmerOpacitySubtle
        case .standard: return SolaceTheme.shimmerOpacityStandard
        case .prominent: return SolaceTheme.shimmerOpacityProminent
        }
    }

    /// Multiplier applied to gradient blob opacity for each intensity level
    var gradientMultiplier: Double {
        switch self {
        case .subtle: return 0.35
        case .standard: return 0.6
        case .prominent: return 1.0
        }
    }
}

// Legacy alias
typealias CausticIntensity = ShimmerIntensity

// MARK: - Gradient Color Sets

/// Local gradient-specific pastel colors (not theme tokens)
private enum GradientPalette {
    // Light mode pastels
    static let lightPink = Color(red: 0xF4/255, green: 0xD4/255, blue: 0xE4/255)
    static let lightLavender = Color(red: 0xE8/255, green: 0xD5/255, blue: 0xF0/255)
    static let lightBlue = Color(red: 0xD4/255, green: 0xE8/255, blue: 0xF8/255)
    static let lightCream = Color(red: 0xFA/255, green: 0xF7/255, blue: 0xF5/255)

    // Dark mode deep muted tones
    static let darkPurple = Color(red: 0x2A/255, green: 0x20/255, blue: 0x40/255)
    static let darkBlue = Color(red: 0x1C/255, green: 0x20/255, blue: 0x30/255)
    static let darkCharcoal = Color(red: 0x1C/255, green: 0x1B/255, blue: 0x1F/255)
    static let darkLavender = Color(red: 0x30/255, green: 0x20/255, blue: 0x40/255)
}

// MARK: - Ambient Background View

struct AmbientBackgroundView: View {
    var intensity: ShimmerIntensity = .standard

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    /// The four gradient colors, switching between light and dark palettes
    private var gradientColors: [Color] {
        if isDark {
            return [
                GradientPalette.darkPurple,
                GradientPalette.darkBlue,
                GradientPalette.darkCharcoal,
                GradientPalette.darkLavender
            ]
        } else {
            return [
                GradientPalette.lightPink,
                GradientPalette.lightLavender,
                GradientPalette.lightBlue,
                GradientPalette.lightCream
            ]
        }
    }

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            if reduceMotion {
                staticGradient
            } else {
                animatedGradient
            }
        }
    }

    // MARK: - Static Fallback (Reduce Motion)

    private var staticGradient: some View {
        let colors = gradientColors
        let multiplier = intensity.gradientMultiplier

        return ZStack {
            // Layer 4 large radial gradient circles at fixed positions
            // to form a soft, static watercolor wash
            Circle()
                .fill(
                    RadialGradient(
                        colors: [colors[0].opacity(0.6 * multiplier), colors[0].opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 300
                    )
                )
                .frame(width: 600, height: 600)
                .offset(x: -80, y: -120)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [colors[1].opacity(0.5 * multiplier), colors[1].opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 280
                    )
                )
                .frame(width: 560, height: 560)
                .offset(x: 100, y: -60)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [colors[2].opacity(0.5 * multiplier), colors[2].opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 320
                    )
                )
                .frame(width: 640, height: 640)
                .offset(x: -40, y: 140)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [colors[3].opacity(0.4 * multiplier), colors[3].opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 260
                    )
                )
                .frame(width: 520, height: 520)
                .offset(x: 60, y: 80)
        }
        .drawingGroup()
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Animated Gradient (15fps TimelineView)

    private var animatedGradient: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            GeometryReader { geo in
                let size = geo.size
                let cx = size.width * 0.5
                let cy = size.height * 0.5
                let colors = gradientColors
                let m = intensity.gradientMultiplier

                // Each blob orbits gently using sin/cos at different phases
                // Period ~10 seconds, amplitude ~15-20% of viewport
                let phase0 = time * 0.6
                let phase1 = time * 0.5 + 1.8
                let phase2 = time * 0.45 + 3.6
                let phase3 = time * 0.55 + 5.4

                let drift: CGFloat = min(size.width, size.height) * 0.18
                let blobSize = max(size.width, size.height) * 1.6

                ZStack {
                    // Blob 0 — pink / dark purple (top-left orbit)
                    blobCircle(
                        color: colors[0],
                        opacity: 0.6 * m,
                        size: blobSize,
                        radius: blobSize * 0.35,
                        offsetX: cx * 0.3 + CGFloat(cos(phase0)) * drift,
                        offsetY: cy * 0.3 + CGFloat(sin(phase0 * 0.8)) * drift
                    )

                    // Blob 1 — lavender / dark blue (top-right orbit)
                    blobCircle(
                        color: colors[1],
                        opacity: 0.5 * m,
                        size: blobSize * 0.9,
                        radius: blobSize * 0.32,
                        offsetX: cx * 1.5 + CGFloat(sin(phase1)) * drift,
                        offsetY: cy * 0.5 + CGFloat(cos(phase1 * 1.1)) * drift
                    )

                    // Blob 2 — light blue / dark charcoal (bottom-left orbit)
                    blobCircle(
                        color: colors[2],
                        opacity: 0.5 * m,
                        size: blobSize * 1.05,
                        radius: blobSize * 0.38,
                        offsetX: cx * 0.6 + CGFloat(cos(phase2 * 0.9)) * drift,
                        offsetY: cy * 1.4 + CGFloat(sin(phase2)) * drift
                    )

                    // Blob 3 — cream / dark lavender (bottom-right orbit)
                    blobCircle(
                        color: colors[3],
                        opacity: 0.4 * m,
                        size: blobSize * 0.85,
                        radius: blobSize * 0.30,
                        offsetX: cx * 1.3 + CGFloat(sin(phase3 * 1.2)) * drift,
                        offsetY: cy * 1.2 + CGFloat(cos(phase3)) * drift
                    )
                }
                .drawingGroup()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Blob Circle Helper

    /// Creates a single oversized radial-gradient circle positioned at the given offset.
    private func blobCircle(
        color: Color,
        opacity: Double,
        size: CGFloat,
        radius: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat
    ) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            .frame(width: size, height: size)
            .position(x: offsetX, y: offsetY)
    }
}
