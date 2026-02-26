import Foundation

// MARK: - Request Types

struct ClaudeRequest: Codable, Sendable {
    let model: String
    let max_tokens: Int
    let messages: [MessageParam]
    let system: String?
    let stream: Bool
    let tools: [ToolDefinition]?
    let thinking: ThinkingConfig?

    init(
        model: String,
        max_tokens: Int,
        messages: [MessageParam],
        system: String? = nil,
        stream: Bool = true,
        tools: [ToolDefinition]? = nil,
        thinking: ThinkingConfig? = nil
    ) {
        self.model = model
        self.max_tokens = max_tokens
        self.messages = messages
        self.system = system
        self.stream = stream
        self.tools = tools
        self.thinking = thinking
    }
}

struct ThinkingConfig: Codable, Sendable {
    let type: String
    let budget_tokens: Int

    init(budget_tokens: Int = 10000) {
        self.type = "enabled"
        self.budget_tokens = budget_tokens
    }
}

struct MessageParam: Codable, Sendable {
    let role: String
    let content: [ContentBlock]

    init(role: String, content: [ContentBlock]) {
        self.role = role
        self.content = content
    }

    init(role: String, text: String) {
        self.role = role
        self.content = [.text(TextContent(text: text))]
    }
}

// MARK: - Content Blocks

enum ContentBlock: Codable, Sendable {
    case text(TextContent)
    case thinking(ThinkingContent)
    case toolUse(ToolUseContent)
    case toolResult(ToolResultContent)

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let singleContainer = try decoder.singleValueContainer()
        switch type {
        case "text":
            self = .text(try singleContainer.decode(TextContent.self))
        case "thinking":
            self = .thinking(try singleContainer.decode(ThinkingContent.self))
        case "tool_use":
            self = .toolUse(try singleContainer.decode(ToolUseContent.self))
        case "tool_result":
            self = .toolResult(try singleContainer.decode(ToolResultContent.self))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown content block type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let content):
            try content.encode(to: encoder)
        case .thinking(let content):
            try content.encode(to: encoder)
        case .toolUse(let content):
            try content.encode(to: encoder)
        case .toolResult(let content):
            try content.encode(to: encoder)
        }
    }
}

struct TextContent: Codable, Sendable {
    let type: String
    let text: String

    init(text: String) {
        self.type = "text"
        self.text = text
    }
}

struct ThinkingContent: Codable, Sendable {
    let type: String
    let thinking: String

    init(thinking: String) {
        self.type = "thinking"
        self.thinking = thinking
    }
}

struct ToolUseContent: Codable, Sendable {
    let type: String
    let id: String
    let name: String
    let input: JSONValue

    init(id: String, name: String, input: JSONValue) {
        self.type = "tool_use"
        self.id = id
        self.name = name
        self.input = input
    }
}

struct ToolResultContent: Codable, Sendable {
    let type: String
    let tool_use_id: String
    let content: String
    let is_error: Bool?

    init(tool_use_id: String, content: String, is_error: Bool? = nil) {
        self.type = "tool_result"
        self.tool_use_id = tool_use_id
        self.content = content
        self.is_error = is_error
    }
}

// MARK: - A generic JSON value for tool inputs/schemas

enum JSONValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? container.decode([String: JSONValue].self) { self = .object(v) }
        else if container.decodeNil() { self = .null }
        else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    /// Convert to a JSON-serializable dictionary/value for embedding in strings
    func toAny() -> Any {
        switch self {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .array(let v): return v.map { $0.toAny() }
        case .object(let v): return v.mapValues { $0.toAny() }
        case .null: return NSNull()
        }
    }

    /// Convert to a JSON string
    func toJSONString() -> String {
        do {
            let data = try JSONEncoder().encode(self)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }
}

// MARK: - Tool Definition

struct ToolDefinition: Codable, Sendable {
    let name: String
    let description: String
    let input_schema: JSONValue
}

// MARK: - SSE Stream Event Types

enum ClaudeStreamEventType: String, Sendable {
    case messageStart = "message_start"
    case contentBlockStart = "content_block_start"
    case contentBlockDelta = "content_block_delta"
    case contentBlockStop = "content_block_stop"
    case messageDelta = "message_delta"
    case messageStop = "message_stop"
    case ping = "ping"
    case error = "error"
}

// MARK: - SSE Event Payloads

struct SSEMessageStart: Codable, Sendable {
    let type: String
    let message: SSEMessage
}

struct SSEMessage: Codable, Sendable {
    let id: String
    let type: String
    let role: String
    let model: String
    let usage: SSEUsage?
}

struct SSEUsage: Codable, Sendable {
    let input_tokens: Int?
    let output_tokens: Int?
}

struct SSEContentBlockStart: Codable, Sendable {
    let type: String
    let index: Int
    let content_block: SSEContentBlock
}

struct SSEContentBlock: Codable, Sendable {
    let type: String
    let text: String?
    let id: String?      // for tool_use
    let name: String?    // for tool_use
    let thinking: String? // for thinking
}

struct SSEContentBlockDelta: Codable, Sendable {
    let type: String
    let index: Int
    let delta: SSEDelta
}

struct SSEDelta: Codable, Sendable {
    let type: String
    let text: String?          // for text_delta
    let thinking: String?      // for thinking_delta
    let partial_json: String?  // for input_json_delta
}

struct SSEContentBlockStop: Codable, Sendable {
    let type: String
    let index: Int
}

struct SSEMessageDelta: Codable, Sendable {
    let type: String
    let delta: SSEMessageDeltaPayload
    let usage: SSEUsage?
}

struct SSEMessageDeltaPayload: Codable, Sendable {
    let stop_reason: String?
    let stop_sequence: String?
}

struct SSEError: Codable, Sendable {
    let type: String
    let error: SSEErrorDetail
}

struct SSEErrorDetail: Codable, Sendable {
    let type: String
    let message: String
}
