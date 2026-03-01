import Foundation

/// Main application coordinator that wires all services together
actor DaemonApp {
    private let config: DaemonConfig
    private let server: WebSocketServer
    private let claudeClient: ClaudeAPIClient
    private let mcpManager: MCPManager
    private let conversationStore: ConversationStore
    private let skillStore: SkillStore

    // Workflow subsystem
    private let workflowStore: WorkflowStore
    private let workflowExecutor: WorkflowExecutor
    private let workflowScheduler: WorkflowScheduler
    private let notificationService: NotificationService
    private let eventBus: EventBus

    // Email subsystem
    private let emailConfigStore: EmailConfigStore
    private let emailTriggerStore: EmailTriggerStore
    private let attachmentProcessor: AttachmentProcessor
    private var agentMailClient: AgentMailClient?
    private var emailPollingService: EmailPollingService?
    private var emailConversationBridge: EmailConversationBridge?
    private var emailApprovalStore: EmailApprovalStore?

    init(config: DaemonConfig) {
        self.config = config
        self.server = WebSocketServer(port: config.port)
        self.claudeClient = ClaudeAPIClient(config: config)
        self.mcpManager = MCPManager(config: config)
        self.conversationStore = ConversationStore(directory: config.conversationsDirectory)
        self.skillStore = SkillStore(skillsDirectory: config.skillsDirectory)

        // Workflow components
        self.workflowStore = WorkflowStore(
            workflowsDirectory: config.workflowsDirectory,
            executionsDirectory: config.executionsDirectory
        )
        self.notificationService = NotificationService(server: server)
        self.eventBus = EventBus()

        // Email components
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let basePath = "\(homeDir)/.love-me"
        self.emailConfigStore = EmailConfigStore(basePath: basePath)
        self.emailTriggerStore = EmailTriggerStore(basePath: basePath)
        self.attachmentProcessor = AttachmentProcessor(basePath: basePath)

        // Executor needs mcpManager and store
        self.workflowExecutor = WorkflowExecutor(mcpManager: mcpManager, store: workflowStore)

        // Scheduler fires workflow executions
        let executor = self.workflowExecutor
        let notifService = self.notificationService

        self.workflowScheduler = WorkflowScheduler { workflow in
            let execution = await executor.execute(workflow: workflow, triggerInfo: "cron: \(workflow.trigger)")

            // Send notifications based on execution result
            switch execution.status {
            case .completed:
                await notifService.notifyWorkflowCompleted(execution: execution, prefs: workflow.notificationPrefs)
            case .failed:
                await notifService.notifyWorkflowFailed(execution: execution, prefs: workflow.notificationPrefs)
            default:
                break
            }
        }
    }

    /// Start all services
    func start() async throws {
        // Ensure directories exist
        try config.ensureDirectories()

        // Start MCP servers
        await mcpManager.startAll()
        let toolCount = await mcpManager.toolCount

        // Load agent skills
        await skillStore.loadAll()
        let skillCount = await skillStore.count

        // Wire up executor callbacks for real-time WebSocket broadcasting
        await workflowExecutor.setCallbacks(
            onStepUpdate: { [weak self] execution, stepResult in
                guard let self = self else { return }
                await self.broadcastStepUpdate(execution: execution, stepResult: stepResult)
            },
            onExecutionUpdate: { [weak self] execution in
                guard let self = self else { return }
                await self.broadcastExecutionUpdate(execution: execution)
            }
        )

        // Load and schedule enabled cron workflows
        do {
            let enabledWorkflows = try await workflowStore.getEnabled()
            await workflowScheduler.scheduleAll(enabledWorkflows)
            Logger.info("Scheduled \(enabledWorkflows.filter { if case .cron = $0.trigger { return true }; return false }.count) cron workflow(s)")

            // Subscribe event-based workflows to the event bus
            for workflow in enabledWorkflows {
                if case .event(let source, let eventType, _) = workflow.trigger {
                    let executor = self.workflowExecutor
                    let notifService = self.notificationService
                    await eventBus.subscribe(source: source, eventType: eventType, id: workflow.id) { _ in
                        let execution = await executor.execute(workflow: workflow, triggerInfo: "event: \(source):\(eventType)")
                        switch execution.status {
                        case .completed:
                            await notifService.notifyWorkflowCompleted(execution: execution, prefs: workflow.notificationPrefs)
                        case .failed:
                            await notifService.notifyWorkflowFailed(execution: execution, prefs: workflow.notificationPrefs)
                        default:
                            break
                        }
                    }
                }
            }
        } catch {
            Logger.error("Failed to load workflows for scheduling: \(error)")
        }

        // Start email subsystem if configured
        await startEmailSubsystemIfConfigured()

        // Set up WebSocket connection handler (sends status on connect)
        await server.setConnectionHandler { [weak self] client in
            guard let self = self else { return }
            await self.sendStatus(to: client)
        }

        // Set up WebSocket message handler
        await server.setMessageHandler { [weak self] client, message in
            guard let self = self else { return }
            await self.handleMessage(message, from: client)
        }

        // Start WebSocket server
        try await server.start()

        Logger.info("Daemon started - port: \(config.port), tools: \(toolCount), skills: \(skillCount)")
    }

    /// Stop all services
    func stop() async {
        await emailPollingService?.stop()
        await workflowScheduler.removeAll()
        await server.stop()
        await mcpManager.stopAll()
        Logger.info("Daemon stopped")
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: WSMessage, from client: WebSocketClient) async {
        switch message.type {
        case WSMessageType.ping:
            await handlePing(client: client)

        case WSMessageType.userMessage:
            await handleUserMessage(message, client: client)

        case WSMessageType.newConversation:
            await handleNewConversation(client: client)

        case WSMessageType.loadConversation:
            await handleLoadConversation(message, client: client)

        case WSMessageType.deleteConversation:
            await handleDeleteConversation(message, client: client)

        case WSMessageType.listConversations:
            await handleListConversations(client: client)

        // Workflow messages
        case WSMessageType.createWorkflow:
            await handleCreateWorkflow(message, client: client)

        case WSMessageType.updateWorkflow:
            await handleUpdateWorkflow(message, client: client)

        case WSMessageType.deleteWorkflow:
            await handleDeleteWorkflow(message, client: client)

        case WSMessageType.listWorkflows:
            await handleListWorkflows(client: client)

        case WSMessageType.getWorkflow:
            await handleGetWorkflow(message, client: client)

        case WSMessageType.runWorkflow:
            await handleRunWorkflow(message, client: client)

        case WSMessageType.cancelWorkflow:
            await handleCancelWorkflow(message, client: client)

        case WSMessageType.listExecutions:
            await handleListExecutions(message, client: client)

        case WSMessageType.getExecution:
            await handleGetExecution(message, client: client)

        // Email messages
        case WSMessageType.emailStatus:
            await handleEmailStatus(client: client)

        case WSMessageType.emailConnect:
            await handleEmailConnect(message, client: client)

        case WSMessageType.emailAuthDisconnect:
            await handleEmailAuthDisconnect(client: client)

        case WSMessageType.emailPollNow:
            await handleEmailPollNow(client: client)

        case WSMessageType.emailUpdatePolling:
            await handleEmailUpdatePolling(message, client: client)

        case WSMessageType.emailMessagesList:
            await handleEmailMessagesList(client: client)

        case WSMessageType.emailTriggersList:
            await handleEmailTriggersList(client: client)

        case WSMessageType.emailTriggerCreate:
            await handleEmailTriggerCreate(message, client: client)

        case WSMessageType.emailTriggerUpdate:
            await handleEmailTriggerUpdate(message, client: client)

        case WSMessageType.emailTriggerDelete:
            await handleEmailTriggerDelete(message, client: client)

        // Email Approval messages
        case WSMessageType.emailApprovalApprove:
            await handleEmailApprovalApprove(message, client: client)

        case WSMessageType.emailApprovalDismiss:
            await handleEmailApprovalDismiss(message, client: client)

        case WSMessageType.emailApprovalsList:
            await handleEmailApprovalsList(client: client)

        // Visual Builder messages
        case WSMessageType.mcpToolsList:
            await handleMCPToolsList(client: client)

        case WSMessageType.parseSchedule:
            await handleParseSchedule(message, client: client)

        case WSMessageType.buildWorkflow:
            await handleBuildWorkflow(message, client: client)

        default:
            Logger.error("Unknown message type: \(message.type)")
            await sendError(to: client, message: "Unknown message type: \(message.type)", code: "UNKNOWN_TYPE")
        }
    }

    // MARK: - Ping

    private func handlePing(client: WebSocketClient) async {
        let pong = WSMessage(type: WSMessageType.pong)
        try? await client.send(pong)
    }

    // MARK: - User Message / Claude Streaming

    private func handleUserMessage(_ message: WSMessage, client: WebSocketClient) async {
        guard let conversationId = message.conversationId else {
            await sendError(to: client, message: "Missing conversationId", code: "MISSING_FIELD")
            return
        }
        guard let content = message.content, !content.isEmpty else {
            await sendError(to: client, message: "Missing message content", code: "MISSING_FIELD")
            return
        }

        // Check for API key
        guard config.apiKey != nil else {
            await sendError(
                to: client,
                message: "No ANTHROPIC_API_KEY configured. Set the environment variable and restart the daemon.",
                code: "NO_API_KEY"
            )
            return
        }

        // Save user message to conversation
        let userMsg = StoredMessage(role: "user", content: content)
        do {
            _ = try await conversationStore.addMessage(to: conversationId, message: userMsg)
        } catch {
            await sendError(to: client, message: "Failed to save message: \(error)", code: "STORAGE_ERROR")
            return
        }

        // Start the Claude API streaming loop (may involve tool calls)
        await streamClaudeResponse(conversationId: conversationId, client: client)
    }

    private func buildSystemPrompt() async -> String {
        var prompt = config.systemPrompt

        // Append skill metadata summary (lightweight — always loaded)
        if let summary = await skillStore.getMetadataSummary() {
            prompt += "\n\n" + summary
        }

        // Inject full skill content for active MCP servers (on-demand)
        let activeServers = await mcpManager.activeServerNames
        if let skillContent = await skillStore.getActiveSkillContent(activeServers: activeServers) {
            prompt += "\n\n# Expert Instructions\n\n" + skillContent
        }

        return prompt
    }

    private func streamClaudeResponse(conversationId: String, client: WebSocketClient) async {
        do {
            // Build messages from conversation history
            let apiMessages = try await conversationStore.buildAPIMessages(conversationId: conversationId)
            var tools = await mcpManager.getToolDefinitions()

            // Built-in create_workflow tool — allows Claude to build workflows from chat
            tools.append(ToolDefinition(
                name: "create_workflow",
                description: "Create and save an automated workflow from a natural language description. Use when the user asks to build, create, or save a workflow.",
                input_schema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "description": .object([
                            "type": .string("string"),
                            "description": .string("Natural language description of the workflow to create")
                        ])
                    ]),
                    "required": .array([.string("description")])
                ])
            ))

            let systemPrompt = await buildSystemPrompt()

            Logger.info("Calling Claude API: \(apiMessages.count) messages, \(tools.count) tools")

            let stream = await claudeClient.streamRequest(
                messages: apiMessages,
                tools: tools,
                systemPrompt: systemPrompt
            )

            Logger.info("Stream created, starting iteration")

            var fullText = ""
            var fullThinking = ""
            var thinkingStartTime: Date?
            var pendingToolCalls: [(id: String, name: String, input: String)] = []
            var hasToolCalls = false

            for try await event in stream {
                switch event {
                case .thinkingStart:
                    thinkingStartTime = Date()

                case .thinkingDelta(let chunk):
                    fullThinking += chunk
                    let msg = WSMessage(
                        type: WSMessageType.thinkingChunk,
                        conversationId: conversationId,
                        content: chunk
                    )
                    try? await client.send(msg)

                case .thinkingDone:
                    let duration = thinkingStartTime.map { Date().timeIntervalSince($0) } ?? 0
                    let msg = WSMessage(
                        type: WSMessageType.thinkingDone,
                        conversationId: conversationId,
                        metadata: ["thinkingDuration": .double(duration)]
                    )
                    try? await client.send(msg)

                case .textStart:
                    break

                case .textDelta(let chunk):
                    fullText += chunk
                    let msg = WSMessage(
                        type: WSMessageType.assistantChunk,
                        conversationId: conversationId,
                        content: chunk
                    )
                    try? await client.send(msg)

                case .textDone:
                    break

                case .toolUseStart(let id, let name):
                    hasToolCalls = true
                    let serverName = name == "create_workflow" ? "built-in" : await mcpManager.serverForTool(name: name) ?? "unknown"
                    let msg = WSMessage(
                        type: WSMessageType.toolCallStart,
                        id: id,
                        conversationId: conversationId,
                        metadata: [
                            "toolName": .string(name),
                            "serverName": .string(serverName),
                            "input": .string("")
                        ]
                    )
                    try? await client.send(msg)

                case .toolUseInputDelta:
                    break // Just accumulating in the API client

                case .toolUseDone(let id, let name, let input):
                    pendingToolCalls.append((id: id, name: name, input: input))

                case .messageComplete:
                    break

                case .error(let errorMsg):
                    await sendError(to: client, message: errorMsg, code: "API_ERROR")
                    return
                }
            }

            // Save assistant text response if any
            if !fullText.isEmpty {
                let assistantMsg = StoredMessage(role: "assistant", content: fullText)
                _ = try? await conversationStore.addMessage(to: conversationId, message: assistantMsg)
            }

            // Handle tool calls
            if hasToolCalls && !pendingToolCalls.isEmpty {
                // Save tool_use messages
                for toolCall in pendingToolCalls {
                    let toolUseMsg = StoredMessage(
                        role: "tool_use",
                        content: toolCall.input,
                        metadata: [
                            "toolId": toolCall.id,
                            "toolName": toolCall.name
                        ]
                    )
                    _ = try? await conversationStore.addMessage(to: conversationId, message: toolUseMsg)
                }

                // Execute tool calls and store results
                for toolCall in pendingToolCalls {
                    let startTime = Date()

                    // Built-in create_workflow tool — intercept before MCP
                    if toolCall.name == "create_workflow" {
                        do {
                            // Parse description from tool input
                            var description = ""
                            if let inputData = toolCall.input.data(using: .utf8),
                               let json = try? JSONDecoder().decode([String: String].self, from: inputData) {
                                description = json["description"] ?? toolCall.input
                            } else {
                                description = toolCall.input
                            }

                            let resultContent: String
                            if let workflow = await buildWorkflowFromPrompt(description) {
                                try await workflowStore.create(workflow)

                                // Save tool_result
                                let toolResultMsg = StoredMessage(
                                    role: "tool_result",
                                    content: "Workflow '\(workflow.name)' created successfully (ID: \(workflow.id)). It has \(workflow.steps.count) step(s).",
                                    metadata: [
                                        "toolId": toolCall.id,
                                        "toolName": toolCall.name,
                                        "isError": "false"
                                    ]
                                )
                                _ = try? await conversationStore.addMessage(to: conversationId, message: toolResultMsg)

                                resultContent = "Workflow '\(workflow.name)' created successfully with \(workflow.steps.count) step(s). ID: \(workflow.id)"

                                // Broadcast workflowCreated so Workflows tab updates
                                let wfMsg = WSMessage(
                                    type: WSMessageType.workflowCreated,
                                    id: workflow.id,
                                    metadata: ["name": .string(workflow.name)]
                                )
                                await server.broadcast(wfMsg)
                            } else {
                                let toolResultMsg = StoredMessage(
                                    role: "tool_result",
                                    content: "Failed to build workflow from description.",
                                    metadata: [
                                        "toolId": toolCall.id,
                                        "toolName": toolCall.name,
                                        "isError": "true"
                                    ]
                                )
                                _ = try? await conversationStore.addMessage(to: conversationId, message: toolResultMsg)

                                resultContent = "Failed to build workflow from description."
                            }

                            let duration = Date().timeIntervalSince(startTime)
                            let doneMsg = WSMessage(
                                type: WSMessageType.toolCallDone,
                                id: toolCall.id,
                                conversationId: conversationId,
                                metadata: [
                                    "toolName": .string(toolCall.name),
                                    "serverName": .string("built-in"),
                                    "success": .bool(!resultContent.contains("Failed")),
                                    "result": .string(resultContent),
                                    "duration": .double(duration)
                                ]
                            )
                            try? await client.send(doneMsg)
                        } catch {
                            let duration = Date().timeIntervalSince(startTime)
                            let errorContent = "Error creating workflow: \(error.localizedDescription)"
                            let toolResultMsg = StoredMessage(
                                role: "tool_result",
                                content: errorContent,
                                metadata: [
                                    "toolId": toolCall.id,
                                    "toolName": toolCall.name,
                                    "isError": "true"
                                ]
                            )
                            _ = try? await conversationStore.addMessage(to: conversationId, message: toolResultMsg)

                            let doneMsg = WSMessage(
                                type: WSMessageType.toolCallDone,
                                id: toolCall.id,
                                conversationId: conversationId,
                                metadata: [
                                    "toolName": .string(toolCall.name),
                                    "serverName": .string("built-in"),
                                    "success": .bool(false),
                                    "error": .string(error.localizedDescription),
                                    "duration": .double(duration)
                                ]
                            )
                            try? await client.send(doneMsg)
                        }
                        continue  // Skip MCP tool path
                    }

                    let serverName = await mcpManager.serverForTool(name: toolCall.name) ?? "unknown"

                    do {
                        // Parse the input JSON
                        let inputValue: JSONValue
                        if let inputData = toolCall.input.data(using: .utf8),
                           let decoded = try? JSONDecoder().decode(JSONValue.self, from: inputData) {
                            inputValue = decoded
                        } else {
                            inputValue = .object([:])
                        }

                        let result = try await mcpManager.callTool(
                            name: toolCall.name,
                            arguments: inputValue
                        )

                        let duration = Date().timeIntervalSince(startTime)

                        // Save tool result
                        let toolResultMsg = StoredMessage(
                            role: "tool_result",
                            content: result.content,
                            metadata: [
                                "toolId": toolCall.id,
                                "toolName": toolCall.name,
                                "isError": result.isError ? "true" : "false"
                            ]
                        )
                        _ = try? await conversationStore.addMessage(to: conversationId, message: toolResultMsg)

                        // Send tool_call_done to client (cap result to 4KB for UI performance)
                        let clientResult = result.content.count > 4_000
                            ? String(result.content.prefix(4_000)) + "\n[...truncated]"
                            : result.content
                        let doneMsg = WSMessage(
                            type: WSMessageType.toolCallDone,
                            id: toolCall.id,
                            conversationId: conversationId,
                            metadata: [
                                "toolName": .string(toolCall.name),
                                "serverName": .string(serverName),
                                "success": .bool(!result.isError),
                                "result": .string(clientResult),
                                "duration": .double(duration)
                            ]
                        )
                        try? await client.send(doneMsg)
                    } catch {
                        let duration = Date().timeIntervalSince(startTime)

                        // Save error tool result
                        let errorContent = "Error: \(error.localizedDescription)"
                        let toolResultMsg = StoredMessage(
                            role: "tool_result",
                            content: errorContent,
                            metadata: [
                                "toolId": toolCall.id,
                                "toolName": toolCall.name,
                                "isError": "true"
                            ]
                        )
                        _ = try? await conversationStore.addMessage(to: conversationId, message: toolResultMsg)

                        let doneMsg = WSMessage(
                            type: WSMessageType.toolCallDone,
                            id: toolCall.id,
                            conversationId: conversationId,
                            metadata: [
                                "toolName": .string(toolCall.name),
                                "serverName": .string(serverName),
                                "success": .bool(false),
                                "error": .string(error.localizedDescription),
                                "duration": .double(duration)
                            ]
                        )
                        try? await client.send(doneMsg)
                    }
                }

                // Continue the Claude conversation with tool results (multi-turn loop)
                await streamClaudeResponse(conversationId: conversationId, client: client)
                return
            }

            // No tool calls - streaming complete
            let messageId = UUID().uuidString
            let doneMsg = WSMessage(
                type: WSMessageType.assistantDone,
                id: messageId,
                conversationId: conversationId
            )
            try? await client.send(doneMsg)

        } catch {
            await sendError(to: client, message: "Claude API error: \(error.localizedDescription)", code: "API_ERROR")
        }
    }

    // MARK: - Conversation Management

    private func handleNewConversation(client: WebSocketClient) async {
        do {
            let conversation = try await conversationStore.create()
            let msg = WSMessage(
                type: WSMessageType.conversationCreated,
                conversationId: conversation.id,
                metadata: ["title": .string(conversation.title)]
            )
            try? await client.send(msg)
        } catch {
            await sendError(to: client, message: "Failed to create conversation: \(error)", code: "STORAGE_ERROR")
        }
    }

    private func handleLoadConversation(_ message: WSMessage, client: WebSocketClient) async {
        guard let conversationId = message.conversationId else {
            await sendError(to: client, message: "Missing conversationId", code: "MISSING_FIELD")
            return
        }

        do {
            let conversation = try await conversationStore.load(id: conversationId)
            let messagesMetadata = conversation.messages.map { msg -> MetadataValue in
                var dict: [String: MetadataValue] = [
                    "role": .string(msg.role),
                    "content": .string(msg.content),
                    "timestamp": .string(ISO8601DateFormatter().string(from: msg.timestamp))
                ]
                if let meta = msg.metadata {
                    var metaValues: [String: MetadataValue] = [:]
                    for (k, v) in meta {
                        metaValues[k] = .string(v)
                    }
                    dict["metadata"] = .object(metaValues)
                }
                return .object(dict)
            }

            let msg = WSMessage(
                type: WSMessageType.conversationLoaded,
                conversationId: conversationId,
                metadata: [
                    "title": .string(conversation.title),
                    "messages": .array(messagesMetadata)
                ]
            )
            try? await client.send(msg)
        } catch {
            await sendError(to: client, message: "Failed to load conversation: \(error)", code: "STORAGE_ERROR")
        }
    }

    private func handleDeleteConversation(_ message: WSMessage, client: WebSocketClient) async {
        guard let conversationId = message.conversationId else {
            await sendError(to: client, message: "Missing conversationId", code: "MISSING_FIELD")
            return
        }

        do {
            try await conversationStore.delete(id: conversationId)
            let msg = WSMessage(
                type: WSMessageType.conversationDeleted,
                conversationId: conversationId
            )
            try? await client.send(msg)
        } catch {
            await sendError(to: client, message: "Failed to delete conversation: \(error)", code: "STORAGE_ERROR")
        }
    }

    private func handleListConversations(client: WebSocketClient) async {
        do {
            let conversations = try await conversationStore.listAll()
            let formatter = ISO8601DateFormatter()
            let convMetadata = conversations.map { conv -> MetadataValue in
                var dict: [String: MetadataValue] = [
                    "id": .string(conv.id),
                    "title": .string(conv.title),
                    "lastMessageAt": .string(formatter.string(from: conv.lastMessageAt)),
                    "messageCount": .int(conv.messageCount)
                ]
                if let sourceType = conv.sourceType {
                    dict["sourceType"] = .string(sourceType)
                }
                return .object(dict)
            }

            let msg = WSMessage(
                type: WSMessageType.conversationList,
                metadata: ["conversations": .array(convMetadata)]
            )
            try? await client.send(msg)
        } catch {
            await sendError(to: client, message: "Failed to list conversations: \(error)", code: "STORAGE_ERROR")
        }
    }

    // MARK: - Workflow Management

    private func handleCreateWorkflow(_ message: WSMessage, client: WebSocketClient) async {
        guard let metadata = message.metadata,
              let workflow = decodeWorkflowFromMetadata(metadata) else {
            await sendError(to: client, message: "Invalid workflow data", code: "INVALID_DATA")
            return
        }

        do {
            try await workflowStore.create(workflow)

            // Schedule if cron trigger and enabled
            if workflow.enabled {
                if case .cron = workflow.trigger {
                    await workflowScheduler.add(workflow: workflow)
                } else if case .event(let source, let eventType, _) = workflow.trigger {
                    let executor = self.workflowExecutor
                    let notifService = self.notificationService
                    await eventBus.subscribe(source: source, eventType: eventType, id: workflow.id) { _ in
                        let execution = await executor.execute(workflow: workflow, triggerInfo: "event: \(source):\(eventType)")
                        switch execution.status {
                        case .completed:
                            await notifService.notifyWorkflowCompleted(execution: execution, prefs: workflow.notificationPrefs)
                        case .failed:
                            await notifService.notifyWorkflowFailed(execution: execution, prefs: workflow.notificationPrefs)
                        default:
                            break
                        }
                    }
                }
            }

            let msg = WSMessage(
                type: WSMessageType.workflowCreated,
                id: workflow.id,
                metadata: ["name": .string(workflow.name)]
            )
            try? await client.send(msg)
        } catch {
            await sendError(to: client, message: "Failed to create workflow: \(error)", code: "STORAGE_ERROR")
        }
    }

    private func handleUpdateWorkflow(_ message: WSMessage, client: WebSocketClient) async {
        guard let metadata = message.metadata,
              let workflow = decodeWorkflowFromMetadata(metadata) else {
            await sendError(to: client, message: "Invalid workflow data", code: "INVALID_DATA")
            return
        }

        do {
            try await workflowStore.update(workflow)

            // Re-schedule
            await workflowScheduler.remove(workflowId: workflow.id)
            await eventBus.unsubscribe(id: workflow.id)

            if workflow.enabled {
                if case .cron = workflow.trigger {
                    await workflowScheduler.add(workflow: workflow)
                } else if case .event(let source, let eventType, _) = workflow.trigger {
                    let executor = self.workflowExecutor
                    let notifService = self.notificationService
                    await eventBus.subscribe(source: source, eventType: eventType, id: workflow.id) { _ in
                        let execution = await executor.execute(workflow: workflow, triggerInfo: "event: \(source):\(eventType)")
                        switch execution.status {
                        case .completed:
                            await notifService.notifyWorkflowCompleted(execution: execution, prefs: workflow.notificationPrefs)
                        case .failed:
                            await notifService.notifyWorkflowFailed(execution: execution, prefs: workflow.notificationPrefs)
                        default:
                            break
                        }
                    }
                }
            }

            let msg = WSMessage(
                type: WSMessageType.workflowUpdated,
                id: workflow.id,
                metadata: ["name": .string(workflow.name)]
            )
            try? await client.send(msg)
        } catch {
            await sendError(to: client, message: "Failed to update workflow: \(error)", code: "STORAGE_ERROR")
        }
    }

    private func handleDeleteWorkflow(_ message: WSMessage, client: WebSocketClient) async {
        guard let workflowId = message.id ?? message.metadata?["workflowId"]?.stringValue else {
            await sendError(to: client, message: "Missing workflowId", code: "MISSING_FIELD")
            return
        }

        do {
            try await workflowStore.delete(id: workflowId)
            await workflowScheduler.remove(workflowId: workflowId)
            await eventBus.unsubscribe(id: workflowId)

            let msg = WSMessage(
                type: WSMessageType.workflowDeleted,
                id: workflowId
            )
            try? await client.send(msg)
        } catch {
            await sendError(to: client, message: "Failed to delete workflow: \(error)", code: "STORAGE_ERROR")
        }
    }

    private func handleListWorkflows(client: WebSocketClient) async {
        do {
            let summaries = try await workflowStore.listAll()
            let formatter = ISO8601DateFormatter()
            let items = summaries.map { s -> MetadataValue in
                var dict: [String: MetadataValue] = [
                    "id": .string(s.id),
                    "name": .string(s.name),
                    "description": .string(s.description),
                    "enabled": .bool(s.enabled),
                    "triggerType": .string(s.triggerType),
                    "triggerDetail": .string(s.triggerDetail),
                    "stepCount": .int(s.stepCount)
                ]
                if let status = s.lastRunStatus {
                    dict["lastRunStatus"] = .string(status)
                }
                if let date = s.lastRunAt {
                    dict["lastRunAt"] = .string(formatter.string(from: date))
                }
                return .object(dict)
            }

            let msg = WSMessage(
                type: WSMessageType.workflowList,
                metadata: ["workflows": .array(items)]
            )
            try? await client.send(msg)
        } catch {
            await sendError(to: client, message: "Failed to list workflows: \(error)", code: "STORAGE_ERROR")
        }
    }

    private func handleGetWorkflow(_ message: WSMessage, client: WebSocketClient) async {
        guard let workflowId = message.id ?? message.metadata?["workflowId"]?.stringValue else {
            await sendError(to: client, message: "Missing workflowId", code: "MISSING_FIELD")
            return
        }

        do {
            let workflow = try await workflowStore.get(id: workflowId)
            let msg = WSMessage(
                type: WSMessageType.workflowDetail,
                id: workflowId,
                metadata: encodeWorkflowToMetadata(workflow)
            )
            try? await client.send(msg)
        } catch {
            await sendError(to: client, message: "Failed to get workflow: \(error)", code: "STORAGE_ERROR")
        }
    }

    private func handleRunWorkflow(_ message: WSMessage, client: WebSocketClient) async {
        guard let workflowId = message.id ?? message.metadata?["workflowId"]?.stringValue else {
            await sendError(to: client, message: "Missing workflowId", code: "MISSING_FIELD")
            return
        }

        // Extract runtime input parameters if provided
        var inputParams: [String: String] = [:]
        if case .object(let paramsDict) = message.metadata?["inputParams"] {
            for (key, val) in paramsDict {
                if let str = val.stringValue {
                    inputParams[key] = str
                }
            }
        }

        do {
            let workflow = try await workflowStore.get(id: workflowId)

            // Send start notification
            await notificationService.notifyWorkflowStarted(
                execution: WorkflowExecution(workflowId: workflow.id, workflowName: workflow.name, triggerInfo: "manual"),
                prefs: workflow.notificationPrefs
            )

            // Execute in background
            let capturedParams = inputParams
            Task {
                let execution = await workflowExecutor.execute(workflow: workflow, triggerInfo: "manual", inputParams: capturedParams)

                switch execution.status {
                case .completed:
                    await notificationService.notifyWorkflowCompleted(execution: execution, prefs: workflow.notificationPrefs)
                case .failed:
                    await notificationService.notifyWorkflowFailed(execution: execution, prefs: workflow.notificationPrefs)
                default:
                    break
                }
            }
        } catch {
            await sendError(to: client, message: "Failed to run workflow: \(error)", code: "STORAGE_ERROR")
        }
    }

    private func handleCancelWorkflow(_ message: WSMessage, client: WebSocketClient) async {
        guard let executionId = message.id ?? message.metadata?["executionId"]?.stringValue else {
            await sendError(to: client, message: "Missing executionId", code: "MISSING_FIELD")
            return
        }

        await workflowExecutor.cancel(executionId: executionId)
    }

    private func handleListExecutions(_ message: WSMessage, client: WebSocketClient) async {
        guard let workflowId = message.id ?? message.metadata?["workflowId"]?.stringValue else {
            await sendError(to: client, message: "Missing workflowId", code: "MISSING_FIELD")
            return
        }

        do {
            let executions = try await workflowStore.listExecutions(workflowId: workflowId)
            let formatter = ISO8601DateFormatter()
            let items = executions.map { e -> MetadataValue in
                var dict: [String: MetadataValue] = [
                    "id": .string(e.id),
                    "workflowId": .string(e.workflowId),
                    "workflowName": .string(e.workflowName),
                    "status": .string(e.status.rawValue),
                    "startedAt": .string(formatter.string(from: e.startedAt)),
                    "triggerInfo": .string(e.triggerInfo)
                ]
                if let completedAt = e.completedAt {
                    dict["completedAt"] = .string(formatter.string(from: completedAt))
                }
                let steps = e.stepResults.map { s -> MetadataValue in
                    var stepDict: [String: MetadataValue] = [
                        "stepId": .string(s.stepId),
                        "stepName": .string(s.stepName),
                        "status": .string(s.status.rawValue)
                    ]
                    if let startedAt = s.startedAt { stepDict["startedAt"] = .string(formatter.string(from: startedAt)) }
                    if let completedAt = s.completedAt { stepDict["completedAt"] = .string(formatter.string(from: completedAt)) }
                    if let output = s.output { stepDict["output"] = .string(output) }
                    if let error = s.error { stepDict["error"] = .string(error) }
                    return .object(stepDict)
                }
                dict["steps"] = .array(steps)
                return .object(dict)
            }

            let msg = WSMessage(
                type: WSMessageType.executionList,
                metadata: ["executions": .array(items)]
            )
            try? await client.send(msg)
        } catch {
            await sendError(to: client, message: "Failed to list executions: \(error)", code: "STORAGE_ERROR")
        }
    }

    private func handleGetExecution(_ message: WSMessage, client: WebSocketClient) async {
        guard let executionId = message.id ?? message.metadata?["executionId"]?.stringValue else {
            await sendError(to: client, message: "Missing executionId", code: "MISSING_FIELD")
            return
        }

        do {
            let execution = try await workflowStore.getExecution(id: executionId)
            let formatter = ISO8601DateFormatter()

            var dict: [String: MetadataValue] = [
                "id": .string(execution.id),
                "workflowId": .string(execution.workflowId),
                "workflowName": .string(execution.workflowName),
                "status": .string(execution.status.rawValue),
                "startedAt": .string(formatter.string(from: execution.startedAt)),
                "triggerInfo": .string(execution.triggerInfo)
            ]
            if let completedAt = execution.completedAt {
                dict["completedAt"] = .string(formatter.string(from: completedAt))
            }
            let steps = execution.stepResults.map { s -> MetadataValue in
                var stepDict: [String: MetadataValue] = [
                    "stepId": .string(s.stepId),
                    "stepName": .string(s.stepName),
                    "status": .string(s.status.rawValue)
                ]
                if let startedAt = s.startedAt { stepDict["startedAt"] = .string(formatter.string(from: startedAt)) }
                if let completedAt = s.completedAt { stepDict["completedAt"] = .string(formatter.string(from: completedAt)) }
                if let output = s.output { stepDict["output"] = .string(output) }
                if let error = s.error { stepDict["error"] = .string(error) }
                return .object(stepDict)
            }
            dict["steps"] = .array(steps)

            let msg = WSMessage(
                type: WSMessageType.executionDetail,
                id: executionId,
                metadata: dict
            )
            try? await client.send(msg)
        } catch {
            await sendError(to: client, message: "Failed to get execution: \(error)", code: "STORAGE_ERROR")
        }
    }

    // MARK: - Workflow Broadcasting

    private func broadcastStepUpdate(execution: WorkflowExecution, stepResult: StepResult) async {
        let formatter = ISO8601DateFormatter()
        var stepDict: [String: MetadataValue] = [
            "stepId": .string(stepResult.stepId),
            "stepName": .string(stepResult.stepName),
            "status": .string(stepResult.status.rawValue)
        ]
        if let startedAt = stepResult.startedAt { stepDict["startedAt"] = .string(formatter.string(from: startedAt)) }
        if let completedAt = stepResult.completedAt { stepDict["completedAt"] = .string(formatter.string(from: completedAt)) }
        if let output = stepResult.output { stepDict["output"] = .string(output) }
        if let error = stepResult.error { stepDict["error"] = .string(error) }

        let msg = WSMessage(
            type: WSMessageType.workflowStepUpdate,
            id: execution.id,
            metadata: [
                "executionId": .string(execution.id),
                "workflowId": .string(execution.workflowId),
                "workflowName": .string(execution.workflowName),
                "step": .object(stepDict)
            ]
        )
        await server.broadcast(msg)
    }

    private func broadcastExecutionUpdate(execution: WorkflowExecution) async {
        let formatter = ISO8601DateFormatter()
        var dict: [String: MetadataValue] = [
            "executionId": .string(execution.id),
            "workflowId": .string(execution.workflowId),
            "workflowName": .string(execution.workflowName),
            "status": .string(execution.status.rawValue),
            "startedAt": .string(formatter.string(from: execution.startedAt))
        ]
        if let completedAt = execution.completedAt {
            dict["completedAt"] = .string(formatter.string(from: completedAt))
        }

        let msgType = (execution.status == .running)
            ? WSMessageType.workflowExecutionStarted
            : WSMessageType.workflowExecutionDone

        let msg = WSMessage(
            type: msgType,
            id: execution.id,
            metadata: dict
        )
        await server.broadcast(msg)
    }

    // MARK: - Email Subsystem

    private func startEmailSubsystemIfConfigured() async {
        guard let emailConfig = await emailConfigStore.load() else {
            Logger.info("Email not configured — skipping email subsystem startup")
            return
        }

        let client = AgentMailClient(apiKey: emailConfig.apiKey, inboxId: emailConfig.inboxId)
        self.agentMailClient = client

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let basePath = "\(homeDir)/.love-me"

        let approvalStore = EmailApprovalStore(basePath: basePath)
        self.emailApprovalStore = approvalStore

        let bridge = EmailConversationBridge(
            triggerStore: emailTriggerStore,
            workflowStore: workflowStore,
            workflowExecutor: workflowExecutor,
            eventBus: eventBus,
            approvalStore: approvalStore
        )
        self.emailConversationBridge = bridge

        // Wire the workflow builder so the bridge can create workflows for approval
        await bridge.setWorkflowBuilder { [weak self] prompt in
            guard let self = self else { return nil }
            return await self.buildWorkflowFromPrompt(prompt)
        }

        // Wire the email classifier using Claude
        let claudeClient = self.claudeClient
        await bridge.setClassifyEmail { emailText in
            let messages = [MessageParam(role: "user", text: emailText)]
            return try await claudeClient.singleRequest(
                messages: messages,
                systemPrompt: "You are an email classifier. Respond only with the requested JSON."
            )
        }

        // Wire approval notifications to broadcast to clients
        let server = self.server
        await bridge.setOnApprovalCreated { [self] approval in
            let msg = WSMessage(
                type: WSMessageType.emailApprovalPending,
                id: approval.id,
                metadata: self.encodeApprovalToMetadata(approval)
            )
            await server.broadcast(msg)
        }

        let polling = EmailPollingService(
            agentMailClient: client,
            eventBus: eventBus,
            configStore: emailConfigStore,
            statePath: "\(basePath)/email-state.json"
        )
        self.emailPollingService = polling

        // Wire polling to bridge + chat conversation creation
        await polling.setOnEmailReceived { [weak self] (email: EmailMessage) in
            guard let self = self else { return }
            await self.emailConversationBridge?.handleIncomingEmail(email)
            await self.createEmailConversation(email)
        }

        await polling.start()
        Logger.info("Email subsystem started for \(emailConfig.emailAddress)")
    }

    // MARK: - Email → Chat Conversation

    /// Creates a chat conversation from an incoming email with auto-analysis from Claude.
    /// Runs in the background so the analysis is ready when the user opens the conversation.
    private func createEmailConversation(_ email: EmailMessage) async {
        do {
            let conversation = try await conversationStore.create(
                title: "Email: \(email.subject)",
                sourceType: "email"
            )

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short

            let emailContent = """
            **From:** \(email.from)
            **Subject:** \(email.subject)
            **Date:** \(dateFormatter.string(from: email.receivedAt))

            \(email.bodyText)
            """

            let emailMsg = StoredMessage(
                role: "user",
                content: emailContent,
                metadata: [
                    "sourceType": "email",
                    "emailMessageId": email.id,
                    "emailFrom": email.from
                ]
            )
            _ = try await conversationStore.addMessage(to: conversation.id, message: emailMsg)

            // Run Claude analysis in background
            let analysisPrompt = """
            You received an email. Analyze it and provide:
            1. A brief summary (1-2 sentences)
            2. Key action items or requests, if any
            3. Suggested next steps — what you can help with (e.g. draft a reply, create a workflow, look something up)

            Be concise and helpful. The user can continue chatting with you about this email.
            """

            let analysisMessages = [
                MessageParam(role: "user", text: emailContent),
                MessageParam(role: "user", text: analysisPrompt)
            ]

            let analysis = try await claudeClient.singleRequest(
                messages: analysisMessages,
                systemPrompt: "You are a helpful AI assistant integrated into the love.Me app. The user has received an email that was forwarded to you for analysis. Provide a concise analysis and offer to help."
            )

            let analysisMsg = StoredMessage(role: "assistant", content: analysis)
            _ = try await conversationStore.addMessage(to: conversation.id, message: analysisMsg)

            // Broadcast to all clients so the conversation list updates
            let broadcastMsg = WSMessage(
                type: WSMessageType.conversationCreated,
                conversationId: conversation.id,
                metadata: [
                    "title": .string(conversation.title),
                    "sourceType": .string("email"),
                    "messageCount": .int(2)
                ]
            )
            await server.broadcast(broadcastMsg)

            Logger.info("Created email conversation '\(conversation.title)' (\(conversation.id))")
        } catch {
            Logger.error("Failed to create email conversation: \(error)")
        }
    }

    // MARK: - Email Message Handlers

    private func handleEmailStatus(client: WebSocketClient) async {
        let config = await emailConfigStore.load()
        let pollingState = await emailPollingService?.getState()
        let formatter = ISO8601DateFormatter()

        var metadata: [String: MetadataValue] = [
            "configured": .bool(config != nil),
        ]

        if let config = config {
            metadata["emailAddress"] = .string(config.emailAddress)
            metadata["inboxId"] = .string(config.inboxId)
            metadata["pollingIntervalSeconds"] = .int(config.pollingIntervalSeconds)
        }

        if let state = pollingState {
            metadata["totalProcessed"] = .int(state.totalProcessed)
            if let lastPoll = state.lastSeenTimestamp {
                metadata["lastPollTime"] = .string(formatter.string(from: lastPoll))
            }
        }

        let msg = WSMessage(
            type: WSMessageType.emailStatusResult,
            metadata: metadata
        )
        try? await client.send(msg)
    }

    private func handleEmailConnect(_ message: WSMessage, client: WebSocketClient) async {
        guard let apiKey = message.metadata?["apiKey"]?.stringValue, !apiKey.isEmpty else {
            await sendError(to: client, message: "Missing API key", code: "MISSING_API_KEY")
            return
        }

        let rawInboxId = message.metadata?["inboxId"]?.stringValue ?? "loveme"
        // Ensure inbox ID is the full email format the API expects
        let inboxId = rawInboxId.contains("@") ? rawInboxId : "\(rawInboxId)@agentmail.to"
        let emailAddress = inboxId

        let emailConfig = EmailConfig(
            apiKey: apiKey,
            inboxId: inboxId,
            emailAddress: emailAddress
        )

        do {
            try await emailConfigStore.save(emailConfig)

            // Start the email subsystem
            await startEmailSubsystemIfConfigured()

            let msg = WSMessage(
                type: WSMessageType.emailConnected,
                metadata: [
                    "emailAddress": .string(emailAddress),
                    "inboxId": .string(inboxId),
                    "success": .bool(true)
                ]
            )
            try? await client.send(msg)
        } catch {
            await sendError(to: client, message: "Failed to save email config: \(error.localizedDescription)", code: "CONFIG_ERROR")
        }
    }

    private func handleEmailAuthDisconnect(client: WebSocketClient) async {
        // Stop polling
        await emailPollingService?.stop()
        self.emailPollingService = nil
        self.agentMailClient = nil
        self.emailConversationBridge = nil

        // Delete config
        do {
            try await emailConfigStore.delete()
        } catch {
            Logger.error("Failed to delete email config: \(error)")
        }

        let msg = WSMessage(type: WSMessageType.emailAuthDisconnected)
        try? await client.send(msg)
    }

    private func handleEmailPollNow(client: WebSocketClient) async {
        guard let polling = emailPollingService else {
            await sendError(to: client, message: "Email not configured", code: "NOT_CONFIGURED")
            return
        }

        let count = await polling.pollNow()
        let msg = WSMessage(
            type: WSMessageType.emailPollResult,
            metadata: ["newEmailCount": .int(count)]
        )
        try? await client.send(msg)
    }

    private func handleEmailUpdatePolling(_ message: WSMessage, client: WebSocketClient) async {
        guard let seconds = message.metadata?["intervalSeconds"]?.intValue else {
            await sendError(to: client, message: "Missing intervalSeconds", code: "MISSING_FIELD")
            return
        }

        do {
            try await emailConfigStore.updatePollingInterval(seconds)
            Logger.info("Email polling interval updated to \(seconds)s")
        } catch {
            await sendError(to: client, message: "Failed to update polling interval: \(error)", code: "STORAGE_ERROR")
        }
    }

    private func handleEmailTriggersList(client: WebSocketClient) async {
        let rules = await emailTriggerStore.listAll()
        let items = rules.map { rule -> MetadataValue in
            .object([
                "id": .string(rule.id),
                "workflowId": .string(rule.workflowId),
                "enabled": .bool(rule.enabled),
                "fromContains": .string(rule.conditions.fromContains ?? ""),
                "subjectContains": .string(rule.conditions.subjectContains ?? ""),
                "bodyContains": .string(rule.conditions.bodyContains ?? ""),
                "hasAttachment": .bool(rule.conditions.hasAttachment ?? false),
                "labelEquals": .string(rule.conditions.labelEquals ?? "")
            ])
        }

        let msg = WSMessage(
            type: WSMessageType.emailTriggersListResult,
            metadata: ["rules": .array(items)]
        )
        try? await client.send(msg)
    }

    private func handleEmailTriggerCreate(_ message: WSMessage, client: WebSocketClient) async {
        guard let metadata = message.metadata else {
            await sendError(to: client, message: "Missing rule data", code: "MISSING_FIELD")
            return
        }

        let rule = EmailTriggerRule(
            workflowId: metadata["workflowId"]?.stringValue ?? "",
            conditions: EmailTriggerConditions(
                fromContains: metadata["fromContains"]?.stringValue,
                subjectContains: metadata["subjectContains"]?.stringValue,
                bodyContains: metadata["bodyContains"]?.stringValue,
                hasAttachment: metadata["hasAttachment"]?.boolValue,
                labelEquals: metadata["labelEquals"]?.stringValue
            ),
            enabled: metadata["enabled"]?.boolValue ?? true
        )

        do {
            try await emailTriggerStore.create(rule)
            let msg = WSMessage(
                type: WSMessageType.emailTriggerCreated,
                id: rule.id,
                metadata: ["success": .bool(true)]
            )
            try? await client.send(msg)
        } catch {
            await sendError(to: client, message: "Failed to create trigger: \(error)", code: "STORAGE_ERROR")
        }
    }

    private func handleEmailTriggerUpdate(_ message: WSMessage, client: WebSocketClient) async {
        guard let metadata = message.metadata,
              let ruleId = message.id ?? metadata["id"]?.stringValue else {
            await sendError(to: client, message: "Missing rule data", code: "MISSING_FIELD")
            return
        }

        let rule = EmailTriggerRule(
            id: ruleId,
            workflowId: metadata["workflowId"]?.stringValue ?? "",
            conditions: EmailTriggerConditions(
                fromContains: metadata["fromContains"]?.stringValue,
                subjectContains: metadata["subjectContains"]?.stringValue,
                bodyContains: metadata["bodyContains"]?.stringValue,
                hasAttachment: metadata["hasAttachment"]?.boolValue,
                labelEquals: metadata["labelEquals"]?.stringValue
            ),
            enabled: metadata["enabled"]?.boolValue ?? true
        )

        do {
            try await emailTriggerStore.update(rule)
            let msg = WSMessage(
                type: WSMessageType.emailTriggerUpdated,
                id: rule.id,
                metadata: ["success": .bool(true)]
            )
            try? await client.send(msg)
        } catch {
            await sendError(to: client, message: "Failed to update trigger: \(error)", code: "STORAGE_ERROR")
        }
    }

    private func handleEmailTriggerDelete(_ message: WSMessage, client: WebSocketClient) async {
        guard let ruleId = message.id ?? message.metadata?["id"]?.stringValue else {
            await sendError(to: client, message: "Missing rule ID", code: "MISSING_FIELD")
            return
        }

        do {
            try await emailTriggerStore.delete(id: ruleId)
            let msg = WSMessage(
                type: WSMessageType.emailTriggerDeleted,
                id: ruleId
            )
            try? await client.send(msg)
        } catch {
            await sendError(to: client, message: "Failed to delete trigger: \(error)", code: "STORAGE_ERROR")
        }
    }

    private func handleEmailMessagesList(client: WebSocketClient) async {
        guard let agentMail = agentMailClient else {
            await sendError(to: client, message: "Email not configured", code: "NOT_CONFIGURED")
            return
        }

        do {
            let messages = try await agentMail.listMessages(limit: 50)
            let formatter = ISO8601DateFormatter()

            let items = messages.map { msg -> MetadataValue in
                .object([
                    "id": .string(msg.id),
                    "from": .string(msg.from),
                    "subject": .string(msg.subject),
                    "date": .string(formatter.string(from: msg.receivedAt)),
                    "preview": .string(String(msg.bodyText.prefix(100)).replacingOccurrences(of: "\n", with: " ")),
                    "attachmentCount": .int(msg.attachments.count)
                ])
            }

            let msg = WSMessage(
                type: WSMessageType.emailMessagesListResult,
                metadata: ["messages": .array(items)]
            )
            try? await client.send(msg)
        } catch {
            await sendError(to: client, message: "Failed to list emails: \(error.localizedDescription)", code: "EMAIL_ERROR")
        }
    }

    // MARK: - Email Approval Handlers

    private func handleEmailApprovalApprove(_ message: WSMessage, client: WebSocketClient) async {
        guard let approvalId = message.id ?? message.metadata?["approvalId"]?.stringValue else {
            await sendError(to: client, message: "Missing approval ID", code: "MISSING_FIELD")
            return
        }
        guard let store = emailApprovalStore else {
            await sendError(to: client, message: "Approval store not available", code: "NOT_CONFIGURED")
            return
        }

        guard let approval = await store.get(id: approvalId) else {
            await sendError(to: client, message: "Approval not found", code: "NOT_FOUND")
            return
        }

        do {
            try await store.update(id: approvalId, status: .approved)

            // Broadcast status update
            var updatedApproval = approval
            updatedApproval.status = .approved
            let updateMsg = WSMessage(
                type: WSMessageType.emailApprovalUpdated,
                id: approvalId,
                metadata: encodeApprovalToMetadata(updatedApproval)
            )
            await server.broadcast(updateMsg)

            switch approval.classification {
            case .workflow:
                await executeApprovedWorkflow(approval)
            case .simpleReply:
                await sendSimpleReply(approval)
            case .noAction:
                break
            }
        } catch {
            await sendError(to: client, message: "Failed to approve: \(error)", code: "APPROVAL_ERROR")
        }
    }

    private func handleEmailApprovalDismiss(_ message: WSMessage, client: WebSocketClient) async {
        guard let approvalId = message.id ?? message.metadata?["approvalId"]?.stringValue else {
            await sendError(to: client, message: "Missing approval ID", code: "MISSING_FIELD")
            return
        }
        guard let store = emailApprovalStore else {
            await sendError(to: client, message: "Approval store not available", code: "NOT_CONFIGURED")
            return
        }

        guard let approval = await store.get(id: approvalId) else {
            await sendError(to: client, message: "Approval not found", code: "NOT_FOUND")
            return
        }

        do {
            try await store.update(id: approvalId, status: .dismissed)

            // Delete pre-created workflow if it exists
            if let workflowId = approval.workflowId {
                try? await workflowStore.delete(id: workflowId)
                Logger.info("Deleted pre-created workflow \(workflowId) for dismissed approval")
            }

            var updatedApproval = approval
            updatedApproval.status = .dismissed
            let updateMsg = WSMessage(
                type: WSMessageType.emailApprovalUpdated,
                id: approvalId,
                metadata: encodeApprovalToMetadata(updatedApproval)
            )
            await server.broadcast(updateMsg)
        } catch {
            await sendError(to: client, message: "Failed to dismiss: \(error)", code: "APPROVAL_ERROR")
        }
    }

    private func handleEmailApprovalsList(client: WebSocketClient) async {
        guard let store = emailApprovalStore else {
            let msg = WSMessage(
                type: WSMessageType.emailApprovalsListResult,
                metadata: ["approvals": .array([])]
            )
            try? await client.send(msg)
            return
        }

        let approvals = await store.listAll()
        let items = approvals.map { encodeApprovalToMetadataValue($0) }

        let msg = WSMessage(
            type: WSMessageType.emailApprovalsListResult,
            metadata: ["approvals": .array(items)]
        )
        try? await client.send(msg)
    }

    // MARK: - Approval Execution

    private func executeApprovedWorkflow(_ approval: PendingEmailApproval) async {
        guard let workflowId = approval.workflowId else {
            Logger.error("No workflow ID in approval \(approval.id)")
            return
        }

        do {
            let workflow = try await workflowStore.get(id: workflowId)
            let executor = self.workflowExecutor
            let approvalId = approval.id

            Task {
                let execution = await executor.execute(
                    workflow: workflow,
                    triggerInfo: "email_approval: \(approval.email.subject)"
                )

                switch execution.status {
                case .completed:
                    Logger.info("Approved workflow '\(workflow.name)' completed")
                    await self.composeAndSendReply(approval: approval, execution: execution)
                case .failed:
                    Logger.error("Approved workflow '\(workflow.name)' failed")
                    try? await self.emailApprovalStore?.update(id: approvalId, status: .failed)
                    let failMsg = WSMessage(
                        type: WSMessageType.emailAutoReplyStatus,
                        id: approvalId,
                        metadata: [
                            "status": .string("failed"),
                            "reason": .string("Workflow execution failed")
                        ]
                    )
                    await self.server.broadcast(failMsg)
                default:
                    break
                }
            }
        } catch {
            Logger.error("Failed to load workflow for approval \(approval.id): \(error)")
        }
    }

    private func composeAndSendReply(approval: PendingEmailApproval, execution: WorkflowExecution) async {
        // Gather step outputs
        let stepOutputs = execution.stepResults.compactMap { result -> String? in
            guard let output = result.output else { return nil }
            return "[\(result.stepName)]: \(output)"
        }.joined(separator: "\n\n")

        let composePrompt = """
        Compose a professional reply email based on the workflow results below.
        Keep it concise and friendly. Do NOT include a subject line — just the body text.

        Original email from: \(approval.email.from)
        Original subject: \(approval.email.subject)
        Original message preview: \(approval.email.preview)

        Workflow results:
        \(stepOutputs.isEmpty ? "Workflow completed successfully with no text output." : stepOutputs)
        """

        do {
            let replyBody = try await claudeClient.singleRequest(
                messages: [MessageParam(role: "user", text: composePrompt)],
                systemPrompt: "You are a helpful email assistant. Write only the email body text, no subject line or headers."
            )

            guard let agentMail = agentMailClient else {
                Logger.error("AgentMail client not available for reply")
                return
            }

            _ = try await agentMail.replyToEmail(
                messageId: approval.email.messageId,
                threadId: approval.email.threadId,
                body: replyBody
            )

            try? await emailApprovalStore?.update(id: approval.id, status: .completed)

            let statusMsg = WSMessage(
                type: WSMessageType.emailAutoReplyStatus,
                id: approval.id,
                metadata: [
                    "status": .string("completed"),
                    "replyPreview": .string(String(replyBody.prefix(200)))
                ]
            )
            await server.broadcast(statusMsg)

            Logger.info("Auto-reply sent for approval \(approval.id)")
        } catch {
            Logger.error("Failed to compose/send reply for approval \(approval.id): \(error)")
            try? await emailApprovalStore?.update(id: approval.id, status: .failed)

            let failMsg = WSMessage(
                type: WSMessageType.emailAutoReplyStatus,
                id: approval.id,
                metadata: [
                    "status": .string("failed"),
                    "reason": .string("Failed to send reply: \(error.localizedDescription)")
                ]
            )
            await server.broadcast(failMsg)
        }
    }

    private func sendSimpleReply(_ approval: PendingEmailApproval) async {
        do {
            let replyBody: String
            if let suggested = approval.suggestedReply, !suggested.isEmpty {
                replyBody = suggested
            } else {
                replyBody = try await claudeClient.singleRequest(
                    messages: [MessageParam(role: "user", text: """
                    Write a brief, friendly reply to this email.
                    From: \(approval.email.from)
                    Subject: \(approval.email.subject)
                    Preview: \(approval.email.preview)
                    """)],
                    systemPrompt: "You are a helpful email assistant. Write only the email body text."
                )
            }

            guard let agentMail = agentMailClient else {
                Logger.error("AgentMail client not available for reply")
                return
            }

            _ = try await agentMail.replyToEmail(
                messageId: approval.email.messageId,
                threadId: approval.email.threadId,
                body: replyBody
            )

            try? await emailApprovalStore?.update(id: approval.id, status: .completed)

            let statusMsg = WSMessage(
                type: WSMessageType.emailAutoReplyStatus,
                id: approval.id,
                metadata: [
                    "status": .string("completed"),
                    "replyPreview": .string(String(replyBody.prefix(200)))
                ]
            )
            await server.broadcast(statusMsg)

            Logger.info("Simple reply sent for approval \(approval.id)")
        } catch {
            Logger.error("Failed to send simple reply for approval \(approval.id): \(error)")
            try? await emailApprovalStore?.update(id: approval.id, status: .failed)

            let failMsg = WSMessage(
                type: WSMessageType.emailAutoReplyStatus,
                id: approval.id,
                metadata: [
                    "status": .string("failed"),
                    "reason": .string("Failed to send reply: \(error.localizedDescription)")
                ]
            )
            await server.broadcast(failMsg)
        }
    }

    // MARK: - Approval Metadata Helpers

    nonisolated private func encodeApprovalToMetadata(_ approval: PendingEmailApproval) -> [String: MetadataValue] {
        let formatter = ISO8601DateFormatter()
        var meta: [String: MetadataValue] = [
            "approvalId": .string(approval.id),
            "classification": .string(approval.classification.rawValue),
            "status": .string(approval.status.rawValue),
            "emailFrom": .string(approval.email.from),
            "emailSubject": .string(approval.email.subject),
            "emailPreview": .string(approval.email.preview),
            "emailMessageId": .string(approval.email.messageId),
            "emailThreadId": .string(approval.email.threadId),
            "createdAt": .string(formatter.string(from: approval.createdAt)),
        ]
        if let wfId = approval.workflowId { meta["workflowId"] = .string(wfId) }
        if let wfName = approval.workflowName { meta["workflowName"] = .string(wfName) }
        if let count = approval.workflowStepCount { meta["workflowStepCount"] = .int(count) }
        if let reply = approval.suggestedReply { meta["suggestedReply"] = .string(reply) }
        return meta
    }

    nonisolated private func encodeApprovalToMetadataValue(_ approval: PendingEmailApproval) -> MetadataValue {
        .object(encodeApprovalToMetadata(approval))
    }

    // MARK: - Visual Builder

    private func handleMCPToolsList(client: WebSocketClient) async {
        let tools = await mcpManager.getTools()
        let items = tools.map { tool -> MetadataValue in
            .object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "serverName": .string(tool.serverName),
                "inputSchema": metadataFromJSON(tool.inputSchema)
            ])
        }
        let msg = WSMessage(
            type: WSMessageType.mcpToolsListResult,
            metadata: ["tools": .array(items)]
        )
        try? await client.send(msg)
    }

    private func handleParseSchedule(_ message: WSMessage, client: WebSocketClient) async {
        guard let text = message.content ?? message.metadata?["text"]?.stringValue else {
            await sendError(to: client, message: "Missing schedule text", code: "MISSING_FIELD")
            return
        }

        if let result = NaturalScheduleParser.parse(text) {
            let msg = WSMessage(
                type: WSMessageType.parseScheduleResult,
                metadata: [
                    "cron": .string(result.cron),
                    "description": .string(result.description),
                    "success": .bool(true)
                ]
            )
            try? await client.send(msg)
        } else {
            let msg = WSMessage(
                type: WSMessageType.parseScheduleResult,
                metadata: [
                    "success": .bool(false),
                    "message": .string("Could not parse schedule. Try phrases like 'every 5 minutes' or 'daily at 9am'.")
                ]
            )
            try? await client.send(msg)
        }
    }

    private func handleBuildWorkflow(_ message: WSMessage, client: WebSocketClient) async {
        guard let prompt = message.content ?? message.metadata?["prompt"]?.stringValue else {
            await sendError(to: client, message: "Missing workflow prompt", code: "MISSING_FIELD")
            return
        }

        guard config.apiKey != nil else {
            await sendError(to: client, message: "No ANTHROPIC_API_KEY configured", code: "NO_API_KEY")
            return
        }

        // Gather available MCP tools for context, including input schemas
        let tools = await mcpManager.getTools()
        let toolCatalog = tools.map { tool -> String in
            var entry = "- \(tool.name) (server: \(tool.serverName)): \(tool.description)"
            // Include required parameters so Claude knows what inputs to generate
            if case .object(let schema) = tool.inputSchema,
               case .object(let props) = schema["properties"] {
                let required: [String]
                if case .array(let reqArr) = schema["required"] {
                    required = reqArr.compactMap { if case .string(let s) = $0 { return s }; return nil }
                } else {
                    required = []
                }
                let params = props.keys.sorted().map { key -> String in
                    let isReq = required.contains(key)
                    let desc: String
                    if case .object(let propObj) = props[key],
                       case .string(let d) = propObj["description"] {
                        desc = d
                    } else {
                        desc = ""
                    }
                    return "    \(key)\(isReq ? " (required)" : ""): \(desc)"
                }.joined(separator: "\n")
                if !params.isEmpty {
                    entry += "\n  Parameters:\n\(params)"
                }
            }
            return entry
        }.joined(separator: "\n")

        let systemPrompt = """
        You are a workflow builder for the love.Me automation system. The user will describe a workflow in natural language. You must generate a valid workflow JSON object.

        Available MCP tools:
        \(toolCatalog.isEmpty ? "No MCP tools currently connected." : toolCatalog)

        Output ONLY a valid JSON object (no markdown, no explanation) with this exact schema:
        {
          "name": "Workflow Name",
          "description": "What this workflow does",
          "triggerType": "cron" or "manual",
          "schedule": "natural language schedule (only when triggerType is cron)",
          "inputParams": [
            { "name": "param_name", "label": "Human Label", "placeholder": "hint text" }
          ],
          "steps": [
            {
              "name": "Step Name",
              "toolName": "exact_tool_name_from_catalog",
              "serverName": "exact_server_name_from_catalog",
              "needsConfiguration": false,
              "inputs": {
                "paramName": "value or {{__input__.param_name}}"
              }
            }
          ]
        }

        Trigger type rules:
        - Use "cron" with a "schedule" when the prompt describes a recurring/scheduled task or includes all concrete values needed to run
        - Use "manual" with "inputParams" when the prompt describes a reusable/on-demand task, or when specific values (URLs, IDs, file paths) are not provided and should be supplied at runtime
        - For manual triggers, define each runtime input in "inputParams" and reference them in step inputs as {{__input__.param_name}}
        - When triggerType is "manual", omit "schedule". When triggerType is "cron", omit "inputParams"

        Rules:
        - Map user descriptions to real tools from the catalog when possible
        - If no matching tool exists, set toolName to a descriptive placeholder and needsConfiguration to true
        - Steps are linear (executed top-to-bottom in sequence)
        - Use the user's language for step names (human-readable)
        - Keep step count minimal — only what the user described
        - IMPORTANT: Always include the "inputs" object with all required parameters for each tool
        - Generate creative, sensible default values for inputs based on what the user asked for
        - For code execution tools, write the actual code that accomplishes the user's goal
        """

        let userMessage = MessageParam(role: "user", text: prompt)

        do {
            let responseText = try await claudeClient.singleRequest(
                messages: [userMessage],
                systemPrompt: systemPrompt
            )

            // Strip markdown fences if Claude wrapped the JSON
            var cleanedText = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanedText.hasPrefix("```") {
                // Remove opening fence (```json or ```)
                if let firstNewline = cleanedText.firstIndex(of: "\n") {
                    cleanedText = String(cleanedText[cleanedText.index(after: firstNewline)...])
                }
                // Remove closing fence
                if cleanedText.hasSuffix("```") {
                    cleanedText = String(cleanedText.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            // Parse the AI response as JSON
            guard let jsonData = cleanedText.data(using: .utf8) else {
                await sendError(to: client, message: "Invalid response from AI", code: "PARSE_ERROR")
                return
            }

            // Decode the AI-generated workflow
            struct AIInputParam: Codable {
                let name: String
                let label: String
                let placeholder: String?
            }
            struct AIWorkflow: Codable {
                let name: String
                let description: String
                let triggerType: String?
                let schedule: String?
                let inputParams: [AIInputParam]?
                let steps: [AIStep]
            }
            struct AIStep: Codable {
                let name: String
                let toolName: String
                let serverName: String
                let needsConfiguration: Bool?
                let inputs: [String: JSONValue]?
            }

            let aiWorkflow = try JSONDecoder().decode(AIWorkflow.self, from: jsonData)
            let resolvedTriggerType = aiWorkflow.triggerType ?? "cron"

            // Parse schedule to cron (only relevant for cron triggers)
            var cronExpression = "0 * * * *"
            var scheduleDescription = ""
            if resolvedTriggerType == "cron", let schedule = aiWorkflow.schedule {
                let scheduleResult = NaturalScheduleParser.parse(schedule)
                cronExpression = scheduleResult?.cron ?? "0 * * * *"
                scheduleDescription = scheduleResult?.description ?? schedule
            }

            // Build workflow steps
            let workflowId = UUID().uuidString
            var stepMetadata: [MetadataValue] = []
            var previousStepId: String?

            for aiStep in aiWorkflow.steps {
                let stepId = UUID().uuidString
                var stepDict: [String: MetadataValue] = [
                    "id": .string(stepId),
                    "name": .string(aiStep.name),
                    "toolName": .string(aiStep.toolName),
                    "serverName": .string(aiStep.serverName),
                    "onError": .string("stop"),
                    "needsConfiguration": .bool(aiStep.needsConfiguration ?? false)
                ]

                // Include AI-generated inputs (convert JSONValue -> string for MetadataValue)
                if let inputs = aiStep.inputs, !inputs.isEmpty {
                    var inputDict: [String: MetadataValue] = [:]
                    for (key, value) in inputs {
                        switch value {
                        case .string(let str):
                            inputDict[key] = .string(str)
                        case .int(let num):
                            inputDict[key] = .string(String(num))
                        case .double(let num):
                            inputDict[key] = .string(String(num))
                        case .bool(let b):
                            inputDict[key] = .string(String(b))
                        default:
                            // For arrays/objects/null, serialize to JSON string
                            inputDict[key] = .string(value.toJSONString())
                        }
                    }
                    stepDict["inputs"] = .object(inputDict)
                }

                // Linear dependency chain
                if let prevId = previousStepId {
                    stepDict["dependsOn"] = .array([.string(prevId)])
                }

                stepMetadata.append(.object(stepDict))
                previousStepId = stepId
            }

            let hasUnconfigured = aiWorkflow.steps.contains { $0.needsConfiguration ?? false }

            var resultMetadata: [String: MetadataValue] = [
                "success": .bool(true),
                "id": .string(workflowId),
                "name": .string(aiWorkflow.name),
                "description": .string(aiWorkflow.description),
                "cronExpression": .string(cronExpression),
                "scheduleDescription": .string(scheduleDescription),
                "steps": .array(stepMetadata),
                "needsConfiguration": .bool(hasUnconfigured),
                "triggerType": .string(resolvedTriggerType)
            ]

            if resolvedTriggerType == "manual", let inputParams = aiWorkflow.inputParams {
                let paramsMeta: [MetadataValue] = inputParams.map { param in
                    var dict: [String: MetadataValue] = [
                        "name": .string(param.name),
                        "label": .string(param.label)
                    ]
                    if let placeholder = param.placeholder {
                        dict["placeholder"] = .string(placeholder)
                    }
                    return .object(dict)
                }
                resultMetadata["inputParams"] = .array(paramsMeta)
            }

            let resultMsg = WSMessage(
                type: WSMessageType.buildWorkflowResult,
                id: workflowId,
                metadata: resultMetadata
            )
            try? await client.send(resultMsg)

        } catch {
            Logger.error("Build workflow failed: \(error)")
            await sendError(to: client, message: "Failed to build workflow: \(error.localizedDescription)", code: "BUILD_ERROR")
        }
    }

    // MARK: - Shared Workflow Builder

    /// Build a workflow from a natural language prompt using Claude.
    /// Shared between handleBuildWorkflow (WebSocket) and EmailConversationBridge (email briefs).
    func buildWorkflowFromPrompt(_ prompt: String) async -> WorkflowDefinition? {
        guard config.apiKey != nil else {
            Logger.error("buildWorkflowFromPrompt: No ANTHROPIC_API_KEY configured")
            return nil
        }

        let tools = await mcpManager.getTools()
        let toolCatalog = tools.map { tool -> String in
            var entry = "- \(tool.name) (server: \(tool.serverName)): \(tool.description)"
            if case .object(let schema) = tool.inputSchema,
               case .object(let props) = schema["properties"] {
                let required: [String]
                if case .array(let reqArr) = schema["required"] {
                    required = reqArr.compactMap { if case .string(let s) = $0 { return s }; return nil }
                } else {
                    required = []
                }
                let params = props.keys.sorted().map { key -> String in
                    let isReq = required.contains(key)
                    let desc: String
                    if case .object(let propObj) = props[key],
                       case .string(let d) = propObj["description"] {
                        desc = d
                    } else {
                        desc = ""
                    }
                    return "    \(key)\(isReq ? " (required)" : ""): \(desc)"
                }.joined(separator: "\n")
                if !params.isEmpty {
                    entry += "\n  Parameters:\n\(params)"
                }
            }
            return entry
        }.joined(separator: "\n")

        let systemPrompt = """
        You are a workflow builder for the love.Me automation system. The user will describe a workflow in natural language. You must generate a valid workflow JSON object.

        Available MCP tools:
        \(toolCatalog.isEmpty ? "No MCP tools currently connected." : toolCatalog)

        Output ONLY a valid JSON object (no markdown, no explanation) with this exact schema:
        {
          "name": "Workflow Name",
          "description": "What this workflow does",
          "triggerType": "cron" or "manual",
          "schedule": "natural language schedule (only when triggerType is cron)",
          "inputParams": [
            { "name": "param_name", "label": "Human Label", "placeholder": "hint text" }
          ],
          "steps": [
            {
              "name": "Step Name",
              "toolName": "exact_tool_name_from_catalog",
              "serverName": "exact_server_name_from_catalog",
              "needsConfiguration": false,
              "inputs": {
                "paramName": "value or {{__input__.param_name}}"
              }
            }
          ]
        }

        Trigger type rules:
        - Use "cron" with a "schedule" when the prompt describes a recurring/scheduled task or includes all concrete values needed to run
        - Use "manual" with "inputParams" when the prompt describes a reusable/on-demand task, or when specific values (URLs, IDs, file paths) are not provided and should be supplied at runtime
        - For manual triggers, define each runtime input in "inputParams" and reference them in step inputs as {{__input__.param_name}}
        - When triggerType is "manual", omit "schedule". When triggerType is "cron", omit "inputParams"

        Rules:
        - Map user descriptions to real tools from the catalog when possible
        - If no matching tool exists, set toolName to a descriptive placeholder and needsConfiguration to true
        - Steps are linear (executed top-to-bottom in sequence)
        - Use the user's language for step names (human-readable)
        - Keep step count minimal — only what the user described
        - IMPORTANT: Always include the "inputs" object with all required parameters for each tool
        - Generate creative, sensible default values for inputs based on what the user asked for
        - For code execution tools, write the actual code that accomplishes the user's goal
        """

        let userMessage = MessageParam(role: "user", text: prompt)

        do {
            let responseText = try await claudeClient.singleRequest(
                messages: [userMessage],
                systemPrompt: systemPrompt
            )

            var cleanedText = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanedText.hasPrefix("```") {
                if let firstNewline = cleanedText.firstIndex(of: "\n") {
                    cleanedText = String(cleanedText[cleanedText.index(after: firstNewline)...])
                }
                if cleanedText.hasSuffix("```") {
                    cleanedText = String(cleanedText.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            guard let jsonData = cleanedText.data(using: .utf8) else {
                Logger.error("buildWorkflowFromPrompt: Invalid response from AI")
                return nil
            }

            struct AIInputParam: Codable {
                let name: String
                let label: String
                let placeholder: String?
            }
            struct AIWorkflow: Codable {
                let name: String
                let description: String
                let triggerType: String?
                let schedule: String?
                let inputParams: [AIInputParam]?
                let steps: [AIStep]
            }
            struct AIStep: Codable {
                let name: String
                let toolName: String
                let serverName: String
                let needsConfiguration: Bool?
                let inputs: [String: JSONValue]?
            }

            let aiWorkflow = try JSONDecoder().decode(AIWorkflow.self, from: jsonData)
            let resolvedTriggerType = aiWorkflow.triggerType ?? "cron"

            // Build trigger based on type
            let trigger: WorkflowTrigger
            if resolvedTriggerType == "manual" {
                let params: [InputParam] = (aiWorkflow.inputParams ?? []).map { p in
                    InputParam(name: p.name, label: p.label, placeholder: p.placeholder)
                }
                trigger = .manual(inputParams: params)
            } else {
                var cronExpression = "0 * * * *"
                if let schedule = aiWorkflow.schedule {
                    let scheduleResult = NaturalScheduleParser.parse(schedule)
                    cronExpression = scheduleResult?.cron ?? "0 * * * *"
                }
                trigger = .cron(expression: cronExpression)
            }

            var steps: [WorkflowStep] = []
            var previousStepId: String?

            for aiStep in aiWorkflow.steps {
                let stepId = UUID().uuidString
                var inputTemplate: [String: StringOrVariable] = [:]

                if let inputs = aiStep.inputs {
                    for (key, value) in inputs {
                        switch value {
                        case .string(let str):
                            if str.contains("{{") {
                                inputTemplate[key] = .template(str)
                            } else {
                                inputTemplate[key] = .literal(str)
                            }
                        default:
                            inputTemplate[key] = .literal(value.toJSONString())
                        }
                    }
                }

                var dependsOn: [String]?
                if let prevId = previousStepId {
                    dependsOn = [prevId]
                }

                steps.append(WorkflowStep(
                    id: stepId,
                    name: aiStep.name,
                    toolName: aiStep.toolName,
                    serverName: aiStep.serverName,
                    inputTemplate: inputTemplate,
                    dependsOn: dependsOn,
                    onError: .stop
                ))
                previousStepId = stepId
            }

            return WorkflowDefinition(
                id: UUID().uuidString,
                name: aiWorkflow.name,
                description: aiWorkflow.description,
                enabled: true,
                trigger: trigger,
                steps: steps
            )

        } catch {
            Logger.error("buildWorkflowFromPrompt: \(error)")
            return nil
        }
    }

    /// Convert JSONValue to MetadataValue for WebSocket transport
    private func metadataFromJSON(_ json: JSONValue) -> MetadataValue {
        switch json {
        case .string(let v): return .string(v)
        case .int(let v): return .int(v)
        case .double(let v): return .double(v)
        case .bool(let v): return .bool(v)
        case .null: return .null
        case .array(let arr): return .array(arr.map { metadataFromJSON($0) })
        case .object(let obj):
            var dict: [String: MetadataValue] = [:]
            for (k, v) in obj { dict[k] = metadataFromJSON(v) }
            return .object(dict)
        }
    }

    // MARK: - Status

    func sendStatus(to client: WebSocketClient) async {
        let toolCount = await mcpManager.toolCount
        let workflowCount: Int
        do {
            workflowCount = try await workflowStore.listAll().count
        } catch {
            workflowCount = 0
        }

        let emailConfig = await emailConfigStore.load()

        var metadata: [String: MetadataValue] = [
            "connected": .bool(true),
            "hasApiKey": .bool(config.apiKey != nil),
            "toolCount": .int(toolCount),
            "workflowCount": .int(workflowCount),
            "daemonVersion": .string(config.daemonVersion),
            "emailConfigured": .bool(emailConfig != nil)
        ]

        if let emailConfig = emailConfig {
            metadata["emailAddress"] = .string(emailConfig.emailAddress)
        }

        let msg = WSMessage(
            type: WSMessageType.status,
            metadata: metadata
        )
        try? await client.send(msg)
    }

    // MARK: - Error Helper

    private func sendError(to client: WebSocketClient, message: String, code: String) async {
        let msg = WSMessage(
            type: WSMessageType.error,
            content: message,
            metadata: ["code": .string(code)]
        )
        try? await client.send(msg)
    }

    // MARK: - Workflow Serialization Helpers

    private func decodeWorkflowFromMetadata(_ metadata: [String: MetadataValue]) -> WorkflowDefinition? {
        guard let name = metadata["name"]?.stringValue else { return nil }

        let id = metadata["id"]?.stringValue ?? UUID().uuidString
        let description = metadata["description"]?.stringValue ?? ""
        let enabled = metadata["enabled"]?.boolValue ?? true

        // Parse trigger
        let trigger: WorkflowTrigger
        let triggerType = metadata["triggerType"]?.stringValue ?? "cron"
        if triggerType == "cron" {
            let expression = metadata["cronExpression"]?.stringValue ?? "0 * * * *"
            trigger = .cron(expression: expression)
        } else if triggerType == "manual" {
            var inputParams: [InputParam]?
            if case .array(let items) = metadata["inputParams"] {
                inputParams = items.compactMap { item -> InputParam? in
                    guard case .object(let dict) = item,
                          let name = dict["name"]?.stringValue,
                          let label = dict["label"]?.stringValue else { return nil }
                    return InputParam(name: name, label: label, placeholder: dict["placeholder"]?.stringValue)
                }
            }
            trigger = .manual(inputParams: inputParams)
        } else {
            let source = metadata["eventSource"]?.stringValue ?? ""
            let eventType = metadata["eventType"]?.stringValue ?? ""
            trigger = .event(source: source, eventType: eventType, filter: nil)
        }

        // Parse steps
        var steps: [WorkflowStep] = []
        if case .array(let stepValues) = metadata["steps"] {
            for stepValue in stepValues {
                if case .object(let stepDict) = stepValue {
                    // Parse inputTemplate
                    var inputTemplate: [String: StringOrVariable] = [:]
                    if case .object(let inputDict) = stepDict["inputTemplate"] {
                        for (key, val) in inputDict {
                            if case .object(let varObj) = val {
                                if varObj["type"]?.stringValue == "template",
                                   let templateValue = varObj["value"]?.stringValue {
                                    inputTemplate[key] = .template(templateValue)
                                } else if let stepId = varObj["stepId"]?.stringValue,
                                          let jsonPath = varObj["jsonPath"]?.stringValue {
                                    inputTemplate[key] = .variable(stepId: stepId, jsonPath: jsonPath)
                                }
                            } else if let strVal = val.stringValue {
                                inputTemplate[key] = .literal(strVal)
                            }
                        }
                    }

                    // Parse dependsOn
                    var dependsOn: [String]?
                    if case .array(let deps) = stepDict["dependsOn"] {
                        dependsOn = deps.compactMap { $0.stringValue }
                    }

                    let stepName = stepDict["name"]?.stringValue ?? "Step"
                    Logger.info("Decoded step '\(stepName)' with \(inputTemplate.count) input(s): \(inputTemplate.keys.sorted().joined(separator: ", "))")

                    let step = WorkflowStep(
                        id: stepDict["id"]?.stringValue ?? UUID().uuidString,
                        name: stepName,
                        toolName: stepDict["toolName"]?.stringValue ?? "",
                        serverName: stepDict["serverName"]?.stringValue ?? "",
                        inputTemplate: inputTemplate,
                        dependsOn: dependsOn,
                        onError: ErrorPolicy(rawValue: stepDict["onError"]?.stringValue ?? "stop") ?? .stop
                    )
                    steps.append(step)
                }
            }
        }

        // Parse notification prefs
        let notificationPrefs = NotificationPrefs(
            notifyOnStart: metadata["notifyOnStart"]?.boolValue ?? false,
            notifyOnComplete: metadata["notifyOnComplete"]?.boolValue ?? true,
            notifyOnError: metadata["notifyOnError"]?.boolValue ?? true,
            notifyOnStepComplete: metadata["notifyOnStepComplete"]?.boolValue ?? false
        )

        return WorkflowDefinition(
            id: id,
            name: name,
            description: description,
            enabled: enabled,
            trigger: trigger,
            steps: steps,
            notificationPrefs: notificationPrefs
        )
    }

    private func encodeWorkflowToMetadata(_ workflow: WorkflowDefinition) -> [String: MetadataValue] {
        let formatter = ISO8601DateFormatter()
        var dict: [String: MetadataValue] = [
            "id": .string(workflow.id),
            "name": .string(workflow.name),
            "description": .string(workflow.description),
            "enabled": .bool(workflow.enabled),
            "created": .string(formatter.string(from: workflow.created)),
            "updated": .string(formatter.string(from: workflow.updated)),
            "notifyOnStart": .bool(workflow.notificationPrefs.notifyOnStart),
            "notifyOnComplete": .bool(workflow.notificationPrefs.notifyOnComplete),
            "notifyOnError": .bool(workflow.notificationPrefs.notifyOnError),
            "notifyOnStepComplete": .bool(workflow.notificationPrefs.notifyOnStepComplete)
        ]

        // Encode trigger
        switch workflow.trigger {
        case .cron(let expression):
            dict["triggerType"] = .string("cron")
            dict["cronExpression"] = .string(expression)
        case .event(let source, let eventType, let filter):
            dict["triggerType"] = .string("event")
            dict["eventSource"] = .string(source)
            dict["eventType"] = .string(eventType)
            if let filter = filter {
                var filterDict: [String: MetadataValue] = [:]
                for (k, v) in filter { filterDict[k] = .string(v) }
                dict["eventFilter"] = .object(filterDict)
            }
        case .manual(let inputParams):
            dict["triggerType"] = .string("manual")
            if let params = inputParams {
                dict["inputParams"] = .array(params.map { param in
                    var paramDict: [String: MetadataValue] = [
                        "name": .string(param.name),
                        "label": .string(param.label)
                    ]
                    if let placeholder = param.placeholder {
                        paramDict["placeholder"] = .string(placeholder)
                    }
                    return .object(paramDict)
                })
            }
        }

        // Encode steps
        let steps = workflow.steps.map { step -> MetadataValue in
            var stepDict: [String: MetadataValue] = [
                "id": .string(step.id),
                "name": .string(step.name),
                "toolName": .string(step.toolName),
                "serverName": .string(step.serverName),
                "onError": .string(step.onError.rawValue)
            ]

            // Encode inputTemplate
            if !step.inputTemplate.isEmpty {
                var inputDict: [String: MetadataValue] = [:]
                for (key, value) in step.inputTemplate {
                    switch value {
                    case .literal(let str):
                        inputDict[key] = .string(str)
                    case .variable(let stepId, let jsonPath):
                        inputDict[key] = .object([
                            "stepId": .string(stepId),
                            "jsonPath": .string(jsonPath)
                        ])
                    case .template(let templateStr):
                        inputDict[key] = .object([
                            "type": .string("template"),
                            "value": .string(templateStr)
                        ])
                    }
                }
                stepDict["inputTemplate"] = .object(inputDict)
            }

            // Encode dependsOn
            if let deps = step.dependsOn, !deps.isEmpty {
                stepDict["dependsOn"] = .array(deps.map { .string($0) })
            }

            return .object(stepDict)
        }
        dict["steps"] = .array(steps)

        return dict
    }
}
