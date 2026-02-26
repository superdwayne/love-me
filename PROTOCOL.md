# WebSocket Message Protocol

All messages are JSON objects with this structure:

```json
{
  "type": "<message_type>",
  "id": "<optional_message_uuid>",
  "conversationId": "<optional_conversation_uuid>",
  "content": "<string_payload>",
  "metadata": { ... }
}
```

## Message Types

### Client → Server (iOS App → Daemon)

| Type | Fields | Description |
|------|--------|-------------|
| `user_message` | `conversationId`, `content` | User sends a chat message |
| `new_conversation` | — | Request to create a new conversation |
| `load_conversation` | `conversationId` | Load a specific conversation |
| `delete_conversation` | `conversationId` | Delete a conversation |
| `list_conversations` | — | Request conversation list |
| `ping` | — | Keep-alive ping |

### Server → Client (Daemon → iOS App)

| Type | Fields | Description |
|------|--------|-------------|
| `assistant_chunk` | `conversationId`, `content` | Streamed response text token(s) |
| `assistant_done` | `conversationId`, `id` | Response streaming complete |
| `thinking_chunk` | `conversationId`, `content` | Streamed thinking text |
| `thinking_done` | `conversationId`, `metadata.thinkingDuration` | Thinking complete |
| `tool_call_start` | `conversationId`, `id`, `metadata.toolName`, `metadata.serverName`, `metadata.input` | Tool execution started |
| `tool_call_done` | `conversationId`, `id`, `metadata.toolName`, `metadata.success`, `metadata.result`, `metadata.error`, `metadata.duration` | Tool execution completed |
| `error` | `content`, `metadata.code` | Error occurred |
| `status` | `metadata.connected`, `metadata.hasApiKey`, `metadata.toolCount`, `metadata.daemonVersion` | Daemon status update |
| `pong` | — | Keep-alive response |
| `conversation_list` | `metadata.conversations` (array of {id, title, lastMessageAt, messageCount}) | Conversation list response |
| `conversation_loaded` | `conversationId`, `metadata.messages` (array of messages) | Full conversation data |
| `conversation_created` | `conversationId`, `metadata.title` | New conversation created |
| `conversation_deleted` | `conversationId` | Conversation deleted confirmation |

## Swift Model (shared between iOS and Daemon)

```swift
import Foundation

struct WSMessage: Codable, Sendable {
    let type: String
    let id: String?
    let conversationId: String?
    let content: String?
    let metadata: [String: MetadataValue]?

    init(type: String, id: String? = nil, conversationId: String? = nil,
         content: String? = nil, metadata: [String: MetadataValue]? = nil) {
        self.type = type
        self.id = id
        self.conversationId = conversationId
        self.content = content
        self.metadata = metadata
    }
}

// A simple JSON value type for metadata
enum MetadataValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([MetadataValue])
    case object([String: MetadataValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([MetadataValue].self) { self = .array(v) }
        else if let v = try? container.decode([String: MetadataValue].self) { self = .object(v) }
        else if container.decodeNil() { self = .null }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type") }
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

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }
    var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }
    var doubleValue: Double? {
        if case .double(let v) = self { return v }
        return nil
    }
    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }
}

// Convenience message type constants
enum WSMessageType {
    // Client → Server
    static let userMessage = "user_message"
    static let newConversation = "new_conversation"
    static let loadConversation = "load_conversation"
    static let deleteConversation = "delete_conversation"
    static let listConversations = "list_conversations"
    static let ping = "ping"

    // Server → Client
    static let assistantChunk = "assistant_chunk"
    static let assistantDone = "assistant_done"
    static let thinkingChunk = "thinking_chunk"
    static let thinkingDone = "thinking_done"
    static let toolCallStart = "tool_call_start"
    static let toolCallDone = "tool_call_done"
    static let error = "error"
    static let status = "status"
    static let pong = "pong"
    static let conversationList = "conversation_list"
    static let conversationLoaded = "conversation_loaded"
    static let conversationCreated = "conversation_created"
    static let conversationDeleted = "conversation_deleted"
}
```

## Connection Flow

1. iOS app connects to `ws://<host>:<port>` (default port 9200)
2. Daemon sends `status` message with capabilities
3. iOS app sends `list_conversations` to populate sidebar
4. User sends `user_message` → daemon streams back `thinking_chunk`*, `thinking_done`*, `tool_call_start`*, `tool_call_done`*, `assistant_chunk`+, `assistant_done`
5. Ping/pong every 30 seconds for keep-alive

## Auto-Reconnect

iOS app implements exponential backoff: 1s, 2s, 4s, 8s, 16s, max 30s. Reset backoff on successful connection.
