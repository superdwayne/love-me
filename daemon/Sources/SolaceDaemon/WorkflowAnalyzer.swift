import Foundation

/// Analyzes workflow definitions for missing elements, issues, and improvement opportunities.
/// Uses both static analysis and LLM-powered reasoning. Can auto-fix detected issues.
actor WorkflowAnalyzer {
    private let mcpManager: MCPManager
    private let llmProvider: (any LLMProvider)?

    init(mcpManager: MCPManager, llmProvider: (any LLMProvider)? = nil) {
        self.mcpManager = mcpManager
        self.llmProvider = llmProvider
    }

    // MARK: - Analysis API

    /// Analyze a workflow and return a comprehensive report
    func analyze(workflow: WorkflowDefinition) async -> WorkflowAnalysisResult {
        let startTime = Date()
        Logger.info("WorkflowAnalyzer: Starting analysis of '\(workflow.name)'")

        let availableTools = await mcpManager.getTools()

        // Run static analysis
        let staticIssues = analyzeStatic(workflow: workflow, availableTools: availableTools)
        let missingElements = analyzeMissingElements(workflow: workflow, availableTools: availableTools)

        // Run LLM-powered analysis if available
        let llmIssues: [WorkflowIssue]
        if llmProvider != nil {
            llmIssues = await analyzeWithLLM(workflow: workflow, availableTools: availableTools)
        } else {
            llmIssues = []
        }

        // Combine issues, deduplicating by message
        var allIssues = staticIssues + llmIssues
        allIssues = deduplicateIssues(allIssues)

        // Generate recommendations
        let recommendations = generateRecommendations(for: workflow, issues: allIssues, missingElements: missingElements)

        let score = calculateHealthScore(for: allIssues)
        let healthScore = HealthScore(from: score)

        let duration = Date().timeIntervalSince(startTime)
        Logger.info("WorkflowAnalyzer: Analysis complete in \(String(format: "%.1f", duration))s — \(allIssues.count) issue(s), health: \(healthScore.rawValue)")

        return WorkflowAnalysisResult(
            workflowId: workflow.id,
            workflowName: workflow.name,
            overallHealth: healthScore,
            issues: allIssues,
            missingElements: missingElements,
            recommendations: recommendations,
            analyzedAt: startTime
        )
    }

    // MARK: - Auto-Fix API

    /// Analyze and auto-fix a workflow, returning the fixed definition + enhancement history
    /// - Parameter executionErrors: Optional runtime errors from a previous test execution.
    ///   When provided, these are included in the LLM fixer prompt so fixes address actual runtime failures.
    func enhance(workflow: WorkflowDefinition, executionErrors: [(stepName: String, error: String)] = []) async -> EnhanceResult {
        let analysis = await analyze(workflow: workflow)

        // If no issues at all, return as-is
        if analysis.issues.isEmpty && analysis.missingElements.isEmpty {
            Logger.info("WorkflowAnalyzer: No issues found for '\(workflow.name)'")
            return EnhanceResult(
                workflow: workflow,
                analysis: analysis,
                fixedIssues: [],
                enhancementStep: nil
            )
        }

        let criticalOrWarning = analysis.issues.filter { $0.severity == .critical || $0.severity == .warning }
        Logger.info("WorkflowAnalyzer: Attempting auto-fix — \(criticalOrWarning.count) critical/warning, \(analysis.issues.count) total, \(analysis.missingElements.count) missing elements")

        // Try LLM-powered fix first
        if let llm = llmProvider {
            let fixResult = await autoFixWithLLM(
                workflow: workflow,
                analysis: analysis,
                llm: llm,
                executionErrors: executionErrors
            )
            if let fixResult {
                return fixResult
            }
        }

        // Fall back to static fixes
        let staticResult = autoFixStatic(workflow: workflow, analysis: analysis)
        return staticResult
    }

    // MARK: - Static Analysis

    private func analyzeStatic(
        workflow: WorkflowDefinition,
        availableTools: [MCPToolInfo]
    ) -> [WorkflowIssue] {
        var issues: [WorkflowIssue] = []
        let availableToolNames = Set(availableTools.map { $0.name })

        for step in workflow.steps {
            // Check if tool exists
            if !availableToolNames.contains(step.toolName) {
                issues.append(WorkflowIssue(
                    id: UUID().uuidString,
                    severity: .critical,
                    category: .wrongTool,
                    message: "Step '\(step.name)' uses unknown tool '\(step.toolName)'",
                    affectedStepId: step.id,
                    affectedStepName: step.name,
                    suggestion: "Replace with a valid tool from the MCP server catalog"
                ))
            }

            // Check for placeholder/empty inputs
            let placeholderValues = ["", "{{}}", "todo", "placeholder", "your_", "example_"]
            for (key, value) in step.inputTemplate {
                let strValue = value.resolve(with: [:])
                if placeholderValues.contains(strValue.lowercased()) ||
                   (strValue.starts(with: "{{") && !strValue.contains("step_") &&
                    !strValue.contains("__input__")) {
                    issues.append(WorkflowIssue(
                        id: UUID().uuidString,
                        severity: .critical,
                        category: .missingInputs,
                        message: "Step '\(step.name)' has empty or placeholder input for '\(key)'",
                        affectedStepId: step.id,
                        affectedStepName: step.name,
                        suggestion: "Provide a specific value or valid step reference"
                    ))
                }
            }

            // Check for data flow issues (referencing non-existent steps)
            if let pattern = try? NSRegularExpression(pattern: #"{{([^.}]+)\.([^}]+)}}"#, options: []) {
                for (_, value) in step.inputTemplate {
                    let strValue = value.resolve(with: [:])
                    let matches = pattern.matches(in: strValue, range: NSRange(strValue.startIndex..., in: strValue))
                    for match in matches {
                        if match.numberOfRanges >= 2 {
                            let stepIdRange = match.range(at: 1)
                            if let swiftRange = Range(stepIdRange, in: strValue) {
                                let referencedStepId = String(strValue[swiftRange])
                                let stepExists = workflow.steps.contains { $0.id == referencedStepId }
                                if !stepExists && referencedStepId != "__input__" {
                                    issues.append(WorkflowIssue(
                                        id: UUID().uuidString,
                                        severity: .critical,
                                        category: .dataFlow,
                                        message: "Step '\(step.name)' references non-existent step '\(referencedStepId)'",
                                        affectedStepId: step.id,
                                        affectedStepName: step.name,
                                        suggestion: "Verify the step ID or remove the invalid reference"
                                    ))
                                }
                            }
                        }
                    }
                }
            }

            // Check dependsOn references
            if let dependsOn = step.dependsOn {
                for depId in dependsOn {
                    let stepExists = workflow.steps.contains { $0.id == depId }
                    if !stepExists {
                        issues.append(WorkflowIssue(
                            id: UUID().uuidString,
                            severity: .warning,
                            category: .dataFlow,
                            message: "Step '\(step.name)' depends on non-existent step '\(depId)'",
                            affectedStepId: step.id,
                            affectedStepName: step.name,
                            suggestion: "Remove the dependency or add the missing step"
                        ))
                    }
                }
            }
        }

        // Check workflow has at least one step
        if workflow.steps.isEmpty {
            issues.append(WorkflowIssue(
                id: UUID().uuidString,
                severity: .critical,
                category: .missingSteps,
                message: "Workflow has no steps defined",
                affectedStepId: nil,
                affectedStepName: nil,
                suggestion: "Add at least one step to define the workflow's purpose"
            ))
        }

        // Check for missing description
        if workflow.description.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(WorkflowIssue(
                id: UUID().uuidString,
                severity: .suggestion,
                category: .missingSteps,
                message: "Workflow has no description",
                affectedStepId: nil,
                affectedStepName: nil,
                suggestion: "Add a clear description so others understand the workflow's purpose"
            ))
        }

        return issues
    }

    private func analyzeMissingElements(
        workflow: WorkflowDefinition,
        availableTools: [MCPToolInfo]
    ) -> [MissingElement] {
        var missingElements: [MissingElement] = []

        // Check for input parameters on manual trigger
        if case .manual(let inputParams) = workflow.trigger {
            if inputParams == nil || inputParams?.isEmpty == true {
                let placeholderSteps = workflow.steps.filter { step in
                    step.inputTemplate.contains { (_, value) in
                        let strValue = value.resolve(with: [:])
                        return strValue.isEmpty || (strValue.starts(with: "{{") && !strValue.contains("__input__"))
                    }
                }

                if !placeholderSteps.isEmpty {
                    missingElements.append(MissingElement(
                        id: UUID().uuidString,
                        elementType: .inputParameter,
                        description: "Manual trigger has no input parameters but steps have placeholder values",
                        recommendedValue: nil,
                        stepId: nil
                    ))
                }
            }
        }

        // Check for steps that might need error handling
        let hasErrorHandling = workflow.steps.contains { $0.onError != .stop }
        if !hasErrorHandling && workflow.steps.count > 2 {
            missingElements.append(MissingElement(
                id: UUID().uuidString,
                elementType: .errorHandling,
                description: "Workflow has multiple steps but lacks error handling configuration",
                recommendedValue: "retry or autofix",
                stepId: nil
            ))
        }

        // Check for notification settings
        if !workflow.notificationPrefs.notifyOnComplete &&
           !workflow.notificationPrefs.notifyOnError {
            missingElements.append(MissingElement(
                id: UUID().uuidString,
                elementType: .notificationSetting,
                description: "Workflow has no notification preferences set",
                recommendedValue: "enable complete/error notifications",
                stepId: nil
            ))
        }

        return missingElements
    }

    // MARK: - LLM-Powered Analysis

    private func analyzeWithLLM(
        workflow: WorkflowDefinition,
        availableTools: [MCPToolInfo]
    ) async -> [WorkflowIssue] {
        guard let llm = llmProvider else { return [] }

        let toolCatalog = buildToolCatalog(for: availableTools)
        let stepsDescription = workflow.steps.enumerated().map { idx, step in
            let inputs = step.inputTemplate.map { "\($0.key)=\($0.value.resolve(with: [:]))" }.joined(separator: ", ")
            return "  Step \(idx + 1) [\(step.id)]: \(step.name) — tool: \(step.toolName) (server: \(step.serverName)), inputs: {\(inputs)}, onError: \(step.onError.rawValue)"
        }.joined(separator: "\n")

        let triggerDesc: String
        switch workflow.trigger {
        case .cron(let expr): triggerDesc = "cron(\(expr))"
        case .event(let src, let evt, _): triggerDesc = "event(\(src):\(evt))"
        case .manual(let params): triggerDesc = "manual(\(params?.count ?? 0) inputs)"
        }

        let userPrompt = """
        Analyze this workflow for issues:

        Name: \(workflow.name)
        Description: \(workflow.description.isEmpty ? "(none)" : workflow.description)
        Trigger: \(triggerDesc)
        Steps:
        \(stepsDescription)

        Available tools:
        \(toolCatalog)

        Check for:
        - Wrong or non-existent tool names
        - Missing required parameters for each tool
        - Data flow gaps between steps
        - Missing error handling for unreliable steps
        - Performance issues (unnecessary sequential steps that could be parallel)

        Format EACH issue as exactly:
        ISSUE: [critical|warning|suggestion] | [missing_inputs|missing_steps|wrong_tool|data_flow|parameter_error|trigger_type|performance|security] | <step_id or N/A> | <description> | <fix suggestion>

        If no issues: respond with NO ISSUES FOUND
        """

        do {
            let response = try await llm.singleRequest(
                messages: [MessageParam(role: "user", text: userPrompt)],
                systemPrompt: Self.analyzerSystemPrompt
            )
            return parseLLMIssues(response: response, workflow: workflow)
        } catch {
            Logger.error("WorkflowAnalyzer: LLM analysis failed: \(error)")
            return []
        }
    }

    private func parseLLMIssues(response: String, workflow: WorkflowDefinition) -> [WorkflowIssue] {
        if response.contains("NO ISSUES FOUND") { return [] }

        var issues: [WorkflowIssue] = []

        for line in response.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("ISSUE:") else { continue }

            let rest = trimmed.replacingOccurrences(of: "ISSUE:", with: "").trimmingCharacters(in: .whitespaces)
            let parts = rest.split(separator: "|", maxSplits: 4).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count >= 5 else { continue }

            let severityStr = parts[0].lowercased()
            let severity: IssueSeverity
            if severityStr.contains("critical") { severity = .critical }
            else if severityStr.contains("warning") { severity = .warning }
            else { severity = .suggestion }

            let categoryStr = parts[1].lowercased()
            let category: IssueCategory
            switch categoryStr {
            case let s where s.contains("missing_inputs"): category = .missingInputs
            case let s where s.contains("missing_steps"): category = .missingSteps
            case let s where s.contains("wrong_tool"): category = .wrongTool
            case let s where s.contains("data_flow"): category = .dataFlow
            case let s where s.contains("parameter"): category = .parameterError
            case let s where s.contains("trigger"): category = .triggerType
            case let s where s.contains("performance"): category = .performance
            case let s where s.contains("security"): category = .security
            default: category = .parameterError
            }

            let stepIdStr = parts[2]
            let affectedStepId = stepIdStr == "N/A" ? nil : stepIdStr
            let affectedStepName = affectedStepId.flatMap { id in
                workflow.steps.first { $0.id == id }?.name
            }

            issues.append(WorkflowIssue(
                id: UUID().uuidString,
                severity: severity,
                category: category,
                message: parts[3],
                affectedStepId: affectedStepId,
                affectedStepName: affectedStepName,
                suggestion: parts[4]
            ))
        }

        return issues
    }

    // MARK: - Auto-Fix: LLM

    private func autoFixWithLLM(
        workflow: WorkflowDefinition,
        analysis: WorkflowAnalysisResult,
        llm: any LLMProvider,
        executionErrors: [(stepName: String, error: String)] = []
    ) async -> EnhanceResult? {
        let availableTools = await mcpManager.getTools()
        let toolCatalog = buildToolCatalog(for: availableTools)

        let issuesDescription = analysis.issues.map { issue in
            "[\(issue.severity.rawValue)] \(issue.category.rawValue): \(issue.message) → \(issue.suggestion)"
        }.joined(separator: "\n")

        let stepsJSON: String
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(workflow.steps)
            stepsJSON = String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            stepsJSON = "[]"
        }

        let triggerJSON: String
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(workflow.trigger)
            triggerJSON = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            triggerJSON = "{}"
        }

        let runtimeErrorsSection: String
        if !executionErrors.isEmpty {
            let errDesc = executionErrors.map { "- Step '\($0.stepName)': \($0.error)" }.joined(separator: "\n")
            runtimeErrorsSection = """

            RUNTIME ERRORS FROM LAST TEST EXECUTION:
            \(errDesc)

            These are actual errors that occurred when the workflow was executed.
            Pay special attention to fixing these — they indicate real failures, not just static analysis guesses.

            """
        } else {
            runtimeErrorsSection = ""
        }

        let userPrompt = """
        Fix this workflow by addressing all identified issues.

        Current workflow:
        - Name: \(workflow.name)
        - Description: \(workflow.description)
        - Trigger: \(triggerJSON)
        - Steps: \(stepsJSON)

        Issues found:
        \(issuesDescription)
        \(runtimeErrorsSection)
        Available tools:
        \(toolCatalog)

        Return a FIXED version of the workflow as JSON with this exact structure:
        {
            "name": "<fixed name>",
            "description": "<fixed description>",
            "trigger": { "type": "manual|cron|event", ... },
            "steps": [
                {
                    "name": "<step name>",
                    "toolName": "<exact tool name from catalog>",
                    "serverName": "<server name>",
                    "inputTemplate": { "<key>": { "type": "literal", "value": "<val>" } },
                    "onError": "autofix|retry|skip|stop"
                }
            ],
            "fixes_applied": [
                { "issue_id": "<id>", "description": "<what was fixed>" }
            ]
        }

        IMPORTANT:
        - Only use tools that exist in the available tools catalog
        - Fill in concrete parameter values, not placeholders
        - Fix data flow by ensuring step references are valid
        - Add error handling where missing
        - Return ONLY valid JSON, no markdown fences, no explanation
        """

        do {
            let response = try await llm.singleRequest(
                messages: [MessageParam(role: "user", text: userPrompt)],
                systemPrompt: Self.fixerSystemPrompt
            )

            return parseFixedWorkflow(
                response: response,
                original: workflow,
                analysis: analysis
            )
        } catch {
            Logger.error("WorkflowAnalyzer: LLM auto-fix failed: \(error)")
            return nil
        }
    }

    private func parseFixedWorkflow(
        response: String,
        original: WorkflowDefinition,
        analysis: WorkflowAnalysisResult
    ) -> EnhanceResult? {
        // Clean the response
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Logger.error("WorkflowAnalyzer: Failed to parse LLM fix response as JSON")
            return nil
        }

        // Extract fixed steps
        guard let stepsArray = json["steps"] as? [[String: Any]] else {
            Logger.error("WorkflowAnalyzer: No steps in LLM fix response")
            return nil
        }

        var fixedSteps: [WorkflowStep] = []
        for stepDict in stepsArray {
            guard let name = stepDict["name"] as? String,
                  let toolName = stepDict["toolName"] as? String,
                  let serverName = stepDict["serverName"] as? String else { continue }

            var inputTemplate: [String: StringOrVariable] = [:]
            if let inputs = stepDict["inputTemplate"] as? [String: Any] {
                for (key, val) in inputs {
                    if let valDict = val as? [String: Any], let type = valDict["type"] as? String {
                        switch type {
                        case "literal":
                            if let v = valDict["value"] as? String {
                                inputTemplate[key] = .literal(v)
                            }
                        case "variable":
                            if let stepId = valDict["stepId"] as? String,
                               let jsonPath = valDict["jsonPath"] as? String {
                                inputTemplate[key] = .variable(stepId: stepId, jsonPath: jsonPath)
                            }
                        case "template":
                            if let v = valDict["value"] as? String {
                                inputTemplate[key] = .template(v)
                            }
                        default:
                            if let v = val as? String {
                                inputTemplate[key] = .literal(v)
                            }
                        }
                    } else if let v = val as? String {
                        inputTemplate[key] = .literal(v)
                    }
                }
            }

            let errorPolicyStr = stepDict["onError"] as? String ?? "autofix"
            let errorPolicy = ErrorPolicy(rawValue: errorPolicyStr) ?? .autofix
            let preferredProvider = stepDict["preferredProvider"] as? String

            fixedSteps.append(WorkflowStep(
                name: name,
                toolName: toolName,
                serverName: serverName,
                inputTemplate: inputTemplate,
                onError: errorPolicy,
                preferredProvider: preferredProvider
            ))
        }

        guard !fixedSteps.isEmpty else {
            Logger.error("WorkflowAnalyzer: LLM fix produced no valid steps")
            return nil
        }

        // Parse fixes applied
        var fixedIssueIds: [String] = []
        if let fixesApplied = json["fixes_applied"] as? [[String: Any]] {
            fixedIssueIds = fixesApplied.compactMap { $0["issue_id"] as? String }
        }

        // Build fixed workflow
        let fixedName = json["name"] as? String ?? original.name
        let fixedDescription = json["description"] as? String ?? original.description

        // Parse trigger if provided
        var fixedTrigger = original.trigger
        if let triggerDict = json["trigger"] as? [String: Any],
           let triggerType = triggerDict["type"] as? String {
            switch triggerType {
            case "cron":
                if let expr = triggerDict["expression"] as? String {
                    fixedTrigger = .cron(expression: expr)
                }
            case "manual":
                fixedTrigger = .manual(inputParams: nil)
            default:
                break
            }
        }

        // Mark issues as fixed
        let fixedIssues = analysis.issues.compactMap { issue -> CritiqueIssue? in
            if fixedIssueIds.contains(issue.id) || issue.severity == .critical {
                return CritiqueIssue(
                    severity: .critical,
                    description: issue.message,
                    affectedStep: issue.affectedStepName,
                    suggestion: issue.suggestion
                )
            }
            return nil
        }

        let enhancementStep = EnhancementStep(
            enhancementType: .autoOptimization,
            issuesIdentified: analysis.issues.map { issue in
                CritiqueIssue(
                    severity: issue.severity == .critical ? .critical : .suggestion,
                    description: issue.message,
                    affectedStep: issue.affectedStepName,
                    suggestion: issue.suggestion
                )
            },
            issuesFixed: fixedIssues
        )

        let fixedWorkflow = WorkflowDefinition(
            id: original.id,
            name: fixedName,
            description: fixedDescription,
            enabled: original.enabled,
            trigger: fixedTrigger,
            steps: fixedSteps,
            notificationPrefs: NotificationPrefs(
                notifyOnComplete: true,
                notifyOnError: true
            ),
            created: original.created,
            updated: Date(),
            originalPrompt: original.originalPrompt,
            enhancedPrompt: original.enhancedPrompt,
            enhancementHistory: (original.enhancementHistory ?? []) + [enhancementStep]
        )

        Logger.info("WorkflowAnalyzer: LLM auto-fix produced \(fixedSteps.count) step(s), \(fixedIssues.count) fix(es)")

        return EnhanceResult(
            workflow: fixedWorkflow,
            analysis: analysis,
            fixedIssues: fixedIssues,
            enhancementStep: enhancementStep
        )
    }

    // MARK: - Auto-Fix: Static

    private func autoFixStatic(
        workflow: WorkflowDefinition,
        analysis: WorkflowAnalysisResult
    ) -> EnhanceResult {
        var fixedSteps = workflow.steps
        var fixedIssues: [CritiqueIssue] = []

        // Fix: Remove invalid dependsOn references
        for i in fixedSteps.indices {
            if let deps = fixedSteps[i].dependsOn {
                let validDeps = deps.filter { depId in
                    workflow.steps.contains { $0.id == depId }
                }
                if validDeps.count != deps.count {
                    fixedSteps[i] = WorkflowStep(
                        id: fixedSteps[i].id,
                        name: fixedSteps[i].name,
                        toolName: fixedSteps[i].toolName,
                        serverName: fixedSteps[i].serverName,
                        inputTemplate: fixedSteps[i].inputTemplate,
                        dependsOn: validDeps.isEmpty ? nil : validDeps,
                        onError: fixedSteps[i].onError,
                        preferredProvider: fixedSteps[i].preferredProvider
                    )
                    fixedIssues.append(CritiqueIssue(
                        severity: .suggestion,
                        description: "Removed invalid dependency references from step '\(fixedSteps[i].name)'",
                        affectedStep: fixedSteps[i].name,
                        suggestion: "Dependency references cleaned up"
                    ))
                }
            }
        }

        // Fix: Add error handling if missing
        let hasErrorHandling = fixedSteps.contains { $0.onError != .stop }
        if !hasErrorHandling && fixedSteps.count > 2 {
            for i in fixedSteps.indices {
                fixedSteps[i] = WorkflowStep(
                    id: fixedSteps[i].id,
                    name: fixedSteps[i].name,
                    toolName: fixedSteps[i].toolName,
                    serverName: fixedSteps[i].serverName,
                    inputTemplate: fixedSteps[i].inputTemplate,
                    dependsOn: fixedSteps[i].dependsOn,
                    onError: .autofix,
                    preferredProvider: fixedSteps[i].preferredProvider
                )
            }
            fixedIssues.append(CritiqueIssue(
                severity: .suggestion,
                description: "Added autofix error handling to all steps",
                affectedStep: nil,
                suggestion: "Steps now use autofix error policy"
            ))
        }

        // Fix: Enable notifications
        var fixedNotifs = workflow.notificationPrefs
        if !fixedNotifs.notifyOnComplete || !fixedNotifs.notifyOnError {
            fixedNotifs = NotificationPrefs(
                notifyOnStart: fixedNotifs.notifyOnStart,
                notifyOnComplete: true,
                notifyOnError: true,
                notifyOnStepComplete: fixedNotifs.notifyOnStepComplete
            )
            fixedIssues.append(CritiqueIssue(
                severity: .suggestion,
                description: "Enabled completion and error notifications",
                affectedStep: nil,
                suggestion: "Notifications configured"
            ))
        }

        let enhancementStep = fixedIssues.isEmpty ? nil : EnhancementStep(
            enhancementType: .autoOptimization,
            issuesIdentified: analysis.issues.map { issue in
                CritiqueIssue(
                    severity: issue.severity == .critical ? .critical : .suggestion,
                    description: issue.message,
                    affectedStep: issue.affectedStepName,
                    suggestion: issue.suggestion
                )
            },
            issuesFixed: fixedIssues
        )

        let fixedWorkflow = WorkflowDefinition(
            id: workflow.id,
            name: workflow.name,
            description: workflow.description,
            enabled: workflow.enabled,
            trigger: workflow.trigger,
            steps: fixedSteps,
            notificationPrefs: fixedNotifs,
            created: workflow.created,
            updated: Date(),
            originalPrompt: workflow.originalPrompt,
            enhancedPrompt: workflow.enhancedPrompt,
            enhancementHistory: (workflow.enhancementHistory ?? []) + (enhancementStep.map { [$0] } ?? [])
        )

        return EnhanceResult(
            workflow: fixedWorkflow,
            analysis: analysis,
            fixedIssues: fixedIssues,
            enhancementStep: enhancementStep
        )
    }

    // MARK: - Helper Methods

    private func deduplicateIssues(_ issues: [WorkflowIssue]) -> [WorkflowIssue] {
        var seen: Set<String> = []
        var unique: [WorkflowIssue] = []

        for issue in issues {
            let key = "\(issue.message)|\(issue.affectedStepId ?? "nil")"
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(issue)
            }
        }

        return unique
    }

    private func calculateHealthScore(for issues: [WorkflowIssue]) -> Int {
        var score = 100
        for issue in issues where !issue.fixed {
            switch issue.severity {
            case .critical: score -= 25
            case .warning: score -= 10
            case .suggestion: score -= 3
            }
        }
        return max(0, score)
    }

    private func buildToolCatalog(for tools: [MCPToolInfo]) -> String {
        tools.prefix(80).map { tool -> String in
            var entry = "- \(tool.name) (server: \(tool.serverName)): \(tool.description)"
            if case .object(let schema) = tool.inputSchema,
               case .object(let props) = schema["properties"] {
                let required: [String]
                if case .array(let reqArr) = schema["required"] {
                    required = reqArr.compactMap { if case .string(let s) = $0 { return s }; return nil }
                } else {
                    required = []
                }
                let params = props.keys.sorted().prefix(8).map { key -> String in
                    let isReq = required.contains(key)
                    return "    \(key)\(isReq ? " (required)" : "")"
                }.joined(separator: "\n")
                if !params.isEmpty {
                    entry += "\n\(params)"
                }
            }
            return entry
        }.joined(separator: "\n")
    }

    private func generateRecommendations(
        for workflow: WorkflowDefinition,
        issues: [WorkflowIssue],
        missingElements: [MissingElement]
    ) -> [Recommendation] {
        var recommendations: [Recommendation] = []
        let criticalIssues = issues.filter { $0.severity == .critical }
        let warningIssues = issues.filter { $0.severity == .warning }

        if criticalIssues.contains(where: { $0.category == .missingInputs }) {
            recommendations.append(Recommendation(
                id: UUID().uuidString,
                title: "Add Input Parameters",
                description: "Define runtime input parameters for dynamic values in your workflow",
                category: .userExperience
            ))
        }

        if criticalIssues.contains(where: { $0.category == .dataFlow }) {
            recommendations.append(Recommendation(
                id: UUID().uuidString,
                title: "Fix Data Flow",
                description: "Ensure all step references point to existing steps with correct output paths",
                category: .reliability
            ))
        }

        if criticalIssues.contains(where: { $0.category == .wrongTool }) {
            recommendations.append(Recommendation(
                id: UUID().uuidString,
                title: "Review Tool Selection",
                description: "Verify all tools exist and are appropriate for the workflow's purpose",
                category: .automation
            ))
        }

        if warningIssues.contains(where: { $0.category == .performance }) {
            recommendations.append(Recommendation(
                id: UUID().uuidString,
                title: "Optimize Performance",
                description: "Consider using caching or parallel execution for long-running steps",
                category: .optimization
            ))
        }

        if missingElements.contains(where: { $0.elementType == .notificationSetting }) {
            recommendations.append(Recommendation(
                id: UUID().uuidString,
                title: "Configure Notifications",
                description: "Set up notifications to stay informed about workflow status",
                category: .userExperience
            ))
        }

        if workflow.steps.count > 5 {
            recommendations.append(Recommendation(
                id: UUID().uuidString,
                title: "Consider Modularization",
                description: "Large workflows may benefit from being split into smaller, reusable workflows",
                category: .optimization
            ))
        }

        return recommendations
    }

    // MARK: - System Prompts

    private static let analyzerSystemPrompt = """
    You are a Workflow Analyzer. Review workflow definitions for correctness and suggest improvements.

    Rules:
    - Only flag real issues — don't invent problems
    - Verify tool names against the provided catalog
    - Check that step inputs match the tool's required parameters
    - Verify data flow: ensure referenced step IDs exist and produce expected output
    - Use the exact pipe-delimited format specified
    - Be concise and actionable
    """

    private static let fixerSystemPrompt = """
    You are a Workflow Auto-Fixer. Given a broken workflow and its issues, produce a corrected version.

    Rules:
    - Only use tools that exist in the provided catalog
    - Fill in concrete, reasonable default values for missing inputs
    - Fix data flow by correcting step references
    - Add autofix error handling for steps that might fail
    - Preserve the user's original intent — don't add unnecessary steps
    - Return ONLY valid JSON, no markdown fences
    - Keep the same step IDs where possible
    """
}

// MARK: - Enhance Result

struct EnhanceResult: Sendable {
    let workflow: WorkflowDefinition
    let analysis: WorkflowAnalysisResult
    let fixedIssues: [CritiqueIssue]
    let enhancementStep: EnhancementStep?
}

// MARK: - User Feedback

struct UserFeedback: Codable, Sendable {
    let issueId: String
    let action: FeedbackAction
    let notes: String?

    enum FeedbackAction: String, Codable, Sendable {
        case fixed = "fixed"
        case ignored = "ignored"
        case needsMoreInfo = "needs_more_info"
    }
}
