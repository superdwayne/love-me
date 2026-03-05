import SwiftUI

// MARK: - Flat Card Background Modifier

struct GlassBackgroundModifier: ViewModifier {
    let opacity: Double
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.surface)
            )
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }
}

// MARK: - Elevated Card Modifier

struct GlassElevatedModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.surfaceElevated)
            )
            .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
    }
}

// MARK: - Input Field Modifier

struct GlassInputModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.inputBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.divider.opacity(0.3), lineWidth: 0.3)
            )
    }
}

// MARK: - Input Field Focused Modifier

struct GlassInputFocusedModifier: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.inputBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isFocused ? Color.coral.opacity(0.4) : Color.divider.opacity(0.3),
                        lineWidth: isFocused ? 1.0 : 0.5
                    )
            )
            .shadow(color: isFocused ? Color.coral.opacity(0.1) : .clear, radius: 8, y: 0)
    }
}

// MARK: - Shimmer Modifier

struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1.0

    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if !reduceMotion {
                        GeometryReader { geo in
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: max(0, phase - 0.15)),
                                    .init(color: Color.coral.opacity(0.06), location: phase),
                                    .init(color: .clear, location: min(1, phase + 0.15))
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.conversationBlockRadius))
                            .allowsHitTesting(false)
                        }
                        .onAppear {
                            withAnimation(
                                .linear(duration: SolaceTheme.shimmerDuration)
                                .repeatForever(autoreverses: false)
                            ) {
                                phase = 2.0
                            }
                        }
                    }
                }
            )
    }
}

// MARK: - Ripple Modifier

struct RippleModifier: ViewModifier {
    @Binding var trigger: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rippleScale: CGFloat = 0
    @State private var rippleOpacity: Double = 0.15

    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if !reduceMotion {
                        Circle()
                            .stroke(Color.shimmerAccent, lineWidth: 1.5)
                            .scaleEffect(rippleScale)
                            .opacity(rippleOpacity)
                            .allowsHitTesting(false)
                    }
                }
            )
            .onChange(of: trigger) { _, newValue in
                guard newValue, !reduceMotion else { return }
                rippleScale = 0
                rippleOpacity = 0.15
                withAnimation(.easeOut(duration: SolaceTheme.rippleDuration)) {
                    rippleScale = 1.0
                    rippleOpacity = 0
                }
                // Reset trigger
                DispatchQueue.main.asyncAfter(deadline: .now() + SolaceTheme.rippleDuration) {
                    trigger = false
                }
            }
    }
}

// MARK: - View Extension

extension View {
    func glassBackground(opacity: Double = 0.8, cornerRadius: CGFloat = SolaceTheme.cardRadius) -> some View {
        modifier(GlassBackgroundModifier(opacity: opacity, cornerRadius: cornerRadius))
    }

    func glassElevated(cornerRadius: CGFloat = SolaceTheme.cardRadius) -> some View {
        modifier(GlassElevatedModifier(cornerRadius: cornerRadius))
    }

    func glassInput(cornerRadius: CGFloat = SolaceTheme.inputFieldRadius) -> some View {
        modifier(GlassInputModifier(cornerRadius: cornerRadius))
    }

    func glassInputFocused(isFocused: Bool, cornerRadius: CGFloat = SolaceTheme.inputFieldRadius) -> some View {
        modifier(GlassInputFocusedModifier(isFocused: isFocused, cornerRadius: cornerRadius))
    }

    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }

    func waterShimmer() -> some View {
        modifier(ShimmerModifier())
    }

    func rippleEffect(trigger: Binding<Bool>) -> some View {
        modifier(RippleModifier(trigger: trigger))
    }
}
