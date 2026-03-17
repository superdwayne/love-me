import Foundation

/// Executes workflows by running steps in dependency order using MCP tool calls.
///
/// Steps are topologically sorted based on their `dependsOn` declarations and
/// executed sequentially. Each step's output is available for variable resolution
/// in downstream steps.
///
/// Note: This actor is decoupled from DaemonApp via EventBus for workflow events.
/// The previous callback-based pattern is still supported for backwards compatibility,
/// but new code should subscribe to workflow events via EventBus instead.
actor WorkflowExecutor {
    private let mcpManager: MCPManager
    private let store: WorkflowStore
    private let llmProvider: (any LLMProvider)?
    private let providerPool: ProviderPool?
    private let eventBus: EventBus
    private var runningExecutions: [String: Task<Void, Never>] = [:]

    /// Legacy: Callback for broadcasting individual step updates to WebSocket clients
    /// Deprecated: Use EventBus to subscribe to "workflow:step_update" events instead
    private var onStepUpdate: (@Sendable (WorkflowExecution, StepResult) async -> Void)?

    /// Legacy: Callback for broadcasting execution-level updates to WebSocket clients
    /// Deprecated: Use EventBus to subscribe to "workflow:execution_update" events instead
    private var onExecutionUpdate: (@Sendable (WorkflowExecution) async -> Void)?

    init(mcpManager: MCPManager, store: WorkflowStore, eventBus: EventBus, llmProvider: (any LLMProvider)? = nil, providerPool: ProviderPool? = nil) {
        self.mcpManager = mcpManager
        self.store = store
        self.eventBus = eventBus
        self.llmProvider = llmProvider
        self.providerPool = providerPool
    }

    /// Set callbacks for broadcasting updates (legacy API, kept for backwards compatibility)
    /// Deprecated: Use EventBus subscription instead for cleaner decoupling
    func setCallbacks(
        onStepUpdate: @escaping @Sendable (WorkflowExecution, StepResult) async -> Void,
        onExecutionUpdate: @escaping @Sendable (WorkflowExecution) async -> Void
    ) {
        self.onStepUpdate = onStepUpdate
        self.onExecutionUpdate = onExecutionUpdate
    }

    // MARK: - Public API

    /// Execute a workflow definition, returning the final execution record.
    ///
    /// Steps run in topological order (respecting `dependsOn`). The execution
    /// Task is tracked so it can be cancelled via `cancel(executionId:)`.
    func execute(workflow: WorkflowDefinition, triggerInfo: String, inputParams: [String: String] = [:]) async -> WorkflowExecution {
        // 1. Build the initial execution record
        let executionId = UUID().uuidString
        var execution = WorkflowExecution(
            id: executionId,
            workflowId: workflow.id,
            workflowName: workflow.name,
            status: .running,
            startedAt: Date(),
            triggerInfo: triggerInfo,
            stepResults: workflow.steps.map { step in
                StepResult(stepId: step.id, stepName: step.name, status: .pending)
            }
        )

        // 2. Persist the initial state
        do {
            try await store.saveExecution(execution)
        } catch {
            Logger.error("Failed to save initial execution state: \(error)")
        }

        // 3. Broadcast execution start (fire-and-forget — don't block step execution)
        Logger.info("Workflow '\(workflow.name)' execution \(executionId) started")
        if let callback = onExecutionUpdate {
            let exec = execution
            Task { await callback(exec) }
        }

        // 4. Run steps directly (cancellation handled via runningExecutions task tracking)
        execution = await runSteps(workflow: workflow, execution: execution, inputParams: inputParams)

        // Reload the latest execution state from the store
        do {
            execution = try await store.getExecution(id: executionId)
        } catch {
            Logger.error("Failed to reload execution \(executionId): \(error)")
        }

        return execution
    }

    /// Cancel a running execution by its ID.
    func cancel(executionId: String) {
        guard let task = runningExecutions[executionId] else {
            Logger.info("Cancel requested for execution \(executionId) but it is not running")
            return
        }
        Logger.info("Cancelling execution \(executionId)")
        task.cancel()
        runningExecutions.removeValue(forKey: executionId)
    }

    // MARK: - Private Helpers

    private func removeRunningExecution(id: String) {
        runningExecutions.removeValue(forKey: id)
    }

    /// Core execution loop: topological sort then run each step.
    private func runSteps(
        workflow: WorkflowDefinition,
        execution: WorkflowExecution,
        inputParams: [String: String] = [:]
    ) async -> WorkflowExecution {
        var execution = execution

        // Resolve execution order via topological sort
        Logger.info("Running \(workflow.steps.count) step(s) for workflow '\(workflow.name)'")
        let sortedSteps = topologicalSort(steps: workflow.steps)

        guard !sortedSteps.isEmpty else {
            Logger.error("Workflow '\(workflow.name)' has no steps or contains a dependency cycle")
            execution.status = .failed
            execution.completedAt = Date()
            await saveAndBroadcastExecution(&execution)
            return execution
        }

        // Track outputs keyed by step ID for variable resolution.
        // Pre-seed __input__ with runtime parameters so steps can reference them.
        var stepOutputs: [String: String] = [:]
        if !inputParams.isEmpty {
            if let data = try? JSONSerialization.data(withJSONObject: inputParams),
               let json = String(data: data, encoding: .utf8) {
                stepOutputs["__input__"] = json
                Logger.info("Seeded __input__ with \(inputParams.count) param(s): \(inputParams.keys.sorted().joined(separator: ", "))")
            }
        }

        for step in sortedSteps {
            // Check for cancellation before each step
            if Task.isCancelled {
                Logger.info("Execution \(execution.id) cancelled before step '\(step.name)'")
                execution.status = .cancelled
                execution.completedAt = Date()
                await saveAndBroadcastExecution(&execution)
                return execution
            }

            // Mark step as running
            updateStepResult(&execution, stepId: step.id) { result in
                result.status = .running
                result.startedAt = Date()
            }
            await saveAndBroadcastStep(&execution, stepId: step.id)

            // Resolve input template using outputs from completed steps.
            // Coerce string values to the types the tool schema expects (number, boolean, etc.)
            // so tools with strict JSON Schema validation don't reject them.
            let toolSchema = await mcpManager.getTools().first(where: { $0.name == step.toolName })?.inputSchema
            var resolvedInputs: [String: JSONValue] = [:]
            for (key, value) in step.inputTemplate {
                let resolved = value.resolve(with: stepOutputs)
                resolvedInputs[key] = coerceToSchemaType(value: resolved, key: key, schema: toolSchema)
            }
            let arguments = JSONValue.object(resolvedInputs)
            Logger.info("Step '\(step.name)' calling tool '\(step.toolName)' with \(resolvedInputs.count) arg(s): \(resolvedInputs.keys.sorted().joined(separator: ", "))")

            // Execute the tool call, respecting error policy
            let success = await executeStepWithPolicy(
                step: step,
                arguments: arguments,
                execution: &execution,
                stepOutputs: &stepOutputs
            )

            if !success {
                // Execution has been marked as failed inside executeStepWithPolicy
                return execution
            }
        }

        // All steps completed successfully
        execution.status = .completed
        execution.completedAt = Date()
        await saveAndBroadcastExecution(&execution)
        Logger.info("Workflow '\(execution.workflowName)' execution \(execution.id) completed")

        return execution
    }

    /// Execute a single step, handling retries and error policy.
    /// Returns `true` if execution should continue, `false` if it should abort.
    private func executeStepWithPolicy(
        step: WorkflowStep,
        arguments: JSONValue,
        execution: inout WorkflowExecution,
        stepOutputs: inout [String: String]
    ) async -> Bool {
        let maxAttempts = step.onError == .retry ? 2 : 1

        for attempt in 1...maxAttempts {
            do {
                let result = try await mcpManager.callTool(name: step.toolName, arguments: arguments)

                if result.isError {
                    throw WorkflowExecutorError.toolReturnedError(result.content)
                }

                // Success
                updateStepResult(&execution, stepId: step.id) { stepResult in
                    stepResult.status = .success
                    stepResult.completedAt = Date()
                    stepResult.output = result.content
                }
                stepOutputs[step.id] = result.content
                await saveAndBroadcastStep(&execution, stepId: step.id)

                Logger.info("Step '\(step.name)' completed successfully")
                return true

            } catch {
                let isLastAttempt = attempt == maxAttempts
                let errorMessage = "\(error)"

                if step.onError == .retry && !isLastAttempt {
                    Logger.info("Step '\(step.name)' failed (attempt \(attempt)/\(maxAttempts)), retrying: \(errorMessage)")
                    continue
                }

                // Final failure -- apply error policy
                switch step.onError {
                case .stop, .retry:
                    // .retry falls through here on the last attempt
                    // Try auto-fix first if LLM provider is available
                    if llmProvider != nil {
                        Logger.info("Step '\(step.name)' failed, attempting auto-fix before stopping: \(errorMessage)")
                        let fixed = await attemptAutoFix(
                            step: step,
                            originalArguments: arguments,
                            errorMessage: errorMessage,
                            stepOutputs: &stepOutputs,
                            execution: &execution
                        )
                        if fixed { return true }
                    }
                    // Auto-fix unavailable or failed — original stop behavior
                    Logger.error("Step '\(step.name)' failed, stopping execution: \(errorMessage)")
                    updateStepResult(&execution, stepId: step.id) { stepResult in
                        stepResult.status = .error
                        stepResult.completedAt = Date()
                        stepResult.error = errorMessage
                    }
                    await saveAndBroadcastStep(&execution, stepId: step.id)

                    execution.status = .failed
                    execution.completedAt = Date()
                    await saveAndBroadcastExecution(&execution)
                    return false

                case .skip:
                    Logger.info("Step '\(step.name)' failed, skipping: \(errorMessage)")
                    updateStepResult(&execution, stepId: step.id) { stepResult in
                        stepResult.status = .skipped
                        stepResult.completedAt = Date()
                        stepResult.error = errorMessage
                    }
                    await saveAndBroadcastStep(&execution, stepId: step.id)
                    return true

                case .autofix:
                    Logger.info("Step '\(step.name)' failed, attempting auto-fix: \(errorMessage)")
                    let fixed = await attemptAutoFix(
                        step: step,
                        originalArguments: arguments,
                        errorMessage: errorMessage,
                        stepOutputs: &stepOutputs,
                        execution: &execution
                    )
                    if !fixed {
                        execution.status = .failed
                        execution.completedAt = Date()
                        await saveAndBroadcastExecution(&execution)
                        return false
                    }
                    return true
                }
            }
        }

        // Should never reach here, but satisfy the compiler
        return true
    }

    // MARK: - Auto-Fix

    /// Attempt to fix a failed step by asking the LLM to correct the inputs.
    /// Returns `true` if the fix succeeded, `false` otherwise.
    private func attemptAutoFix(
        step: WorkflowStep,
        originalArguments: JSONValue,
        errorMessage: String,
        stepOutputs: inout [String: String],
        execution: inout WorkflowExecution
    ) async -> Bool {
        // 1. Set step status to "fixing" and broadcast
        updateStepResult(&execution, stepId: step.id) { stepResult in
            stepResult.status = .fixing
            stepResult.error = errorMessage
        }
        await saveAndBroadcastStep(&execution, stepId: step.id)

        // 2. Resolve LLM provider — prefer per-step routing, fall back to default
        let llm: any LLMProvider
        if let preferredProvider = step.preferredProvider, let pool = providerPool {
            let spec = AgentProviderSpec.from(providerString: preferredProvider)
            if let resolved = try? await pool.provider(for: spec) {
                llm = resolved
                Logger.info("Auto-fix using per-step provider '\(preferredProvider)' for step '\(step.name)'")
            } else if let fallback = llmProvider {
                llm = fallback
                Logger.info("Auto-fix: per-step provider '\(preferredProvider)' unavailable, using default for step '\(step.name)'")
            } else {
                Logger.error("Auto-fix unavailable: no LLM provider configured")
                updateStepResult(&execution, stepId: step.id) { stepResult in
                    stepResult.status = .error
                    stepResult.completedAt = Date()
                    stepResult.error = "Auto-fix unavailable (no LLM configured). Original error: \(errorMessage)"
                }
                await saveAndBroadcastStep(&execution, stepId: step.id)
                return false
            }
        } else if let defaultLLM = llmProvider {
            llm = defaultLLM
        } else {
            Logger.error("Auto-fix unavailable: no LLM provider configured")
            updateStepResult(&execution, stepId: step.id) { stepResult in
                stepResult.status = .error
                stepResult.completedAt = Date()
                stepResult.error = "Auto-fix unavailable (no LLM configured). Original error: \(errorMessage)"
            }
            await saveAndBroadcastStep(&execution, stepId: step.id)
            return false
        }

        // 3. Get tool schema
        let toolInfo = await mcpManager.getTools().first(where: { $0.name == step.toolName })
        let schemaString: String
        if let schema = toolInfo?.inputSchema,
           let data = try? JSONEncoder().encode(schema),
           let str = String(data: data, encoding: .utf8) {
            schemaString = str
        } else {
            schemaString = "(schema unavailable)"
        }

        // 4. Build original inputs string
        let originalInputsString: String
        if let data = try? JSONEncoder().encode(originalArguments),
           let str = String(data: data, encoding: .utf8) {
            originalInputsString = str
        } else {
            originalInputsString = "(unavailable)"
        }

        // 5. Build previous step outputs context (truncated)
        let prevOutputs = stepOutputs.map { key, value in
            let truncated = value.count > 500 ? String(value.prefix(500)) + "..." : value
            return "  \(key): \(truncated)"
        }.joined(separator: "\n")

        // 6. Call LLM
        let systemPrompt = "You are a workflow step debugger. A step failed. Analyze the error and return ONLY a corrected JSON object with fixed inputs. No explanation, no markdown fences, just valid JSON."

        let userPrompt = """
        Tool: \(step.toolName)
        Server: \(step.serverName)
        Description: \(toolInfo?.description ?? "(unknown)")

        Input Schema:
        \(schemaString)

        Original inputs sent:
        \(originalInputsString)

        Error message:
        \(errorMessage)

        Previous step outputs:
        \(prevOutputs.isEmpty ? "(none)" : prevOutputs)

        Return ONLY a corrected JSON object with the fixed inputs.
        """

        let fixedInputsString: String
        do {
            fixedInputsString = try await llm.singleRequest(
                messages: [MessageParam(role: "user", text: userPrompt)],
                systemPrompt: systemPrompt
            )
            Logger.info("Auto-fix LLM response for step '\(step.name)': \(fixedInputsString.prefix(200))")
        } catch {
            Logger.error("Auto-fix LLM call failed: \(error)")
            updateStepResult(&execution, stepId: step.id) { stepResult in
                stepResult.status = .error
                stepResult.completedAt = Date()
                stepResult.error = "Auto-fix LLM call failed: \(error). Original error: \(errorMessage)"
            }
            await saveAndBroadcastStep(&execution, stepId: step.id)
            return false
        }

        // 7. Parse response — strip markdown fences if present
        var cleaned = fixedInputsString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8),
              let fixedArgs = try? JSONDecoder().decode(JSONValue.self, from: jsonData) else {
            Logger.error("Auto-fix: LLM returned invalid JSON")
            updateStepResult(&execution, stepId: step.id) { stepResult in
                stepResult.status = .error
                stepResult.completedAt = Date()
                stepResult.error = "Auto-fix failed: LLM returned invalid JSON. Original error: \(errorMessage)"
            }
            await saveAndBroadcastStep(&execution, stepId: step.id)
            return false
        }

        // 8. Retry with fixed inputs
        let fixedArguments: JSONValue
        if case .object = fixedArgs {
            fixedArguments = fixedArgs
        } else {
            fixedArguments = .object(["input": fixedArgs])
        }

        do {
            let result = try await mcpManager.callTool(name: step.toolName, arguments: fixedArguments)

            if result.isError {
                throw WorkflowExecutorError.toolReturnedError(result.content)
            }

            // Success — mark step as success
            updateStepResult(&execution, stepId: step.id) { stepResult in
                stepResult.status = .success
                stepResult.completedAt = Date()
                stepResult.output = result.content
                stepResult.error = nil
            }
            stepOutputs[step.id] = result.content
            await saveAndBroadcastStep(&execution, stepId: step.id)
            Logger.info("Auto-fix succeeded for step '\(step.name)'")
            return true

        } catch {
            let fixError = "\(error)"
            Logger.error("Auto-fix retry failed for step '\(step.name)': \(fixError)")
            updateStepResult(&execution, stepId: step.id) { stepResult in
                stepResult.status = .error
                stepResult.completedAt = Date()
                stepResult.error = "Original: \(errorMessage) | Fix attempt: \(fixError)"
            }
            await saveAndBroadcastStep(&execution, stepId: step.id)
            return false
        }
    }

    // MARK: - Topological Sort

    /// Topological sort of workflow steps based on `dependsOn` relationships.
    ///
    /// Uses Kahn's algorithm: repeatedly select steps whose dependencies have
    /// all been satisfied. Returns an empty array if a cycle is detected.
    private func topologicalSort(steps: [WorkflowStep]) -> [WorkflowStep] {
        let stepMap = Dictionary(uniqueKeysWithValues: steps.map { ($0.id, $0) })
        var inDegree: [String: Int] = [:]
        var dependents: [String: [String]] = [:]  // stepId -> [steps that depend on it]

        // Initialize
        for step in steps {
            inDegree[step.id] = step.dependsOn?.count ?? 0
            for dep in step.dependsOn ?? [] {
                dependents[dep, default: []].append(step.id)
            }
        }

        // Seed the queue with steps that have no dependencies
        var queue: [String] = steps
            .filter { (inDegree[$0.id] ?? 0) == 0 }
            .map { $0.id }
        var sorted: [WorkflowStep] = []

        while !queue.isEmpty {
            let currentId = queue.removeFirst()
            guard let step = stepMap[currentId] else { continue }
            sorted.append(step)

            for dependentId in dependents[currentId] ?? [] {
                inDegree[dependentId, default: 0] -= 1
                if inDegree[dependentId] == 0 {
                    queue.append(dependentId)
                }
            }
        }

        // If not all steps were sorted, there is a cycle
        if sorted.count != steps.count {
            Logger.error("Dependency cycle detected in workflow steps")
            return []
        }

        return sorted
    }

    // MARK: - State Management Helpers

    /// Mutate a specific step result inside the execution record.
    private func updateStepResult(
        _ execution: inout WorkflowExecution,
        stepId: String,
        update: (inout StepResult) -> Void
    ) {
        guard let index = execution.stepResults.firstIndex(where: { $0.stepId == stepId }) else {
            Logger.error("Step result not found for stepId: \(stepId)")
            return
        }
        update(&execution.stepResults[index])
    }

    /// Persist execution state and broadcast the step update callback (fire-and-forget).
    private func saveAndBroadcastStep(
        _ execution: inout WorkflowExecution,
        stepId: String
    ) async {
        do {
            try await store.saveExecution(execution)
        } catch {
            Logger.error("Failed to save execution after step update: \(error)")
        }

        if let stepResult = execution.stepResults.first(where: { $0.stepId == stepId }),
           let callback = onStepUpdate {
            let exec = execution
            Task { await callback(exec, stepResult) }
        }
    }

    // MARK: - Type Coercion

    /// Coerce a resolved string value to the JSON type expected by the tool's input schema.
    /// Falls back to `.string()` if the schema is unavailable or the type is unknown.
    private func coerceToSchemaType(value: String, key: String, schema: JSONValue?) -> JSONValue {
        guard let schema = schema,
              case .object(let schemaObj) = schema,
              case .object(let properties) = schemaObj["properties"],
              case .object(let propSchema) = properties[key],
              case .string(let propType) = propSchema["type"] else {
            return .string(value)
        }

        switch propType {
        case "integer":
            if let intVal = Int(value) { return .int(intVal) }
            if let dblVal = Double(value) { return .int(Int(dblVal)) }
            return .string(value)
        case "number":
            if let dblVal = Double(value) { return .double(dblVal) }
            return .string(value)
        case "boolean":
            let lower = value.lowercased()
            if lower == "true" || lower == "1" { return .bool(true) }
            if lower == "false" || lower == "0" { return .bool(false) }
            return .string(value)
        case "array", "object":
            // Try to parse as JSON
            if let data = value.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) {
                return decoded
            }
            return .string(value)
        default:
            return .string(value)
        }
    }

    /// Persist execution state and broadcast the execution update callback (fire-and-forget).
    private func saveAndBroadcastExecution(_ execution: inout WorkflowExecution) async {
        do {
            try await store.saveExecution(execution)
        } catch {
            Logger.error("Failed to save execution state: \(error)")
        }

        if let callback = onExecutionUpdate {
            let exec = execution
            Task { await callback(exec) }
        }
    }
}

// MARK: - Errors

enum WorkflowExecutorError: Error, LocalizedError {
    case toolReturnedError(String)

    var errorDescription: String? {
        switch self {
        case .toolReturnedError(let message):
            return "Tool returned error: \(message)"
        }
    }
}
