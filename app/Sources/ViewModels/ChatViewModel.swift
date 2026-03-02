import Foundation
import Observation
import SwiftUI

struct PendingAttachment: Identifiable {
    let id = UUID().uuidString
    let data: Data
    let mimeType: String
    let fileName: String
    let thumbnail: UIImage?
}

@Observable
@MainActor
final class ChatViewModel {
    var messages: [Message] = []
    var inputText: String = ""
    var isStreaming: Bool = false
    var currentConversationId: String?
    var errorMessage: String?
    var pendingAttachments: [PendingAttachment] = []
    var replyingToMessage: Message?

    private let webSocket: WebSocketClient

    /// The daemon host (used to rewrite localhost image URLs for network access)
    var daemonHost: String {
        UserDefaults.standard.string(forKey: "ws_host") ?? "localhost"
    }

    init(webSocket: WebSocketClient) {
        self.webSocket = webSocket
    }

    /// Rewrite a daemon image URL: replace localhost with the actual daemon host
    func daemonImageURL(from urlString: String) -> URL? {
        let rewritten = urlString.replacingOccurrences(of: "localhost", with: daemonHost)
            .replacingOccurrences(of: "127.0.0.1", with: daemonHost)
        return URL(string: rewritten)
    }

    func addAttachment(data: Data, mimeType: String, fileName: String) {
        let thumbnail = UIImage(data: data)
        let pending = PendingAttachment(
            data: data,
            mimeType: mimeType,
            fileName: fileName,
            thumbnail: thumbnail
        )
        pendingAttachments.append(pending)
    }

    func removeAttachment(_ attachment: PendingAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    func quoteReply(_ message: Message) {
        replyingToMessage = message
    }

    func clearReply() {
        replyingToMessage = nil
    }

    // MARK: - Public Actions

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !text.isEmpty || !attachments.isEmpty else { return }
        guard !isStreaming else { return }

        // Build quoted context if replying
        var fullText = text
        if let reply = replyingToMessage {
            let quoted = reply.content.prefix(200)
            fullText = "> \(quoted)\n\n\(text)"
        }

        // Build message attachments for display
        let messageAttachments = attachments.map { pending in
            MessageAttachment(
                fileName: pending.fileName,
                mimeType: pending.mimeType,
                thumbnailData: pending.data
            )
        }

        let userMessage = Message(
            role: .user,
            content: fullText,
            attachments: messageAttachments,
            timestamp: Date()
        )
        messages.append(userMessage)
        inputText = ""
        pendingAttachments = []
        replyingToMessage = nil

        HapticManager.messageSent()

        // Auto-create conversation ID if none exists
        if currentConversationId == nil {
            currentConversationId = UUID().uuidString
        }

        // Build WebSocket message with attachment data
        var metadata: [String: MetadataValue]? = nil
        if !attachments.isEmpty {
            let attachmentValues: [MetadataValue] = attachments.map { pending in
                .object([
                    "data": .string(pending.data.base64EncodedString()),
                    "mimeType": .string(pending.mimeType),
                    "fileName": .string(pending.fileName)
                ])
            }
            metadata = ["attachments": .array(attachmentValues)]
        }

        let wsMsg = WSMessage(
            type: WSMessageType.userMessage,
            conversationId: currentConversationId,
            content: text.isEmpty ? " " : text,
            metadata: metadata
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

    func cancelGeneration() {
        guard isStreaming else { return }

        let wsMsg = WSMessage(
            type: WSMessageType.cancelGeneration,
            conversationId: currentConversationId
        )
        webSocket.send(wsMsg)

        // Immediately update local state
        if let assistant = currentAssistantMessage {
            assistant.isStreaming = false
            assistant.isThinkingStreaming = false
            // Mark any running tool calls as cancelled
            for i in assistant.toolCalls.indices where assistant.toolCalls[i].status == .running {
                assistant.toolCalls[i].status = .error
                assistant.toolCalls[i].error = "Cancelled by user"
            }
            if assistant.content.isEmpty {
                assistant.content = "Generation stopped."
            }
        }
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
            // Only auto-switch to new conversation if it's NOT an email conversation
            // (email conversations are created in background and shouldn't hijack active chat)
            if let convId = msg.conversationId,
               msg.metadata?["sourceType"]?.stringValue != "email" {
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
            assistant.toolCalls[index].imageURL = msg.metadata?["imageURL"]?.stringValue

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
        let host = daemonHost
        for value in messageValues {
            guard case .object(let dict) = value else { continue }
            guard let roleStr = dict["role"]?.stringValue,
                  let role = Message.MessageRole(rawValue: roleStr),
                  let content = dict["content"]?.stringValue else { continue }

            let msgId = dict["id"]?.stringValue ?? UUID().uuidString

            // Parse attachments from metadata
            var attachments: [MessageAttachment] = []
            if case .object(let meta) = dict["metadata"],
               let filesStr = meta["attachmentFiles"]?.stringValue, !filesStr.isEmpty {
                let filenames = filesStr.split(separator: ",").map(String.init)
                attachments = filenames.map { filename in
                    let url = "http://\(host):9201/images/\(filename)"
                    let ext = (filename as NSString).pathExtension.lowercased()
                    let mimeType: String
                    switch ext {
                    case "jpg", "jpeg": mimeType = "image/jpeg"
                    case "gif": mimeType = "image/gif"
                    case "webp": mimeType = "image/webp"
                    default: mimeType = "image/png"
                    }
                    return MessageAttachment(
                        fileName: filename,
                        mimeType: mimeType,
                        imageURL: url
                    )
                }
            }

            let message = Message(
                id: msgId,
                role: role,
                content: content,
                attachments: attachments,
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
