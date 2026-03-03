import SwiftUI

struct WelcomeView: View {
    @Environment(WebSocketClient.self) private var webSocket
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    // Logo entrance animation
    @State private var logoScale: CGFloat = 0.3
    @State private var logoOpacity: Double = 0
    @State private var logoRotationX: Double = 60
    @State private var logoRotationY: Double = -30
    @State private var logoOffsetY: CGFloat = 40

    // Dot pulse
    @State private var dotScale: CGFloat = 1.0
    @State private var dotGlow: CGFloat = 0

    // Staggered content
    @State private var taglineOpacity: Double = 0
    @State private var taglineOffset: CGFloat = 20
    @State private var featuresOpacity: Double = 0
    @State private var featuresOffset: CGFloat = 30
    @State private var statusOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var buttonOffset: CGFloat = 20

    // Ambient float
    @State private var floatOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: SolaceTheme.xxl) {
            Spacer()

            // 3D Logo
            VStack(spacing: SolaceTheme.md) {
                HStack(spacing: 0) {
                    Text("Solace")
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .foregroundStyle(.textPrimary)

                    Text(".")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.heart)
                        .scaleEffect(dotScale)
                        .shadow(color: .heart.opacity(dotGlow), radius: 12, y: 0)
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                .rotation3DEffect(.degrees(logoRotationX), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
                .rotation3DEffect(.degrees(logoRotationY), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                .offset(y: logoOffsetY + floatOffset)

                // Tagline
                Text("Your personal AI assistant")
                    .font(.system(size: 17))
                    .foregroundStyle(.trust)
                    .opacity(taglineOpacity)
                    .offset(y: taglineOffset)
            }

            // Feature highlights
            VStack(spacing: SolaceTheme.lg) {
                featureRow(icon: "bubble.left.and.bubble.right.fill", label: "Chat with your AI", delay: 0)
                featureRow(icon: "arrow.triangle.branch", label: "Automate with Workflows", delay: 0.08)
                featureRow(icon: "envelope.fill", label: "Agent Mail integration", delay: 0.16)
            }
            .padding(.horizontal, SolaceTheme.xxl)
            .opacity(featuresOpacity)
            .offset(y: featuresOffset)

            // Connection status
            HStack(spacing: SolaceTheme.sm) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)

                Text(connectionText)
                    .font(.system(size: 14))
                    .foregroundStyle(connectionColor)
            }
            .opacity(statusOpacity)

            Spacer()

            // Get Started button
            Button {
                withAnimation(.easeInOut(duration: 0.35)) {
                    hasSeenWelcome = true
                }
            } label: {
                Text("Get Started")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SolaceTheme.lg)
                    .background(.heart)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, SolaceTheme.xxl)
            .padding(.bottom, SolaceTheme.xxl)
            .opacity(buttonOpacity)
            .offset(y: buttonOffset)
        }
        .background(.appBackground)
        .onAppear {
            guard !reduceMotion else {
                // Skip animations, show everything immediately
                logoScale = 1.0
                logoOpacity = 1.0
                logoRotationX = 0
                logoRotationY = 0
                logoOffsetY = 0
                dotScale = 1.0
                taglineOpacity = 1.0
                taglineOffset = 0
                featuresOpacity = 1.0
                featuresOffset = 0
                statusOpacity = 1.0
                buttonOpacity = 1.0
                buttonOffset = 0
                return
            }
            runEntrance()
        }
    }

    // MARK: - Entrance Sequence

    private func runEntrance() {
        // Phase 1: Logo flies in with 3D rotation (0.0s)
        withAnimation(.spring(duration: 0.9, bounce: 0.35)) {
            logoScale = 1.0
            logoOpacity = 1.0
            logoRotationX = 0
            logoRotationY = 0
            logoOffsetY = 0
        }

        // Phase 2: Dot pulses after logo lands (0.7s)
        withAnimation(.easeInOut(duration: 0.5).delay(0.7)) {
            dotScale = 1.3
            dotGlow = 0.6
        }
        withAnimation(.easeInOut(duration: 0.4).delay(1.2)) {
            dotScale = 1.0
            dotGlow = 0
        }

        // Start ambient breathing on the dot
        withAnimation(
            .easeInOut(duration: SolaceTheme.breatheDuration)
            .repeatForever(autoreverses: true)
            .delay(1.6)
        ) {
            dotScale = 1.08
            dotGlow = 0.3
        }

        // Start subtle float
        withAnimation(
            .easeInOut(duration: 4.0)
            .repeatForever(autoreverses: true)
            .delay(1.6)
        ) {
            floatOffset = -6
        }

        // Phase 3: Tagline fades up (0.6s)
        withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
            taglineOpacity = 1.0
            taglineOffset = 0
        }

        // Phase 4: Feature rows slide up (0.9s)
        withAnimation(.easeOut(duration: 0.5).delay(0.9)) {
            featuresOpacity = 1.0
            featuresOffset = 0
        }

        // Phase 5: Status + button (1.2s)
        withAnimation(.easeOut(duration: 0.4).delay(1.2)) {
            statusOpacity = 1.0
        }
        withAnimation(.spring(duration: 0.6, bounce: 0.3).delay(1.4)) {
            buttonOpacity = 1.0
            buttonOffset = 0
        }
    }

    // MARK: - Feature Row

    private func featureRow(icon: String, label: String, delay: Double) -> some View {
        HStack(spacing: SolaceTheme.lg) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.heart)
                .frame(width: 36, height: 36)
                .background(Color.heart.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(.textPrimary)

            Spacer()
        }
    }

    // MARK: - Connection

    private var connectionColor: Color {
        switch webSocket.connectionState {
        case .connected: return .sageGreen
        case .connecting: return .amberGlow
        case .disconnected: return .softRed
        }
    }

    private var connectionText: String {
        switch webSocket.connectionState {
        case .connected: return "Connected to your Mac"
        case .connecting: return "Connecting..."
        case .disconnected: return "Not connected"
        }
    }
}
