import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class ChatViewModel {
    var messages: [Message] = []
    var inputText: String = ""
    var isStreaming: Bool = false
    var currentConversationId: String?
    var errorMessage: String?

    private let webSocket: WebSocketClient

    init(webSocket: WebSocketClient) {
        self.webSocket = webSocket
    }

    // MARK: - Public Actions

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isStreaming else { return }

        let userMessage = Message(
            role: .user,
            content: text,
            timestamp: Date()
        )
        messages.append(userMessage)
        inputText = ""

        HapticManager.messageSent()

        // Auto-create conversation ID if none exists
        if currentConversationId == nil {
            currentConversationId = UUID().uuidString
        }

        // Send to daemon
        let wsMsg = WSMessage(
            type: WSMessageType.userMessage,
            conversationId: currentConversationId,
            content: text
        )
        webSocket.send(wsMsg)

        // Prepare for streaming response
        isStreaming = true
        let assistantMessage = Message(
            role: .assistant,
            isStreaming: true,
            timestamp: Date()
        )
        messages.append(assistantMessage)
    }

    func retryMessage(_ message: Message) {
        guard message.role == .user, message.sendFailed else { return }

        message.sendFailed = false

        let wsMsg = WSMessage(
            type: WSMessageType.userMessage,
            conversationId: currentConversationId,
            content: message.content
        )
        webSocket.send(wsMsg)

        isStreaming = true
        let assistantMessage = Message(
            role: .assistant,
            isStreaming: true,
            timestamp: Date()
        )
        messages.append(assistantMessage)
    }

    func deleteMessage(_ message: Message) {
        messages.removeAll { $0.id == message.id }
    }

    func loadConversation(_ id: String) {
        currentConversationId = id
        messages = []
        isStreaming = false

        let wsMsg = WSMessage(
            type: WSMessageType.loadConversation,
            conversationId: id
        )
        webSocket.send(wsMsg)
    }

    func newConversation() {
        currentConversationId = UUID().uuidString
        messages = []
        isStreaming = false
    }

    func copyMessageContent(_ message: Message) {
        UIPasteboard.general.string = message.content
    }

    // MARK: - Message Handling

    func handleMessage(_ msg: WSMessage) {
        switch msg.type {
        case WSMessageType.assistantChunk:
            handleAssistantChunk(msg)

        case WSMessageType.assistantDone:
            handleAssistantDone(msg)

        case WSMessageType.thinkingChunk:
            handleThinkingChunk(msg)

        case WSMessageType.thinkingDone:
            handleThinkingDone(msg)

        case WSMessageType.toolCallStart:
            handleToolCallStart(msg)

        case WSMessageType.toolCallDone:
            handleToolCallDone(msg)

        case WSMessageType.error:
            handleError(msg)

        case WSMessageType.conversationCreated:
            if let convId = msg.conversationId {
                currentConversationId = convId
            }

        case WSMessageType.conversationLoaded:
            handleConversationLoaded(msg)

        default:
            break
        }
    }

    // MARK: - Private Handlers

    private var currentAssistantMessage: Message? {
        messages.last { $0.role == .assistant }
    }

    private func handleAssistantChunk(_ msg: WSMessage) {
        guard let content = msg.content else { return }
        if let assistant = currentAssistantMessage {
            assistant.content += content
        }
    }

    private func handleAssistantDone(_ msg: WSMessage) {
        if let assistant = currentAssistantMessage {
            assistant.isStreaming = false
        }
        isStreaming = false

        if let convId = msg.conversationId {
            currentConversationId = convId
        }
    }

    private func handleThinkingChunk(_ msg: WSMessage) {
        guard let content = msg.content else { return }
        if let assistant = currentAssistantMessage {
            if assistant.thinkingContent == nil {
                assistant.thinkingContent = ""
                assistant.isThinkingStreaming = true
            }
            assistant.thinkingContent?.append(content)
        }
    }

    private func handleThinkingDone(_ msg: WSMessage) {
        if let assistant = currentAssistantMessage {
            assistant.isThinkingStreaming = false
            if let duration = msg.metadata?["thinkingDuration"]?.doubleValue {
                assistant.thinkingDuration = duration
            }
        }
    }

    private func handleToolCallStart(_ msg: WSMessage) {
        guard let toolId = msg.id else { return }
        let toolName = msg.metadata?["toolName"]?.stringValue ?? "Unknown Tool"
        let serverName = msg.metadata?["serverName"]?.stringValue ?? ""
        let input = msg.metadata?["input"]?.stringValue

        let toolCall = ToolCall(
            id: toolId,
            toolName: toolName,
            serverName: serverName,
            input: input,
            status: .running
        )

        if let assistant = currentAssistantMessage {
            assistant.toolCalls.append(toolCall)
        }
    }

    private func handleToolCallDone(_ msg: WSMessage) {
        guard let toolId = msg.id else { return }
        guard let assistant = currentAssistantMessage else { return }

        if let index = assistant.toolCalls.firstIndex(where: { $0.id == toolId }) {
            let success = msg.metadata?["success"]?.boolValue ?? false
            assistant.toolCalls[index].status = success ? .success : .error
            assistant.toolCalls[index].result = msg.metadata?["result"]?.stringValue
            assistant.toolCalls[index].error = msg.metadata?["error"]?.stringValue
            assistant.toolCalls[index].duration = msg.metadata?["duration"]?.doubleValue

            if success {
                HapticManager.toolCompleted()
            } else {
                HapticManager.toolError()
            }
        }
    }

    private func handleError(_ msg: WSMessage) {
        errorMessage = msg.content ?? "An unknown error occurred"
        isStreaming = false

        if let assistant = currentAssistantMessage, assistant.content.isEmpty {
            assistant.content = "An error occurred: \(errorMessage ?? "Unknown")"
            assistant.isStreaming = false
        }
    }

    private func handleConversationLoaded(_ msg: WSMessage) {
        guard let convId = msg.conversationId else { return }
        currentConversationId = convId

        // Parse messages from metadata
        guard case .array(let messageValues) = msg.metadata?["messages"] else { return }

        var loadedMessages: [Message] = []
        for value in messageValues {
            guard case .object(let dict) = value else { continue }
            guard let roleStr = dict["role"]?.stringValue,
                  let role = Message.MessageRole(rawValue: roleStr),
                  let content = dict["content"]?.stringValue else { continue }

            let msgId = dict["id"]?.stringValue ?? UUID().uuidString
            let message = Message(
                id: msgId,
                role: role,
                content: content,
                timestamp: Date()
            )

            // Parse thinking content if present
            if let thinking = dict["thinkingContent"]?.stringValue {
                message.thinkingContent = thinking
                message.thinkingDuration = dict["thinkingDuration"]?.doubleValue
            }

            loadedMessages.append(message)
        }

        messages = loadedMessages
    }
}
