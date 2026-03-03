import Foundation

/// Stored conversation data
struct StoredConversation: Codable, Sendable {
    let id: String
    var title: String
    let created: Date
    var messages: [StoredMessage]
    var sourceType: String?  // "email" for email conversations, nil for chat

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
    let sourceType: String?
}

/// Persistence layer for conversations
actor ConversationStore {
    private let maxMessagesInMemory = 200
    private let llmContextBudget = 50

    private let directory: String
    private let generatedImagesDirectory: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: String, generatedImagesDirectory: String? = nil) {
        self.directory = directory
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        self.generatedImagesDirectory = generatedImagesDirectory ?? "\(homeDir)/.solace/generated"

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    /// Create a new conversation
    func create(title: String? = nil, sourceType: String? = nil) throws -> StoredConversation {
        let conversation = StoredConversation(
            id: UUID().uuidString,
            title: title ?? "New Conversation",
            created: Date(),
            messages: [],
            sourceType: sourceType
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
            let sourceType = message.metadata?["sourceType"]
            conversation = StoredConversation(
                id: conversationId,
                title: "New Conversation",
                created: Date(),
                messages: [],
                sourceType: sourceType
            )
        }

        // Auto-generate title from first user message
        if conversation.messages.isEmpty && message.role == "user" {
            let titleText = String(message.content.prefix(50))
            conversation.title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        conversation.messages.append(message)
        // Always save the full conversation to disk first
        try save(conversation)

        // Trim in-memory messages if over the limit
        if conversation.messages.count > maxMessagesInMemory {
            let oldCount = conversation.messages.count
            conversation.messages = Array(conversation.messages.suffix(maxMessagesInMemory))
            Logger.info("Trimmed conversation \(conversationId) from \(oldCount) to \(conversation.messages.count) messages")
        }

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
                    messageCount: conv.messageCount,
                    sourceType: conv.sourceType
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

        // Apply LLM context budget: take last N messages, but ensure tool pairs stay intact
        let budgetMessages: [StoredMessage]
        if conversation.messages.count > llmContextBudget {
            var sliced = Array(conversation.messages.suffix(llmContextBudget))

            // If the first message in our slice is a tool_result, we need its matching tool_use.
            // Walk backward from the cut point to include any orphaned tool_use messages.
            while let first = sliced.first,
                  first.role == "tool_result",
                  let toolId = first.metadata?["toolId"] {
                // Find the matching tool_use in the full history before our slice starts
                let cutIndex = conversation.messages.count - sliced.count
                if cutIndex > 0,
                   let matchIndex = conversation.messages[0..<cutIndex].lastIndex(where: {
                       $0.role == "tool_use" && $0.metadata?["toolId"] == toolId
                   }) {
                    // Prepend everything from the matched tool_use to the cut point
                    let prefix = Array(conversation.messages[matchIndex..<cutIndex])
                    sliced = prefix + sliced
                } else {
                    break
                }
            }

            budgetMessages = sliced
        } else {
            budgetMessages = conversation.messages
        }

        // First pass: collect tool_use IDs and tool_result IDs to detect orphans
        var toolUseIds: Set<String> = []
        var toolResultIds: Set<String> = []
        for msg in budgetMessages {
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

        for msg in budgetMessages {
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
                // Check for attachments (images and audio) saved as files
                if let attachmentFiles = msg.metadata?["attachmentFiles"], !attachmentFiles.isEmpty {
                    // Build multi-content block: media first, then text
                    var blocks: [ContentBlock] = []
                    let filenames = attachmentFiles.split(separator: ",").map(String.init)
                    for filename in filenames {
                        let filePath = "\(generatedImagesDirectory)/\(filename)"
                        if let fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
                            let base64 = fileData.base64EncodedString()
                            let ext = (filename as NSString).pathExtension.lowercased()

                            if AttachmentFileHelper.isAudioFile(filename) {
                                // Audio attachment
                                let mediaType: String
                                switch ext {
                                case "m4a": mediaType = "audio/m4a"
                                case "mp3": mediaType = "audio/mp3"
                                case "wav": mediaType = "audio/wav"
                                case "ogg": mediaType = "audio/ogg"
                                case "webm": mediaType = "audio/webm"
                                default: mediaType = "audio/m4a"
                                }
                                blocks.append(.audio(AudioContent(source: AudioSource(mediaType: mediaType, data: base64))))
                            } else {
                                // Image attachment
                                let mediaType: String
                                switch ext {
                                case "jpg", "jpeg": mediaType = "image/jpeg"
                                case "gif": mediaType = "image/gif"
                                case "webp": mediaType = "image/webp"
                                default: mediaType = "image/png"
                                }
                                blocks.append(.image(ImageContent(source: ImageSource(mediaType: mediaType, data: base64))))
                            }
                        }
                    }
                    if !msg.content.isEmpty {
                        blocks.append(.text(TextContent(text: msg.content)))
                    }
                    // Handle multi-block user message by appending all blocks
                    if apiRole != currentRole {
                        if let role = currentRole, !currentBlocks.isEmpty {
                            apiMessages.append(MessageParam(role: role, content: currentBlocks))
                        }
                        currentRole = apiRole
                        currentBlocks = blocks
                    } else {
                        currentBlocks.append(contentsOf: blocks)
                    }
                    continue
                }
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
