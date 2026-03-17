import SwiftUI
import AVFoundation

@Observable
@MainActor
final class VoiceNotePlayer {
    var isPlaying = false
    var progress: Double = 0
    var currentTime: TimeInterval = 0

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    private let audioData: Data
    let duration: TimeInterval

    init(audioData: Data, duration: TimeInterval) {
        self.audioData = audioData
        self.duration = duration
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let player = try AVAudioPlayer(data: audioData, fileTypeHint: AVFileType.m4a.rawValue)
            player.prepareToPlay()
            player.play()
            self.audioPlayer = player
            self.isPlaying = true

            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    guard let player = self.audioPlayer else { return }
                    if player.isPlaying {
                        self.currentTime = player.currentTime
                        self.progress = player.duration > 0 ? player.currentTime / player.duration : 0
                    } else {
                        // Playback finished
                        self.stop()
                    }
                }
            }
        } catch {
            print("VoiceNotePlayer: playback error: \(error)")
        }
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        progressTimer?.invalidate()
        progressTimer = nil
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        progress = 0
        currentTime = 0
        progressTimer?.invalidate()
        progressTimer = nil
    }

    var formattedDuration: String {
        let total = duration > 0 ? duration : (audioPlayer?.duration ?? 0)
        let minutes = Int(total) / 60
        let seconds = Int(total) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    var formattedCurrentTime: String {
        let minutes = Int(currentTime) / 60
        let seconds = Int(currentTime) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

struct VoiceNotePlayerView: View {
    let audioData: Data
    let duration: TimeInterval
    let isUserMessage: Bool

    @State private var player: VoiceNotePlayer?

    var body: some View {
        HStack(spacing: SolaceTheme.sm) {
            // Play/Pause button
            Button {
                ensurePlayer()
                player?.togglePlayback()
            } label: {
                Image(systemName: player?.isPlaying == true ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isUserMessage ? .white : .heart)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(player?.isPlaying == true ? "Pause voice note" : "Play voice note")

            // Waveform / progress bar
            VStack(alignment: .leading, spacing: SolaceTheme.xs) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isUserMessage ? Color.white.opacity(0.3) : Color.textSecondary.opacity(0.3))
                            .frame(height: 4)

                        // Progress fill
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isUserMessage ? Color.white : Color.heart)
                            .frame(width: geo.size.width * (player?.progress ?? 0), height: 4)
                    }
                }
                .frame(height: 4)

                // Waveform bars (decorative)
                HStack(spacing: 2) {
                    ForEach(0..<20, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(barColor(at: i))
                            .frame(width: 3, height: barHeight(at: i))
                    }
                    Spacer()
                }
                .frame(height: 16)
            }

            // Duration label
            Text(player?.isPlaying == true ? (player?.formattedCurrentTime ?? "0:00") : formatDuration(duration))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(isUserMessage ? .white.opacity(0.8) : .textSecondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.vertical, SolaceTheme.xs)
        .onDisappear {
            player?.stop()
        }
    }

    private func ensurePlayer() {
        if player == nil {
            player = VoiceNotePlayer(audioData: audioData, duration: duration)
        }
    }

    private func barColor(at index: Int) -> Color {
        let progressFraction = player?.progress ?? 0
        let barFraction = Double(index) / 20.0
        if barFraction <= progressFraction {
            return isUserMessage ? .white : .heart
        }
        return isUserMessage ? .white.opacity(0.3) : .textSecondary.opacity(0.3)
    }

    private func barHeight(at index: Int) -> CGFloat {
        // Pseudo-waveform pattern
        let heights: [CGFloat] = [4, 8, 6, 12, 10, 14, 8, 16, 12, 10, 14, 8, 12, 16, 10, 6, 14, 8, 10, 6]
        let idx = index % heights.count
        return heights[idx]
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

// MARK: - Remote Voice Note (fetches audio from URL for conversation history)

struct RemoteVoiceNoteView: View {
    let url: URL
    let duration: TimeInterval
    let isUserMessage: Bool

    @State private var audioData: Data?
    @State private var isLoading = false
    @State private var loadFailed = false

    var body: some View {
        if let data = audioData {
            VoiceNotePlayerView(
                audioData: data,
                duration: duration,
                isUserMessage: isUserMessage
            )
        } else if isLoading {
            HStack(spacing: SolaceTheme.sm) {
                ProgressView()
                    .tint(isUserMessage ? .white : .textSecondary)
                Text("Loading voice note...")
                    .font(.system(size: 13))
                    .foregroundStyle(isUserMessage ? .white.opacity(0.8) : .textSecondary)
            }
            .padding(.vertical, SolaceTheme.xs)
        } else if loadFailed {
            HStack(spacing: SolaceTheme.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(isUserMessage ? .white : .softRed)
                Text("Voice note unavailable")
                    .font(.system(size: 13))
                    .foregroundStyle(isUserMessage ? .white.opacity(0.8) : .textSecondary)
            }
            .padding(.vertical, SolaceTheme.xs)
        } else {
            HStack(spacing: SolaceTheme.sm) {
                Image(systemName: "waveform")
                    .foregroundStyle(isUserMessage ? .white : .heart)
                Text("Voice note")
                    .font(.system(size: 13))
                    .foregroundStyle(isUserMessage ? .white.opacity(0.8) : .textSecondary)
            }
            .padding(.vertical, SolaceTheme.xs)
            .onTapGesture {
                fetchAudio()
            }
            .onAppear {
                fetchAudio()
            }
        }
    }

    private func fetchAudio() {
        guard !isLoading else { return }
        isLoading = true
        loadFailed = false

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                await MainActor.run {
                    self.audioData = data
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.loadFailed = true
                    self.isLoading = false
                }
            }
        }
    }
}
