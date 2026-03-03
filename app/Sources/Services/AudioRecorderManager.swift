import AVFoundation
import Observation

@Observable
@MainActor
final class AudioRecorderManager {
    var isRecording = false
    var recordingDuration: TimeInterval = 0

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var durationTimer: Timer?

    /// Start recording audio in M4A format (AAC codec).
    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("AudioRecorderManager: failed to configure audio session: \(error)")
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let filename = "voice_\(UUID().uuidString.prefix(8)).m4a"
        let url = tempDir.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128000
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record()
            self.audioRecorder = recorder
            self.recordingURL = url
            self.isRecording = true
            self.recordingDuration = 0

            // Start duration timer
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    self.recordingDuration = self.audioRecorder?.currentTime ?? 0
                }
            }

            HapticManager.recordingStarted()
        } catch {
            print("AudioRecorderManager: failed to start recording: \(error)")
        }
    }

    /// Stop recording and return the audio data and duration.
    func stopRecording() -> (data: Data, duration: TimeInterval)? {
        guard let recorder = audioRecorder, isRecording else { return nil }

        let duration = recorder.currentTime
        recorder.stop()

        durationTimer?.invalidate()
        durationTimer = nil
        isRecording = false

        HapticManager.recordingStopped()

        guard let url = recordingURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: url)
        recordingURL = nil
        audioRecorder = nil

        return (data: data, duration: duration)
    }

    /// Cancel a recording without returning data.
    func cancelRecording() {
        audioRecorder?.stop()
        durationTimer?.invalidate()
        durationTimer = nil
        isRecording = false

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        audioRecorder = nil
        recordingDuration = 0
    }

    /// Formatted duration string (e.g., "0:05", "1:23").
    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
