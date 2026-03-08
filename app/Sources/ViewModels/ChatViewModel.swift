import Foundation
import Observation
import SwiftUI

struct PendingAttachment: Identifiable {
    let id: String
    var data: Data
    var mimeType: String
    var fileName: String
    var thumbnail: UIImage?
    var isLoading: Bool
    var audioDuration: TimeInterval?

    var isAudio: Bool {
        mimeType.hasPrefix("audio/")
    }

    init(id: String = UUID().uuidString, data: Data, mimeType: String, fileName: String, thumbnail: UIImage? = nil, isLoading: Bool = false, audioDuration: TimeInterval? = nil) {
        self.id = id
        self.data = data
        self.mimeType = mimeType
        self.fileName = fileName
        self.thumbnail = thumbnail
        self.isLoading = isLoading
        self.audioDuration = audioDuration
    }
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

    // Search state
    var isSearchActive: Bool = false
    var searchQuery: String = ""
    var searchMatches: [(messageId: String, range: Range<String.Index>)] = []
    var currentMatchIndex: Int = 0

    var currentMatchMessageId: String? {
        guard !searchMatches.isEmpty, currentMatchIndex < searchMatches.count else { return nil }
        return searchMatches[currentMatchIndex].messageId
    }

    // Editing state
    var editingMessageId: String?
    var editingText: String = ""

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

    func addVoiceNote(data: Data, duration: TimeInterval) {
        let fileName = "voice_\(UUID().uuidString.prefix(8)).m4a"
        let pending = PendingAttachment(
            data: data,
            mimeType: "audio/m4a",
            fileName: fileName,
            audioDuration: duration
        )
        pendingAttachments.append(pending)
    }

    func removeAttachment(_ attachment: PendingAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    /// Add a placeholder attachment that shows a loading indicator while compression runs.
    func addLoadingPlaceholder(id: String, fileName: String) {
        let placeholder = PendingAttachment(
            id: id,
            data: Data(),
            mimeType: "image/jpeg",
            fileName: fileName,
            isLoading: true
        )
        pendingAttachments.append(placeholder)
    }

    /// Replace a loading placeholder with compressed data. Removes the placeholder if not found.
    func finalizeAttachment(id: String, data: Data, mimeType: String, fileName: String) {
        guard let index = pendingAttachments.firstIndex(where: { $0.id == id }) else { return }
        pendingAttachments[index].data = data
        pendingAttachments[index].mimeType = mimeType
        pendingAttachments[index].fileName = fileName
        pendingAttachments[index].thumbnail = UIImage(data: data)
        pendingAttachments[index].isLoading = false
    }

    /// Whether any attachment is still being compressed.
    var hasLoadingAttachments: Bool {
        pendingAttachments.contains { $0.isLoading }
    }

    func quoteReply(_ message: Message) {
        replyingToMessage = message
    }

    func clearReply() {
        replyingToMessage = nil
    }

    // MARK: - Search

    func toggleSearch() {
        isSearchActive.toggle()
        if !isSearchActive {
            searchQuery = ""
            searchMatches = []
            currentMatchIndex = 0
        }
    }

    func updateSearchResults() {
        guard !searchQuery.isEmpty else {
            searchMatches = []
            currentMatchIndex = 0
            return
        }

        let query = searchQuery.lowercased()
        var matches: [(messageId: String, range: Range<String.Index>)] = []

        for message in messages {
            let content = message.content.lowercased()
            var searchStart = content.startIndex
            while let range = content.range(of: query, range: searchStart..<content.endIndex) {
                matches.append((messageId: message.id, range: range))
                searchStart = range.upperBound
            }
        }

        searchMatches = matches
        currentMatchIndex = matches.isEmpty ? 0 : max(0, matches.count - 1)
    }

    func nextMatch() {
        guard !searchMatches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % searchMatches.count
    }

    func previousMatch() {
        guard !searchMatches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + searchMatches.count) % searchMatches.count
    }

    // MARK: - Editing

    func startEditing(_ message: Message) {
        editingMessageId = message.id
        editingText = message.content
    }

    func cancelEditing() {
        editingMessageId = nil
        editingText = ""
    }

