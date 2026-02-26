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
            let tools = await mcpManager.getToolDefinitions()
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
                    let serverName = await mcpManager.serverForTool(name: name) ?? "unknown"
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
                .object([
                    "id": .string(conv.id),
                    "title": .string(conv.title),
                    "lastMessageAt": .string(formatter.string(from: conv.lastMessageAt)),
                    "messageCount": .int(conv.messageCount)
                ])
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

        do {
            let workflow = try await workflowStore.get(id: workflowId)

            // Send start notification
            await notificationService.notifyWorkflowStarted(
                execution: WorkflowExecution(workflowId: workflow.id, workflowName: workflow.name, triggerInfo: "manual"),
                prefs: workflow.notificationPrefs
            )

            // Execute in background
            Task {
                let execution = await workflowExecutor.execute(workflow: workflow, triggerInfo: "manual")

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

        // Gather available MCP tools for context
        let tools = await mcpManager.getTools()
        let toolCatalog = tools.map { tool -> String in
            "- \(tool.name) (server: \(tool.serverName)): \(tool.description)"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are a workflow builder for the love.Me automation system. The user will describe a workflow in natural language. You must generate a valid workflow JSON object.

        Available MCP tools:
        \(toolCatalog.isEmpty ? "No MCP tools currently connected." : toolCatalog)

        Output ONLY a valid JSON object (no markdown, no explanation) with this exact schema:
        {
          "name": "Workflow Name",
          "description": "What this workflow does",
          "schedule": "natural language schedule like 'every 5 minutes'",
          "steps": [
            {
              "name": "Step Name",
              "toolName": "exact_tool_name_from_catalog",
              "serverName": "exact_server_name_from_catalog",
              "needsConfiguration": false
            }
          ]
        }

        Rules:
        - Map user descriptions to real tools from the catalog when possible
        - If no matching tool exists, set toolName to a descriptive placeholder and needsConfiguration to true
        - Steps are linear (executed top-to-bottom in sequence)
        - Use the user's language for step names (human-readable)
        - The schedule field should be natural language (will be parsed to cron separately)
        - Keep step count minimal — only what the user described
        """

        let userMessage = MessageParam(role: "user", text: prompt)

        do {
            let responseText = try await claudeClient.singleRequest(
                messages: [userMessage],
                systemPrompt: systemPrompt
            )

            // Parse the AI response as JSON
            guard let jsonData = responseText.data(using: .utf8) else {
                await sendError(to: client, message: "Invalid response from AI", code: "PARSE_ERROR")
                return
            }

            // Decode the AI-generated workflow
            struct AIWorkflow: Codable {
                let name: String
                let description: String
                let schedule: String
                let steps: [AIStep]
            }
            struct AIStep: Codable {
                let name: String
                let toolName: String
                let serverName: String
                let needsConfiguration: Bool?
            }

            let aiWorkflow = try JSONDecoder().decode(AIWorkflow.self, from: jsonData)

            // Parse schedule to cron
            let scheduleResult = NaturalScheduleParser.parse(aiWorkflow.schedule)
            let cronExpression = scheduleResult?.cron ?? "0 * * * *"
            let scheduleDescription = scheduleResult?.description ?? aiWorkflow.schedule

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

                // Linear dependency chain
                if let prevId = previousStepId {
                    stepDict["dependsOn"] = .array([.string(prevId)])
                }

                stepMetadata.append(.object(stepDict))
                previousStepId = stepId
            }

            let hasUnconfigured = aiWorkflow.steps.contains { $0.needsConfiguration ?? false }

            let resultMsg = WSMessage(
                type: WSMessageType.buildWorkflowResult,
                id: workflowId,
                metadata: [
                    "success": .bool(true),
                    "id": .string(workflowId),
                    "name": .string(aiWorkflow.name),
                    "description": .string(aiWorkflow.description),
                    "cronExpression": .string(cronExpression),
                    "scheduleDescription": .string(scheduleDescription),
                    "steps": .array(stepMetadata),
                    "needsConfiguration": .bool(hasUnconfigured),
                    "triggerType": .string("cron")
                ]
            )
            try? await client.send(resultMsg)

        } catch {
            Logger.error("Build workflow failed: \(error)")
            await sendError(to: client, message: "Failed to build workflow: \(error.localizedDescription)", code: "BUILD_ERROR")
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

        let msg = WSMessage(
            type: WSMessageType.status,
            metadata: [
                "connected": .bool(true),
                "hasApiKey": .bool(config.apiKey != nil),
                "toolCount": .int(toolCount),
                "workflowCount": .int(workflowCount),
                "daemonVersion": .string(config.daemonVersion)
            ]
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
                            if case .object(let varObj) = val,
                               let stepId = varObj["stepId"]?.stringValue,
                               let jsonPath = varObj["jsonPath"]?.stringValue {
                                inputTemplate[key] = .variable(stepId: stepId, jsonPath: jsonPath)
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

                    let step = WorkflowStep(
                        id: stepDict["id"]?.stringValue ?? UUID().uuidString,
                        name: stepDict["name"]?.stringValue ?? "Step",
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
