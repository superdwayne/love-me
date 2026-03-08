import Foundation
import Observation

@Observable
@MainActor
final class AgentPlanViewModel {
    // Published state
    var currentPlan: AgentPlan?
    var currentExecution: AgentExecution?
    var agentStreams: [String: String] = [:]    // agentId -> accumulated text
    var agentThinking: [String: String] = [:]   // agentId -> thinking text
    var agentToolActivity: [String: String] = [:]  // agentId -> current tool name
    var agentFallbacks: [String: (from: String, to: String, reason: String)] = [:]  // agentId -> fallback info
    var showPlanReview: Bool = false
    var isExecuting: Bool = false
    var recentPlans: [AgentPlan] = []
    var recentExecutions: [AgentExecution] = []

    private let webSocket: WebSocketClient

    init(webSocket: WebSocketClient) {
        self.webSocket = webSocket
    }

    // MARK: - Message Routing

    func handleMessage(_ msg: WSMessage) {
        switch msg.type {
        case WSMessageType.planGenerated:
            handlePlanGenerated(msg)

        case WSMessageType.planExecutionStarted:
            handlePlanExecutionStarted(msg)

        case WSMessageType.agentStarted:
            handleAgentStarted(msg)

        case WSMessageType.agentProgress:
            handleAgentProgress(msg)

        case WSMessageType.agentThinking:
            handleAgentThinking(msg)

        case WSMessageType.agentToolStart:
            handleAgentToolStart(msg)

        case WSMessageType.agentToolDone:
            handleAgentToolDone(msg)

        case WSMessageType.agentCompleted:
            handleAgentCompleted(msg)

        case WSMessageType.agentFailed:
            handleAgentFailed(msg)

        case WSMessageType.agentSpawning:
            handleAgentSpawning(msg)

        case WSMessageType.providerFallback:
            handleProviderFallback(msg)

        case WSMessageType.planExecutionDone:
            handlePlanExecutionDone(msg)

        case WSMessageType.planListResult:
            handlePlanListResult(msg)

        case WSMessageType.planExecutionDetail:
            handlePlanExecutionDetail(msg)

        default:
            break
        }
    }

    // MARK: - Actions

    func approvePlan() {
        guard let plan = currentPlan else { return }
        let msg = WSMessage(type: WSMessageType.planApprove, id: plan.id)
        webSocket.send(msg)
        showPlanReview = false
    }

    func rejectPlan() {
        guard let plan = currentPlan else { return }
        let msg = WSMessage(type: WSMessageType.planReject, id: plan.id)
        webSocket.send(msg)
        showPlanReview = false
        currentPlan = nil
    }

    func cancelExecution() {
        guard let execution = currentExecution else { return }
        let msg = WSMessage(type: WSMessageType.planCancel, id: execution.id)
        webSocket.send(msg)
    }

    func dismissExecution() {
        isExecuting = false
        currentExecution = nil
    }

    func requestPlanList() {
        let msg = WSMessage(type: WSMessageType.planList)
        webSocket.send(msg)
    }

    func requestExecutionDetail(executionId: String) {
        let msg = WSMessage(
            type: WSMessageType.planGetExecution,
            metadata: ["executionId": .string(executionId)]
        )
        webSocket.send(msg)
    }

    func sendEditAndApprove(metadata: [String: MetadataValue]) {
        let msg = WSMessage(type: WSMessageType.planEdit, metadata: metadata)
        webSocket.send(msg)
        showPlanReview = false
    }

    // MARK: - Private Handlers

