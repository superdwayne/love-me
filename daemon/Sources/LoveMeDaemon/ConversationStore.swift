import Foundation

/// Stored conversation data
struct StoredConversation: Codable, Sendable {
    let id: String
    var title: String
    let created: Date
    var messages: [StoredMessage]

    var lastMessageAt: Date {
        messages.last?.timestamp ?? created
    }

    var messageCount: Int {
        messages.count
    }
}

struct StoredMessage: Codable, Sendable {
    let role: String      // "user", "assistant", "thinking", "tool_use", "tool_result"
    let content: String
    let timestamp: Date
    let metadata: [String: String]?

    init(role: String, content: String, timestamp: Date = Date(), metadata: [String: String]? = nil) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

/// Summary info for listing conversations
struct ConversationSummary: Sendable {
    let id: String
    let title: String
    let lastMessageAt: Date
    let messageCount: Int
}

/// Persistence layer for conversations
actor ConversationStore {
    private let directory: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: String) {
        self.directory = directory

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    /// Create a new conversation
    func create(title: String? = nil) throws -> StoredConversation {
        let conversation = StoredConversation(
            id: UUID().uuidString,
            title: title ?? "New Conversation",
            created: Date(),
            messages: []
        )
        try save(conversation)
        return conversation
    }

    /// Load a conversation by ID
    func load(id: String) throws -> StoredConversation {
        let path = filePath(for: id)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try decoder.decode(StoredConversation.self, from: data)
    }

    /// Save a conversation
    func save(_ conversation: StoredConversation) throws {
        let data = try encoder.encode(conversation)
        let path = filePath(for: conversation.id)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// Add a message to a conversation and save (auto-creates if needed)
    func addMessage(to conversationId: String, message: StoredMessage) throws -> StoredConversation {
        var conversation: StoredConversation
        do {
            conversation = try load(id: conversationId)
        } catch {
            // Auto-create conversation if it doesn't exist
            conversation = StoredConversation(
                id: conversationId,
                title: "New Conversation",
                created: Date(),
                messages: []
            )
        }

        // Auto-generate title from first user message
        if conversation.messages.isEmpty && message.role == "user" {
            let titleText = String(message.content.prefix(50))
            conversation.title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        conversation.messages.append(message)
        try save(conversation)
        return conversation
    }

    /// List all conversations sorted by last message time (newest first)
    func listAll() throws -> [ConversationSummary] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory) else {
            return []
        }

        var conversations: [ConversationSummary] = []

        for file in files where file.hasSuffix(".json") {
            let path = "\(directory)/\(file)"
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let conv = try decoder.decode(StoredConversation.self, from: data)
                conversations.append(ConversationSummary(
                    id: conv.id,
                    title: conv.title,
                    lastMessageAt: conv.lastMessageAt,
                    messageCount: conv.messageCount
                ))
            } catch {
                Logger.error("Failed to load conversation from \(file): \(error)")
            }
        }

        // Sort newest first
        conversations.sort { $0.lastMessageAt > $1.lastMessageAt }
        return conversations
    }

    /// Delete a conversation
    func delete(id: String) throws {
        let path = filePath(for: id)
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }
    }

    /// Build MessageParam array from stored conversation for Claude API
    func buildAPIMessages(conversationId: String) throws -> [MessageParam] {
        let conversation = try load(id: conversationId)

        // First pass: collect tool_use IDs and tool_result IDs to detect orphans
        var toolUseIds: Set<String> = []
        var toolResultIds: Set<String> = []
        for msg in conversation.messages {
            if msg.role == "tool_use", let toolId = msg.metadata?["toolId"] {
                toolUseIds.insert(toolId)
            } else if msg.role == "tool_result", let toolId = msg.metadata?["toolId"] {
                toolResultIds.insert(toolId)
            }
        }
        let orphanedToolIds = toolUseIds.subtracting(toolResultIds)

        // Build a sanitized message list, inserting synthetic tool_results for orphans
        var sanitized: [StoredMessage] = []
        var pendingOrphanIds: [String] = []

        for msg in conversation.messages {
            if msg.role == "tool_use", let toolId = msg.metadata?["toolId"],
               orphanedToolIds.contains(toolId) {
                // Still include the tool_use, but track it needs a synthetic result
                sanitized.append(msg)
                pendingOrphanIds.append(toolId)
                continue
            }

            // Before adding a non-tool_use message, flush any pending orphan results
            // (tool_results must follow immediately after the tool_use assistant block)
            if !pendingOrphanIds.isEmpty && msg.role != "tool_use" {
                for orphanId in pendingOrphanIds {
                    sanitized.append(StoredMessage(
                        role: "tool_result",
                        content: "Error: tool call was interrupted (client disconnected or timeout)",
                        metadata: ["toolId": orphanId, "isError": "true"]
                    ))
                }
                pendingOrphanIds.removeAll()
            }

            sanitized.append(msg)
        }

        // Flush any remaining orphans at the end
        for orphanId in pendingOrphanIds {
            sanitized.append(StoredMessage(
                role: "tool_result",
                content: "Error: tool call was interrupted (client disconnected or timeout)",
                metadata: ["toolId": orphanId, "isError": "true"]
            ))
        }

        // Second pass: group consecutive messages by API role
        var apiMessages: [MessageParam] = []
        var currentBlocks: [ContentBlock] = []
        var currentRole: String? = nil

        for msg in sanitized {
            let apiRole: String
            let block: ContentBlock

            switch msg.role {
            case "user":
                apiRole = "user"
                block = .text(TextContent(text: msg.content))
            case "assistant":
                apiRole = "assistant"
                block = .text(TextContent(text: msg.content))
            case "tool_use":
                apiRole = "assistant"
                let toolId = msg.metadata?["toolId"] ?? ""
                let toolName = msg.metadata?["toolName"] ?? ""
                let inputJSON: JSONValue
                if let inputData = msg.content.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(JSONValue.self, from: inputData) {
                    inputJSON = decoded
                } else {
                    inputJSON = .object([:])
                }
                block = .toolUse(ToolUseContent(id: toolId, name: toolName, input: inputJSON))
            case "tool_result":
                apiRole = "user"
                let toolId = msg.metadata?["toolId"] ?? ""
                let isError = msg.metadata?["isError"] == "true"
                block = .toolResult(ToolResultContent(
                    tool_use_id: toolId,
                    content: msg.content,
                    is_error: isError
                ))
            default:
                continue
            }

            if apiRole != currentRole {
                if let role = currentRole, !currentBlocks.isEmpty {
                    apiMessages.append(MessageParam(role: role, content: currentBlocks))
                }
                currentRole = apiRole
                currentBlocks = [block]
            } else {
                currentBlocks.append(block)
            }
        }

        // Flush remaining
        if let role = currentRole, !currentBlocks.isEmpty {
            apiMessages.append(MessageParam(role: role, content: currentBlocks))
        }

        return apiMessages
    }

    // MARK: - Private

    private func filePath(for id: String) -> String {
        "\(directory)/\(id).json"
    }
}
