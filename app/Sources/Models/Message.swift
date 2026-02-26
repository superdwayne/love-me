import Foundation
import Observation

@Observable
final class Message: Identifiable, @unchecked Sendable {
    let id: String
    let role: MessageRole
    var content: String
    var thinkingContent: String?
    var thinkingDuration: Double?
    var isStreaming: Bool
    var isThinkingStreaming: Bool
    var toolCalls: [ToolCall]
    var sendFailed: Bool
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String = "",
        thinkingContent: String? = nil,
        thinkingDuration: Double? = nil,
        isStreaming: Bool = false,
        isThinkingStreaming: Bool = false,
        toolCalls: [ToolCall] = [],
        sendFailed: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.thinkingDuration = thinkingDuration
        self.isStreaming = isStreaming
        self.isThinkingStreaming = isThinkingStreaming
        self.toolCalls = toolCalls
        self.sendFailed = sendFailed
        self.timestamp = timestamp
    }

    enum MessageRole: String, Codable, Sendable {
        case user
        case assistant
    }
}

struct ToolCall: Identifiable, Sendable {
    let id: String
    let toolName: String
    let serverName: String
    var input: String?
    var result: String?
    var error: String?
    var status: ToolStatus
    var duration: Double?

    enum ToolStatus: Sendable {
        case running
        case success
        case error
    }

    init(
        id: String = UUID().uuidString,
        toolName: String,
        serverName: String,
        input: String? = nil,
        result: String? = nil,
        error: String? = nil,
        status: ToolStatus = .running,
        duration: Double? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.serverName = serverName
        self.input = input
        self.result = result
        self.error = error
        self.status = status
        self.duration = duration
    }
}
