import SwiftUI

struct ThinkingPanel: View {
    let message: Message
    @State private var isExpanded = false
    @State private var pulseOpacity: Double = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Header - always visible
            Button {
                withAnimation(.spring(duration: SolaceTheme.springDuration)) {
                    isExpanded.toggle()
                }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand") thinking details")

            // Expanded content
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.cardRadius))
    }

    private var header: some View {
        HStack(spacing: SolaceTheme.sm) {
            Image(systemName: "brain")
                .font(.system(size: 12))
                .foregroundStyle(.coral)
                .opacity(message.isThinkingStreaming ? pulseOpacity : 1.0)
                .onAppear {
                    guard message.isThinkingStreaming, !reduceMotion else { return }
                    withAnimation(
                        .easeInOut(duration: SolaceTheme.thinkingPulseDuration)
                        .repeatForever(autoreverses: true)
                    ) {
                        pulseOpacity = 0.5
                    }
                }
                .onChange(of: message.isThinkingStreaming) { _, isStreaming in
                    if !isStreaming {
                        withAnimation(.easeOut(duration: 0.2)) {
                            pulseOpacity = 1.0
                        }
                    }
                }

            if message.isThinkingStreaming {
                Text("Thinking...")
                    .font(.thinking)
                    .foregroundStyle(.textSecondary)
            } else if let duration = message.thinkingDuration {
                Text("Thought for \(String(format: "%.1f", duration))s")
                    .font(.thinking)
                    .foregroundStyle(.textSecondary.opacity(0.7))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.textSecondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(.horizontal, SolaceTheme.md)
        .frame(height: SolaceTheme.thinkingCollapsedHeight)
        .frame(minHeight: SolaceTheme.minTouchTarget)
    }

    private var expandedContent: some View {
        ScrollView {
            Text(message.thinkingContent ?? "")
                .font(.thinking)
                .foregroundStyle(.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SolaceTheme.md)
        }
        .frame(maxHeight: SolaceTheme.thinkingMaxExpandedHeight)
    }

    private var borderColor: Color {
        isExpanded ? .coral.opacity(0.15) : .coral.opacity(0.2)
    }

    private var accessibilityLabel: String {
        if message.isThinkingStreaming {
            return "AI is thinking"
        } else if let duration = message.thinkingDuration {
            return "AI thought for \(String(format: "%.1f", duration)) seconds"
        }
        return "AI thinking panel"
    }
}
