import SwiftUI

// MARK: - Overlay Container

struct AmbientListeningOverlay: View {
    @Environment(AmbientListeningViewModel.self) private var vm

    var body: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                VStack(alignment: .trailing, spacing: SolaceTheme.sm) {
                    // Suggestion cards
                    if !vm.suggestions.isEmpty {
                        AmbientSuggestionsStack()
                    }

                    // Transcript panel
                    if vm.showTranscriptPanel {
                        AmbientTranscriptPanel()
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    // Floating mic button
                    AmbientMicButton()
                }
                .padding(.trailing, SolaceTheme.lg)
                .padding(.bottom, 140) // Above tab bar + input bar
            }
        }
        .animation(.spring(duration: 0.35), value: vm.showTranscriptPanel)
        .animation(.spring(duration: 0.35), value: vm.suggestions.count)
    }
}

// MARK: - Floating Mic Button

private struct AmbientMicButton: View {
    @Environment(AmbientListeningViewModel.self) private var vm
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        Button {
            vm.toggleListening()
        } label: {
            ZStack {
                // Pulsing ring when active
                if vm.isListening {
                    Circle()
                        .stroke(Color.coral.opacity(0.3), lineWidth: 2)
                        .frame(width: 64, height: 64)
                        .scaleEffect(pulseScale)
                        .opacity(2.0 - Double(pulseScale))
                }

                Circle()
                    .fill(vm.isListening ? Color.coral : Color.surface)
                    .frame(width: 52, height: 52)
                    .shadow(color: vm.isListening ? Color.coral.opacity(0.3) : .black.opacity(0.1), radius: 12, y: 4)

                Image(systemName: vm.isListening ? "waveform" : "mic")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(vm.isListening ? .white : .coral)
                    .symbolEffect(.variableColor.iterative, isActive: vm.isListening)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    vm.showTranscriptPanel.toggle()
                }
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.4
            }
        }
    }
}

// MARK: - Transcript Panel

private struct AmbientTranscriptPanel: View {
    @Environment(AmbientListeningViewModel.self) private var vm

    var body: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            HStack {
                if vm.isListening {
                    Circle()
                        .fill(Color.coral)
                        .frame(width: 8, height: 8)
                    Text("Listening...")
                        .font(.captionMedium)
                        .foregroundStyle(.coral)
                } else {
                    Text("Paused")
                        .font(.captionMedium)
                        .foregroundStyle(.textSecondary)
                }

                Spacer()

                if vm.isAnalyzing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.coral)
                        Text("Analyzing...")
                            .font(.captionSmall)
                            .foregroundStyle(.textSecondary)
                    }
                }

                Button {
                    vm.showTranscriptPanel = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.textSecondary)
                }
            }

            if vm.currentTranscript.isEmpty {
                Text("Speak and your words will appear here...")
                    .font(.bodySmall)
                    .foregroundStyle(.textSecondary.opacity(0.5))
                    .italic()
            } else {
                ScrollView {
                    Text(vm.currentTranscript)
                        .font(.bodySmall)
                        .foregroundStyle(.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
        }
        .padding(SolaceTheme.md)
        .frame(width: 260)
        .glassElevated(cornerRadius: 16)
    }
}

// MARK: - Suggestions Stack

private struct AmbientSuggestionsStack: View {
    @Environment(AmbientListeningViewModel.self) private var vm

    var body: some View {
        VStack(spacing: SolaceTheme.sm) {
            ForEach(vm.suggestions.prefix(3)) { suggestion in
                AmbientSuggestionCard(suggestion: suggestion)
            }

            if vm.suggestions.count > 3 {
                Text("+\(vm.suggestions.count - 3) more")
                    .font(.captionSmall)
                    .foregroundStyle(.textSecondary)
            }
        }
    }
}

// MARK: - Suggestion Card

private struct AmbientSuggestionCard: View {
    @Environment(AmbientListeningViewModel.self) private var vm
    let suggestion: AmbientSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: SolaceTheme.sm) {
            HStack(spacing: SolaceTheme.sm) {
                Image(systemName: suggestion.typeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.coral)
                    .frame(width: 24, height: 24)
                    .background(Color.coral.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.typeLabel)
                        .font(.tiny)
                        .foregroundStyle(.textSecondary)
                        .textCase(.uppercase)
                    Text(suggestion.title)
                        .font(.bodySmallMedium)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(2)
                }

                Spacer()
            }

            if !suggestion.description.isEmpty {
                Text(suggestion.description)
                    .font(.captionSmall)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: SolaceTheme.sm) {
                Spacer()

                switch suggestion.status {
                case .pending:
                    Button {
                        vm.dismissSuggestion(suggestion)
                    } label: {
                        Text("Dismiss")
                            .font(.captionMedium)
                            .foregroundStyle(.textSecondary)
                            .padding(.horizontal, SolaceTheme.md)
                            .padding(.vertical, SolaceTheme.xs)
                    }

                    Button {
                        vm.approveSuggestion(suggestion)
                    } label: {
                        Text("Approve")
                            .font(.captionMedium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, SolaceTheme.md)
                            .padding(.vertical, SolaceTheme.xs)
                            .background(Color.coral)
                            .clipShape(Capsule())
                    }

                case .approving:
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.coral)
                        Text("Running...")
                            .font(.captionMedium)
                            .foregroundStyle(.textSecondary)
                    }

                case .completed:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.success)
                        Text("Done")
                            .font(.captionMedium)
                            .foregroundStyle(.success)
                    }

                case .dismissed:
                    EmptyView()
                }
            }
        }
        .padding(SolaceTheme.md)
        .frame(width: 260)
        .glassElevated(cornerRadius: 16)
    }
}
