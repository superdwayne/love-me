import SwiftUI

struct ConnectionBanner: View {
    @Environment(WebSocketClient.self) private var webSocket
    @State private var isDismissed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !isDismissed {
            HStack(spacing: SolaceTheme.sm) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text(bannerTitle)
                        .font(.system(size: 14, weight: .medium))

                    if webSocket.retryCount > 3 {
                        Text("Retry attempt \(webSocket.retryCount)")
                            .font(.system(size: 12))
                            .opacity(0.8)
                    }
                }

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: SolaceTheme.minTouchTarget,
                               height: SolaceTheme.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss connection banner")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, SolaceTheme.lg)
            .padding(.vertical, SolaceTheme.sm)
            .background(bannerColor)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onChange(of: webSocket.connectionState) { oldState, newState in
                if newState == .connected {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDismissed = true
                    }
                } else if newState == .disconnected && oldState != .disconnected {
                    // Always reappear when connection transitions to disconnected
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDismissed = false
                    }
                }
            }
            .accessibilityLabel(bannerTitle)
        }
    }

    private var bannerTitle: String {
        if webSocket.retryCount > 3 {
            return "Can't reach your Mac. Check that the daemon is running."
        }
        return "Connection lost. Reconnecting..."
    }

    private var bannerColor: Color {
        webSocket.retryCount > 3 ? .softRed : .amberGlow
    }
}
