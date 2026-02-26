import SwiftUI

struct EmptyStateView: View {
    @Environment(WebSocketClient.self) private var webSocket
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breatheScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: LoveMeTheme.lg) {
            Spacer()

            // Logo
            HStack(spacing: 0) {
                Text("love")
                    .font(.emptyStateTitle)
                    .foregroundStyle(.textPrimary)

                Text(".")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.heart)
                    .scaleEffect(breatheScale)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(
                            .easeInOut(duration: LoveMeTheme.breatheDuration)
                            .repeatForever(autoreverses: true)
                        ) {
                            breatheScale = 1.08
                        }
                    }

                Text("Me")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.textPrimary)
            }

            // Subtitle
            Text("Send a message to get started.")
                .font(.chatMessage)
                .foregroundStyle(.trust)

            // Connection status
            HStack(spacing: LoveMeTheme.sm) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)

                Text(connectionText)
                    .font(.system(size: 14))
                    .foregroundStyle(connectionColor)
            }
            .padding(.top, LoveMeTheme.sm)

            Spacer()
            Spacer()
        }
        .offset(y: -60)
    }

    private var connectionColor: Color {
        switch webSocket.connectionState {
        case .connected: return .sageGreen
        case .connecting: return .amberGlow
        case .disconnected: return .softRed
        }
    }

    private var connectionText: String {
        switch webSocket.connectionState {
        case .connected: return "Connected to your Mac."
        case .connecting: return "Connecting..."
        case .disconnected: return "Not connected."
        }
    }
}
