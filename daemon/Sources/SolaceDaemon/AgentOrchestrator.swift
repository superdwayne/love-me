import Foundation

/// Orchestrates agent plan execution: resolves dependency DAG, runs agents in parallel waves,
/// streams progress events, and supports recursive sub-agent spawning.
actor AgentOrchestrator {
    private let providerPool: ProviderPool
    private let mcpManager: MCPManager
    private let planStore: AgentPlanStore
    private let maxConcurrentAgents: Int
    private let maxNestingDepth: Int
    private let maxTotalAgents: Int

    /// Tracks total agent count across the entire execution tree
    private var totalAgentCount: Int = 0

    init(
        providerPool: ProviderPool,
        mcpManager: MCPManager,
        planStore: AgentPlanStore,
        maxConcurrentAgents: Int = 5,
        maxNestingDepth: Int = 3,
        maxTotalAgents: Int = 20
    ) {
        self.providerPool = providerPool
        self.mcpManager = mcpManager
        self.planStore = planStore
        self.maxConcurrentAgents = maxConcurrentAgents
        self.maxNestingDepth = maxNestingDepth
        self.maxTotalAgents = maxTotalAgents
    }

    // MARK: - Main Entry Point

    /// Execute an agent plan, streaming progress events via the onUpdate callback.
    func execute(
        plan: AgentPlan,
        nestingDepth: Int = 0,
        onUpdate: @escaping @Sendable (AgentUpdate) async -> Void
    ) async throws -> AgentExecution {
        // Create execution record
        var execution = AgentExecution(
            planId: plan.id,
            planName: plan.name,
            status: .running,
            agentResults: plan.agents.map { agent in
                AgentResult(
                    agentId: agent.id,
                    agentName: agent.name,
                    provider: agent.providerSpec.providerName,
                    model: agent.providerSpec.modelName
                )
            }
        )
        try? await planStore.saveExecution(execution)

        // Track total agents
        totalAgentCount += plan.agents.count
        if totalAgentCount > maxTotalAgents {
            execution.status = .failed
            execution.completedAt = Date()
            try? await planStore.saveExecution(execution)
            throw OrchestratorError.maxTotalAgentsExceeded(totalAgentCount, maxTotalAgents)
        }

        // Topological sort into dependency waves
        let waves: [[AgentTask]]
        do {
            waves = try topologicalSort(agents: plan.agents)
        } catch {
            execution.status = .failed
            execution.completedAt = Date()
            try? await planStore.saveExecution(execution)
            throw error
        }

        // Completed agent outputs for downstream context injection
        var agentOutputs: [String: String] = [:]

        // Execute waves sequentially, agents within each wave in parallel
        for wave in waves {
            if Task.isCancelled {
                execution.status = .cancelled
                execution.completedAt = Date()
                try? await planStore.saveExecution(execution)
                return execution
            }

            // Run agents in this wave concurrently, limited by maxConcurrentAgents
            let results = await withTaskGroup(of: (String, String?, String?).self) { group in
                var launched = 0
                var waveQueue = wave
                var collected: [(String, String?, String?)] = []

                // Launch initial batch
                while !waveQueue.isEmpty && launched < maxConcurrentAgents {
                    let agent = waveQueue.removeFirst()
                    launched += 1
                    let contextSnapshot = agentOutputs
                    let depth = nestingDepth

                    group.addTask {
                        do {
                            let output = try await self.runAgent(
                                agent,
                                context: self.buildAgentContext(agent, agentOutputs: contextSnapshot),
                                nestingDepth: depth,
                                onUpdate: onUpdate
                            )
                            return (agent.id, output, nil)
                        } catch {
                            return (agent.id, nil, error.localizedDescription)
                        }
                    }
                }

                // As agents complete, launch more from the queue
                for await result in group {
                    collected.append(result)
                    if !waveQueue.isEmpty {
                        let agent = waveQueue.removeFirst()
                        let contextSnapshot = agentOutputs
                        let depth = nestingDepth

                        group.addTask {
                            do {
                                let output = try await self.runAgent(
                                    agent,
                                    context: self.buildAgentContext(agent, agentOutputs: contextSnapshot),
                                    nestingDepth: depth,
                                    onUpdate: onUpdate
                                )
                                return (agent.id, output, nil)
                            } catch {
                                return (agent.id, nil, error.localizedDescription)
                            }
                        }
                    }
                }

                return collected
            }

            // Process wave results
            for (agentId, output, error) in results {
                if let idx = execution.agentResults.firstIndex(where: { $0.agentId == agentId }) {
                    if let output = output {
                        execution.agentResults[idx].status = .success
                        execution.agentResults[idx].output = output
                        execution.agentResults[idx].completedAt = Date()
                        agentOutputs[agentId] = output
                    } else {
                        execution.agentResults[idx].status = .error
                        execution.agentResults[idx].error = error ?? "Unknown error"
                        execution.agentResults[idx].completedAt = Date()
                    }
                }
            }

            // Persist after each wave
            try? await planStore.saveExecution(execution)
        }

        // Finalize execution
        let hasFailures = execution.agentResults.contains { $0.status == .error }
        execution.status = hasFailures ? .failed : .completed
        execution.completedAt = Date()
        try? await planStore.saveExecution(execution)

        return execution
    }

    // MARK: - Single Agent Runner

    /// Run a single agent as an isolated multi-turn conversation with scoped MCP tools.
    private func runAgent(
        _ task: AgentTask,
        context: String,
        nestingDepth: Int,
        onUpdate: @escaping @Sendable (AgentUpdate) async -> Void
    ) async throws -> String {
        // Create provider
        let provider: any LLMProvider
        do {
            provider = try await providerPool.provider(for: task.providerSpec)
        } catch {
            // Fallback to Claude Sonnet
            await onUpdate(.providerFallback(
                agentId: task.id,
                from: task.providerSpec.providerName,
                to: "Claude Sonnet",
                reason: error.localizedDescription
            ))
            let fallbackSpec = AgentProviderSpec(provider: .claude(model: "claude-sonnet-4-5-20250929"))
            provider = try await providerPool.provider(for: fallbackSpec)
        }

        await onUpdate(.agentStarted(
            agentId: task.id,
            agentName: task.name,
            provider: provider.providerName,
            model: provider.modelName
        ))

        // Build scoped tool definitions
        var tools = await scopedToolDefinitions(for: task)

        // Add spawn_agents tool if not at max nesting depth
        if nestingDepth < maxNestingDepth {
            tools.append(spawnAgentsTool())
        }

        // If provider doesn't support tools but task requires them, inject as text
        var systemPrompt = buildAgentSystemPrompt(task: task, context: context)
        var effectiveTools = tools
        if !provider.supportsTools && !tools.isEmpty {
            let toolList = tools.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
            systemPrompt += "\n\nAvailable tools:\n\(toolList)\n\nTo use a tool, describe the tool call in your response."
            effectiveTools = []
        }

        // Multi-turn conversation loop
        var messages: [MessageParam] = [
            MessageParam(role: "user", text: task.objective)
        ]
        var turnCount = 0
        var toolCallCount = 0
        var finalOutput = ""

        while turnCount < task.maxTurns {
            if Task.isCancelled { throw OrchestratorError.cancelled }
            turnCount += 1

            // Stream response
            let stream = await provider.streamRequest(
                messages: messages,
                tools: effectiveTools,
                systemPrompt: systemPrompt
            )

            var textChunks: [String] = []
            var thinkingChunks: [String] = []
            var pendingToolCalls: [(id: String, name: String, input: String)] = []
            var hasToolCalls = false

            for try await event in stream {
                if Task.isCancelled { throw OrchestratorError.cancelled }

                switch event {
                case .thinkingDelta(let chunk):
                    thinkingChunks.append(chunk)
                    await onUpdate(.agentThinking(agentId: task.id, text: chunk))

                case .textDelta(let chunk):
                    textChunks.append(chunk)
                    await onUpdate(.agentProgress(agentId: task.id, text: chunk))

                case .toolUseStart(_, let name):
                    hasToolCalls = true
                    let serverName = await mcpManager.serverForTool(name: name) ?? "built-in"
                    await onUpdate(.agentToolStart(agentId: task.id, tool: name, server: serverName))

                case .toolUseDone(let id, let name, let input):
                    pendingToolCalls.append((id: id, name: name, input: input))

                case .error(let errorMsg):
                    throw OrchestratorError.providerError(errorMsg)

                default:
                    break
                }
            }

            let fullText = textChunks.joined()
            let fullThinking = thinkingChunks.joined()

            // Build assistant message content blocks
            var assistantBlocks: [ContentBlock] = []
            if !fullThinking.isEmpty {
                assistantBlocks.append(.thinking(ThinkingContent(thinking: fullThinking)))
            }
            if !fullText.isEmpty {
                assistantBlocks.append(.text(TextContent(text: fullText)))
            }
            for tc in pendingToolCalls {
                let inputValue: JSONValue
                if let data = tc.input.data(using: .utf8),
                   let parsed = try? JSONDecoder().decode(JSONValue.self, from: data) {
                    inputValue = parsed
                } else {
                    inputValue = .string(tc.input)
                }
                assistantBlocks.append(.toolUse(ToolUseContent(id: tc.id, name: tc.name, input: inputValue)))
            }

            if !assistantBlocks.isEmpty {
                messages.append(MessageParam(role: "assistant", content: assistantBlocks))
            }

            // If no tool calls, we're done
            if !hasToolCalls || pendingToolCalls.isEmpty {
                finalOutput = fullText
                break
            }

            // Execute tool calls
            var toolResultBlocks: [ContentBlock] = []
            for toolCall in pendingToolCalls {
                if Task.isCancelled { throw OrchestratorError.cancelled }
                toolCallCount += 1

                let resultContent: String
                let isError: Bool

                // Intercept spawn_agents
                if toolCall.name == "spawn_agents" {
                    do {
                        let childResult = try await handleSpawnAgents(
                            input: toolCall.input,
                            parentAgentId: task.id,
                            nestingDepth: nestingDepth,
                            onUpdate: onUpdate
                        )
                        resultContent = childResult
                        isError = false
                    } catch {
                        resultContent = "Error spawning agents: \(error.localizedDescription)"
                        isError = true
                    }
                } else {
                    // Execute via MCP
                    do {
                        let inputValue: JSONValue
                        if let data = toolCall.input.data(using: .utf8),
                           let parsed = try? JSONDecoder().decode(JSONValue.self, from: data) {
                            inputValue = parsed
                        } else {
                            inputValue = .object([:])
                        }

                        let result = try await mcpManager.callTool(name: toolCall.name, arguments: inputValue)
                        resultContent = result.content
                        isError = result.isError

                        await onUpdate(.agentToolDone(
                            agentId: task.id,
                            tool: toolCall.name,
                            result: String(result.content.prefix(200)),
                            success: !result.isError
                        ))
                    } catch {
                        resultContent = "Tool error: \(error.localizedDescription)"
                        isError = true

                        await onUpdate(.agentToolDone(
                            agentId: task.id,
                            tool: toolCall.name,
                            result: error.localizedDescription,
                            success: false
                        ))
                    }
                }

                toolResultBlocks.append(.toolResult(ToolResultContent(
                    tool_use_id: toolCall.id,
                    content: resultContent,
                    is_error: isError
                )))
            }

            messages.append(MessageParam(role: "user", content: toolResultBlocks))
        }

        if finalOutput.isEmpty {
            finalOutput = "[Agent completed after \(turnCount) turns with \(toolCallCount) tool calls]"
        }

        await onUpdate(.agentCompleted(agentId: task.id, output: finalOutput))
        return finalOutput
    }

    // MARK: - Sub-Agent Spawning (US-008)

    /// Handle the spawn_agents built-in tool call
    private func handleSpawnAgents(
        input: String,
        parentAgentId: String,
        nestingDepth: Int,
        onUpdate: @escaping @Sendable (AgentUpdate) async -> Void
    ) async throws -> String {
        guard nestingDepth + 1 <= maxNestingDepth else {
            throw OrchestratorError.maxNestingDepthExceeded(nestingDepth + 1, maxNestingDepth)
        }

        // Parse the spawn_agents input
        guard let data = input.data(using: .utf8),
              let json = try? JSONDecoder().decode(SpawnAgentsInput.self, from: data) else {
            throw OrchestratorError.invalidSpawnInput(input)
        }

        // Build child plan
        let childPlan = AgentPlan(
            name: json.name,
            description: json.description,
            agents: json.agents.map { agentInput in
                AgentTask(
                    name: agentInput.name,
                    objective: agentInput.objective,
                    requiredTools: agentInput.requiredTools ?? [],
                    requiredServers: agentInput.requiredServers ?? [],
                    dependsOn: agentInput.dependsOn,
                    maxTurns: agentInput.maxTurns ?? 10,
                    providerSpec: AgentProviderSpec.from(providerString: agentInput.provider ?? "claude:sonnet")
                )
            }
        )

        try? await planStore.savePlan(childPlan)

        await onUpdate(.agentSpawning(agentId: parentAgentId, childPlan: childPlan))

        // Execute child plan recursively
        let childExecution = try await execute(
            plan: childPlan,
            nestingDepth: nestingDepth + 1,
            onUpdate: onUpdate
        )

        // Aggregate child results
        let resultSummary = childExecution.agentResults.map { result in
            "[\(result.agentName)] (\(result.status.rawValue)): \(result.output ?? result.error ?? "no output")"
        }.joined(separator: "\n\n")

        return "Sub-agent plan '\(childPlan.name)' completed (\(childExecution.status.rawValue)):\n\n\(resultSummary)"
    }

    // MARK: - Topological Sort (Kahn's Algorithm)

    /// Sort agents into dependency waves for parallel execution.
    /// Returns an array of waves, where each wave contains agents that can run concurrently.
    private func topologicalSort(agents: [AgentTask]) throws -> [[AgentTask]] {
        let agentMap = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        var inDegree: [String: Int] = [:]
        var dependents: [String: [String]] = [:]

        // Initialize
        for agent in agents {
            inDegree[agent.id] = 0
        }

        // Build graph
        for agent in agents {
            if let deps = agent.dependsOn {
                for depId in deps {
                    guard agentMap[depId] != nil else {
                        throw OrchestratorError.unknownDependency(agent.id, depId)
                    }
                    inDegree[agent.id, default: 0] += 1
                    dependents[depId, default: []].append(agent.id)
                }
            }
        }

        // Process waves
        var waves: [[AgentTask]] = []
        var remaining = Set(agents.map { $0.id })

        while !remaining.isEmpty {
            // Find all agents with no unresolved dependencies
            let wave = remaining.filter { (inDegree[$0] ?? 0) == 0 }

            if wave.isEmpty {
                throw OrchestratorError.circularDependency
            }

            let waveAgents = wave.compactMap { agentMap[$0] }
            waves.append(waveAgents)

            // Remove this wave and update in-degrees
            for agentId in wave {
                remaining.remove(agentId)
                for dependent in dependents[agentId] ?? [] {
                    inDegree[dependent, default: 0] -= 1
                }
            }
        }

        return waves
    }

    // MARK: - Helper Methods

    /// Build context string from upstream agent outputs
    private func buildAgentContext(_ task: AgentTask, agentOutputs: [String: String]) -> String {
        guard let deps = task.dependsOn, !deps.isEmpty else { return "" }

        var contextParts: [String] = []
        for depId in deps {
            if let output = agentOutputs[depId] {
                contextParts.append("--- Output from upstream agent '\(depId)' ---\n\(output)")
            }
        }

        return contextParts.isEmpty ? "" : contextParts.joined(separator: "\n\n")
    }

    /// Build system prompt for an individual agent
    private func buildAgentSystemPrompt(task: AgentTask, context: String) -> String {
        var prompt = """
        You are an autonomous agent executing a specific task as part of a larger plan.

        Your task: \(task.objective)
        """

        if !task.systemPrompt.isEmpty {
            prompt += "\n\nAdditional instructions:\n\(task.systemPrompt)"
        }

        if !context.isEmpty {
            prompt += "\n\nContext from upstream agents:\n\(context)"
        }

        prompt += """


        Complete your task thoroughly and provide a clear, useful output.
        Focus on your specific objective — do not try to handle tasks assigned to other agents.
        """

        return prompt
    }

    /// Get tool definitions scoped to the agent's requiredTools
    private func scopedToolDefinitions(for task: AgentTask) async -> [ToolDefinition] {
        let allTools = await mcpManager.getToolDefinitions()

        if task.requiredTools.isEmpty {
            return allTools
        }

        let requiredSet = Set(task.requiredTools)
        return allTools.filter { requiredSet.contains($0.name) }
    }

    /// Build the spawn_agents tool definition
    private func spawnAgentsTool() -> ToolDefinition {
        ToolDefinition(
            name: "spawn_agents",
            description: "Spawn a sub-plan of agents to handle a complex sub-task. Use when your current task needs further decomposition into parallel sub-tasks.",
            input_schema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Name for the sub-plan")
                    ]),
                    "description": .object([
                        "type": .string("string"),
                        "description": .string("Description of what the sub-plan accomplishes")
                    ]),
                    "agents": .object([
                        "type": .string("array"),
                        "description": .string("Array of agent definitions"),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "name": .object(["type": .string("string")]),
                                "objective": .object(["type": .string("string")]),
                                "requiredTools": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                                "requiredServers": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                                "dependsOn": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                                "provider": .object(["type": .string("string"), "description": .string("Provider:model string, e.g. 'claude:sonnet'")]),
                                "maxTurns": .object(["type": .string("integer")])
                            ]),
                            "required": .array([.string("name"), .string("objective")])
                        ])
                    ])
                ]),
                "required": .array([.string("name"), .string("description"), .string("agents")])
            ])
        )
    }
}

