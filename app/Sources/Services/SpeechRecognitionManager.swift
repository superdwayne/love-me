import AVFoundation
import Observation
import Speech

private enum AudioSetupError: Error {
    case invalidFormat
}

/// Owns the AVAudioEngine and runs all audio operations off the main thread.
/// Marked @unchecked Sendable so it can be captured in GCD / Task closures.
private final class AudioEngineController: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?

    /// Store the request before dispatching to background. Call from MainActor.
    func prepare(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    /// Creates a fresh AVAudioEngine on the calling thread, configures the
    /// audio session, installs a tap, and starts capturing. Call from background.
    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let newEngine = AVAudioEngine()
        let inputNode = newEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioSetupError.invalidFormat
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        newEngine.prepare()
        try newEngine.start()
        self.engine = newEngine
    }

    /// Tears down the engine. Safe to call even if start() was never called.
    func stop() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        request = nil
    }
}

@Observable
@MainActor
final class SpeechRecognitionManager {
    var isListening = false
    var transcribedText = ""
    var error: String?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioController = AudioEngineController()

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    func startListening() {
        guard !isListening else { return }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            beginRecognition()
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    if status == .authorized {
                        self.beginRecognition()
                    } else {
                        self.error = "Speech recognition permission denied"
                    }
                }
            }
        case .denied, .restricted:
            error = "Speech recognition permission denied"
        @unknown default:
            break
        }
    }

    func stopListening() {
        audioController.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    private func beginRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            error = "Speech recognizer not available"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcribedText = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stopListening()
                }
            }
        }

        // Hand the request to the controller on MainActor, then start the
        // engine on a background queue so we never block the UI.
        audioController.prepare(request: request)
        let controller = audioController
        Task {
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try controller.start()
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                // Back on MainActor
                isListening = true
                transcribedText = ""
                error = nil
                HapticManager.recordingStarted()
            } catch is AudioSetupError {
                self.error = "Microphone not available"
                stopListening()
            } catch {
                self.error = "Audio engine error: \(error.localizedDescription)"
                stopListening()
            }
        }
    }
}