    private func handlePlanGenerated(_ msg: WSMessage) {
        guard let meta = msg.metadata else { return }

        let dateFormatter = ISO8601DateFormatter()

        // Parse agents array from metadata
        var agents: [AgentTask] = []
        if case .array(let agentItems) = meta["agents"] {
            for item in agentItems {
                guard case .object(let dict) = item else { continue }
                guard let id = dict["id"]?.stringValue,
                      let name = dict["name"]?.stringValue else { continue }

                let providerSpec = parseProviderSpec(dict["providerSpec"])

                // Parse requiredTools
                var requiredTools: [String] = []
                if case .array(let tools) = dict["requiredTools"] {
                    requiredTools = tools.compactMap { $0.stringValue }
                }

                // Parse requiredServers
                var requiredServers: [String] = []
                if case .array(let servers) = dict["requiredServers"] {
                    requiredServers = servers.compactMap { $0.stringValue }
                }

                // Parse dependsOn
                var dependsOn: [String]?
                if case .array(let deps) = dict["dependsOn"] {
                    dependsOn = deps.compactMap { $0.stringValue }
                }

                // outputSchema as JSON string
                var outputSchema: String?
                if let schemaVal = dict["outputSchema"], case .object(_) = schemaVal {
                    if let schemaData = try? JSONEncoder().encode(schemaVal),
                       let schemaStr = String(data: schemaData, encoding: .utf8) {
                        outputSchema = schemaStr
                    }
                }

                agents.append(AgentTask(
                    id: id,
                    name: name,
                    objective: dict["objective"]?.stringValue ?? "",
                    systemPrompt: dict["systemPrompt"]?.stringValue ?? "",
                    requiredTools: requiredTools,
                    requiredServers: requiredServers,
                    dependsOn: dependsOn,
                    maxTurns: dict["maxTurns"]?.intValue ?? 10,
                    providerSpec: providerSpec,
                    outputSchema: outputSchema
                ))
            }
        }

        var created = Date()
        if let dateStr = meta["created"]?.stringValue,
           let parsed = dateFormatter.date(from: dateStr) {
            created = parsed
        }

        let plan = AgentPlan(
            id: msg.id ?? meta["id"]?.stringValue ?? UUID().uuidString,
            name: meta["name"]?.stringValue ?? "Untitled Plan",
            description: meta["description"]?.stringValue ?? "",
            agents: agents,
            createdFrom: meta["createdFrom"]?.stringValue,
            estimatedCost: meta["estimatedCost"]?.doubleValue,
            created: created
        )

        currentPlan = plan
        showPlanReview = true

        // Clear previous streams
        agentStreams = [:]
        agentThinking = [:]
        agentToolActivity = [:]

        HapticManager.connectionEstablished()
    }

    private func handlePlanExecutionStarted(_ msg: WSMessage) {
        guard let meta = msg.metadata else { return }

        let dateFormatter = ISO8601DateFormatter()

        // Parse agent results
        var agentResults: [AgentResult] = []
        if case .array(let resultItems) = meta["agentResults"] {
            for item in resultItems {
                guard case .object(let dict) = item else { continue }
                agentResults.append(parseAgentResult(dict))
            }
        }

        var startedAt = Date()
        if let dateStr = meta["startedAt"]?.stringValue,
           let parsed = dateFormatter.date(from: dateStr) {
            startedAt = parsed
        }

        let statusStr = meta["status"]?.stringValue ?? "running"
        let status = AgentExecutionStatus(rawValue: statusStr) ?? .running

        let execution = AgentExecution(
            id: msg.id ?? meta["executionId"]?.stringValue ?? UUID().uuidString,
            planId: meta["planId"]?.stringValue ?? currentPlan?.id ?? "",
            planName: meta["planName"]?.stringValue ?? currentPlan?.name ?? "",
            status: status,
            startedAt: startedAt,
            agentResults: agentResults,
            parentAgentId: meta["parentAgentId"]?.stringValue
        )

        currentExecution = execution
        isExecuting = true
        showPlanReview = false

        // Clear streams for fresh execution
        agentStreams = [:]
        agentThinking = [:]
        agentToolActivity = [:]
        agentFallbacks = [:]

        HapticManager.stepStarted()
    }

