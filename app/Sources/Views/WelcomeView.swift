import SwiftUI

struct WelcomeView: View {
    @Environment(WebSocketClient.self) private var webSocket
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    // Staggered entrance
    @State private var logoOpacity: Double = 0
    @State private var logoOffset: CGFloat = 16
    @State private var taglineOpacity: Double = 0
    @State private var taglineOffset: CGFloat = 12
    @State private var featuresOpacity: Double = 0
    @State private var featuresOffset: CGFloat = 16
    @State private var statusOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var buttonOffset: CGFloat = 12

    var body: some View {
        VStack(spacing: SolaceTheme.xxl) {
            Spacer()

            // Wordmark
            VStack(spacing: SolaceTheme.md) {
                HStack(spacing: 0) {
                    Text("Solace")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.textPrimary)

                    Text(".")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.coral)
                }
                .opacity(logoOpacity)
                .offset(y: logoOffset)

                Text("Your AI, ready to work.")
                    .font(.system(size: 16))
                    .foregroundStyle(.textSecondary)
                    .opacity(taglineOpacity)
                    .offset(y: taglineOffset)
            }

            // Feature chips
            VStack(spacing: SolaceTheme.sm) {
                featureRow(icon: "bubble.left.and.bubble.right", label: "Chat with your AI")
                featureRow(icon: "bolt.fill", label: "Automate with Workflows")
                featureRow(icon: "envelope.fill", label: "Agent Mail integration")
            }
            .padding(.horizontal, SolaceTheme.xxl)
            .opacity(featuresOpacity)
            .offset(y: featuresOffset)

            // Connection status
            HStack(spacing: SolaceTheme.sm) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 6, height: 6)

                Text(connectionText)
                    .font(.system(size: 13))
                    .foregroundStyle(.textSecondary)
            }
            .opacity(statusOpacity)

            Spacer()

            // Get Started button
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    hasSeenWelcome = true
                }
            } label: {
                Text("Get Started")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SolaceTheme.lg)
                    .background(.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, SolaceTheme.xxl)
            .padding(.bottom, SolaceTheme.xxl)
            .opacity(buttonOpacity)
            .offset(y: buttonOffset)
        }
        .background(.appBackground)
        .onAppear {
            guard !reduceMotion else {
                logoOpacity = 1.0
                logoOffset = 0
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
        withAnimation(.easeOut(duration: 0.4)) {
            logoOpacity = 1.0
            logoOffset = 0
        }

        withAnimation(.easeOut(duration: 0.35).delay(0.2)) {
            taglineOpacity = 1.0
            taglineOffset = 0
        }

        withAnimation(.easeOut(duration: 0.35).delay(0.4)) {
            featuresOpacity = 1.0
            featuresOffset = 0
        }

        withAnimation(.easeOut(duration: 0.3).delay(0.6)) {
            statusOpacity = 1.0
        }

        withAnimation(.easeOut(duration: 0.35).delay(0.7)) {
            buttonOpacity = 1.0
            buttonOffset = 0
        }
    }

    // MARK: - Feature Row

    private func featureRow(icon: String, label: String) -> some View {
        HStack(spacing: SolaceTheme.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.coral)
                .frame(width: 32, height: 32)
                .background(Color.coral.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(.textPrimary)

            Spacer()
        }
        .padding(.horizontal, SolaceTheme.lg)
        .padding(.vertical, SolaceTheme.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.cardRadius))
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
