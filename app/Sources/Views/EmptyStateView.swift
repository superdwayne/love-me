import SwiftUI

struct EmptyStateView: View {
    @Environment(WebSocketClient.self) private var webSocket
    @Environment(ChatViewModel.self) private var chatVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breatheScale: CGFloat = 1.0

    private let suggestions = [
        "What can you help me with?",
        "Create a workflow to monitor my inbox",
        "Summarize my recent emails",
    ]

    var body: some View {
        VStack(spacing: SolaceTheme.lg) {
            Spacer()

            // Logo
            HStack(spacing: 0) {
                Text("Solace")
                    .font(.emptyStateTitle)
                    .foregroundStyle(.textPrimary)

                Text(".")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.heart)
                    .scaleEffect(breatheScale)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(
                            .easeInOut(duration: SolaceTheme.breatheDuration)
                            .repeatForever(autoreverses: true)
                        ) {
                            breatheScale = 1.08
                        }
                    }
            }

            // Subtitle
            Text("Send a message to get started.")
                .font(.chatMessage)
                .foregroundStyle(.trust)

            // Connection status
            HStack(spacing: SolaceTheme.sm) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)

                Text(connectionText)
                    .font(.system(size: 14))
                    .foregroundStyle(connectionColor)
            }
            .padding(.top, SolaceTheme.sm)

            // Suggestion chips
            VStack(spacing: SolaceTheme.sm) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        chatVM.inputText = suggestion
                        chatVM.sendMessage()
                    } label: {
                        HStack(spacing: SolaceTheme.sm) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.heart)
                            Text(suggestion)
                                .font(.system(size: 14))
                                .foregroundStyle(.textPrimary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, SolaceTheme.md)
                        .padding(.vertical, SolaceTheme.sm)
                        .frame(maxWidth: 300, alignment: .leading)
                        .background(Color.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, SolaceTheme.sm)

            Spacer()
            Spacer()
        }
        .offset(y: -40)
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
