import Foundation

/// Persistent storage for agent plans and their execution history.
/// Follows the same pattern as WorkflowStore.
actor AgentPlanStore {
    private let plansDirectory: String
    private let executionsDirectory: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(plansDirectory: String, executionsDirectory: String) {
        self.plansDirectory = plansDirectory
        self.executionsDirectory = executionsDirectory

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        // Ensure directories exist
        let fm = FileManager.default
        for dir in [plansDirectory, executionsDirectory] {
            if !fm.fileExists(atPath: dir) {
                try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Plan CRUD

    func savePlan(_ plan: AgentPlan) throws {
        let data = try encoder.encode(plan)
        let path = planFilePath(for: plan.id)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        Logger.info("Saved agent plan '\(plan.name)' (\(plan.id))")
    }

    func getPlan(_ id: String) -> AgentPlan? {
        let path = planFilePath(for: id)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? decoder.decode(AgentPlan.self, from: data)
    }

    func listPlans() -> [AgentPlan] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: plansDirectory) else { return [] }

        var plans: [AgentPlan] = []
        for file in files where file.hasSuffix(".json") {
            let path = "\(plansDirectory)/\(file)"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let plan = try? decoder.decode(AgentPlan.self, from: data) {
                plans.append(plan)
            }
        }

        return plans.sorted { $0.created > $1.created }
    }

    func deletePlan(_ id: String) throws {
        let path = planFilePath(for: id)
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
            Logger.info("Deleted agent plan \(id)")
        }
    }

    // MARK: - Execution CRUD

    func saveExecution(_ execution: AgentExecution) throws {
        let data = try encoder.encode(execution)
        let path = executionFilePath(for: execution.id)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        Logger.info("Saved agent execution \(execution.id) (status: \(execution.status.rawValue))")
    }

    func getExecution(_ id: String) -> AgentExecution? {
        let path = executionFilePath(for: id)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? decoder.decode(AgentExecution.self, from: data)
    }

    /// Atomic read-modify-write for an execution
    func updateExecution(_ id: String, mutate: (inout AgentExecution) -> Void) throws {
        let path = executionFilePath(for: id)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        var execution = try decoder.decode(AgentExecution.self, from: data)
        mutate(&execution)
        let updated = try encoder.encode(execution)
        try updated.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    func listExecutions(planId: String? = nil) -> [AgentExecution] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: executionsDirectory) else { return [] }

        var executions: [AgentExecution] = []
        for file in files where file.hasSuffix(".json") {
            let path = "\(executionsDirectory)/\(file)"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let execution = try? decoder.decode(AgentExecution.self, from: data) {
                if let planId = planId {
                    if execution.planId == planId {
                        executions.append(execution)
                    }
                } else {
                    executions.append(execution)
                }
            }
        }

        return executions.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Private

    private func sanitizeId(_ id: String) -> String {
        id.replacingOccurrences(of: "/", with: "")
          .replacingOccurrences(of: "\\", with: "")
          .replacingOccurrences(of: "..", with: "")
    }

    private func planFilePath(for id: String) -> String {
        "\(plansDirectory)/\(sanitizeId(id)).json"
    }

    private func executionFilePath(for id: String) -> String {
        "\(executionsDirectory)/\(sanitizeId(id)).json"
    }
}