    private func handleAgentStarted(_ msg: WSMessage) {
        let agentId = msg.metadata?["agentId"]?.stringValue ?? ""
        let agentName = msg.metadata?["agentName"]?.stringValue ?? ""
        let provider = msg.metadata?["provider"]?.stringValue ?? ""
        let model = msg.metadata?["model"]?.stringValue ?? ""

        guard !agentId.isEmpty else { return }

        // Initialize stream for this agent
        agentStreams[agentId] = ""
        agentThinking[agentId] = ""

        // Update or add agent result in current execution
        if var execution = currentExecution {
            if let index = execution.agentResults.firstIndex(where: { $0.agentId == agentId }) {
                execution.agentResults[index].status = .running
                execution.agentResults[index].startedAt = Date()
            } else {
                execution.agentResults.append(AgentResult(
                    agentId: agentId,
                    agentName: agentName,
                    status: .running,
                    provider: provider,
                    model: model,
                    startedAt: Date()
                ))
            }
            currentExecution = execution
        }

        HapticManager.stepStarted()
    }

    private func handleAgentProgress(_ msg: WSMessage) {
        let agentId = msg.metadata?["agentId"]?.stringValue ?? ""
        let text = msg.content ?? ""

        guard !agentId.isEmpty else { return }

        agentStreams[agentId, default: ""] += text
    }

    private func handleAgentThinking(_ msg: WSMessage) {
        let agentId = msg.metadata?["agentId"]?.stringValue ?? ""
        let text = msg.content ?? ""

        guard !agentId.isEmpty else { return }

        agentThinking[agentId, default: ""] += text
    }

    private func handleAgentToolStart(_ msg: WSMessage) {
        let agentId = msg.metadata?["agentId"]?.stringValue ?? ""
        let tool = msg.metadata?["tool"]?.stringValue ?? ""

        guard !agentId.isEmpty else { return }

        agentToolActivity[agentId] = tool
    }

    private func handleAgentToolDone(_ msg: WSMessage) {
        let agentId = msg.metadata?["agentId"]?.stringValue ?? ""

        guard !agentId.isEmpty else { return }

        agentToolActivity[agentId] = nil

        // Update tool call count
        if var execution = currentExecution,
           let index = execution.agentResults.firstIndex(where: { $0.agentId == agentId }) {
            execution.agentResults[index].toolCallCount += 1
            currentExecution = execution
        }
    }

    private func handleAgentCompleted(_ msg: WSMessage) {
        let agentId = msg.metadata?["agentId"]?.stringValue ?? ""
        let output = msg.content ?? msg.metadata?["output"]?.stringValue ?? ""

        guard !agentId.isEmpty else { return }

        // Clear tool activity
        agentToolActivity[agentId] = nil

        // Update agent result
        if var execution = currentExecution,
           let index = execution.agentResults.firstIndex(where: { $0.agentId == agentId }) {
            execution.agentResults[index].status = .success
            execution.agentResults[index].completedAt = Date()
            execution.agentResults[index].output = output
            currentExecution = execution
        }

        HapticManager.stepCompleted()
    }

    private func handleAgentFailed(_ msg: WSMessage) {
        let agentId = msg.metadata?["agentId"]?.stringValue ?? ""
        let error = msg.content ?? msg.metadata?["error"]?.stringValue ?? "Unknown error"

        guard !agentId.isEmpty else { return }

        // Clear tool activity
        agentToolActivity[agentId] = nil

        // Update agent result
        if var execution = currentExecution,
           let index = execution.agentResults.firstIndex(where: { $0.agentId == agentId }) {
            execution.agentResults[index].status = .error
            execution.agentResults[index].completedAt = Date()
            execution.agentResults[index].error = error
            currentExecution = execution
        }

        HapticManager.toolError()
    }

    private func handleAgentSpawning(_ msg: WSMessage) {
        let agentId = msg.metadata?["agentId"]?.stringValue ?? ""
        let childPlanId = msg.metadata?["childPlanId"]?.stringValue

        guard !agentId.isEmpty else { return }

        // Update agent result to spawning status
        if var execution = currentExecution,
           let index = execution.agentResults.firstIndex(where: { $0.agentId == agentId }) {
            execution.agentResults[index].status = .spawning
            if let childId = childPlanId {
                execution.agentResults[index].childExecutionId = childId
            }
            currentExecution = execution
        }
    }

