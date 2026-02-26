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
    // Client -> Server
    static let userMessage = "user_message"
    static let newConversation = "new_conversation"
    static let loadConversation = "load_conversation"
    static let deleteConversation = "delete_conversation"
    static let listConversations = "list_conversations"
    static let ping = "ping"

    // Server -> Client
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

    // Client -> Server (Workflows)
    static let createWorkflow = "create_workflow"
    static let updateWorkflow = "update_workflow"
    static let deleteWorkflow = "delete_workflow"
    static let listWorkflows = "list_workflows"
    static let getWorkflow = "get_workflow"
    static let runWorkflow = "run_workflow"
    static let cancelWorkflow = "cancel_workflow"
    static let listExecutions = "list_executions"
    static let getExecution = "get_execution"

    // Server -> Client (Workflows)
    static let workflowCreated = "workflow_created"
    static let workflowUpdated = "workflow_updated"
    static let workflowDeleted = "workflow_deleted"
    static let workflowList = "workflow_list"
    static let workflowDetail = "workflow_detail"
    static let workflowExecutionStarted = "workflow_execution_started"
    static let workflowStepUpdate = "workflow_step_update"
    static let workflowExecutionDone = "workflow_execution_done"
    static let executionList = "execution_list"
    static let executionDetail = "execution_detail"
    static let workflowNotification = "workflow_notification"

    // Client -> Server (Visual Builder)
    static let mcpToolsList = "mcp_tools_list"
    static let parseSchedule = "parse_schedule"
    static let buildWorkflow = "build_workflow"

    // Server -> Client (Visual Builder)
    static let mcpToolsListResult = "mcp_tools_list_result"
    static let parseScheduleResult = "parse_schedule_result"
    static let buildWorkflowResult = "build_workflow_result"
}
