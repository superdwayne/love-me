import Foundation

/// Executes workflows by running steps in dependency order using MCP tool calls.
///
/// Steps are topologically sorted based on their `dependsOn` declarations and
/// executed sequentially. Each step's output is available for variable resolution
/// in downstream steps.
actor WorkflowExecutor {
    private let mcpManager: MCPManager
    private let store: WorkflowStore
    private var runningExecutions: [String: Task<Void, Never>] = [:]

    /// Callback for broadcasting individual step updates to WebSocket clients
    private var onStepUpdate: (@Sendable (WorkflowExecution, StepResult) async -> Void)?

    /// Callback for broadcasting execution-level updates to WebSocket clients
    private var onExecutionUpdate: (@Sendable (WorkflowExecution) async -> Void)?

    init(mcpManager: MCPManager, store: WorkflowStore) {
        self.mcpManager = mcpManager
        self.store = store
    }

    /// Set callbacks for broadcasting updates (called after init to break circular references)
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
    func execute(workflow: WorkflowDefinition, triggerInfo: String) async -> WorkflowExecution {
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
        execution = await runSteps(workflow: workflow, execution: execution)

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
        execution: WorkflowExecution
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

        // Track outputs keyed by step ID for variable resolution
        var stepOutputs: [String: String] = [:]

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

            // Resolve input template using outputs from completed steps
            var resolvedInputs: [String: JSONValue] = [:]
            for (key, value) in step.inputTemplate {
                let resolved = value.resolve(with: stepOutputs)
                resolvedInputs[key] = .string(resolved)
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
                }
            }
        }

        // Should never reach here, but satisfy the compiler
        return true
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
