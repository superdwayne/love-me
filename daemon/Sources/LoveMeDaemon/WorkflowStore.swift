import Foundation

/// Persistence layer for workflow definitions and execution history
actor WorkflowStore {
    private let workflowsDirectory: String
    private let executionsDirectory: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(workflowsDirectory: String, executionsDirectory: String) {
        self.workflowsDirectory = workflowsDirectory
        self.executionsDirectory = executionsDirectory

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - Workflow CRUD

    /// Create a new workflow definition
    func create(_ workflow: WorkflowDefinition) throws {
        let data = try encoder.encode(workflow)
        let path = workflowFilePath(for: workflow.id)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        Logger.info("Created workflow '\(workflow.name)' (\(workflow.id))")
    }

    /// Load a workflow definition by ID
    func get(id: String) throws -> WorkflowDefinition {
        let path = workflowFilePath(for: id)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try decoder.decode(WorkflowDefinition.self, from: data)
    }

    /// Update an existing workflow definition
    func update(_ workflow: WorkflowDefinition) throws {
        let path = workflowFilePath(for: workflow.id)
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            throw WorkflowStoreError.workflowNotFound(workflow.id)
        }
        let data = try encoder.encode(workflow)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        Logger.info("Updated workflow '\(workflow.name)' (\(workflow.id))")
    }

    /// Delete a workflow definition by ID
    func delete(id: String) throws {
        let path = workflowFilePath(for: id)
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
            Logger.info("Deleted workflow \(id)")
        }
    }

    /// List all workflows as summaries, including last execution status
    func listAll() throws -> [WorkflowSummary] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: workflowsDirectory) else {
            return []
        }

        var summaries: [WorkflowSummary] = []

        for file in files where file.hasSuffix(".json") {
            let path = "\(workflowsDirectory)/\(file)"
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let definition = try decoder.decode(WorkflowDefinition.self, from: data)
                let lastExecution = try? getLatestExecution(workflowId: definition.id)
                summaries.append(WorkflowSummary(from: definition, lastExecution: lastExecution))
            } catch {
                Logger.error("Failed to load workflow from \(file): \(error)")
            }
        }

        // Sort by name alphabetically
        summaries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return summaries
    }

    /// Get all enabled workflow definitions
    func getEnabled() throws -> [WorkflowDefinition] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: workflowsDirectory) else {
            return []
        }

        var workflows: [WorkflowDefinition] = []

        for file in files where file.hasSuffix(".json") {
            let path = "\(workflowsDirectory)/\(file)"
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let definition = try decoder.decode(WorkflowDefinition.self, from: data)
                if definition.enabled {
                    workflows.append(definition)
                }
            } catch {
                Logger.error("Failed to load workflow from \(file): \(error)")
            }
        }

        return workflows
    }

    // MARK: - Execution CRUD

    /// Save a workflow execution record
    func saveExecution(_ execution: WorkflowExecution) throws {
        let data = try encoder.encode(execution)
        let path = executionFilePath(for: execution.id)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        Logger.info("Saved execution \(execution.id) for workflow '\(execution.workflowName)' (status: \(execution.status.rawValue))")
    }

    /// Load an execution by ID
    func getExecution(id: String) throws -> WorkflowExecution {
        let path = executionFilePath(for: id)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try decoder.decode(WorkflowExecution.self, from: data)
    }

    /// List executions for a specific workflow, sorted by startedAt descending
    func listExecutions(workflowId: String, limit: Int = 20) throws -> [WorkflowExecution] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: executionsDirectory) else {
            return []
        }

        var executions: [WorkflowExecution] = []

        for file in files where file.hasSuffix(".json") {
            let path = "\(executionsDirectory)/\(file)"
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let execution = try decoder.decode(WorkflowExecution.self, from: data)
                if execution.workflowId == workflowId {
                    executions.append(execution)
                }
            } catch {
                Logger.error("Failed to load execution from \(file): \(error)")
            }
        }

        // Sort newest first
        executions.sort { $0.startedAt > $1.startedAt }

        // Limit results
        if executions.count > limit {
            return Array(executions.prefix(limit))
        }
        return executions
    }

    /// Get the most recent execution for a workflow (used for summaries)
    func getLatestExecution(workflowId: String) throws -> WorkflowExecution? {
        let executions = try listExecutions(workflowId: workflowId, limit: 1)
        return executions.first
    }

    // MARK: - Private

    private func workflowFilePath(for id: String) -> String {
        "\(workflowsDirectory)/\(id).json"
    }

    private func executionFilePath(for id: String) -> String {
        "\(executionsDirectory)/\(id).json"
    }
}

// MARK: - Errors

enum WorkflowStoreError: Error, LocalizedError {
    case workflowNotFound(String)

    var errorDescription: String? {
        switch self {
        case .workflowNotFound(let id):
            return "Workflow not found: \(id)"
        }
    }
}
