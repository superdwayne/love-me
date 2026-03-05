import AVFoundation
import SwiftUI

@Observable @MainActor
final class AmbientMusicManager {
    static let shared = AmbientMusicManager()

    var isPlaying = false
    var currentTrackId: String = "garden"
    var volume: Float = 0.3

    private var player: AVAudioPlayer?
    private var fadeTimer: Timer?

    struct Track: Identifiable {
        let id: String
        let name: String
        let icon: String
        let filename: String
    }

    static let tracks: [Track] = [
        Track(id: "garden", name: "Garden", icon: "leaf.fill", filename: "garden"),
        Track(id: "water", name: "Water", icon: "drop.fill", filename: "water"),
        Track(id: "rest", name: "Rest", icon: "moon.fill", filename: "rest"),
    ]

    private init() {
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            print("[AmbientMusic] Audio session error: \(error)")
        }
    }

    func play() {
        guard let track = Self.tracks.first(where: { $0.id == currentTrackId }),
              let url = Bundle.main.url(forResource: track.filename, withExtension: "m4a") else {
            print("[AmbientMusic] Track not found: \(currentTrackId)")
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.volume = volume
            player?.play()
            isPlaying = true
        } catch {
            print("[AmbientMusic] Playback error: \(error)")
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        player?.stop()
        player = nil
        isPlaying = false
    }

    func setVolume(_ newVolume: Float) {
        volume = newVolume
        player?.volume = newVolume
    }

    func switchTrack(_ trackId: String) {
        let wasPlaying = isPlaying
        stop()
        currentTrackId = trackId
        if wasPlaying {
            play()
        }
    }

    func fadeIn(duration: TimeInterval = 1.5) {
        guard !isPlaying else { return }
        player?.volume = 0
        play()
        animateVolume(to: volume, duration: duration)
    }

    func fadeOut(duration: TimeInterval = 1.5) {
        guard isPlaying else { return }
        let savedVolume = volume
        animateVolume(to: 0, duration: duration) { [weak self] in
            Task { @MainActor in
                self?.pause()
                self?.player?.volume = savedVolume
            }
        }
    }

    private func animateVolume(to target: Float, duration: TimeInterval, completion: (@Sendable () -> Void)? = nil) {
        fadeTimer?.invalidate()
        let steps = 30
        let interval = duration / Double(steps)
        let startVolume = player?.volume ?? 0
        let delta = (target - startVolume) / Float(steps)
        nonisolated(unsafe) var step = 0
        nonisolated(unsafe) let capturedPlayer = player
        nonisolated(unsafe) var capturedCompletion = completion

        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            step += 1
            let newVol = startVolume + delta * Float(step)
            capturedPlayer?.volume = newVol
            if step >= steps {
                timer.invalidate()
                capturedPlayer?.volume = target
                capturedCompletion?()
                capturedCompletion = nil
            }
        }
    }
}
