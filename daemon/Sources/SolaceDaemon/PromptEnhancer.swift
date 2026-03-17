import Foundation

// MARK: - Result Types

struct ResearchResult: Sendable {
    let findings: String
    let toolsUsed: [String]
}

struct StepBreakdown: Sendable {
    let toolName: String
    let serverName: String
    let inputs: [String: String]
    let rationale: String
}

struct DecompositionResult: Sendable {
    let steps: [StepBreakdown]
    let rawText: String
}

struct CritiqueIssue: Codable, Sendable {
    enum Severity: String, Codable, Sendable {
        case critical
        case suggestion
    }
    let severity: Severity
    let description: String
    let affectedStep: String?
    let suggestion: String
}

struct CritiqueResult: Sendable {
    let issues: [CritiqueIssue]
    let rawText: String
}

struct EnhancementResult: Sendable {
    let enhancedPrompt: String
    let research: ResearchResult
    let decomposition: DecompositionResult
    let critique: CritiqueResult
}

// MARK: - PromptEnhancer Actor

actor PromptEnhancer {
    private let llmProvider: any LLMProvider
    private let mcpManager: MCPManager
    private let maxResearchToolCalls = 5

    init(llmProvider: any LLMProvider, mcpManager: MCPManager) {
        self.llmProvider = llmProvider
        self.mcpManager = mcpManager
    }

    // MARK: - Top-Level Pipeline

    func enhance(prompt: String) async throws -> EnhancementResult {
        let startTime = Date()
        Logger.info("PromptEnhancer: Starting enhancement pipeline for prompt (\(prompt.prefix(80))...)")

        let toolCatalog = await buildToolCatalog()

        // Phase 1: Research
        let research = await research(prompt: prompt, toolCatalog: toolCatalog)
        Logger.info("PromptEnhancer: Research phase complete — \(research.toolsUsed.count) tool(s) used")

        // Phase 2: Decompose
        var decomposition = await decompose(prompt: prompt, research: research, toolCatalog: toolCatalog)
        Logger.info("PromptEnhancer: Decomposition phase complete — \(decomposition.steps.count) step(s)")

        // Phase 3: Critique
        let critique = await critique(prompt: prompt, decomposition: decomposition, toolCatalog: toolCatalog)
        let criticalCount = critique.issues.filter { $0.severity == .critical }.count
        Logger.info("PromptEnhancer: Critique phase complete — \(critique.issues.count) issue(s), \(criticalCount) critical")

        // Phase 3.5: Re-decompose if critical issues found (max 1 retry)
        if criticalCount > 0 {
            Logger.info("PromptEnhancer: Re-decomposing with critique feedback")
            decomposition = await decompose(
                prompt: prompt,
                research: research,
                toolCatalog: toolCatalog,
                critiqueFeedback: critique
            )
            Logger.info("PromptEnhancer: Re-decomposition complete — \(decomposition.steps.count) step(s)")
        }

        // Phase 4: Synthesize
        let enhancedPrompt = await synthesize(
            prompt: prompt,
            research: research,
            decomposition: decomposition,
            critique: critique
        )

        let duration = Date().timeIntervalSince(startTime)
        Logger.info("PromptEnhancer: Pipeline complete in \(String(format: "%.1f", duration))s")

        return EnhancementResult(
            enhancedPrompt: enhancedPrompt,
            research: research,
            decomposition: decomposition,
            critique: critique
        )
    }

    // MARK: - Phase 1: Research Agent

    private func research(prompt: String, toolCatalog: String) async -> ResearchResult {
        Logger.info("PromptEnhancer: Research phase started")

        let tools = await mcpManager.getToolDefinitions()
        var messages: [MessageParam] = [
            MessageParam(role: "user", text: """
            I need to build an automation workflow for this request:
            "\(prompt)"

            Available tools:
            \(toolCatalog)

            Research the user's environment by calling relevant tools to gather context. For example:
            - List directories or files if the workflow involves file operations
            - Check available APIs or endpoints if the workflow involves web services
            - Read configuration files if the workflow needs specific settings

            Gather context that will help build a robust workflow. Be targeted — only call tools directly relevant to the request. After gathering context, summarize your findings.
            """)
        ]

        var toolsUsed: [String] = []
        var toolCallCount = 0

        // Multi-turn tool-calling loop
        for _ in 0..<maxResearchToolCalls {
            let stream = await llmProvider.streamRequest(
                messages: messages,
                tools: tools,
                systemPrompt: Self.researchSystemPrompt
            )

            var textResponse = ""
            var pendingToolCalls: [(id: String, name: String, input: String)] = []

            do {
                for try await event in stream {
                    switch event {
                    case .textDelta(let delta):
                        textResponse += delta
                    case .toolUseDone(let id, let name, let input):
                        pendingToolCalls.append((id: id, name: name, input: input))
                    default:
                        break
                    }
                }
            } catch {
                Logger.error("PromptEnhancer: Research stream error: \(error)")
                break
            }

            // If no tool calls, the agent is done researching
            if pendingToolCalls.isEmpty {
                return ResearchResult(findings: textResponse, toolsUsed: toolsUsed)
            }

            // Execute tool calls and build tool result messages
            messages.append(MessageParam(role: "assistant", text: textResponse))

            var toolResults: [ContentBlock] = []
            for call in pendingToolCalls {
                toolCallCount += 1
                toolsUsed.append(call.name)
                Logger.info("PromptEnhancer: Research calling tool '\(call.name)'")

                let result: String
                do {
                    let args = parseJSONArguments(call.input)
                    let toolResult = try await mcpManager.callTool(name: call.name, arguments: args)
                    result = toolResult.content
                } catch {
                    result = "Error calling tool: \(error.localizedDescription)"
                }

                toolResults.append(.toolResult(ToolResultContent(
                    tool_use_id: call.id,
                    content: result
                )))
            }
            messages.append(MessageParam(role: "user", content: toolResults))

            // Check if we've hit the tool call limit
            if toolCallCount >= maxResearchToolCalls {
                Logger.info("PromptEnhancer: Research hit tool call limit (\(maxResearchToolCalls))")
                // One more LLM call to get the summary
                do {
                    let summary = try await llmProvider.singleRequest(
                        messages: messages + [MessageParam(role: "user", text: "Summarize your research findings concisely. No more tool calls.")],
                        systemPrompt: "Summarize the research findings gathered so far. Be concise and factual."
                    )
                    return ResearchResult(findings: summary, toolsUsed: toolsUsed)
                } catch {
                    Logger.error("PromptEnhancer: Research summary error: \(error)")
                    return ResearchResult(findings: "Research completed with \(toolsUsed.count) tool calls but summary failed.", toolsUsed: toolsUsed)
                }
            }
        }

        return ResearchResult(findings: "No findings gathered.", toolsUsed: toolsUsed)
    }

    // MARK: - Phase 2: Decomposer Agent

    private func decompose(
        prompt: String,
        research: ResearchResult,
        toolCatalog: String,
        critiqueFeedback: CritiqueResult? = nil
    ) async -> DecompositionResult {
        Logger.info("PromptEnhancer: Decomposition phase started")

        var userMessage = """
        Original user request:
        "\(prompt)"

        Research findings:
        \(research.findings)

        Available tools:
        \(toolCatalog)

        Break this workflow into explicit, ordered steps. For each step, specify:
        1. The exact tool name from the catalog
        2. The server name that provides the tool
        3. Specific parameter values (not placeholders — use real values based on research)
        4. Brief rationale for why this step is needed

        Format each step as:
        STEP <n>:
        - Tool: <toolName>
        - Server: <serverName>
        - Inputs: <key=value, key=value>
        - Rationale: <why this step>
        """

        if let feedback = critiqueFeedback {
            let issueText = feedback.issues.map { issue in
                "[\(issue.severity.rawValue.uppercased())] \(issue.description) → \(issue.suggestion)"
            }.joined(separator: "\n")
            userMessage += "\n\nCritique feedback to address:\n\(issueText)"
        }

        do {
            let response = try await llmProvider.singleRequest(
                messages: [MessageParam(role: "user", text: userMessage)],
                systemPrompt: Self.decomposerSystemPrompt
            )

            let steps = parseDecomposition(response)
            return DecompositionResult(steps: steps, rawText: response)
        } catch {
            Logger.error("PromptEnhancer: Decomposition error: \(error)")
            return DecompositionResult(steps: [], rawText: "Decomposition failed: \(error)")
        }
    }

    // MARK: - Phase 3: Critic Agent

    private func critique(
        prompt: String,
        decomposition: DecompositionResult,
        toolCatalog: String
    ) async -> CritiqueResult {
        Logger.info("PromptEnhancer: Critique phase started")

        let userMessage = """
        Original user request:
        "\(prompt)"

        Proposed workflow breakdown:
        \(decomposition.rawText)

        Available tools:
        \(toolCatalog)

        Review this workflow plan and identify issues:
        - Missing steps that the user would expect
        - Wrong tool choices (a better tool exists in the catalog)
        - Incomplete or incorrect parameters
        - Data flow gaps (step N needs data that no previous step produces)
        - Edge cases that could cause failure

        For each issue, specify:
        ISSUE:
        - Severity: CRITICAL or SUGGESTION
        - Description: what's wrong
        - Affected Step: which step number (or "overall")
        - Fix: how to resolve it

        If the plan looks solid, respond with: NO ISSUES FOUND
        """

        do {
            let response = try await llmProvider.singleRequest(
                messages: [MessageParam(role: "user", text: userMessage)],
                systemPrompt: Self.criticSystemPrompt
            )

            let issues = parseCritique(response)
            return CritiqueResult(issues: issues, rawText: response)
        } catch {
            Logger.error("PromptEnhancer: Critique error: \(error)")
            return CritiqueResult(issues: [], rawText: "Critique failed: \(error)")
        }
    }

    // MARK: - Phase 4: Synthesizer Agent

    private func synthesize(
        prompt: String,
        research: ResearchResult,
        decomposition: DecompositionResult,
        critique: CritiqueResult
    ) async -> String {
        Logger.info("PromptEnhancer: Synthesis phase started")

        let critiqueSection: String
        if critique.issues.isEmpty {
            critiqueSection = "No issues found — plan approved as-is."
        } else {
            critiqueSection = critique.issues.map { issue in
                "[\(issue.severity.rawValue.uppercased())] \(issue.description) → \(issue.suggestion)"
            }.joined(separator: "\n")
        }

        let userMessage = """
        I need you to write a detailed, specific prompt for a workflow builder AI. Combine all the information below into a single, clear instruction.

        Original user request:
        "\(prompt)"

        Research findings:
        \(research.findings)

        Step-by-step breakdown:
        \(decomposition.rawText)

        Critique notes:
        \(critiqueSection)

        Write a detailed prompt that tells the workflow builder exactly what to build. Include:
        - Specific tool names and server names for each step
        - Exact parameter values (from research, not placeholders)
        - How data flows between steps (which step outputs feed into which inputs)
        - Error handling notes from the critique
        - The trigger type (cron with schedule, or manual with input parameters)

        Write ONLY the enhanced prompt — no preamble, no explanation.
        """

        do {
            let response = try await llmProvider.singleRequest(
                messages: [MessageParam(role: "user", text: userMessage)],
                systemPrompt: Self.synthesizerSystemPrompt
            )
            Logger.info("PromptEnhancer: Synthesis phase complete")
            return response
        } catch {
            Logger.error("PromptEnhancer: Synthesis error: \(error)")
            return prompt // Fallback to original
        }
    }

    // MARK: - Tool Catalog Builder

    private func buildToolCatalog() async -> String {
        let tools = await mcpManager.getTools()
        return tools.map { tool -> String in
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
    }

    // MARK: - Parsing Helpers

    private func parseDecomposition(_ text: String) -> [StepBreakdown] {
        var steps: [StepBreakdown] = []
        let lines = text.components(separatedBy: "\n")
        var currentTool = ""
        var currentServer = ""
        var currentInputs: [String: String] = [:]
        var currentRationale = ""
        var inStep = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("STEP ") {
                if inStep && !currentTool.isEmpty {
                    steps.append(StepBreakdown(
                        toolName: currentTool, serverName: currentServer,
                        inputs: currentInputs, rationale: currentRationale
                    ))
                }
                currentTool = ""
                currentServer = ""
                currentInputs = [:]
                currentRationale = ""
                inStep = true
            } else if trimmed.hasPrefix("- Tool:") {
                currentTool = trimmed.replacingOccurrences(of: "- Tool:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- Server:") {
                currentServer = trimmed.replacingOccurrences(of: "- Server:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- Inputs:") {
                let inputStr = trimmed.replacingOccurrences(of: "- Inputs:", with: "").trimmingCharacters(in: .whitespaces)
                for pair in inputStr.components(separatedBy: ", ") {
                    let parts = pair.components(separatedBy: "=")
                    if parts.count >= 2 {
                        currentInputs[parts[0].trimmingCharacters(in: .whitespaces)] =
                            parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
                    }
                }
            } else if trimmed.hasPrefix("- Rationale:") {
                currentRationale = trimmed.replacingOccurrences(of: "- Rationale:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        // Capture last step
        if inStep && !currentTool.isEmpty {
            steps.append(StepBreakdown(
                toolName: currentTool, serverName: currentServer,
                inputs: currentInputs, rationale: currentRationale
            ))
        }

        return steps
    }

    private func parseCritique(_ text: String) -> [CritiqueIssue] {
        if text.contains("NO ISSUES FOUND") {
            return []
        }

        var issues: [CritiqueIssue] = []
        let lines = text.components(separatedBy: "\n")
        var currentSeverity: CritiqueIssue.Severity?
        var currentDescription = ""
        var currentAffectedStep: String?
        var currentSuggestion = ""
        var inIssue = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("ISSUE:") || trimmed == "ISSUE" {
                if inIssue, let severity = currentSeverity {
                    issues.append(CritiqueIssue(
                        severity: severity, description: currentDescription,
                        affectedStep: currentAffectedStep, suggestion: currentSuggestion
                    ))
                }
                currentSeverity = nil
                currentDescription = ""
                currentAffectedStep = nil
                currentSuggestion = ""
                inIssue = true
            } else if trimmed.hasPrefix("- Severity:") {
                let val = trimmed.replacingOccurrences(of: "- Severity:", with: "").trimmingCharacters(in: .whitespaces).uppercased()
                currentSeverity = val.contains("CRITICAL") ? .critical : .suggestion
            } else if trimmed.hasPrefix("- Description:") {
                currentDescription = trimmed.replacingOccurrences(of: "- Description:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- Affected Step:") {
                currentAffectedStep = trimmed.replacingOccurrences(of: "- Affected Step:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- Fix:") {
                currentSuggestion = trimmed.replacingOccurrences(of: "- Fix:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        // Capture last issue
        if inIssue, let severity = currentSeverity {
            issues.append(CritiqueIssue(
                severity: severity, description: currentDescription,
                affectedStep: currentAffectedStep, suggestion: currentSuggestion
            ))
        }

        return issues
    }

    private func parseJSONArguments(_ input: String) -> JSONValue {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .object([:])
        }
        return jsonValueFromAny(json)
    }

    private func jsonValueFromAny(_ value: Any) -> JSONValue {
        if let dict = value as? [String: Any] {
            var obj: [String: JSONValue] = [:]
            for (k, v) in dict { obj[k] = jsonValueFromAny(v) }
            return .object(obj)
        } else if let arr = value as? [Any] {
            return .array(arr.map { jsonValueFromAny($0) })
        } else if let str = value as? String {
            return .string(str)
        } else if let num = value as? Int {
            return .int(num)
        } else if let num = value as? Double {
            return .double(num)
        } else if let bool = value as? Bool {
            return .bool(bool)
        }
        return .null
    }

    // MARK: - System Prompts

    private static let researchSystemPrompt = """
    You are a Research agent in a workflow enhancement pipeline. Your job is to gather context about the user's environment that will help build a better automation workflow.

    You have access to MCP tools. Use them to:
    - Explore file systems, directories, or projects relevant to the request
    - Check API capabilities or available endpoints
    - Read configuration files or environment details
    - Verify assumptions about the user's setup

    Rules:
    - Be targeted — only call tools directly relevant to the user's workflow request
    - Don't modify anything — read-only operations only
    - After gathering enough context, provide a concise summary of your findings
    - Focus on facts that will help specify exact tool parameters and step ordering
    """

    private static let decomposerSystemPrompt = """
    You are a Decomposer agent in a workflow enhancement pipeline. Your job is to break a vague workflow description into explicit, unambiguous steps.

    For each step you must specify:
    - The EXACT tool name from the provided catalog
    - The EXACT server name that hosts the tool
    - Specific parameter values (not placeholders — use real values from the research)
    - A brief rationale for why this step is needed

    Rules:
    - Only use tools that exist in the provided catalog
    - Resolve all ambiguity — pick specific tools and fill in concrete values
    - Order steps logically with data dependencies in mind
    - Keep the step count minimal — only what's needed to accomplish the goal

    Format your response using this exact structure for each step:
    STEP <n>:
    - Tool: <exact_tool_name>
    - Server: <exact_server_name>
    - Inputs: <key=value, key=value>
    - Rationale: <brief explanation>
    """

    private static let criticSystemPrompt = """
    You are a Critic agent in a workflow enhancement pipeline. Your job is to review a proposed workflow plan and identify problems.

    Look for:
    - Missing steps the user would expect
    - Wrong tool choices (a better tool exists)
    - Incomplete or incorrect parameters
    - Data flow gaps (step N needs data no previous step produces)
    - Edge cases that could cause failure
    - Missing error handling for unreliable operations

    Rules:
    - Be constructive — identify problems AND suggest fixes
    - Mark issues as CRITICAL (must fix) or SUGGESTION (nice to have)
    - If the plan is solid, respond with: NO ISSUES FOUND
    - Don't invent requirements the user didn't ask for

    Format each issue as:
    ISSUE:
    - Severity: CRITICAL or SUGGESTION
    - Description: <what's wrong>
    - Affected Step: <step number or "overall">
    - Fix: <how to resolve>
    """

    private static let synthesizerSystemPrompt = """
    You are a Synthesizer agent in a workflow enhancement pipeline. Your job is to combine research, decomposition, and critique into a single detailed prompt for a workflow builder AI.

    The workflow builder will use your prompt to generate a JSON workflow definition. Your prompt should be so detailed and specific that the builder can produce a perfect workflow on the first try.

    Rules:
    - Include specific tool names and server names
    - Include exact parameter values (not placeholders)
    - Describe data flow between steps explicitly
    - Mention the trigger type (cron with schedule, or manual with input parameters)
    - Incorporate fixes for any critical issues from the critique
    - Write in clear, imperative language
    - Output ONLY the enhanced prompt — no preamble, no meta-commentary
    """
}