// MARK: - Input Types for spawn_agents

private struct SpawnAgentsInput: Codable {
    let name: String
    let description: String
    let agents: [SpawnAgentDef]
}

private struct SpawnAgentDef: Codable {
    let name: String
    let objective: String
    let requiredTools: [String]?
    let requiredServers: [String]?
    let dependsOn: [String]?
    let provider: String?
    let maxTurns: Int?
}

// MARK: - Errors

enum OrchestratorError: Error, LocalizedError {
    case circularDependency
    case unknownDependency(String, String)
    case maxNestingDepthExceeded(Int, Int)
    case maxTotalAgentsExceeded(Int, Int)
    case invalidSpawnInput(String)
    case providerError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .circularDependency:
            return "Circular dependency detected in agent plan"
        case .unknownDependency(let agent, let dep):
            return "Agent '\(agent)' depends on unknown agent '\(dep)'"
        case .maxNestingDepthExceeded(let depth, let max):
            return "Max nesting depth exceeded (\(depth)/\(max))"
        case .maxTotalAgentsExceeded(let count, let max):
            return "Max total agents exceeded (\(count)/\(max))"
        case .invalidSpawnInput(let input):
            return "Invalid spawn_agents input: \(input.prefix(100))"
        case .providerError(let msg):
            return "Provider error: \(msg)"
        case .cancelled:
            return "Agent execution was cancelled"
        }
    }
}
