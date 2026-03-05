import SwiftUI

struct VoiceTabView: View {
    @Environment(AmbientListeningViewModel.self) private var ambientVM

    var body: some View {
        List {
            ambientListeningSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // MARK: - Ambient Listening

    private var ambientListeningSection: some View {
        Section {
            HStack(spacing: SolaceTheme.md) {
                ZStack {
                    Circle()
                        .fill(ambientVM.isListening ? Color.coral.opacity(0.15) : Color.dusk.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: ambientVM.isListening ? "ear.fill" : "ear")
                        .font(.system(size: 22))
                        .foregroundStyle(ambientVM.isListening ? .coral : .dusk)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ambient Listening")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                    Text(ambientVM.isListening ? "Listening for context..." : "Continuous background awareness")
                        .font(.toolDetail)
                        .foregroundStyle(ambientVM.isListening ? .coral : .dusk)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { ambientVM.isListening },
                    set: { _ in ambientVM.toggleListening() }
                ))
                .tint(.coral)
                .labelsHidden()
            }
            .frame(minHeight: SolaceTheme.minTouchTarget)
            .listRowBackground(Color.surface)

            if ambientVM.isListening && !ambientVM.currentTranscript.isEmpty {
                VStack(alignment: .leading, spacing: SolaceTheme.sm) {
                    HStack(spacing: SolaceTheme.xs) {
                        Circle()
                            .fill(Color.coral)
                            .frame(width: 6, height: 6)
                        Text("Live transcript")
                            .font(.captionMedium)
                            .foregroundStyle(.coral)
                    }
                    Text(ambientVM.currentTranscript)
                        .font(.toolDetail)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(4)
                }
                .padding(.vertical, SolaceTheme.xs)
                .listRowBackground(Color.surface)
            }

            if ambientVM.isAnalyzing {
                HStack(spacing: SolaceTheme.sm) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.coral)
                    Text("Analyzing speech...")
                        .font(.toolDetail)
                        .foregroundStyle(.dusk)
                }
                .frame(minHeight: SolaceTheme.minTouchTarget)
                .listRowBackground(Color.surface)
            }
        } header: {
            Text("AMBIENT LISTENING")
                .font(.sectionHeaderSerif)
                .foregroundStyle(.dusk)
                .tracking(1.2)
        } footer: {
            Text("Ambient listening continuously captures speech and sends it to Solace for analysis. Suggestions appear as floating cards.")
                .font(.captionSmall)
                .foregroundStyle(.dusk.opacity(0.7))
        }
    }
}
