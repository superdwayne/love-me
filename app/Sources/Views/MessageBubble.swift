import SwiftUI

struct MessageBubble: View {
    let message: Message
    @Environment(ChatViewModel.self) private var chatVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: UIScreen.main.bounds.width * (1 - LoveMeTheme.bubbleMaxWidthRatio))
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: LoveMeTheme.xs) {
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
                Spacer(minLength: UIScreen.main.bounds.width * (1 - LoveMeTheme.bubbleMaxWidthRatio))
            }
        }
        .opacity(message.sendFailed ? 0.6 : 1.0)
        .opacity(appeared ? 1.0 : 0.0)
        .offset(y: appeared ? 0 : (message.role == .user ? 10 : 0))
        .scaleEffect(appeared ? 1.0 : (message.role == .user ? 0.8 : 1.0))
        .offset(x: appeared ? 0 : (message.role == .assistant ? -20 : 0))
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(duration: LoveMeTheme.springDuration)) {
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
        .padding(LoveMeTheme.md)
        .frame(maxWidth: UIScreen.main.bounds.width * LoveMeTheme.bubbleMaxWidthRatio,
               alignment: message.role == .user ? .trailing : .leading)
        .background(bubbleBackground)
        .clipShape(bubbleShape)
        .overlay {
            if message.role == .assistant {
                RoundedRectangle(cornerRadius: LoveMeTheme.bubbleRadius)
                    .stroke(Color.assistantBubbleBorder, lineWidth: 1)
            }
        }
    }

    private var streamingPlaceholder: some View {
        HStack(spacing: LoveMeTheme.xs) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.trust)
                    .frame(width: 6, height: 6)
                    .opacity(0.5)
            }
        }
        .padding(.vertical, LoveMeTheme.sm)
    }

    private var bubbleBackground: Color {
        message.role == .user
            ? .heart.opacity(0.9)
            : .surface
    }

    private var bubbleShape: UnevenRoundedRectangle {
        if message.role == .user {
            return UnevenRoundedRectangle(
                topLeadingRadius: LoveMeTheme.bubbleRadius,
                bottomLeadingRadius: LoveMeTheme.bubbleRadius,
                bottomTrailingRadius: LoveMeTheme.bubbleTailRadius,
                topTrailingRadius: LoveMeTheme.bubbleRadius
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: LoveMeTheme.bubbleRadius,
                bottomLeadingRadius: LoveMeTheme.bubbleTailRadius,
                bottomTrailingRadius: LoveMeTheme.bubbleRadius,
                topTrailingRadius: LoveMeTheme.bubbleRadius
            )
        }
    }

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
}
