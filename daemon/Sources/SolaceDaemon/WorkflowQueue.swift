import Foundation

/// Priority level for workflow execution
enum WorkflowPriority: Comparable {
    case low
    case normal
    case high

    static func < (lhs: WorkflowPriority, rhs: WorkflowPriority) -> Bool {
        let order: [WorkflowPriority] = [.low, .normal, .high]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// Manages workflow execution with priority-based queuing and concurrent execution limits.
///
/// The queue maintains three priority levels (high, normal, low) and enforces a maximum
/// concurrent execution limit. When a slot becomes available, the highest-priority pending
/// workflow is dequeued and executed.
///
/// This architecture prevents resource exhaustion from unbounded concurrent workflows
/// while enabling prioritization of time-sensitive work (email-triggered workflows) over
/// background tasks (scheduled/cron workflows).
actor WorkflowQueue {
    private let workflowExecutor: WorkflowExecutor
    private let maxConcurrent: Int

    // MARK: - Queue State

    private var highPriorityQueue: [(workflow: WorkflowDefinition, triggerInfo: String, inputParams: [String: String], onComplete: (@Sendable (WorkflowExecution) async -> Void)?)] = []
    private var normalPriorityQueue: [(workflow: WorkflowDefinition, triggerInfo: String, inputParams: [String: String], onComplete: (@Sendable (WorkflowExecution) async -> Void)?)] = []
    private var lowPriorityQueue: [(workflow: WorkflowDefinition, triggerInfo: String, inputParams: [String: String], onComplete: (@Sendable (WorkflowExecution) async -> Void)?)] = []

    // Track running execution tasks by execution ID
    // Also keep a reverse mapping from tracking key to execution ID for cleanup
    private var runningExecutions: [String: Task<Void, Never>] = [:]
    private var trackingKeyToExecutionId: [String: String] = [:]

    // Track failed executions to clean up stale entries
    private var maxTrackedExecutions = 1000
    private var executionHistory: [(id: String, key: String, timestamp: Date)] = []

    init(workflowExecutor: WorkflowExecutor, maxConcurrent: Int = 5) {
        self.workflowExecutor = workflowExecutor
        self.maxConcurrent = maxConcurrent
    }

    // MARK: - Public API

    /// Enqueue a workflow for execution with optional priority.
    ///
    /// - Parameters:
    ///   - workflow: The workflow to execute
    ///   - triggerInfo: Human-readable description of what triggered this workflow
    ///   - inputParams: Runtime parameters to pass to the workflow
    ///   - priority: Execution priority (default: normal)
    ///   - onComplete: Optional callback invoked when execution completes
    func enqueue(
        workflow: WorkflowDefinition,
        triggerInfo: String,
        inputParams: [String: String] = [:],
        priority: WorkflowPriority = .normal,
        onComplete: (@Sendable (WorkflowExecution) async -> Void)? = nil
    ) async {
        let item = (workflow: workflow, triggerInfo: triggerInfo, inputParams: inputParams, onComplete: onComplete)

        switch priority {
        case .high:
            highPriorityQueue.append(item)
        case .normal:
            normalPriorityQueue.append(item)
        case .low:
            lowPriorityQueue.append(item)
        }

        Logger.info("Workflow '\(workflow.name)' enqueued with priority \(priority) - running: \(runningExecutions.count), queued: \(highPriorityQueue.count + normalPriorityQueue.count + lowPriorityQueue.count)")

        // Try to dequeue and start a new execution if we have available capacity
        await processQueue()
    }

    /// Cancel a running workflow execution by ID.
    func cancel(executionId: String) async {
        // Look up the tracking key from the execution ID reverse mapping
        guard let trackingKey = trackingKeyToExecutionId.first(where: { $0.value == executionId })?.key,
              let task = runningExecutions[trackingKey] else {
            Logger.info("Cancel requested for execution \(executionId) but it is not running")
            return
        }
        Logger.info("Cancelling execution \(executionId) (tracking key: \(trackingKey))")
        task.cancel()
        runningExecutions.removeValue(forKey: trackingKey)
        trackingKeyToExecutionId.removeValue(forKey: trackingKey)
    }

    /// Get current queue status: running count and breakdown by priority.
    func getQueueStatus() -> (running: Int, queued: Int, queuedByPriority: [String: Int]) {
        return (
            running: runningExecutions.count,
            queued: highPriorityQueue.count + normalPriorityQueue.count + lowPriorityQueue.count,
            queuedByPriority: [
                "high": highPriorityQueue.count,
                "normal": normalPriorityQueue.count,
                "low": lowPriorityQueue.count
            ]
        )
    }

    // MARK: - Private Helpers

    /// Process the queue: dequeue workflows while capacity allows and execute them.
    private func processQueue() async {
        while runningExecutions.count < maxConcurrent {
            // Dequeue highest-priority workflow
            guard let (workflow, triggerInfo, inputParams, onComplete) = dequeueNextWorkflow() else {
                // Queue is empty
                break
            }

            // Create a unique tracking key for this execution attempt
            let trackingKey = "\(workflow.id)-\(triggerInfo)-\(UUID().uuidString)"

            // Start execution in background and track it
            let task = Task {
                let execution = await workflowExecutor.execute(
                    workflow: workflow,
                    triggerInfo: triggerInfo,
                    inputParams: inputParams
                )

                // Update reverse mapping with actual execution ID
                await self.recordExecutionId(trackingKey: trackingKey, executionId: execution.id)

                // Invoke optional completion callback
                if let callback = onComplete {
                    await callback(execution)
                }

                // Record execution in history for periodic cleanup
                await self.recordExecutionHistory(trackingKey: trackingKey, executionId: execution.id)

                // Clean up and try to process more work
                await self.removeRunningExecution(trackingKey: trackingKey)
                await self.processQueue()
            }

            // Store the tracking task
            runningExecutions[trackingKey] = task

            Logger.info("Started execution (tracking as \(trackingKey)) for workflow '\(workflow.name)'")
        }
    }

    /// Dequeue the next highest-priority workflow from the queues.
    private func dequeueNextWorkflow() -> (workflow: WorkflowDefinition, triggerInfo: String, inputParams: [String: String], onComplete: (@Sendable (WorkflowExecution) async -> Void)?)? {
        if !highPriorityQueue.isEmpty {
            return highPriorityQueue.removeFirst()
        } else if !normalPriorityQueue.isEmpty {
            return normalPriorityQueue.removeFirst()
        } else if !lowPriorityQueue.isEmpty {
            return lowPriorityQueue.removeFirst()
        }
        return nil
    }

    /// Remove a completed execution from tracking.
    private func removeRunningExecution(trackingKey: String) async {
        runningExecutions.removeValue(forKey: trackingKey)
        trackingKeyToExecutionId.removeValue(forKey: trackingKey)
    }

    /// Record the actual execution ID after it's created.
    private func recordExecutionId(trackingKey: String, executionId: String) async {
        trackingKeyToExecutionId[trackingKey] = executionId
    }

    /// Record execution in history for periodic cleanup of stale entries.
    private func recordExecutionHistory(trackingKey: String, executionId: String) async {
        executionHistory.append((id: executionId, key: trackingKey, timestamp: Date()))

        // Clean up old history entries if we exceed max
        if executionHistory.count > maxTrackedExecutions {
            let entriesToRemove = executionHistory.count - maxTrackedExecutions
            executionHistory.removeFirst(entriesToRemove)
            Logger.info("Trimmed execution history: removed \(entriesToRemove) entries (max: \(maxTrackedExecutions))")
        }
    }

    /// Periodic cleanup of stale entries (call this method periodically if needed).
    /// This ensures orphaned entries don't accumulate if tasks are canceled abnormally.
    func cleanupStaleEntries() async {
        let now = Date()
        let staleThreshold: TimeInterval = 3600  // 1 hour

        // Remove stale running executions
        let staleKeys = runningExecutions.filter { _, task in
            // If task is cancelled, it's stale
            task.isCancelled
        }.keys.map { $0 }

        for key in staleKeys {
            Logger.info("Removing stale execution entry: \(key)")
            await removeRunningExecution(trackingKey: key)
        }

        // Trim execution history if needed
        let validHistory = executionHistory.filter { entry in
            now.timeIntervalSince(entry.timestamp) < staleThreshold
        }

        if validHistory.count < executionHistory.count {
            Logger.info("Cleaned up execution history: \(executionHistory.count - validHistory.count) old entries")
            executionHistory = validHistory
        }
    }
}
