import SwiftUI

// MARK: - Streaming Dots Animation

private struct StreamingDotsView: View {
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: SolaceTheme.xs) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.trust)
                    .frame(width: 6, height: 6)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

struct MessageBubble: View {
    let message: Message
    @Environment(ChatViewModel.self) private var chatVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var dragOffset: CGFloat = 0
    @State private var didTriggerReply = false

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: UIScreen.main.bounds.width * (1 - SolaceTheme.bubbleMaxWidthRatio))
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: SolaceTheme.xs) {
                bubbleContent
                    .contextMenu {
                        Button {
                            chatVM.copyMessageContent(message)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }

                        if message.role == .user {
                            Button {
                                chatVM.retryMessage(message)
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                        }

                        Button(role: .destructive) {
                            chatVM.deleteMessage(message)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                // Timestamp
                Text(formattedTimestamp)
                    .font(.timestamp)
                    .foregroundStyle(.trust)

                // Failed state
                if message.sendFailed {
                    Text("Not sent. Tap to retry.")
                        .font(.system(size: 12))
                        .foregroundStyle(.softRed)
                        .onTapGesture {
                            chatVM.retryMessage(message)
                        }
                }
            }

            if message.role == .assistant {
                Spacer(minLength: UIScreen.main.bounds.width * (1 - SolaceTheme.bubbleMaxWidthRatio))
            }
        }
        .opacity(message.sendFailed ? 0.6 : 1.0)
        .opacity(appeared ? 1.0 : 0.0)
        .offset(y: appeared ? 0 : (message.role == .user ? 10 : 0))
        .scaleEffect(appeared ? 1.0 : (message.role == .user ? 0.8 : 1.0))
        .offset(x: appeared ? 0 : (message.role == .assistant ? -20 : 0))
        .offset(x: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    // Only allow right-swipe
                    guard value.translation.width > 0 else { return }
                    dragOffset = min(value.translation.width * 0.4, 60)
                    if dragOffset > 40 && !didTriggerReply {
                        didTriggerReply = true
                        HapticManager.longPress()
                    }
                }
                .onEnded { _ in
                    if didTriggerReply {
                        chatVM.quoteReply(message)
                    }
                    withAnimation(.spring(duration: 0.25)) {
                        dragOffset = 0
                    }
                    didTriggerReply = false
                }
        )
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(duration: SolaceTheme.springDuration)) {
                    appeared = true
                }
            }
        }
    }

    private var bubbleContent: some View {
        Group {
            if message.content.isEmpty && message.isStreaming {
                streamingPlaceholder
            } else {
                Text(MarkdownRenderer.render(message.content))
                    .font(.chatMessage)
                    .foregroundStyle(message.role == .user ? .white : .textPrimary)
            }
        }
        .padding(SolaceTheme.md)
        .frame(maxWidth: UIScreen.main.bounds.width * SolaceTheme.bubbleMaxWidthRatio,
               alignment: message.role == .user ? .trailing : .leading)
        .background(bubbleBackground)
        .clipShape(bubbleShape)
        .overlay {
            if message.role == .assistant {
                RoundedRectangle(cornerRadius: SolaceTheme.bubbleRadius)
                    .stroke(Color.assistantBubbleBorder, lineWidth: 1)
            }
        }
    }

    private var streamingPlaceholder: some View {
        StreamingDotsView()
            .padding(.vertical, SolaceTheme.sm)
    }

    private var bubbleBackground: Color {
        message.role == .user
            ? .heart.opacity(0.9)
            : .surface
    }

    private var bubbleShape: UnevenRoundedRectangle {
        if message.role == .user {
            return UnevenRoundedRectangle(
                topLeadingRadius: SolaceTheme.bubbleRadius,
                bottomLeadingRadius: SolaceTheme.bubbleRadius,
                bottomTrailingRadius: SolaceTheme.bubbleTailRadius,
                topTrailingRadius: SolaceTheme.bubbleRadius
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: SolaceTheme.bubbleRadius,
                bottomLeadingRadius: SolaceTheme.bubbleTailRadius,
                bottomTrailingRadius: SolaceTheme.bubbleRadius,
                topTrailingRadius: SolaceTheme.bubbleRadius
            )
        }
    }

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
}
