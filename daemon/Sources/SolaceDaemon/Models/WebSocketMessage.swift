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
    static let cancelGeneration = "cancel_generation"
    static let editMessage = "edit_message"

    // Server -> Client
    static let assistantChunk = "assistant_chunk"
    static let assistantDone = "assistant_done"
    static let thinkingChunk = "thinking_chunk"
    static let thinkingDone = "thinking_done"
    static let toolCallStart = "tool_call_start"
    static let toolCallDone = "tool_call_done"
    static let toolCallFailed = "tool_call_failed"
    static let error = "error"
    static let status = "status"
    static let modelLoading = "model_loading"
    static let pong = "pong"
    static let conversationList = "conversation_list"
    static let conversationLoaded = "conversation_loaded"
    static let conversationCreated = "conversation_created"
    static let conversationDeleted = "conversation_deleted"
    static let messageEdited = "message_edited"

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

    // Client -> Server (MCP Server Management)
    static let mcpServersList = "mcp_servers_list"
    static let mcpServerToggle = "mcp_server_toggle"
    static let mcpServerAdd = "mcp_server_add"
    static let mcpServerDelete = "mcp_server_delete"

    // Server -> Client (MCP Server Management)
    static let mcpServersListResult = "mcp_servers_list_result"
    static let mcpServerToggleResult = "mcp_server_toggle_result"
    static let mcpServerAddResult = "mcp_server_add_result"
    static let mcpServerDeleteResult = "mcp_server_delete_result"

    // Client -> Server (Ollama Tool Server Management)
    static let ollamaServerToggle = "ollama_server_toggle"
    static let ollamaToolsList = "ollama_tools_list"
    static let ollamaPinnedToolsSet = "ollama_pinned_tools_set"

    // Server -> Client (Ollama Tool Server Management)
    static let ollamaServerToggleResult = "ollama_server_toggle_result"
    static let ollamaToolsListResult = "ollama_tools_list_result"
    static let ollamaPinnedToolsResult = "ollama_pinned_tools_result"

    // Client -> Server (Email / Agent Mail)
    static let emailStatus = "email_status"
    static let emailConnect = "email_connect"
    static let emailAuthDisconnect = "email_auth_disconnect"
    static let emailPollNow = "email_poll_now"
    static let emailUpdatePolling = "email_update_polling"
    static let emailMessagesList = "email_messages_list"
    static let emailTriggersList = "email_triggers_list"
    static let emailTriggerCreate = "email_trigger_create"
    static let emailTriggerUpdate = "email_trigger_update"
    static let emailTriggerDelete = "email_trigger_delete"

    // Server -> Client (Email / Agent Mail)
    static let emailStatusResult = "email_status_result"
    static let emailConnected = "email_connected"
    static let emailAuthDisconnected = "email_auth_disconnected"
    static let emailMessagesListResult = "email_messages_list_result"
    static let emailBriefWorkflowCreated = "email_brief_workflow_created"
    static let emailTriggersListResult = "email_triggers_list_result"
    static let emailTriggerCreated = "email_trigger_created"
    static let emailTriggerUpdated = "email_trigger_updated"
    static let emailTriggerDeleted = "email_trigger_deleted"
    static let emailPollResult = "email_poll_result"
    static let emailReceived = "email_received"

    // Client -> Server (Email Detail / Actions)
    static let emailGetDetail = "email_get_detail"
    static let emailReply = "email_reply"
    static let emailArchive = "email_archive"
    static let emailDelete = "email_delete"

    // Server -> Client (Email Detail / Actions)
    static let emailDetailResult = "email_detail_result"
    static let emailReplyResult = "email_reply_result"
    static let emailActionResult = "email_action_result"

    // Client -> Server (Email Approval)
    static let emailApprovalApprove = "email_approval_approve"
    static let emailApprovalDismiss = "email_approval_dismiss"
    static let emailApprovalsList = "email_approvals_list"

    // Server -> Client (Email Approval)
    static let emailApprovalPending = "email_approval_pending"
    static let emailApprovalUpdated = "email_approval_updated"
    static let emailApprovalsListResult = "email_approvals_list_result"
    static let emailAutoReplyStatus = "email_auto_reply_status"

    // Client -> Server (Provider Management)
    static let getProviders = "get_providers"
    static let setProvider = "set_provider"
    static let getOllamaModels = "get_ollama_models"

    // Server -> Client (Provider Management)
    static let providersStatus = "providers_status"
    static let providerUpdated = "provider_updated"
    static let ollamaModelsList = "ollama_models_list"

    // Client -> Server (Health)
    static let getHealth = "get_health"

    // Server -> Client (Health)
    static let healthResult = "health_result"

    // Client -> Server (Usage)
    static let usageStatus = "usage_status"

    // Server -> Client (Usage)
    static let usageStatusResult = "usage_status_result"

    // Client -> Server (Ambient Listening)
    static let ambientAnalyze = "ambient_analyze"
    static let ambientActionApprove = "ambient_action_approve"

    // Server -> Client (Ambient Listening)
    static let ambientAnalyzing = "ambient_analyzing"
    static let ambientSuggestions = "ambient_suggestions"
    static let ambientActionResult = "ambient_action_result"

    // Client -> Server (Agent Plans)
    static let planApprove = "plan_approve"
    static let planReject = "plan_reject"
    static let planEdit = "plan_edit"
    static let planCancel = "plan_cancel"
    static let planList = "plan_list"
    static let planGetExecution = "plan_get_execution"

    // Server -> Client (Agent Plans)
    static let planGenerated = "plan_generated"
    static let planExecutionStarted = "plan_execution_started"
    static let agentStarted = "agent_started"
    static let agentProgress = "agent_progress"
    static let agentThinking = "agent_thinking"
    static let agentToolStart = "agent_tool_start"
    static let agentToolDone = "agent_tool_done"
    static let agentCompleted = "agent_completed"
    static let agentFailed = "agent_failed"
    static let agentSpawning = "agent_spawning"
    static let providerFallback = "provider_fallback"
    static let planExecutionDone = "plan_execution_done"
    static let planListResult = "plan_list_result"
    static let planExecutionDetail = "plan_execution_detail"
}
