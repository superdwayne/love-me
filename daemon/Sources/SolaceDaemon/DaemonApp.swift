import Foundation

/// Main application coordinator that wires all services together
actor DaemonApp {
    private let config: DaemonConfig
    private let server: WebSocketServer
    private let claudeClient: ClaudeAPIClient
    private var llmProvider: any LLMProvider
    private let mcpManager: MCPManager
    private let conversationStore: ConversationStore
    private let skillStore: SkillStore

    // Workflow subsystem
    private let workflowStore: WorkflowStore
    private let workflowExecutor: WorkflowExecutor
    private let workflowQueue: WorkflowQueue
    private let workflowScheduler: WorkflowScheduler
    private let notificationService: NotificationService
    private let eventBus: EventBus

    // Image server for serving generated/attached images to the iOS app
    private let imageServer: ImageServer
    private let generatedImagesDirectory: String

    // Email subsystem
    private let emailConfigStore: EmailConfigStore
    private let emailTriggerStore: EmailTriggerStore
    private let attachmentProcessor: AttachmentProcessor
    private var agentMailClient: AgentMailClient?
    private var emailPollingService: EmailPollingService?
    private var emailConversationBridge: EmailConversationBridge?
    private var emailApprovalStore: EmailApprovalStore?

    // Prompt enhancement pipeline
    private let promptEnhancer: PromptEnhancer

    // Ollama health check
    private var ollamaHealthTask: Task<Void, Never>?

    // Active generation task tracking for cancellation
    private var activeGenerationTasks: [String: Task<Void, Never>] = [:]

    // Startup time for health endpoint uptime calculation
    private let startedAt = Date()

    init(config: DaemonConfig) {
        self.config = config
        self.server = WebSocketServer(port: config.port)
        self.claudeClient = ClaudeAPIClient(config: config)
        self.llmProvider = ClaudeAPIClient(config: config)  // Default; overridden in start() if Ollama configured
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

        // Image server for generated/attached images
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let basePath = "\(homeDir)/.solace"
        self.generatedImagesDirectory = "\(basePath)/generated"
        self.imageServer = ImageServer(port: 9201, imageDirectory: "\(basePath)/generated")

        // Email components
        self.emailConfigStore = EmailConfigStore(basePath: basePath)
        self.emailTriggerStore = EmailTriggerStore(basePath: basePath)
        self.attachmentProcessor = AttachmentProcessor(basePath: basePath)

        // Prompt enhancement pipeline
        self.promptEnhancer = PromptEnhancer(llmProvider: claudeClient, mcpManager: mcpManager)

        // Executor needs mcpManager, store, and eventBus for decoupling
        self.workflowExecutor = WorkflowExecutor(mcpManager: mcpManager, store: workflowStore, eventBus: eventBus, llmProvider: claudeClient)

        // Queue manages concurrent execution with priority-based scheduling
        self.workflowQueue = WorkflowQueue(workflowExecutor: self.workflowExecutor, maxConcurrent: 5)

        // Scheduler fires workflow executions through the queue with low priority
        let queue = self.workflowQueue
        let notifService = self.notificationService

        self.workflowScheduler = WorkflowScheduler { workflow in
            await queue.enqueue(
                workflow: workflow,
                triggerInfo: "cron: \(workflow.trigger)",
                priority: .low,
                onComplete: { execution in
                    switch execution.status {
                    case .completed:
                        await notifService.notifyWorkflowCompleted(execution: execution, prefs: workflow.notificationPrefs)
                    case .failed:
                        await notifService.notifyWorkflowFailed(execution: execution, prefs: workflow.notificationPrefs)
                    default:
                        break
                    }
                }
            )
        }
    }

    /// Start all services
    func start() async throws {
        // Ensure directories exist
        try config.ensureDirectories()

        // Initialize the LLM provider based on config
        await initializeProvider()

        // Start image server for serving generated/attached images
        try await imageServer.start()

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
                    let queue = self.workflowQueue
                    let notifService = self.notificationService
                    await eventBus.subscribe(source: source, eventType: eventType, id: workflow.id) { _ in
                        await queue.enqueue(
                            workflow: workflow,
                            triggerInfo: "event: \(source):\(eventType)",
                            priority: .normal,
                            onComplete: { execution in
                                switch execution.status {
                                case .completed:
                                    await notifService.notifyWorkflowCompleted(execution: execution, prefs: workflow.notificationPrefs)
                                case .failed:
                                    await notifService.notifyWorkflowFailed(execution: execution, prefs: workflow.notificationPrefs)
                                default:
                                    break
                                }
                            }
                        )
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

    /// Stop all services with graceful cleanup
    func stop() async {
        Logger.info("Shutting down... cancelling active generation tasks")
        for (convId, task) in activeGenerationTasks {
            task.cancel()
            Logger.info("  Cancelled generation for conversation \(convId)")
        }
        activeGenerationTasks.removeAll()

        Logger.info("Shutting down... stopping Ollama health check")
        ollamaHealthTask?.cancel()
        ollamaHealthTask = nil

        Logger.info("Shutting down... stopping email polling")
        await emailPollingService?.stop()

        Logger.info("Shutting down... removing scheduled workflows")
        await workflowScheduler.removeAll()

        Logger.info("Shutting down... closing WebSocket clients")
        await server.stop()

        Logger.info("Shutting down... stopping MCP servers")
        await mcpManager.stopAll()

        Logger.info("Daemon stopped cleanly")
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: WSMessage, from client: WebSocketClient) async {
        switch message.type {
        case WSMessageType.ping:
            await handlePing(client: client)

        case WSMessageType.userMessage:
            await handleUserMessage(message, client: client)

        case WSMessageType.cancelGeneration:
            await handleCancelGeneration(message, client: client)

        case WSMessageType.newConversation:
            await handleNewConversation(client: client)

        case WSMessageType.loadConversation:
            await handleLoadConversation(message, client: client)

        case WSMessageType.deleteConversation:
            await handleDeleteConversation(message, client: client)

        case WSMessageType.listConversations:
            await handleListConversations(client: client)

        case WSMessageType.editMessage:
            await handleEditMessage(message, client: client)

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

        // MCP Server Management messages
        case WSMessageType.mcpServersList:
            await handleMCPServersList(client: client)

        case WSMessageType.mcpServerToggle:
            await handleMCPServerToggle(message, client: client)

        // Provider Management messages
        case WSMessageType.getProviders:
            await handleGetProviders(client: client)

        case WSMessageType.setProvider:
            await handleSetProvider(message, client: client)

        // Health
        case WSMessageType.getHealth:
            await handleGetHealth(client: client)

        // Ambient Listening
        case WSMessageType.ambientAnalyze:
            await handleAmbientAnalyze(message, client: client)

        case WSMessageType.ambientActionApprove:
            await handleAmbientActionApprove(message, client: client)

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

        // US-014: Reject duplicate messages while generation is active for this conversation
        if activeGenerationTasks[conversationId] != nil {
            Logger.info("Ignoring duplicate userMessage for conversation \(conversationId) — generation already active")
            let msg = WSMessage(
                type: WSMessageType.error,
                conversationId: conversationId,
                content: "Waiting for response...",
                metadata: ["code": .string("GENERATION_ACTIVE")]
            )
            try? await client.send(msg)
            return
        }

        let content = message.content ?? ""
        let hasAttachments: Bool
        if case .array(let arr) = message.metadata?["attachments"], !arr.isEmpty {
            hasAttachments = true
        } else {
            hasAttachments = false
        }
        guard !content.isEmpty || hasAttachments else {
            await sendError(to: client, message: "Missing message content", code: "MISSING_FIELD")
            return
        }

        // Check for API key (only required for Claude provider)
        if llmProvider.providerName == "Claude" {
            guard config.apiKey != nil else {
                await sendError(
                    to: client,
                    message: "No ANTHROPIC_API_KEY configured. Set the environment variable and restart the daemon.",
                    code: "NO_API_KEY"
                )
                return
            }
        }

        // Process attachments (images and audio) if present
        var msgMetadata: [String: String]? = nil
        if case .array(let attachments) = message.metadata?["attachments"] {
            var savedFilenames: [String] = []
            for attachment in attachments {
                guard case .object(let att) = attachment,
                      let b64Data = att["data"]?.stringValue,
                      let mimeType = att["mimeType"]?.stringValue else { continue }
                if let filename = AttachmentFileHelper.saveBase64File(
                    data: b64Data, mimeType: mimeType, directory: generatedImagesDirectory
                ) {
                    savedFilenames.append(filename)
                }
            }
            if !savedFilenames.isEmpty {
                msgMetadata = ["attachmentFiles": savedFilenames.joined(separator: ",")]
            }
        }

        // Save user message to conversation
        let userMsg = StoredMessage(role: "user", content: content, metadata: msgMetadata)
        do {
            _ = try await conversationStore.addMessage(to: conversationId, message: userMsg)
        } catch {
            await sendError(to: client, message: "Failed to save message: \(error)", code: "STORAGE_ERROR")
            return
        }

        // Start the LLM streaming loop in a trackable task for cancellation
        let task = Task { [weak self] in
            guard let self else { return }
            await self.streamLLMResponse(conversationId: conversationId, client: client)
            await self.removeGenerationTask(conversationId: conversationId)
        }
        activeGenerationTasks[conversationId] = task
    }

    private func removeGenerationTask(conversationId: String) {
        activeGenerationTasks.removeValue(forKey: conversationId)
    }

    private func handleCancelGeneration(_ message: WSMessage, client: WebSocketClient) async {
        guard let conversationId = message.conversationId else {
            await sendError(to: client, message: "Missing conversationId", code: "MISSING_FIELD")
            return
        }

        if let task = activeGenerationTasks[conversationId] {
            Logger.info("Cancelling generation for conversation \(conversationId)")
            task.cancel()
            activeGenerationTasks.removeValue(forKey: conversationId)

            // Send assistant_done to cleanly end the stream on the client
            let done = WSMessage(
                type: WSMessageType.assistantDone,
                conversationId: conversationId,
                metadata: ["cancelled": .bool(true)]
            )
            try? await client.send(done)
        } else {
            Logger.info("Cancel requested for conversation \(conversationId) but no active generation")
        }
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

    private func streamLLMResponse(conversationId: String, client: WebSocketClient) async {
        do {
            // Build messages from conversation history
            let apiMessages = try await conversationStore.buildAPIMessages(conversationId: conversationId)
            var tools = await mcpManager.getToolDefinitions()

            // Built-in create_workflow tool — allows Claude to build workflows from chat
            if !tools.contains(where: { $0.name == "create_workflow" }) {
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
            }

            var systemPrompt = await buildSystemPrompt()

            // Only pass tools if provider supports them
            var effectiveTools = llmProvider.supportsTools ? tools : []

            // Augment system prompt for Ollama with text-based tool call instructions
            if llmProvider.providerName == "Ollama" && !effectiveTools.isEmpty {
                // Strip create_workflow from both the prompt AND the native tools array —
                // Ollama models latch onto it because it's the simplest tool (just a description string)
                effectiveTools = effectiveTools.filter { $0.name != "create_workflow" }
                let toolList = effectiveTools.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
                systemPrompt += """

                \n\n# Tool Usage Instructions

                You have access to the following tools:
                \(toolList)

                When you want to use a tool, you MUST output a tool call block in this EXACT format:

                <tool_call>
                {"name": "tool_name", "arguments": {"param": "value"}}
                </tool_call>

                CRITICAL RULES:
                - Only use a tool when the user explicitly asks you to perform an action that requires it.
                - Do NOT describe how to use tools or explain what you would do. Actually invoke them using the format above.
                - You may use multiple <tool_call> blocks in one response.
                - After outputting tool call blocks, STOP and wait for tool results before continuing.
                - Tool results will be provided to you in follow-up messages.
                - Always use the exact tool names listed above.
                - For normal conversation, just respond naturally without using tools.
                """
            }

            Logger.info("Calling \(llmProvider.providerName) API: \(apiMessages.count) messages, \(effectiveTools.count) tools")

            let stream = await llmProvider.streamRequest(
                messages: apiMessages,
                tools: effectiveTools,
                systemPrompt: systemPrompt
            )

            Logger.info("Stream created, starting iteration")

            var fullTextChunks: [String] = []
            var fullThinkingChunks: [String] = []
            var thinkingStartTime: Date?
            var pendingToolCalls: [(id: String, name: String, input: String)] = []
            var hasToolCalls = false

            for try await event in stream {
                // Check for cancellation between stream events
                if Task.isCancelled {
                    Logger.info("streamLLMResponse: cancelled for conversation \(conversationId)")
                    // Save partial response if any text was generated
                    if !fullTextChunks.isEmpty {
                        let partialMsg = StoredMessage(role: "assistant", content: fullTextChunks.joined() + "\n\n[Generation cancelled]")
                        _ = try? await conversationStore.addMessage(to: conversationId, message: partialMsg)
                    }
                    return
                }

                switch event {
                case .thinkingStart:
                    thinkingStartTime = Date()

                case .thinkingDelta(let chunk):
                    fullThinkingChunks.append(chunk)
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
                    fullTextChunks.append(chunk)
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
                    // Send assistantDone so client resets streaming state
                    let doneMsg = WSMessage(
                        type: WSMessageType.assistantDone,
                        conversationId: conversationId,
                        metadata: ["error": .bool(true)]
                    )
                    try? await client.send(doneMsg)
                    return
                }
            }

            // Join accumulated chunks (O(n) instead of O(n²) concatenation)
            let fullText = fullTextChunks.joined()

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
                    // Check for cancellation before each tool execution
                    if Task.isCancelled {
                        Logger.info("streamLLMResponse: cancelled during tool execution for conversation \(conversationId)")
                        return
                    }

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

                        var doneMeta: [String: MetadataValue] = [
                            "toolName": .string(toolCall.name),
                            "serverName": .string(serverName),
                            "success": .bool(!result.isError),
                            "result": .string(clientResult),
                            "duration": .double(duration)
                        ]

                        // Extract image URL from tool results for inline display
                        if let imageURL = Self.extractImageURL(from: result.content) {
                            doneMeta["imageURL"] = .string(imageURL)
                        }

                        let doneMsg = WSMessage(
                            type: WSMessageType.toolCallDone,
                            id: toolCall.id,
                            conversationId: conversationId,
                            metadata: doneMeta
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
                await streamLLMResponse(conversationId: conversationId, client: client)
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

    // MARK: - Edit Message

    private func handleEditMessage(_ message: WSMessage, client: WebSocketClient) async {
        guard let conversationId = message.conversationId,
              let originalContent = message.metadata?["originalContent"]?.stringValue,
              let newContent = message.content else {
            await sendError(to: client, message: "Missing edit parameters", code: "MISSING_FIELD")
            return
        }

        do {
            let _ = try await conversationStore.editMessage(
                conversationId: conversationId,
                originalContent: originalContent,
                newContent: newContent
            )

            // Confirm the edit
            let confirmMsg = WSMessage(
                type: WSMessageType.messageEdited,
                conversationId: conversationId,
                metadata: [
                    "originalContent": .string(originalContent),
                    "newContent": .string(newContent)
                ]
            )
            try? await client.send(confirmMsg)

            // Re-generate assistant response
            await streamLLMResponse(conversationId: conversationId, client: client)
        } catch {
            await sendError(to: client, message: "Failed to edit message: \(error)", code: "EDIT_ERROR")
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
                    let queue = self.workflowQueue
                    let notifService = self.notificationService
                    await eventBus.subscribe(source: source, eventType: eventType, id: workflow.id) { _ in
                        await queue.enqueue(
                            workflow: workflow,
                            triggerInfo: "event: \(source):\(eventType)",
                            priority: .normal,
                            onComplete: { execution in
                                switch execution.status {
                                case .completed:
                                    await notifService.notifyWorkflowCompleted(execution: execution, prefs: workflow.notificationPrefs)
                                case .failed:
                                    await notifService.notifyWorkflowFailed(execution: execution, prefs: workflow.notificationPrefs)
                                default:
                                    break
                                }
                            }
                        )
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
                    let queue = self.workflowQueue
                    let notifService = self.notificationService
                    await eventBus.subscribe(source: source, eventType: eventType, id: workflow.id) { _ in
                        await queue.enqueue(
                            workflow: workflow,
                            triggerInfo: "event: \(source):\(eventType)",
                            priority: .normal,
                            onComplete: { execution in
                                switch execution.status {
                                case .completed:
                                    await notifService.notifyWorkflowCompleted(execution: execution, prefs: workflow.notificationPrefs)
                                case .failed:
                                    await notifService.notifyWorkflowFailed(execution: execution, prefs: workflow.notificationPrefs)
                                default:
                                    break
                                }
                            }
                        )
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

            // Enqueue with normal priority (user-initiated)
            await workflowQueue.enqueue(
                workflow: workflow,
                triggerInfo: "manual",
                inputParams: inputParams,
                priority: .normal,
                onComplete: { execution in
                    switch execution.status {
                    case .completed:
                        await self.notificationService.notifyWorkflowCompleted(execution: execution, prefs: workflow.notificationPrefs)
                    case .failed:
                        await self.notificationService.notifyWorkflowFailed(execution: execution, prefs: workflow.notificationPrefs)
                    default:
                        break
                    }
                }
            )
        } catch {
            await sendError(to: client, message: "Failed to run workflow: \(error)", code: "STORAGE_ERROR")
        }
    }

    private func handleCancelWorkflow(_ message: WSMessage, client: WebSocketClient) async {
        guard let executionId = message.id ?? message.metadata?["executionId"]?.stringValue else {
            await sendError(to: client, message: "Missing executionId", code: "MISSING_FIELD")
            return
        }

        await workflowQueue.cancel(executionId: executionId)
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

        // Flatten step fields into top-level metadata (app expects meta["stepId"], not nested)
        var metadata: [String: MetadataValue] = [
            "executionId": .string(execution.id),
            "workflowId": .string(execution.workflowId),
            "workflowName": .string(execution.workflowName)
        ]
        for (key, value) in stepDict {
            metadata[key] = value
        }

        let msg = WSMessage(
            type: WSMessageType.workflowStepUpdate,
            id: execution.id,
            metadata: metadata
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

        // Include steps array so app can populate execution UI immediately
        let stepsArray: [MetadataValue] = execution.stepResults.map { step in
            var stepDict: [String: MetadataValue] = [
                "id": .string(step.stepId),
                "stepName": .string(step.stepName),
                "status": .string(step.status.rawValue)
            ]
            if let startedAt = step.startedAt { stepDict["startedAt"] = .string(formatter.string(from: startedAt)) }
            if let completedAt = step.completedAt { stepDict["completedAt"] = .string(formatter.string(from: completedAt)) }
            if let output = step.output { stepDict["output"] = .string(output) }
            if let error = step.error { stepDict["error"] = .string(error) }
            return .object(stepDict)
        }
        dict["steps"] = .array(stepsArray)

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

        // Register email tools with MCPManager so workflows can use send_email, etc.
        let emailServer = EmailMCPServer(agentMailClient: client, attachmentProcessor: attachmentProcessor)
        let emailTools = await emailServer.getMCPToolInfos()
        await mcpManager.registerExternalTools(
            serverName: EmailMCPServer.serverName,
            tools: emailTools
        ) { name, arguments in
            try await emailServer.callTool(name: name, arguments: arguments)
        }

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let basePath = "\(homeDir)/.solace"

        let approvalStore = EmailApprovalStore(basePath: basePath)
        self.emailApprovalStore = approvalStore

        let bridge = EmailConversationBridge(
            triggerStore: emailTriggerStore,
            workflowStore: workflowStore,
            workflowQueue: workflowQueue,
            eventBus: eventBus,
            approvalStore: approvalStore,
            agentMailClient: client,
            attachmentProcessor: attachmentProcessor
        )
        self.emailConversationBridge = bridge

        // Wire the email classifier/summarizer using Claude
        let claudeClient = self.claudeClient
        await bridge.setClassifyEmail { emailText in
            let messages = [MessageParam(role: "user", text: emailText)]
            return try await claudeClient.singleRequest(
                messages: messages,
                systemPrompt: "You are an email analyzer. Respond only with the requested JSON."
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

        // Wire polling: create conversation first (get ID), then pass to bridge
        await polling.setOnEmailReceived { [weak self] (email: EmailMessage) in
            guard let self = self else { return }
            let conversationId = await self.createEmailConversation(email)
            await self.emailConversationBridge?.handleIncomingEmail(email, conversationId: conversationId)
        }

        await polling.start()
        Logger.info("Email subsystem started for \(emailConfig.emailAddress)")
    }

    // MARK: - Email → Chat Conversation
    /// Claude analysis continues in background after the ID is returned.
    @discardableResult
    private func createEmailConversation(_ email: EmailMessage) async -> String? {
        do {
            let conversation = try await conversationStore.create(
                title: "Email: \(email.subject)",
                sourceType: "email"
            )

            let conversationId = conversation.id

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
            _ = try await conversationStore.addMessage(to: conversationId, message: emailMsg)

            // Run Claude analysis in background (don't block the caller)
            let conversationStore = self.conversationStore
            let claudeClient = self.claudeClient
            let server = self.server
            let title = conversation.title
            Task {
                do {
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
                        systemPrompt: "You are a helpful AI assistant integrated into the Solace app. The user has received an email that was forwarded to you for analysis. Provide a concise analysis and offer to help."
                    )

                    let analysisMsg = StoredMessage(role: "assistant", content: analysis)
                    _ = try await conversationStore.addMessage(to: conversationId, message: analysisMsg)

                    let broadcastMsg = WSMessage(
                        type: WSMessageType.conversationCreated,
                        conversationId: conversationId,
                        metadata: [
                            "title": .string(title),
                            "sourceType": .string("email"),
                            "messageCount": .int(2)
                        ]
                    )
                    await server.broadcast(broadcastMsg)

                    Logger.info("Created email conversation '\(title)' (\(conversationId))")
                } catch {
                    Logger.error("Failed to complete email conversation analysis: \(error)")
                    // Still broadcast the conversation even if analysis failed
                    let broadcastMsg = WSMessage(
                        type: WSMessageType.conversationCreated,
                        conversationId: conversationId,
                        metadata: [
                            "title": .string(title),
                            "sourceType": .string("email"),
                            "messageCount": .int(1)
                        ]
                    )
                    await server.broadcast(broadcastMsg)
                }
            }

            return conversationId
        } catch {
            Logger.error("Failed to create email conversation: \(error)")
            return nil
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

        let rawInboxId = message.metadata?["inboxId"]?.stringValue ?? "solace"
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

        let action = message.metadata?["action"]?.stringValue

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

            switch action {
            case "chat":
                // Client handles navigation to the conversation — no server action needed
                Logger.info("Approval \(approvalId) approved for chat")

            case "auto_workflow":
                // Build workflow on-demand from email body, save, execute, reply
                await buildAndExecuteWorkflowForApproval(approval)

            case "save_auto_flow":
                // Build workflow, save trigger rule for future matching, execute for current email
                await buildAndSaveAutoFlow(approval)

            default:
                // Legacy fallback: route based on classification
                switch approval.classification {
                case .workflow:
                    await executeApprovedWorkflow(approval)
                case .simpleReply:
                    await sendSimpleReply(approval)
                case .noAction:
                    break
                }
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
            let approvalId = approval.id

            await workflowQueue.enqueue(
                workflow: workflow,
                triggerInfo: "email_approval: \(approval.email.subject)",
                priority: .high,
                onComplete: { execution in
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
            )
        } catch {
            Logger.error("Failed to load workflow for approval \(approval.id): \(error)")
        }
    }

    /// Builds a workflow on-demand from the email body text, saves it, executes it, and sends a reply.
    private func buildAndExecuteWorkflowForApproval(_ approval: PendingEmailApproval) async {
        // Broadcast "building" status so the app shows a spinner
        let buildingMsg = WSMessage(
            type: WSMessageType.emailAutoReplyStatus,
            id: approval.id,
            metadata: ["status": .string("building")]
        )
        await server.broadcast(buildingMsg)

        let prompt = """
        Analyze this email brief and create a workflow to accomplish what it describes.

        From: \(approval.email.from)
        Subject: \(approval.email.subject)
        Body:
        \(approval.email.bodyText)
        """

        do {
            guard let workflow = await buildWorkflowFromPrompt(prompt) else {
                Logger.error("buildWorkflowFromPrompt returned nil for approval \(approval.id)")
                try? await emailApprovalStore?.update(id: approval.id, status: .failed)
                let failMsg = WSMessage(
                    type: WSMessageType.emailAutoReplyStatus,
                    id: approval.id,
                    metadata: [
                        "status": .string("failed"),
                        "reason": .string("Failed to generate workflow from email")
                    ]
                )
                await server.broadcast(failMsg)
                return
            }

            try await workflowStore.create(workflow)

            // Broadcast workflow created
            let wfMsg = WSMessage(
                type: WSMessageType.workflowCreated,
                metadata: [
                    "workflowId": .string(workflow.id),
                    "name": .string(workflow.name),
                    "stepCount": .int(workflow.steps.count)
                ]
            )
            await server.broadcast(wfMsg)

            Logger.info("On-demand workflow '\(workflow.name)' created for approval \(approval.id)")

            let approvalId = approval.id

            await workflowQueue.enqueue(
                workflow: workflow,
                triggerInfo: "email_approval_auto: \(approval.email.subject)",
                priority: .high,
                onComplete: { execution in
                    switch execution.status {
                    case .completed:
                        Logger.info("On-demand workflow '\(workflow.name)' completed")
                        await self.composeAndSendReply(approval: approval, execution: execution)
                    case .failed:
                        Logger.error("On-demand workflow '\(workflow.name)' failed")
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
            )
        } catch {
            Logger.error("Failed to build workflow for approval \(approval.id): \(error)")
            try? await emailApprovalStore?.update(id: approval.id, status: .failed)
            let failMsg = WSMessage(
                type: WSMessageType.emailAutoReplyStatus,
                id: approval.id,
                metadata: [
                    "status": .string("failed"),
                    "reason": .string("Failed to build workflow: \(error.localizedDescription)")
                ]
            )
            await server.broadcast(failMsg)
        }
    }

    /// Builds a workflow from the email, saves it permanently, creates a trigger rule for future
    /// matching emails from the same sender, then executes the workflow and replies.
    private func buildAndSaveAutoFlow(_ approval: PendingEmailApproval) async {
        // Broadcast "building" status
        let buildingMsg = WSMessage(
            type: WSMessageType.emailAutoReplyStatus,
            id: approval.id,
            metadata: ["status": .string("building")]
        )
        await server.broadcast(buildingMsg)

        let prompt = """
        Analyze this email brief and create a reusable workflow to accomplish what it describes.
        This workflow will be saved and automatically triggered for future matching emails.

        From: \(approval.email.from)
        Subject: \(approval.email.subject)
        Body:
        \(approval.email.bodyText)
        """

        do {
            guard let workflow = await buildWorkflowFromPrompt(prompt) else {
                Logger.error("buildWorkflowFromPrompt returned nil for auto flow approval \(approval.id)")
                try? await emailApprovalStore?.update(id: approval.id, status: .failed)
                let failMsg = WSMessage(
                    type: WSMessageType.emailAutoReplyStatus,
                    id: approval.id,
                    metadata: [
                        "status": .string("failed"),
                        "reason": .string("Failed to generate workflow from email")
                    ]
                )
                await server.broadcast(failMsg)
                return
            }

            // Save the workflow
            try await workflowStore.create(workflow)

            let wfMsg = WSMessage(
                type: WSMessageType.workflowCreated,
                metadata: [
                    "workflowId": .string(workflow.id),
                    "name": .string(workflow.name),
                    "stepCount": .int(workflow.steps.count)
                ]
            )
            await server.broadcast(wfMsg)

            // Create a trigger rule matching the sender
            let triggerRule = EmailTriggerRule(
                workflowId: workflow.id,
                conditions: EmailTriggerConditions(fromContains: approval.email.from)
            )

            try await emailTriggerStore.create(triggerRule)

            let triggerMsg = WSMessage(
                type: WSMessageType.emailTriggerCreated,
                id: triggerRule.id,
                metadata: [
                    "id": .string(triggerRule.id),
                    "workflowId": .string(workflow.id),
                    "workflowName": .string(workflow.name),
                    "fromContains": .string(approval.email.from),
                    "enabled": .bool(true),
                    "success": .bool(true)
                ]
            )
            await server.broadcast(triggerMsg)

            Logger.info("Auto flow created: workflow '\(workflow.name)' + trigger rule for '\(approval.email.from)'")

            // Execute the workflow for the current email
            let approvalId = approval.id

            await workflowQueue.enqueue(
                workflow: workflow,
                triggerInfo: "email_auto_flow: \(approval.email.subject)",
                priority: .high,
                onComplete: { execution in
                    switch execution.status {
                    case .completed:
                        Logger.info("Auto flow workflow '\(workflow.name)' completed")
                        await self.composeAndSendReply(approval: approval, execution: execution)
                    case .failed:
                        Logger.error("Auto flow workflow '\(workflow.name)' failed")
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
            )
        } catch {
            Logger.error("Failed to build auto flow for approval \(approval.id): \(error)")
            try? await emailApprovalStore?.update(id: approval.id, status: .failed)
            let failMsg = WSMessage(
                type: WSMessageType.emailAutoReplyStatus,
                id: approval.id,
                metadata: [
                    "status": .string("failed"),
                    "reason": .string("Failed to create auto flow: \(error.localizedDescription)")
                ]
            )
            await server.broadcast(failMsg)
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
        if let convId = approval.conversationId { meta["conversationId"] = .string(convId) }
        if let summary = approval.summary { meta["summary"] = .string(summary) }
        if let rec = approval.recommendation { meta["recommendation"] = .string(rec) }
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
                "inputSchema": metadataFromJSON(tool.inputSchema),
                "outputType": .string(tool.outputType.rawValue),
                "acceptsInputTypes": .array(tool.acceptsInputTypes.map { .string($0.rawValue) })
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

        if llmProvider.providerName == "Claude" {
            guard config.apiKey != nil else {
                await sendError(to: client, message: "No ANTHROPIC_API_KEY configured", code: "NO_API_KEY")
                return
            }
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
        You are a workflow builder for the Solace automation system. The user will describe a workflow in natural language. You must generate a valid workflow JSON object.

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
              "id": "step_1",
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

        Step variable references:
        - Give each step a short id like "step_1", "step_2", etc.
        - To reference a previous step's output, use {{step_id.$}} (the $ means the entire output)
        - To reference a specific JSON field from a previous step, use {{step_id.field_name}}
        - Example: if step_1 produces search results, step_2 can use {{step_1.$}} to get all results
        - For runtime input parameters (manual trigger), use {{__input__.param_name}}

        Rules:
        - CRITICAL: Only use tools that exist in the catalog above. NEVER invent tool names.
        - If no matching tool exists for a capability the user needs, set needsConfiguration to true and explain in the step name what tool is needed
        - Steps are linear (executed top-to-bottom in sequence)
        - Use the user's language for step names (human-readable)
        - Keep step count minimal — only what the user described
        - IMPORTANT: Always include the "inputs" object with all required parameters for each tool
        - Generate creative, sensible default values for inputs based on what the user asked for
        - For code execution tools, write the actual code that accomplishes the user's goal
        """

        let userMessage = MessageParam(role: "user", text: prompt)

        do {
            let responseText = try await llmProvider.singleRequest(
                messages: [userMessage],
                systemPrompt: systemPrompt
            )

            // Strip markdown fences if LLM wrapped the JSON
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
                let id: String?
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
            // Map AI-generated step IDs to UUIDs so template references like {{step_1.$}} resolve correctly
            let workflowId = UUID().uuidString
            var aiIdToUUID: [String: String] = [:]
            for (index, aiStep) in aiWorkflow.steps.enumerated() {
                let aiId = aiStep.id ?? "step_\(index)"
                aiIdToUUID[aiId] = UUID().uuidString
            }
            var stepMetadata: [MetadataValue] = []
            var previousStepId: String?

            for (index, aiStep) in aiWorkflow.steps.enumerated() {
                let aiId = aiStep.id ?? "step_\(index)"
                let stepId = aiIdToUUID[aiId]!
                var stepDict: [String: MetadataValue] = [
                    "id": .string(stepId),
                    "name": .string(aiStep.name),
                    "toolName": .string(aiStep.toolName),
                    "serverName": .string(aiStep.serverName),
                    "onError": .string("stop"),
                    "needsConfiguration": .bool(aiStep.needsConfiguration ?? false)
                ]

                // Include AI-generated inputs (convert JSONValue -> string for MetadataValue)
                // Remap AI step IDs to UUIDs in template references like {{step_1.$}}
                if let inputs = aiStep.inputs, !inputs.isEmpty {
                    var inputDict: [String: MetadataValue] = [:]
                    for (key, value) in inputs {
                        var strValue: String
                        switch value {
                        case .string(let str):
                            strValue = str
                        case .int(let num):
                            strValue = String(num)
                        case .double(let num):
                            strValue = String(num)
                        case .bool(let b):
                            strValue = String(b)
                        default:
                            strValue = value.toJSONString()
                        }
                        // Replace AI step IDs with UUIDs in template references
                        for (aiStepId, uuid) in aiIdToUUID {
                            strValue = strValue.replacingOccurrences(of: "{{\(aiStepId).", with: "{{\(uuid).")
                        }
                        inputDict[key] = .string(strValue)
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

    // MARK: - MCP Server Management

    private func handleMCPServersList(client: WebSocketClient) async {
        let servers = await mcpManager.getServerInfoList()
        let items = servers.map { server -> MetadataValue in
            .object([
                "name": .string(server.name),
                "type": .string(server.isStdio ? "stdio" : "http"),
                "enabled": .bool(server.enabled),
                "toolCount": .int(server.toolCount)
            ])
        }
        let msg = WSMessage(
            type: WSMessageType.mcpServersListResult,
            metadata: ["servers": .array(items)]
        )
        try? await client.send(msg)
    }

    private func handleMCPServerToggle(_ message: WSMessage, client: WebSocketClient) async {
        guard let serverName = message.metadata?["serverName"]?.stringValue else {
            await sendError(to: client, message: "Missing serverName", code: "MISSING_FIELD")
            return
        }
        guard let enabled = message.metadata?["enabled"]?.boolValue else {
            await sendError(to: client, message: "Missing enabled", code: "MISSING_FIELD")
            return
        }

        // Update in-memory state
        await mcpManager.setServerEnabled(serverName, enabled)

        // Persist to mcp.json (using JSONSerialization to preserve all fields)
        let configPath = config.mcpConfigPath
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            if var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               var servers = root["mcpServers"] as? [String: Any],
               var serverDict = servers[serverName] as? [String: Any] {
                serverDict["enabled"] = enabled
                servers[serverName] = serverDict
                root["mcpServers"] = servers
                let updatedData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
                try updatedData.write(to: URL(fileURLWithPath: configPath))
                Logger.info("Persisted enabled=\(enabled) for MCP server '\(serverName)' to mcp.json")
            }
        } catch {
            Logger.error("Failed to persist MCP server toggle to config: \(error)")
        }

        // Send confirmation to requesting client
        let confirmMsg = WSMessage(
            type: WSMessageType.mcpServerToggleResult,
            metadata: [
                "serverName": .string(serverName),
                "enabled": .bool(enabled)
            ]
        )
        try? await client.send(confirmMsg)

        // Broadcast updated status to all clients (toolCount reflects new enabled state)
        let toolCount = await mcpManager.toolCount
        let workflowCount: Int
        do {
            workflowCount = try await workflowStore.listAll().count
        } catch {
            workflowCount = 0
        }

        let emailConfig = await emailConfigStore.load()

        var statusMetadata: [String: MetadataValue] = [
            "connected": .bool(true),
            "hasApiKey": .bool(config.apiKey != nil),
            "toolCount": .int(toolCount),
            "workflowCount": .int(workflowCount),
            "daemonVersion": .string(config.daemonVersion),
            "emailConfigured": .bool(emailConfig != nil)
        ]
        if let emailConfig = emailConfig {
            statusMetadata["emailAddress"] = .string(emailConfig.emailAddress)
        }

        let statusMsg = WSMessage(
            type: WSMessageType.status,
            metadata: statusMetadata
        )
        await server.broadcast(statusMsg)
    }

    // MARK: - Shared Workflow Builder

    /// Build a workflow from a natural language prompt using Claude.
    /// Shared between handleBuildWorkflow (WebSocket) and EmailConversationBridge (email briefs).
    func buildWorkflowFromPrompt(_ prompt: String) async -> WorkflowDefinition? {
        // Workflow generation requires LLM — check appropriate key
        if llmProvider.providerName == "Claude" && config.apiKey == nil {
            Logger.error("buildWorkflowFromPrompt: No ANTHROPIC_API_KEY configured")
            return nil
        }

        // Enhance the prompt via the multi-agent pipeline (Claude only — too slow for local/alternative models)
        let originalPrompt = prompt
        var effectivePrompt = prompt
        var enhancedPromptText: String? = nil

        if llmProvider.providerName == "Claude" {
            do {
                let result = try await promptEnhancer.enhance(prompt: prompt)
                effectivePrompt = result.enhancedPrompt
                enhancedPromptText = result.enhancedPrompt
                Logger.info("buildWorkflowFromPrompt: Using enhanced prompt (\(effectivePrompt.count) chars)")
            } catch {
                Logger.error("buildWorkflowFromPrompt: Enhancement failed, using original prompt: \(error)")
            }
        } else {
            Logger.info("buildWorkflowFromPrompt: Skipping enhancement for \(llmProvider.providerName) (non-Claude provider)")
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
        You are a workflow builder for the Solace automation system. The user will describe a workflow in natural language. You must generate a valid workflow JSON object.

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
              "id": "step_1",
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

        Step variable references:
        - Give each step a short id like "step_1", "step_2", etc.
        - To reference a previous step's output, use {{step_id.$}} (the $ means the entire output)
        - To reference a specific JSON field from a previous step, use {{step_id.field_name}}
        - Example: if step_1 produces search results, step_2 can use {{step_1.$}} to get all results
        - For runtime input parameters (manual trigger), use {{__input__.param_name}}

        Rules:
        - CRITICAL: Only use tools that exist in the catalog above. NEVER invent tool names.
        - If no matching tool exists for a capability the user needs, set needsConfiguration to true and explain in the step name what tool is needed
        - Steps are linear (executed top-to-bottom in sequence)
        - Use the user's language for step names (human-readable)
        - Keep step count minimal — only what the user described
        - IMPORTANT: Always include the "inputs" object with all required parameters for each tool
        - Generate creative, sensible default values for inputs based on what the user asked for
        - For code execution tools, write the actual code that accomplishes the user's goal
        """

        let userMessage = MessageParam(role: "user", text: effectivePrompt)

        do {
            let responseText = try await llmProvider.singleRequest(
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
                let id: String?
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

            // Map AI-generated step IDs to UUIDs so template references resolve correctly
            var aiIdToUUID: [String: String] = [:]
            for (index, aiStep) in aiWorkflow.steps.enumerated() {
                let aiId = aiStep.id ?? "step_\(index)"
                aiIdToUUID[aiId] = UUID().uuidString
            }

            var steps: [WorkflowStep] = []
            var previousStepId: String?

            for (index, aiStep) in aiWorkflow.steps.enumerated() {
                let aiId = aiStep.id ?? "step_\(index)"
                let stepId = aiIdToUUID[aiId]!
                var inputTemplate: [String: StringOrVariable] = [:]

                if let inputs = aiStep.inputs {
                    for (key, value) in inputs {
                        switch value {
                        case .string(var str):
                            // Remap AI step IDs to UUIDs in template references
                            for (aiStepId, uuid) in aiIdToUUID {
                                str = str.replacingOccurrences(of: "{{\(aiStepId).", with: "{{\(uuid).")
                            }
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
                    onError: .autofix
                ))
                previousStepId = stepId
            }

            return WorkflowDefinition(
                id: UUID().uuidString,
                name: aiWorkflow.name,
                description: aiWorkflow.description,
                enabled: true,
                trigger: trigger,
                steps: steps,
                originalPrompt: originalPrompt,
                enhancedPrompt: enhancedPromptText
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
            "emailConfigured": .bool(emailConfig != nil),
            "activeProvider": .string(llmProvider.providerName.lowercased()),
            "activeModel": .string(llmProvider.modelName)
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

    // MARK: - Health Endpoint

    private func handleGetHealth(client: WebSocketClient) async {
        let toolCount = await mcpManager.toolCount
        let clientCount = await server.clientCount
        let mcpStatuses = await mcpManager.serverStatuses()
        let uptime = Date().timeIntervalSince(startedAt)

        // Get RSS memory usage (in bytes)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        let rssBytes = result == KERN_SUCCESS ? Int(info.resident_size) : 0

        let mcpStatusArray = mcpStatuses.map { status -> MetadataValue in
            .object([
                "name": .string(status.name),
                "running": .bool(status.running),
                "toolCount": .int(status.toolCount)
            ])
        }

        let msg = WSMessage(
            type: WSMessageType.healthResult,
            metadata: [
                "uptime": .double(uptime),
                "activeConnections": .int(clientCount),
                "activeProvider": .string(llmProvider.providerName.lowercased()),
                "activeModel": .string(llmProvider.modelName),
                "toolCount": .int(toolCount),
                "activeGenerations": .int(activeGenerationTasks.count),
                "memoryRSSBytes": .int(rssBytes),
                "version": .string(DaemonConfig.version),
                "mcpServers": .array(mcpStatusArray)
            ]
        )
        try? await client.send(msg)
    }

    // MARK: - Ambient Listening

    private func handleAmbientAnalyze(_ message: WSMessage, client: WebSocketClient) async {
        guard let transcript = message.content, !transcript.isEmpty else {
            await sendError(to: client, message: "Missing transcript content", code: "MISSING_FIELD")
            return
        }

        // Send "analyzing" indicator
        let analyzingMsg = WSMessage(type: WSMessageType.ambientAnalyzing)
        try? await client.send(analyzingMsg)

        let systemPrompt = """
        You are Solace, an AI assistant analyzing a transcript from ambient speech recognition. \
        The user has been speaking near their device and this text was captured.

        Analyze the transcript and generate actionable suggestions. For each suggestion, determine the best type:
        - "summary": Summarize what was discussed
        - "task": Create a task or to-do item from what was mentioned
        - "workflow": Suggest creating an automation workflow
        - "reminder": Set a reminder for something mentioned
        - "chat": Start a conversation about a topic that was discussed

        Output ONLY a valid JSON array (no markdown, no explanation) with this schema:
        [
          {
            "id": "unique_id",
            "type": "summary|task|workflow|reminder|chat",
            "title": "Short action title",
            "description": "Brief description of what this action would do",
            "actionPayload": "The specific content/prompt to use when executing this action",
            "confidence": 0.0 to 1.0
          }
        ]

        Rules:
        - Generate 1-3 suggestions, only include high-confidence ones (> 0.5)
        - If the transcript is too short or unclear, return an empty array []
        - Keep titles under 50 characters
        - The actionPayload should be the prompt/content needed to execute the action
        - For workflow type, the actionPayload should describe the workflow to create
        - For chat type, the actionPayload should be the opening message/question
        - For task/reminder, the actionPayload should be the task description
        """

        let userMessage = MessageParam(role: "user", text: "Transcript:\n\(transcript)")

        do {
            let responseText = try await llmProvider.singleRequest(
                messages: [userMessage],
                systemPrompt: systemPrompt
            )

            var cleaned = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.hasPrefix("```") {
                if let firstNewline = cleaned.firstIndex(of: "\n") {
                    cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
                }
                if cleaned.hasSuffix("```") {
                    cleaned = String(cleaned.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            guard let jsonData = cleaned.data(using: .utf8) else {
                Logger.error("Ambient analyze: invalid response")
                return
            }

            struct AISuggestion: Codable {
                let id: String
                let type: String
                let title: String
                let description: String
                let actionPayload: String
                let confidence: Double
            }

            let suggestions = try JSONDecoder().decode([AISuggestion].self, from: jsonData)

            let suggestionValues: [MetadataValue] = suggestions.map { s in
                .object([
                    "id": .string(s.id),
                    "type": .string(s.type),
                    "title": .string(s.title),
                    "description": .string(s.description),
                    "actionPayload": .string(s.actionPayload),
                    "confidence": .double(s.confidence)
                ])
            }

            let resultMsg = WSMessage(
                type: WSMessageType.ambientSuggestions,
                metadata: ["suggestions": .array(suggestionValues)]
            )
            try? await client.send(resultMsg)

        } catch {
            Logger.error("Ambient analyze failed: \(error)")
            // Send empty suggestions so client stops spinner
            let emptyMsg = WSMessage(
                type: WSMessageType.ambientSuggestions,
                metadata: ["suggestions": .array([])]
            )
            try? await client.send(emptyMsg)
        }
    }

    private func handleAmbientActionApprove(_ message: WSMessage, client: WebSocketClient) async {
        guard let suggestionId = message.id else {
            await sendError(to: client, message: "Missing suggestion ID", code: "MISSING_FIELD")
            return
        }

        let suggestionType = message.metadata?["type"]?.stringValue ?? "chat"
        let title = message.metadata?["title"]?.stringValue ?? ""
        let actionPayload = message.metadata?["actionPayload"]?.stringValue ?? ""

        switch suggestionType {
        case "workflow":
            // Build and execute a workflow from the suggestion
            guard let workflow = await buildWorkflowFromPrompt(actionPayload) else {
                let failMsg = WSMessage(
                    type: WSMessageType.ambientActionResult,
                    id: suggestionId,
                    metadata: [
                        "success": .bool(false),
                        "error": .string("Failed to generate workflow")
                    ]
                )
                try? await client.send(failMsg)
                return
            }

            do {
                try await workflowStore.create(workflow)
                let wfMsg = WSMessage(
                    type: WSMessageType.workflowCreated,
                    metadata: [
                        "workflowId": .string(workflow.id),
                        "name": .string(workflow.name),
                        "stepCount": .int(workflow.steps.count)
                    ]
                )
                await server.broadcast(wfMsg)

                await workflowQueue.enqueue(
                    workflow: workflow,
                    triggerInfo: "ambient_listening: \(title)",
                    priority: .normal
                )

                let successMsg = WSMessage(
                    type: WSMessageType.ambientActionResult,
                    id: suggestionId,
                    metadata: [
                        "success": .bool(true),
                        "workflowId": .string(workflow.id)
                    ]
                )
                try? await client.send(successMsg)
            } catch {
                let failMsg = WSMessage(
                    type: WSMessageType.ambientActionResult,
                    id: suggestionId,
                    metadata: [
                        "success": .bool(false),
                        "error": .string("Failed to save workflow: \(error.localizedDescription)")
                    ]
                )
                try? await client.send(failMsg)
            }

        case "chat":
            // Create a new conversation and send the message
            do {
                let conversation = try await conversationStore.create()
                let createMsg = WSMessage(
                    type: WSMessageType.conversationCreated,
                    conversationId: conversation.id,
                    metadata: ["title": .string(title)]
                )
                try? await client.send(createMsg)

                // Send the action payload as a user message
                let userMsg = WSMessage(
                    type: WSMessageType.userMessage,
                    conversationId: conversation.id,
                    content: actionPayload
                )
                await handleUserMessage(userMsg, client: client)

                let successMsg = WSMessage(
                    type: WSMessageType.ambientActionResult,
                    id: suggestionId,
                    metadata: [
                        "success": .bool(true),
                        "conversationId": .string(conversation.id)
                    ]
                )
                try? await client.send(successMsg)
            } catch {
                let failMsg = WSMessage(
                    type: WSMessageType.ambientActionResult,
                    id: suggestionId,
                    metadata: [
                        "success": .bool(false),
                        "error": .string("Failed to create conversation: \(error.localizedDescription)")
                    ]
                )
                try? await client.send(failMsg)
            }

        case "summary":
            // Summary is already displayed client-side, just acknowledge
            let successMsg = WSMessage(
                type: WSMessageType.ambientActionResult,
                id: suggestionId,
                metadata: ["success": .bool(true)]
            )
            try? await client.send(successMsg)

        case "task", "reminder":
            // Create a chat conversation with the task/reminder context
            do {
                let conversation = try await conversationStore.create()
                let createMsg = WSMessage(
                    type: WSMessageType.conversationCreated,
                    conversationId: conversation.id,
                    metadata: ["title": .string(title)]
                )
                try? await client.send(createMsg)

                let prompt = suggestionType == "reminder"
                    ? "Set a reminder: \(actionPayload)"
                    : "Create a task: \(actionPayload)"

                let userMsg = WSMessage(
                    type: WSMessageType.userMessage,
                    conversationId: conversation.id,
                    content: prompt
                )
                await handleUserMessage(userMsg, client: client)

                let successMsg = WSMessage(
                    type: WSMessageType.ambientActionResult,
                    id: suggestionId,
                    metadata: [
                        "success": .bool(true),
                        "conversationId": .string(conversation.id)
                    ]
                )
                try? await client.send(successMsg)
            } catch {
                let failMsg = WSMessage(
                    type: WSMessageType.ambientActionResult,
                    id: suggestionId,
                    metadata: [
                        "success": .bool(false),
                        "error": .string("Failed: \(error.localizedDescription)")
                    ]
                )
                try? await client.send(failMsg)
            }

        default:
            let failMsg = WSMessage(
                type: WSMessageType.ambientActionResult,
                id: suggestionId,
                metadata: [
                    "success": .bool(false),
                    "error": .string("Unknown suggestion type: \(suggestionType)")
                ]
            )
            try? await client.send(failMsg)
        }
    }

    // MARK: - Image URL Extraction

    /// Extract an image URL from tool result content for inline display in chat.
    /// Matches common image hosting URLs (Leonardo, CDN URLs, direct image links).
    private static func extractImageURL(from content: String) -> String? {
        // Match URLs ending in common image extensions or from known image CDNs
        let patterns = [
            // Direct image URLs (.png, .jpg, .jpeg, .webp, .gif)
            "https?://[^\\s\"'<>]+\\.(?:png|jpg|jpeg|webp|gif)(?:\\?[^\\s\"'<>]*)?",
            // Leonardo AI CDN URLs
            "https?://cdn\\.leonardo\\.ai/[^\\s\"'<>]+",
            // General CDN image URLs
            "https?://[^\\s\"'<>]*(?:image|img|photo|generated)[^\\s\"'<>]*\\.(?:png|jpg|jpeg|webp|gif)(?:\\?[^\\s\"'<>]*)?"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(content.startIndex..<content.endIndex, in: content)
                if let match = regex.firstMatch(in: content, range: range) {
                    if let matchRange = Range(match.range, in: content) {
                        return String(content[matchRange])
                    }
                }
            }
        }

        return nil
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
                    // Parse inputTemplate (also accept "inputs" key from AI builder)
                    var inputTemplate: [String: StringOrVariable] = [:]
                    if case .object(let inputDict) = stepDict["inputTemplate"] ?? stepDict["inputs"] {
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
                                // Detect {{...}} patterns and treat as templates
                                if strVal.contains("{{") && strVal.contains("}}") {
                                    inputTemplate[key] = .template(strVal)
                                } else {
                                    inputTemplate[key] = .literal(strVal)
                                }
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

    // MARK: - Provider Management

    /// Initialize the LLM provider based on config, with Ollama health check
    private func initializeProvider() async {
        if config.defaultProvider == "ollama", let ollamaConfig = config.ollamaConfig {
            let ollamaClient = OllamaAPIClient(
                endpoint: ollamaConfig.endpoint,
                model: ollamaConfig.model,
                apiKey: config.ollamaApiKey
            )

            // Check Ollama reachability
            let reachable = await ollamaClient.healthCheck()
            if reachable {
                llmProvider = ollamaClient
                Logger.info("Ollama provider active: \(ollamaConfig.model) at \(ollamaConfig.endpoint)")
            } else {
                Logger.error("Ollama unreachable at \(ollamaConfig.endpoint) — falling back to Claude")
                llmProvider = claudeClient

                // Broadcast fallback status to connected clients
                let statusMsg = WSMessage(
                    type: WSMessageType.status,
                    content: "Ollama unavailable, using Claude",
                    metadata: ["providerFallback": .bool(true)]
                )
                await server.broadcast(statusMsg)

                // Start periodic health check to reconnect
                startOllamaHealthCheck(config: ollamaConfig)
            }
        } else if config.defaultProvider == "openai", let openaiKey = config.openaiApiKey {
            let openaiConfig = config.openaiConfig ?? OpenAIProviderConfig.default
            let openaiClient = OpenAIAPIClient(model: openaiConfig.model, apiKey: openaiKey)
            llmProvider = openaiClient
            Logger.info("OpenAI provider active: \(openaiConfig.model)")
        } else {
            llmProvider = claudeClient
            Logger.info("Claude provider active: \(config.claudeModel)")
        }
    }

    /// Periodic health check for Ollama when it was configured but unreachable
    private func startOllamaHealthCheck(config ollamaConfig: OllamaProviderConfig) {
        ollamaHealthTask?.cancel()
        ollamaHealthTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self = self else { return }

                let ollamaClient = OllamaAPIClient(
                    endpoint: ollamaConfig.endpoint,
                    model: ollamaConfig.model,
                    apiKey: self.config.ollamaApiKey
                )

                let reachable = await ollamaClient.healthCheck()
                if reachable {
                    await self.switchProvider(to: ollamaClient)
                    Logger.info("Ollama recovered — switched back to Ollama provider")

                    let statusMsg = WSMessage(
                        type: WSMessageType.providerUpdated,
                        metadata: [
                            "provider": .string("ollama"),
                            "model": .string(ollamaConfig.model),
                            "recovered": .bool(true)
                        ]
                    )
                    await self.server.broadcast(statusMsg)
                    return  // Stop health check loop
                }
            }
        }
    }

    /// Switch the active LLM provider at runtime
    private func switchProvider(to provider: any LLMProvider) {
        llmProvider = provider
        ollamaHealthTask?.cancel()
        ollamaHealthTask = nil
    }

    private func handleGetProviders(client: WebSocketClient) async {
        let ollamaConfig = config.ollamaConfig

        var providers: [[String: MetadataValue]] = []

        // Claude
        providers.append([
            "name": .string("claude"),
            "displayName": .string("Claude"),
            "model": .string(config.claudeModel),
            "active": .bool(llmProvider.providerName == "Claude"),
            "available": .bool(config.apiKey != nil)
        ])

        // Ollama
        if let ollamaConfig = ollamaConfig {
            let ollamaClient = OllamaAPIClient(
                endpoint: ollamaConfig.endpoint,
                model: ollamaConfig.model,
                apiKey: config.ollamaApiKey
            )
            let reachable = await ollamaClient.healthCheck()

            providers.append([
                "name": .string("ollama"),
                "displayName": .string("Ollama"),
                "model": .string(ollamaConfig.model),
                "endpoint": .string(ollamaConfig.endpoint),
                "active": .bool(llmProvider.providerName == "Ollama"),
                "available": .bool(reachable)
            ])
        } else {
            providers.append([
                "name": .string("ollama"),
                "displayName": .string("Ollama"),
                "model": .string(""),
                "endpoint": .string(OllamaProviderConfig.default.endpoint),
                "active": .bool(false),
                "available": .bool(false),
                "configured": .bool(false)
            ])
        }

        // OpenAI
        let openaiConfig = config.openaiConfig
        providers.append([
            "name": .string("openai"),
            "displayName": .string("OpenAI"),
            "model": .string(openaiConfig?.model ?? OpenAIProviderConfig.default.model),
            "active": .bool(llmProvider.providerName == "OpenAI"),
            "available": .bool(config.openaiApiKey != nil),
            "configured": .bool(config.openaiApiKey != nil)
        ])

        let msg = WSMessage(
            type: WSMessageType.providersStatus,
            metadata: [
                "default": .string(config.defaultProvider),
                "active": .string(llmProvider.providerName.lowercased()),
                "activeModel": .string(llmProvider.modelName),
                "providers": .array(providers.map { .object($0) })
            ]
        )
        try? await client.send(msg)
    }

    private func handleSetProvider(_ message: WSMessage, client: WebSocketClient) async {
        guard let providerName = message.metadata?["provider"]?.stringValue else {
            await sendError(to: client, message: "Missing provider name", code: "MISSING_FIELD")
            return
        }

        let endpoint = message.metadata?["endpoint"]?.stringValue
        let model = message.metadata?["model"]?.stringValue

        switch providerName {
        case "claude":
            switchProvider(to: claudeClient)

            // Update config
            let newConfig = ProviderConfig(
                defaultProvider: "claude",
                ollama: config.providerConfig.ollama,
                claude: ClaudeProviderConfig(model: config.claudeModel),
                openai: config.providerConfig.openai
            )
            try? DaemonConfig.saveProviderConfig(newConfig, path: config.providersConfigPath)

            let msg = WSMessage(
                type: WSMessageType.providerUpdated,
                metadata: [
                    "provider": .string("claude"),
                    "model": .string(config.claudeModel),
                    "success": .bool(true)
                ]
            )
            await server.broadcast(msg)

        case "ollama":
            let ollamaEndpoint = endpoint ?? config.ollamaConfig?.endpoint ?? OllamaProviderConfig.default.endpoint
            let ollamaModel = model ?? config.ollamaConfig?.model ?? OllamaProviderConfig.default.model

            let ollamaClient = OllamaAPIClient(
                endpoint: ollamaEndpoint,
                model: ollamaModel,
                apiKey: config.ollamaApiKey
            )

            let reachable = await ollamaClient.healthCheck()
            if reachable {
                switchProvider(to: ollamaClient)

                // Update config
                let newConfig = ProviderConfig(
                    defaultProvider: "ollama",
                    ollama: OllamaProviderConfig(endpoint: ollamaEndpoint, model: ollamaModel),
                    claude: config.providerConfig.claude,
                    openai: config.providerConfig.openai
                )
                try? DaemonConfig.saveProviderConfig(newConfig, path: config.providersConfigPath)

                let msg = WSMessage(
                    type: WSMessageType.providerUpdated,
                    metadata: [
                        "provider": .string("ollama"),
                        "model": .string(ollamaModel),
                        "endpoint": .string(ollamaEndpoint),
                        "success": .bool(true)
                    ]
                )
                await server.broadcast(msg)
            } else {
                let msg = WSMessage(
                    type: WSMessageType.providerUpdated,
                    metadata: [
                        "provider": .string("ollama"),
                        "success": .bool(false),
                        "error": .string("Ollama unreachable at \(ollamaEndpoint)")
                    ]
                )
                try? await client.send(msg)
            }

        case "openai":
            guard let openaiKey = config.openaiApiKey else {
                let msg = WSMessage(
                    type: WSMessageType.providerUpdated,
                    metadata: [
                        "provider": .string("openai"),
                        "success": .bool(false),
                        "error": .string("OPENAI_API_KEY not set in ~/.solace/.env")
                    ]
                )
                try? await client.send(msg)
                return
            }

            let openaiModel = model ?? config.openaiConfig?.model ?? OpenAIProviderConfig.default.model
            let openaiClient = OpenAIAPIClient(model: openaiModel, apiKey: openaiKey)
            switchProvider(to: openaiClient)

            // Update config
            let newConfig = ProviderConfig(
                defaultProvider: "openai",
                ollama: config.providerConfig.ollama,
                claude: config.providerConfig.claude,
                openai: OpenAIProviderConfig(model: openaiModel)
            )
            try? DaemonConfig.saveProviderConfig(newConfig, path: config.providersConfigPath)

            let msg = WSMessage(
                type: WSMessageType.providerUpdated,
                metadata: [
                    "provider": .string("openai"),
                    "model": .string(openaiModel),
                    "success": .bool(true)
                ]
            )
            await server.broadcast(msg)

        default:
            await sendError(to: client, message: "Unknown provider: \(providerName)", code: "UNKNOWN_PROVIDER")
        }
    }
}