    private func handleProviderFallback(_ msg: WSMessage) {
        let agentId = msg.metadata?["agentId"]?.stringValue ?? ""
        let from = msg.metadata?["from"]?.stringValue ?? ""
        let to = msg.metadata?["to"]?.stringValue ?? ""
        let reason = msg.metadata?["reason"]?.stringValue ?? ""

        guard !agentId.isEmpty else { return }

        agentFallbacks[agentId] = (from: from, to: to, reason: reason)
    }

    private func handlePlanExecutionDone(_ msg: WSMessage) {
        guard let meta = msg.metadata else { return }

        let dateFormatter = ISO8601DateFormatter()
        let statusStr = meta["status"]?.stringValue ?? "completed"
        let status = AgentExecutionStatus(rawValue: statusStr) ?? .completed

        if var execution = currentExecution {
            execution.status = status
            if let dateStr = meta["completedAt"]?.stringValue,
               let parsed = dateFormatter.date(from: dateStr) {
                execution.completedAt = parsed
            } else {
                execution.completedAt = Date()
            }
            if let cost = meta["totalCost"]?.doubleValue {
                execution.totalCost = cost
            }
            currentExecution = execution
        }

        isExecuting = false

        HapticManager.workflowCompleted()
    }

    private func handlePlanListResult(_ msg: WSMessage) {
        guard let meta = msg.metadata else { return }

        let dateFormatter = ISO8601DateFormatter()

        // Parse plans
        var plans: [AgentPlan] = []
        if case .array(let planItems) = meta["plans"] {
            for item in planItems {
                guard case .object(let dict) = item else { continue }
                if let plan = parsePlanFromMetadata(dict, dateFormatter: dateFormatter) {
                    plans.append(plan)
                }
            }
        }
        recentPlans = plans

        // Parse executions
        var executions: [AgentExecution] = []
        if case .array(let execItems) = meta["executions"] {
            for item in execItems {
                guard case .object(let dict) = item else { continue }
                if let execution = parseExecutionFromMetadata(dict, dateFormatter: dateFormatter) {
                    executions.append(execution)
                }
            }
        }
        recentExecutions = executions
    }

    private func handlePlanExecutionDetail(_ msg: WSMessage) {
        guard let meta = msg.metadata else { return }

        let dateFormatter = ISO8601DateFormatter()
        if let execution = parseExecutionFromMetadata(meta, dateFormatter: dateFormatter) {
            currentExecution = execution
            isExecuting = execution.status == .running
        }
    }

    // MARK: - Parsing Helpers

    private func parseProviderSpec(_ value: MetadataValue?) -> AgentProviderSpec {
        guard case .object(let dict) = value else {
            return AgentProviderSpec(provider: .claude(model: "claude-sonnet-4-5-20250929"))
        }

        let provider: AgentProvider
        if case .object(let providerDict) = dict["provider"] {
            let type = providerDict["type"]?.stringValue ?? "claude"
            let model = providerDict["model"]?.stringValue ?? "claude-sonnet-4-5-20250929"
            switch type {
            case "ollama": provider = .ollama(model: model)
            case "openai": provider = .openai(model: model)
            default: provider = .claude(model: model)
            }
        } else {
            provider = .claude(model: "claude-sonnet-4-5-20250929")
        }

        return AgentProviderSpec(
            provider: provider,
            thinkingBudget: dict["thinkingBudget"]?.intValue,
            maxTokens: dict["maxTokens"]?.intValue ?? 16384,
            temperature: dict["temperature"]?.doubleValue
        )
    }

    private func parseAgentResult(_ dict: [String: MetadataValue]) -> AgentResult {
        let dateFormatter = ISO8601DateFormatter()

        var startedAt: Date?
        if let dateStr = dict["startedAt"]?.stringValue,
           let parsed = dateFormatter.date(from: dateStr) {
            startedAt = parsed
        }

        var completedAt: Date?
        if let dateStr = dict["completedAt"]?.stringValue,
           let parsed = dateFormatter.date(from: dateStr) {
            completedAt = parsed
        }

        return AgentResult(
            agentId: dict["agentId"]?.stringValue ?? "",
            agentName: dict["agentName"]?.stringValue ?? "",
            status: AgentResultStatus(rawValue: dict["status"]?.stringValue ?? "pending") ?? .pending,
            provider: dict["provider"]?.stringValue ?? "",
            model: dict["model"]?.stringValue ?? "",
            startedAt: startedAt,
            completedAt: completedAt,
            output: dict["output"]?.stringValue,
            error: dict["error"]?.stringValue,
            turnCount: dict["turnCount"]?.intValue ?? 0,
            toolCallCount: dict["toolCallCount"]?.intValue ?? 0,
            childExecutionId: dict["childExecutionId"]?.stringValue
        )
    }