    func saveEdit() {
        guard let editingId = editingMessageId,
              let message = messages.first(where: { $0.id == editingId }) else { return }

        let originalContent = message.content
        let newContent = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newContent.isEmpty, newContent != originalContent else {
            cancelEditing()
            return
        }

        // Optimistically update local state
        message.content = newContent
        message.isEdited = true

        // Remove all messages after the edited one
        if let index = messages.firstIndex(where: { $0.id == editingId }) {
            messages.removeSubrange((index + 1)...)
        }

        // Send edit to daemon
        let wsMsg = WSMessage(
            type: WSMessageType.editMessage,
            conversationId: currentConversationId,
            content: newContent,
            metadata: ["originalContent": .string(originalContent)]
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

        cancelEditing()
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
                thumbnailData: pending.data,
                audioDuration: pending.audioDuration
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
                var obj: [String: MetadataValue] = [
                    "data": .string(pending.data.base64EncodedString()),
                    "mimeType": .string(pending.mimeType),
                    "fileName": .string(pending.fileName)
                ]
                if let duration = pending.audioDuration {
                    obj["audioDuration"] = .double(duration)
                }
                return .object(obj)
            }
            metadata = ["attachments": .array(attachmentValues)]
        }

        let wsMsg = WSMessage(
            type: WSMessageType.userMessage,
            conversationId: currentConversationId,
            content: text.isEmpty ? " " : text,
            metadata: metadata
        )

        guard webSocket.send(wsMsg) else {
            // Send failed — mark the user message as failed so they can retry
            userMessage.sendFailed = true
            HapticManager.toolError()
            return
        }

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

        let wsMsg = WSMessage(
            type: WSMessageType.userMessage,
            conversationId: currentConversationId,
            content: message.content
        )

        guard webSocket.send(wsMsg) else {
            HapticManager.toolError()
            return
        }

        message.sendFailed = false
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

    /// Called when WebSocket connection drops. Resets streaming state so UI isn't stuck.
    func handleConnectionLost() {
        guard isStreaming else { return }
        isStreaming = false
        // Mark the last assistant message as failed
        if let lastAssistant = messages.last(where: { $0.role == .assistant && $0.isStreaming }) {
            lastAssistant.isStreaming = false
            if lastAssistant.content.isEmpty {
                lastAssistant.content = "Connection lost — tap to retry"
            }
        }
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

        case WSMessageType.toolCallFailed:
            handleToolCallFailed(msg)

        case WSMessageType.modelLoading:
            handleModelLoading(msg)

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

        case WSMessageType.messageEdited:
            // Server confirmed the edit, nothing extra needed since we optimistically updated
            break

        default:
            break
        }
    }

    // MARK: - Private Handlers

    private var currentAssistantMessage: Message? {
        messages.last { $0.role == .assistant }
    }

    private func handleModelLoading(_ msg: WSMessage) {
        if let assistant = currentAssistantMessage {
            assistant.loadingStatus = msg.content ?? "Loading model…"
        }
    }

    private func handleAssistantChunk(_ msg: WSMessage) {
        guard let content = msg.content else { return }
        if let assistant = currentAssistantMessage {
            // Clear loading status on first real content
            if assistant.loadingStatus != nil {
                assistant.loadingStatus = nil
            }
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

    private func handleToolCallFailed(_ msg: WSMessage) {
        let reason = msg.metadata?["reason"]?.stringValue ?? "Unknown error"
        let toolName = msg.metadata?["toolName"]?.stringValue

        // Display as a system-like warning in the current assistant message
        let failureText: String
        if let toolName = toolName {
            failureText = "\n\n⚠ Tool call failed (\(toolName)): \(reason)"
        } else {
            failureText = "\n\n⚠ Tool call failed: \(reason)"
        }

        if let assistant = currentAssistantMessage {
            assistant.content += failureText
        }

        HapticManager.toolError()
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
                attachments = filenames.compactMap { filename in
                    let url = "http://\(host):9201/images/\(filename)"
                    let ext = (filename as NSString).pathExtension.lowercased()
                    let audioExts = ["m4a", "mp3", "wav", "ogg", "webm"]
                    if audioExts.contains(ext) {
                        let mimeType = "audio/\(ext)"
                        // For audio, we need to load data from the server for playback
                        return MessageAttachment(
                            fileName: filename,
                            mimeType: mimeType,
                            imageURL: url
                        )
                    } else {
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
