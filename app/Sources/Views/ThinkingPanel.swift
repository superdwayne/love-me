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
                withAnimation(.spring(duration: LoveMeTheme.springDuration)) {
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
        .clipShape(RoundedRectangle(cornerRadius: LoveMeTheme.sm))
        .overlay(
            RoundedRectangle(cornerRadius: LoveMeTheme.sm)
                .stroke(
                    borderColor,
                    lineWidth: 1
                )
        )
    }

    private var header: some View {
        HStack(spacing: LoveMeTheme.sm) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12))
                .foregroundStyle(.amberGlow)
                .opacity(message.isThinkingStreaming ? pulseOpacity : 1.0)
                .onAppear {
                    guard message.isThinkingStreaming, !reduceMotion else { return }
                    withAnimation(
                        .easeInOut(duration: LoveMeTheme.thinkingPulseDuration)
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
                    .foregroundStyle(.amberGlow)
            } else if let duration = message.thinkingDuration {
                Text("Thought for \(String(format: "%.1f", duration))s")
                    .font(.thinking)
                    .foregroundStyle(.amberGlow.opacity(0.8))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.trust)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(.horizontal, LoveMeTheme.md)
        .frame(height: LoveMeTheme.thinkingCollapsedHeight)
        .frame(minHeight: LoveMeTheme.minTouchTarget)
    }

    private var expandedContent: some View {
        ScrollView {
            Text(message.thinkingContent ?? "")
                .font(.thinking)
                .foregroundStyle(.trust)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(LoveMeTheme.md)
        }
        .frame(maxHeight: LoveMeTheme.thinkingMaxExpandedHeight)
    }

    private var borderColor: Color {
        isExpanded ? .amberGlow.opacity(0.2) : .amberGlow.opacity(0.3)
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
