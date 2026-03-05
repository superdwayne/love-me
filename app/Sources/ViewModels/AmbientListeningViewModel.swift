import Foundation
import Observation

// MARK: - Suggestion Model

struct AmbientSuggestion: Identifiable {
    let id: String
    let type: SuggestionType
    let title: String
    let description: String
    let actionPayload: String
    let confidence: Double
    var status: SuggestionStatus = .pending

    enum SuggestionType: String {
        case summary
        case task
        case workflow
        case reminder
        case chat
    }

    enum SuggestionStatus {
        case pending
        case approving
        case completed
        case dismissed
    }

    var typeIcon: String {
        switch type {
        case .summary: return "doc.text"
        case .task: return "checkmark.circle"
        case .workflow: return "arrow.triangle.branch"
        case .reminder: return "bell"
        case .chat: return "bubble.left"
        }
    }

    var typeLabel: String {
        switch type {
        case .summary: return "Summary"
        case .task: return "Task"
        case .workflow: return "Workflow"
        case .reminder: return "Reminder"
        case .chat: return "Chat"
        }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class AmbientListeningViewModel {
    var isListening = false
    var isAnalyzing = false
    var currentTranscript = ""
    var suggestions: [AmbientSuggestion] = []
    var showTranscriptPanel = false
    var error: String?

    private let webSocket: WebSocketClient
    private let listeningManager = AmbientListeningManager()

    init(webSocket: WebSocketClient) {
        self.webSocket = webSocket

        listeningManager.onTranscriptReady = { [weak self] text, duration, sessionCount in
            Task { @MainActor in
                self?.sendForAnalysis(text, duration: duration, sessionCount: sessionCount)
            }
        }
    }

    // MARK: - Public Actions

    func toggleListening() {
        if isListening {
            listeningManager.stopListening()
            isListening = false
            currentTranscript = ""
        } else {
            listeningManager.startListening()
            isListening = true
            error = nil
        }
    }

    func approveSuggestion(_ suggestion: AmbientSuggestion) {
        guard let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
        suggestions[index].status = .approving

        let msg = WSMessage(
            type: WSMessageType.ambientActionApprove,
            id: suggestion.id,
            metadata: [
                "type": .string(suggestion.type.rawValue),
                "title": .string(suggestion.title),
                "description": .string(suggestion.description),
                "actionPayload": .string(suggestion.actionPayload)
            ]
        )
        webSocket.send(msg)
    }

    func dismissSuggestion(_ suggestion: AmbientSuggestion) {
        suggestions.removeAll { $0.id == suggestion.id }
    }

    func clearAll() {
        suggestions.removeAll()
    }

    // MARK: - WS Message Handling

    func handleMessage(_ message: WSMessage) {
        switch message.type {
        case WSMessageType.ambientAnalyzing:
            isAnalyzing = true

        case WSMessageType.ambientSuggestions:
            isAnalyzing = false
            parseSuggestions(from: message)

        case WSMessageType.ambientActionResult:
            handleActionResult(message)

        default:
            break
        }
    }

    // MARK: - Private

    private func sendForAnalysis(_ text: String, duration: Int, sessionCount: Int) {
        guard !text.isEmpty else { return }
        isAnalyzing = true

        let msg = WSMessage(
            type: WSMessageType.ambientAnalyze,
            content: text,
            metadata: [
                "duration": .int(duration),
                "sessionCount": .int(sessionCount)
            ]
        )
        webSocket.send(msg)
    }

    private func parseSuggestions(from message: WSMessage) {
        guard let meta = message.metadata,
              case .array(let items) = meta["suggestions"] else {
            return
        }

        for item in items {
            guard case .object(let dict) = item,
                  let id = dict["id"]?.stringValue,
                  let typeStr = dict["type"]?.stringValue,
                  let type = AmbientSuggestion.SuggestionType(rawValue: typeStr),
                  let title = dict["title"]?.stringValue,
                  let description = dict["description"]?.stringValue else {
                continue
            }

            let payload = dict["actionPayload"]?.stringValue ?? ""
            let confidence: Double
            if let d = dict["confidence"]?.doubleValue {
                confidence = d
            } else if let i = dict["confidence"]?.intValue {
                confidence = Double(i)
            } else {
                confidence = 0.5
            }

            let suggestion = AmbientSuggestion(
                id: id,
                type: type,
                title: title,
                description: description,
                actionPayload: payload,
                confidence: confidence
            )
            suggestions.insert(suggestion, at: 0)
        }
    }

    private func handleActionResult(_ message: WSMessage) {
        guard let id = message.id,
              let index = suggestions.firstIndex(where: { $0.id == id }) else {
            return
        }

        let success = message.metadata?["success"]?.boolValue ?? false
        if success {
            suggestions[index].status = .completed
            // Remove after a delay
            let suggestionId = id
            Task {
                try? await Task.sleep(for: .seconds(2))
                suggestions.removeAll { $0.id == suggestionId }
            }
        } else {
            suggestions[index].status = .pending
            error = message.metadata?["error"]?.stringValue
        }
    }
}