    private func parsePlanFromMetadata(_ dict: [String: MetadataValue], dateFormatter: ISO8601DateFormatter) -> AgentPlan? {
        guard let id = dict["id"]?.stringValue,
              let name = dict["name"]?.stringValue else { return nil }

        var agents: [AgentTask] = []
        if case .array(let agentItems) = dict["agents"] {
            for item in agentItems {
                guard case .object(let agentDict) = item else { continue }
                guard let agentId = agentDict["id"]?.stringValue,
                      let agentName = agentDict["name"]?.stringValue else { continue }

                let providerSpec = parseProviderSpec(agentDict["providerSpec"])

                var requiredTools: [String] = []
                if case .array(let tools) = agentDict["requiredTools"] {
                    requiredTools = tools.compactMap { $0.stringValue }
                }

                var requiredServers: [String] = []
                if case .array(let servers) = agentDict["requiredServers"] {
                    requiredServers = servers.compactMap { $0.stringValue }
                }

                var dependsOn: [String]?
                if case .array(let deps) = agentDict["dependsOn"] {
                    dependsOn = deps.compactMap { $0.stringValue }
                }

                agents.append(AgentTask(
                    id: agentId,
                    name: agentName,
                    objective: agentDict["objective"]?.stringValue ?? "",
                    systemPrompt: agentDict["systemPrompt"]?.stringValue ?? "",
                    requiredTools: requiredTools,
                    requiredServers: requiredServers,
                    dependsOn: dependsOn,
                    maxTurns: agentDict["maxTurns"]?.intValue ?? 10,
                    providerSpec: providerSpec
                ))
            }
        }

        var created = Date()
        if let dateStr = dict["created"]?.stringValue,
           let parsed = dateFormatter.date(from: dateStr) {
            created = parsed
        }

        return AgentPlan(
            id: id,
            name: name,
            description: dict["description"]?.stringValue ?? "",
            agents: agents,
            createdFrom: dict["createdFrom"]?.stringValue,
            estimatedCost: dict["estimatedCost"]?.doubleValue,
            created: created
        )
    }

    private func parseExecutionFromMetadata(_ dict: [String: MetadataValue], dateFormatter: ISO8601DateFormatter) -> AgentExecution? {
        let id = dict["id"]?.stringValue ?? dict["executionId"]?.stringValue
        guard let id else { return nil }

        var startedAt = Date()
        if let dateStr = dict["startedAt"]?.stringValue,
           let parsed = dateFormatter.date(from: dateStr) {
            startedAt = parsed
        }

        var completedAt: Date?
        if let dateStr = dict["completedAt"]?.stringValue,
           let parsed = dateFormatter.date(from: dateStr) {
            completedAt = parsed
        }

        var agentResults: [AgentResult] = []
        if case .array(let resultItems) = dict["agentResults"] {
            for item in resultItems {
                guard case .object(let resultDict) = item else { continue }
                agentResults.append(parseAgentResult(resultDict))
            }
        }

        let statusStr = dict["status"]?.stringValue ?? "pending"
        let status = AgentExecutionStatus(rawValue: statusStr) ?? .pending

        return AgentExecution(
            id: id,
            planId: dict["planId"]?.stringValue ?? "",
            planName: dict["planName"]?.stringValue ?? "",
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            agentResults: agentResults,
            parentAgentId: dict["parentAgentId"]?.stringValue,
            totalCost: dict["totalCost"]?.doubleValue
        )
    }
}
