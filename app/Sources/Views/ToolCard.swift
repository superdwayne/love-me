import SwiftUI

struct ToolCard: View {
    let toolCall: ToolCall
    @State private var isExpanded = false
    @State private var appeared = false
    @State private var gearRotation: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ChatViewModel.self) private var chatVM

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.spring(duration: SolaceTheme.springDuration)) {
                    isExpanded.toggle()
                }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(toolCall.toolName) \(statusLabel)")
            .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand") tool details")

            // Expanded content
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.surface)
        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
        .overlay(
            HStack {
                Rectangle()
                    .fill(borderColor)
                    .frame(width: SolaceTheme.toolCardLeftBorderWidth)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
        )
        .opacity(appeared ? 1.0 : 0.0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: SolaceTheme.appearDuration)) {
                    appeared = true
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: SolaceTheme.sm) {
            statusIcon
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(toolCall.toolName)
                    .font(.toolTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)

                if !toolCall.serverName.isEmpty {
                    Text(toolCall.serverName)
                        .font(.toolDetail)
                        .foregroundStyle(.trust)
                        .lineLimit(1)
                }
            }

            Spacer()

            statusBadge
        }
        .padding(.horizontal, SolaceTheme.md)
        .frame(minHeight: SolaceTheme.toolCardCollapsedHeight)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch toolCall.status {
        case .running:
            Image(systemName: "gearshape")
                .font(.system(size: 14))
                .foregroundStyle(.electricBlue)
                .rotationEffect(.degrees(gearRotation))
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(
                        .linear(duration: 2)
                        .repeatForever(autoreverses: false)
                    ) {
                        gearRotation = 360
                    }
                }

        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.sageGreen)

        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.softRed)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch toolCall.status {
        case .running:
            ProgressView()
                .scaleEffect(0.7)
                .tint(.electricBlue)

        case .success:
            if let duration = toolCall.duration {
                Text(String(format: "%.1fs", duration))
                    .font(.toolDetail)
                    .monospacedDigit()
                    .foregroundStyle(.sageGreen)
            }

        case .error:
            Text("Failed")
                .font(.toolDetail)
                .foregroundStyle(.softRed)
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            Divider()
                .background(.divider)

            if let input = toolCall.input, !input.isEmpty {
                VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                    Text("INPUT")
                        .font(.sectionHeader)
                        .foregroundStyle(.trust)
                        .tracking(1.2)

                    Text(input)
                        .font(.toolDetail)
                        .foregroundStyle(.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SolaceTheme.sm)
                        .background(.codeBg)
                        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.xs))
                }
            }

            // Inline generated image
            if let imageURL = toolCall.imageURL, let url = chatVM.daemonImageURL(from: imageURL) {
                VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                    Text("GENERATED IMAGE")
                        .font(.sectionHeader)
                        .foregroundStyle(.trust)
                        .tracking(1.2)

                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: SolaceTheme.sm)
                                .fill(Color.surfaceElevated)
                                .frame(height: 200)
                                .overlay {
                                    ProgressView()
                                        .tint(.trust)
                                }
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.sm))
                        case .failure:
                            RoundedRectangle(cornerRadius: SolaceTheme.sm)
                                .fill(Color.surfaceElevated)
                                .frame(height: 100)
                                .overlay {
                                    VStack(spacing: SolaceTheme.xs) {
                                        Image(systemName: "photo.badge.exclamationmark")
                                            .font(.system(size: 20))
                                            .foregroundStyle(.trust)
                                        Text("Failed to load image")
                                            .font(.toolDetail)
                                            .foregroundStyle(.trust)
                                    }
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if let result = toolCall.result, !result.isEmpty {
                VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                    Text("RESULT")
                        .font(.sectionHeader)
                        .foregroundStyle(.trust)
                        .tracking(1.2)

                    Text(result)
                        .font(.toolDetail)
                        .foregroundStyle(.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SolaceTheme.sm)
                        .background(.codeBg)
                        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.xs))
                        .lineLimit(10)
                }
            }

            if let error = toolCall.error, !error.isEmpty {
                VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                    Text("ERROR")
                        .font(.sectionHeader)
                        .foregroundStyle(.softRed)
                        .tracking(1.2)

                    Text(error)
                        .font(.toolDetail)
                        .foregroundStyle(.softRed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SolaceTheme.sm)
                        .background(.codeBg)
                        .clipShape(RoundedRectangle(cornerRadius: SolaceTheme.xs))
                }
            }
        }
        .padding(.horizontal, SolaceTheme.md)
        .padding(.bottom, SolaceTheme.md)
    }

    private var borderColor: Color {
        switch toolCall.status {
        case .running: return .electricBlue
        case .success: return .sageGreen
        case .error: return .softRed
        }
    }

    private var statusLabel: String {
        switch toolCall.status {
        case .running: return "running"
        case .success: return "completed successfully"
        case .error: return "failed"
        }
    }
}
