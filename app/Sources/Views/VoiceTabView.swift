import SwiftUI
import AVFoundation
import Speech

struct VoiceTabView: View {
    @Environment(ChatViewModel.self) private var chatVM
    @Environment(AmbientListeningViewModel.self) private var ambientVM
    @State private var speechManager = SpeechRecognitionManager()
    @State private var audioRecorder = AudioRecorderManager()

    var body: some View {
        List {
            dictationSection
            voiceNoteSection
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

    // MARK: - Dictation

    private var dictationSection: some View {
        Section {
            if speechManager.isListening {
                // Active listening state
                VStack(spacing: SolaceTheme.md) {
                    HStack(spacing: SolaceTheme.sm) {
                        Image(systemName: "waveform")
                            .font(.system(size: 16))
                            .foregroundStyle(.coral)
                            .symbolEffect(.variableColor.iterative, isActive: true)
                        Text("Listening...")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.coral)
                        Spacer()
                    }

                    Text(speechManager.transcribedText.isEmpty ? "Speak now..." : speechManager.transcribedText)
                        .font(.chatMessage)
                        .foregroundStyle(speechManager.transcribedText.isEmpty ? .dusk : .textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 60)

                    HStack(spacing: SolaceTheme.md) {
                        Button {
                            speechManager.stopListening()
                        } label: {
                            HStack(spacing: SolaceTheme.xs) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Cancel")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(.dusk)
                            .padding(.horizontal, SolaceTheme.md)
                            .padding(.vertical, SolaceTheme.sm)
                            .background(Color.dusk.opacity(0.1))
                            .clipShape(Capsule())
                        }

                        Spacer()

                        Button {
                            acceptDictation()
                        } label: {
                            HStack(spacing: SolaceTheme.xs) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Use Text")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, SolaceTheme.md)
                            .padding(.vertical, SolaceTheme.sm)
                            .background(Color.coral)
                            .clipShape(Capsule())
                        }
                        .disabled(speechManager.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.vertical, SolaceTheme.sm)
                .listRowBackground(Color.surface)
            } else {
                // Start dictation button
                Button {
                    startSpeechToText()
                } label: {
                    HStack(spacing: SolaceTheme.md) {
                        ZStack {
                            Circle()
                                .fill(Color.coral.opacity(0.12))
                                .frame(width: 48, height: 48)
                            Image(systemName: "mic.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.coral)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dictation")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.textPrimary)
                            Text("Tap to speak, text appears in chat input")
                                .font(.toolDetail)
                                .foregroundStyle(.dusk)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.dusk.opacity(0.5))
                    }
                    .frame(minHeight: SolaceTheme.minTouchTarget)
                }
                .listRowBackground(Color.surface)

                if let error = speechManager.error {
                    Text(error)
                        .font(.toolDetail)
                        .foregroundStyle(.error)
                        .listRowBackground(Color.surface)
                }
            }
        } header: {
            Text("DICTATION")
                .font(.sectionHeaderSerif)
                .foregroundStyle(.dusk)
                .tracking(1.2)
        }
    }

    // MARK: - Voice Note

    private var voiceNoteSection: some View {
        Section {
            if audioRecorder.isRecording {
                // Active recording state
                VStack(spacing: SolaceTheme.md) {
                    HStack(spacing: SolaceTheme.sm) {
                        Circle()
                            .fill(Color.glow)
                            .frame(width: 10, height: 10)
                        Text("Recording")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.textPrimary)
                        Text(audioRecorder.formattedDuration)
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(.dusk)
                        Spacer()
                    }

                    HStack(spacing: SolaceTheme.md) {
                        Button {
                            audioRecorder.cancelRecording()
                        } label: {
                            HStack(spacing: SolaceTheme.xs) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Cancel")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(.dusk)
                            .padding(.horizontal, SolaceTheme.md)
                            .padding(.vertical, SolaceTheme.sm)
                            .background(Color.dusk.opacity(0.1))
                            .clipShape(Capsule())
                        }

                        Spacer()

                        Button {
                            stopRecordingAndSend()
                        } label: {
                            HStack(spacing: SolaceTheme.xs) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Stop & Send")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, SolaceTheme.md)
                            .padding(.vertical, SolaceTheme.sm)
                            .background(Color.glow)
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.vertical, SolaceTheme.sm)
                .listRowBackground(Color.surface)
            } else {
                Button {
                    requestMicAndRecord()
                } label: {
                    HStack(spacing: SolaceTheme.md) {
                        ZStack {
                            Circle()
                                .fill(Color.glow.opacity(0.12))
                                .frame(width: 48, height: 48)
                            Image(systemName: "waveform")
                                .font(.system(size: 22))
                                .foregroundStyle(.glow)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Voice Note")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.textPrimary)
                            Text("Record and send an audio message")
                                .font(.toolDetail)
                                .foregroundStyle(.dusk)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.dusk.opacity(0.5))
                    }
                    .frame(minHeight: SolaceTheme.minTouchTarget)
                }
                .listRowBackground(Color.surface)
            }
        } header: {
            Text("VOICE NOTE")
                .font(.sectionHeaderSerif)
                .foregroundStyle(.dusk)
                .tracking(1.2)
        }
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

    // MARK: - Actions

    private func startSpeechToText() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            speechManager.startListening()
        case .denied:
            break
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                if granted {
                    Task { @MainActor in
                        speechManager.startListening()
                    }
                }
            }
        @unknown default:
            break
        }
    }

    private func acceptDictation() {
        let text = speechManager.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        speechManager.stopListening()
        if !text.isEmpty {
            chatVM.inputText = text
            HapticManager.toolCompleted()
        }
    }

    private func requestMicAndRecord() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            audioRecorder.startRecording()
        case .denied:
            break
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                if granted {
                    Task { @MainActor in
                        audioRecorder.startRecording()
                    }
                }
            }
        @unknown default:
            break
        }
    }

    private func stopRecordingAndSend() {
        guard let result = audioRecorder.stopRecording() else { return }
        chatVM.addVoiceNote(data: result.data, duration: result.duration)
        chatVM.sendMessage()
    }
}
