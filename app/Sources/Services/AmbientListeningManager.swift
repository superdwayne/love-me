import AVFoundation
import Observation
import Speech

/// Owns the AVAudioEngine for ambient listening. Runs audio operations off the main thread.
/// Marked @unchecked Sendable so it can be captured in GCD / Task closures.
private final class AmbientAudioController: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func prepare(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let newEngine = AVAudioEngine()
        let inputNode = newEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "AmbientAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio format"])
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        newEngine.prepare()
        try newEngine.start()
        self.engine = newEngine
    }

    func stop() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        request = nil
    }
}

/// Continuous speech recognition with automatic session rotation (Apple 60s limit),
/// silence detection, and periodic transcript flushing.
@Observable
@MainActor
final class AmbientListeningManager {
    var isListening = false
    var currentTranscript = ""
    var error: String?

    /// Called when a transcript chunk is ready for analysis.
    /// Parameters: (text, durationSeconds, sessionCount)
    var onTranscriptReady: ((String, Int, Int) -> Void)?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioController = AmbientAudioController()

    private var accumulatedTranscript = ""
    private var sessionCount = 0
    private var sessionStartTime: Date?
    private var lastSpeechTime: Date?
    private var rotationTimer: Timer?
    private var silenceTimer: Timer?

    private let sessionDuration: TimeInterval = 55
    private let silenceThreshold: TimeInterval = 5
    private let periodicFlushInterval: TimeInterval = 30
    private let minimumTranscriptLength = 20

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    func startListening() {
        guard !isListening else { return }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            beginAmbientSession()
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    if status == .authorized {
                        self.beginAmbientSession()
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
        rotationTimer?.invalidate()
        rotationTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil

        audioController.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        // Flush any remaining transcript
        if accumulatedTranscript.count >= minimumTranscriptLength {
            let duration = Int(Date().timeIntervalSince(sessionStartTime ?? Date()))
            onTranscriptReady?(accumulatedTranscript.trimmingCharacters(in: .whitespacesAndNewlines), duration, sessionCount)
        }

        accumulatedTranscript = ""
        currentTranscript = ""
        sessionCount = 0
        isListening = false
    }

    // MARK: - Private

    private func beginAmbientSession() {
        sessionCount += 1
        sessionStartTime = sessionStartTime ?? Date()
        lastSpeechTime = Date()
        error = nil

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            error = "Speech recognizer not available"
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.currentTranscript = result.bestTranscription.formattedString
                    self.lastSpeechTime = Date()
                }
                if let error {
                    // Session ended (e.g. 60s limit or rotation) — this is expected
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                        // Recognition cancelled — expected during rotation
                        return
                    }
                    // For other errors during active listening, try to recover
                    if self.isListening {
                        self.rotateSession()
                    }
                }
                if result?.isFinal ?? false, self.isListening {
                    self.rotateSession()
                }
            }
        }

        // Start audio engine on background queue
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
                isListening = true
                startTimers()
            } catch {
                self.error = "Audio error: \(error.localizedDescription)"
                stopListening()
            }
        }
    }

    private func startTimers() {
        rotationTimer?.invalidate()
        silenceTimer?.invalidate()

        // Session rotation timer — rotate before Apple's 60s limit
        rotationTimer = Timer.scheduledTimer(withTimeInterval: sessionDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.rotateSession()
            }
        }

        // Silence/periodic flush check — poll every 1 second
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForFlush()
            }
        }
    }

    private func rotateSession() {
        guard isListening else { return }

        // Accumulate current transcript
        if !currentTranscript.isEmpty {
            if !accumulatedTranscript.isEmpty {
                accumulatedTranscript += " "
            }
            accumulatedTranscript += currentTranscript
            currentTranscript = ""
        }

        // Tear down current recognition (not the audio controller yet)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        audioController.stop()

        // Brief pause then restart
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard self.isListening else { return }
            self.beginAmbientSession()
        }
    }

    private func checkForFlush() {
        guard isListening else { return }

        let total = buildFullTranscript()
        guard total.count >= minimumTranscriptLength else { return }

        let timeSinceLastSpeech = Date().timeIntervalSince(lastSpeechTime ?? Date())
        let timeSinceSessionStart = Date().timeIntervalSince(sessionStartTime ?? Date())

        // Flush on silence (5s pause) or periodic (30s continuous speech)
        if timeSinceLastSpeech >= silenceThreshold || timeSinceSessionStart >= periodicFlushInterval {
            let duration = Int(Date().timeIntervalSince(sessionStartTime ?? Date()))
            onTranscriptReady?(total.trimmingCharacters(in: .whitespacesAndNewlines), duration, sessionCount)

            // Reset accumulated transcript but keep listening
            accumulatedTranscript = ""
            currentTranscript = ""
            sessionStartTime = Date()
        }
    }

    private func buildFullTranscript() -> String {
        var result = accumulatedTranscript
        if !currentTranscript.isEmpty {
            if !result.isEmpty { result += " " }
            result += currentTranscript
        }
        return result
    }
}
