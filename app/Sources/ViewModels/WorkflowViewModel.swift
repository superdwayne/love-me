import Foundation
import Observation

// MARK: - Local Models for iOS UI

struct WorkflowItem: Identifiable, Sendable {
    let id: String
    var name: String
    var description: String
    var enabled: Bool
    var triggerType: String       // "cron" or "event"
    var triggerDetail: String     // cron expression or "source:eventType"
    var stepCount: Int
    var lastRunStatus: String?
    var lastRunAt: Date?
}

struct WorkflowDetail: Sendable {
    let id: String
    var name: String
    var description: String
    var enabled: Bool
    var trigger: WorkflowTriggerInfo
    var steps: [WorkflowStepInfo]
    var notifyOnStart: Bool
    var notifyOnComplete: Bool
    var notifyOnError: Bool
    var notifyOnStepComplete: Bool
}

struct InputParamInfo: Sendable {
    let name: String
    let label: String
    let placeholder: String?
}

struct WorkflowTriggerInfo: Sendable {
    var type: String  // "cron", "event", or "manual"
    var cronExpression: String?
    var eventSource: String?
    var eventType: String?
    var eventFilter: [String: String]?
    var inputParams: [InputParamInfo]?
}

struct WorkflowStepInfo: Identifiable, Sendable {
    let id: String
    var name: String
    var toolName: String
    var serverName: String
    var inputs: [String: String]
    var dependsOn: [String]?
    var onError: String  // "stop", "skip", "retry"
    var preferredProvider: String?  // "provider:model" for per-step LLM routing
}

struct ExecutionItem: Identifiable, Sendable {
    let id: String
    let workflowId: String
    let workflowName: String
    var status: String  // pending, running, completed, failed, cancelled
    let startedAt: Date
    var completedAt: Date?
    var triggerInfo: String
    var steps: [ExecutionStepItem]
}

struct ExecutionStepItem: Identifiable, Sendable {
    let id: String
    let stepName: String
    var status: String  // pending, running, success, error, skipped
    var startedAt: Date?
    var completedAt: Date?
    var output: String?
    var error: String?

    var duration: TimeInterval? {
        guard let start = startedAt, let end = completedAt else { return nil }
        return end.timeIntervalSince(start)
    }
}

struct WorkflowNotification: Sendable {
    let title: String
    let body: String
    let workflowId: String
    let executionId: String
    let type: String  // started, completed, failed, stepCompleted
}

enum ToolIOType: String, Codable, Sendable, CaseIterable {
    case text
    case image
    case file
    case json
    case audio
    case video
    case mesh3d
    case code
    case any
}

struct SchemaProperty: Sendable {
    let name: String
    let type: String  // "string", "number", "boolean", "integer", "array", "object"
    let description: String
    let isRequired: Bool
    let enumValues: [String]?
}

struct MCPToolItem: Identifiable, Sendable {
    var id: String { "\(serverName)_\(name)" }
    let name: String
    let description: String
    let serverName: String
    let outputType: ToolIOType
    let acceptsInputTypes: [ToolIOType]
    let schemaProperties: [SchemaProperty]
}

struct ParsedSchedule: Sendable {
    let success: Bool
    let cron: String?
    let description: String?
    let message: String?
}

struct BuilderWorkflowResult: Sendable {
    let id: String
    let name: String
    let description: String
    let cronExpression: String
    let scheduleDescription: String
    let steps: [BuilderStepResult]
    let needsConfiguration: Bool
    let triggerType: String
    let inputParams: [InputParamInfo]?
}

struct BuilderStepResult: Identifiable, Sendable {
    let id: String
    let name: String
    let toolName: String
    let serverName: String
    let needsConfiguration: Bool
    let inputs: [String: String]
    let dependsOn: [String]?
    let preferredProvider: String?
}

// MARK: - Workflow Analysis & Enhancement Models

struct WorkflowIssueInfo: Identifiable, Sendable {
    let id: String
    let severity: String   // critical, warning, suggestion
    let category: String
    let message: String
    let affectedStepId: String?
    let affectedStepName: String?
    let suggestion: String
    let fixed: Bool
}

struct WorkflowAnalysisInfo: Sendable {
    let workflowId: String
    let workflowName: String
    let overallHealth: String   // excellent, good, fair, poor
    let healthScore: Int
    let issues: [WorkflowIssueInfo]
    let missingElements: [WorkflowMissingElement]
    let recommendations: [WorkflowRecommendation]
}

struct WorkflowMissingElement: Identifiable, Sendable {
    let id: String
    let elementType: String
    let description: String
    let recommendedValue: String?
}

struct WorkflowRecommendation: Identifiable, Sendable {
    let id: String
    let title: String
    let description: String
    let category: String
}

struct WorkflowEnhanceInfo: Sendable {
    let workflowId: String
    let workflowName: String
    let healthScore: Int
    let overallHealth: String
    let issues: [WorkflowIssueInfo]
    let fixesApplied: [WorkflowFixInfo]
    let fixCount: Int
    let enhanced: Bool
}

struct WorkflowFixInfo: Identifiable, Sendable {
    let id: String = UUID().uuidString
    let description: String
    let affectedStep: String?
    let suggestion: String
}

// MARK: - Enhance & Test Models

struct EnhanceTestIterationInfo: Identifiable, Sendable {
    let id: Int  // iteration number
    let preFixHealthScore: Int
    let postFixHealthScore: Int
    let issuesFound: Int
    let issuesFixed: Int
    let fixDescriptions: [String]
    let executionStatus: String
    let failedStepName: String?
    let failedStepError: String?
}

struct EnhanceTestResultInfo: Sendable {
    let converged: Bool
    let iterations: [EnhanceTestIterationInfo]
    let finalHealthScore: Int
    let totalIterations: Int
    let totalFixesApplied: Int
}

// MARK: - Editable Types (shared across builders)

struct EditableStep: Identifiable {
    let id: String
    var name: String
    var toolName: String
    var serverName: String
    var onError: String
    var inputs: [String: String]

    init(id: String = UUID().uuidString, name: String = "", toolName: String = "", serverName: String = "", onError: String = "stop", inputs: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.toolName = toolName
        self.serverName = serverName
        self.onError = onError
        self.inputs = inputs
    }
}

struct EditableInputParam: Identifiable {
    let id: String
    var name: String
    var label: String
    var placeholder: String

    init(id: String = UUID().uuidString, name: String = "", label: String = "", placeholder: String = "") {
        self.id = id
        self.name = name
        self.label = label
        self.placeholder = placeholder
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class WorkflowViewModel {
    var workflows: [WorkflowItem] = []
    var currentWorkflow: WorkflowDetail?
    var executions: [ExecutionItem] = []
    var currentExecution: ExecutionItem?
    var isLoading: Bool = false
    var notification: WorkflowNotification?

    // Toggle state
    private var pendingToggles: [String: Bool] = [:]

    // Visual Builder state
    var availableTools: [MCPToolItem] = []
    var isLoadingTools: Bool = false
    var parsedSchedule: ParsedSchedule?
    var isParsingSchedule: Bool = false
    var builderResult: BuilderWorkflowResult?
    var isBuilding: Bool = false
    var builderError: String?

    // Workflow Enhancement state
    var analysisResult: WorkflowAnalysisInfo?
    var enhanceResult: WorkflowEnhanceInfo?
    var isAnalyzing: Bool = false
    var isEnhancing: Bool = false
    var enhanceError: String?

    // Enhance & Test state
    var isEnhanceTestRunning: Bool = false
    var enhanceTestPhase: String = ""
    var enhanceTestIteration: Int = 0
    var enhanceTestMaxIterations: Int = 0
    var enhanceTestMessage: String = ""
    var enhanceTestResult: EnhanceTestResultInfo?

    // Refinement state
    var isRefining: Bool = false
    var refinementError: String?

    private let webSocket: WebSocketClient

    init(webSocket: WebSocketClient) {
        self.webSocket = webSocket
    }

    // MARK: - Public Actions

    func loadWorkflows() {
        isLoading = true
        let msg = WSMessage(type: WSMessageType.listWorkflows)
        webSocket.send(msg)
    }

    func loadWorkflow(id: String) {
        isLoading = true
        let msg = WSMessage(
            type: WSMessageType.getWorkflow,
            metadata: ["workflowId": .string(id)]
        )
        webSocket.send(msg)
    }

    func createWorkflow(_ detail: WorkflowDetail) {
        let msg = WSMessage(
            type: WSMessageType.createWorkflow,
            metadata: encodeWorkflowDetail(detail)
        )
        webSocket.send(msg)
    }

    func updateWorkflow(_ detail: WorkflowDetail) {
        let msg = WSMessage(
            type: WSMessageType.updateWorkflow,
            metadata: encodeWorkflowDetail(detail)
        )
        webSocket.send(msg)
    }

    func deleteWorkflow(id: String) {
        let msg = WSMessage(
            type: WSMessageType.deleteWorkflow,
            metadata: ["workflowId": .string(id)]
        )
        webSocket.send(msg)
        workflows.removeAll { $0.id == id }
    }

    func runWorkflow(id: String, inputParams: [String: String] = [:]) {
        var metadata: [String: MetadataValue] = ["workflowId": .string(id)]
        if !inputParams.isEmpty {
            var paramsDict: [String: MetadataValue] = [:]
            for (key, value) in inputParams {
                paramsDict[key] = .string(value)
            }
            metadata["inputParams"] = .object(paramsDict)
        }
        let msg = WSMessage(
            type: WSMessageType.runWorkflow,
            metadata: metadata
        )
        webSocket.send(msg)
    }

    func cancelExecution(id: String) {
        let msg = WSMessage(
            type: WSMessageType.cancelWorkflow,
            metadata: ["executionId": .string(id)]
        )
        webSocket.send(msg)
    }

    func loadExecutions(workflowId: String) {
        isLoading = true
        let msg = WSMessage(
            type: WSMessageType.listExecutions,
            metadata: ["workflowId": .string(workflowId)]
        )
        webSocket.send(msg)
    }

    func loadExecution(id: String) {
        isLoading = true
        let msg = WSMessage(
            type: WSMessageType.getExecution,
            metadata: ["executionId": .string(id)]
        )
        webSocket.send(msg)
    }

    func toggleWorkflowEnabled(id: String) {
        // Optimistically update local state
        if let index = workflows.firstIndex(where: { $0.id == id }) {
            let newEnabled = !workflows[index].enabled
            workflows[index].enabled = newEnabled
            // Store pending toggle, then load full detail to send update
            pendingToggles[id] = newEnabled
            loadWorkflow(id: id)
        }
    }

    func loadMCPTools() {
        isLoadingTools = true
        let msg = WSMessage(type: WSMessageType.mcpToolsList)
        webSocket.send(msg)
    }

    func parseSchedule(text: String) {
        isParsingSchedule = true
        let msg = WSMessage(
            type: WSMessageType.parseSchedule,
            content: text
        )
        webSocket.send(msg)
    }

    func buildWorkflow(prompt: String) {
        isBuilding = true
        builderError = nil
        builderResult = nil
        let msg = WSMessage(
            type: WSMessageType.buildWorkflow,
            content: prompt
        )
        webSocket.send(msg)
    }

    func analyzeWorkflow(id: String) {
        isAnalyzing = true
        analysisResult = nil
        let msg = WSMessage(
            type: WSMessageType.analyzeWorkflow,
            id: id,
            metadata: ["workflowId": .string(id)]
        )
        webSocket.send(msg)
    }

    func enhanceWorkflow(id: String) {
        isEnhancing = true
        enhanceResult = nil
        enhanceError = nil
        let msg = WSMessage(
            type: WSMessageType.enhanceWorkflow,
            id: id,
            metadata: ["workflowId": .string(id)]
        )
        webSocket.send(msg)
    }

    func clearAnalysis() {
        analysisResult = nil
        enhanceResult = nil
        enhanceError = nil
    }

    func enhanceAndTest(id: String, maxIterations: Int = 3) {
        isEnhanceTestRunning = true
        enhanceTestPhase = "starting"
        enhanceTestIteration = 0
        enhanceTestMessage = "Starting enhance & test..."
        enhanceTestResult = nil
        let msg = WSMessage(
            type: WSMessageType.enhanceAndTest,
            id: id,
            metadata: [
                "workflowId": .string(id),
                "maxIterations": .int(maxIterations)
            ]
        )
        webSocket.send(msg)
    }

    func cancelEnhanceTest(id: String) {
        let msg = WSMessage(
            type: WSMessageType.cancelEnhanceTest,
            id: id,
            metadata: ["workflowId": .string(id)]
        )
        webSocket.send(msg)
    }

    func clearEnhanceTest() {
        isEnhanceTestRunning = false
        enhanceTestPhase = ""
        enhanceTestIteration = 0
        enhanceTestMaxIterations = 0
        enhanceTestMessage = ""
        enhanceTestResult = nil
    }

    func refineWorkflow(workflowId: String, refinementPrompt: String) {
        isRefining = true
        refinementError = nil
        let msg = WSMessage(
            type: WSMessageType.refineWorkflow,
            id: workflowId,
            content: refinementPrompt,
            metadata: ["workflowId": .string(workflowId), "prompt": .string(refinementPrompt)]
        )
        webSocket.send(msg)
    }

    func validateWorkflow(id: String) {
        let msg = WSMessage(
            type: WSMessageType.validateWorkflow,
            id: id,
            metadata: ["workflowId": .string(id)]
        )
        webSocket.send(msg)
    }

    func saveBuiltWorkflow() {
        guard let result = builderResult else { return }

        let steps = result.steps.map { step in
            WorkflowStepInfo(
                id: step.id,
                name: step.name,
                toolName: step.toolName,
                serverName: step.serverName,
                inputs: step.inputs,
                dependsOn: step.dependsOn,
                onError: "stop",
                preferredProvider: step.preferredProvider
            )
        }

        let trigger: WorkflowTriggerInfo
        if result.triggerType == "manual" {
            trigger = WorkflowTriggerInfo(
                type: "manual",
                inputParams: result.inputParams
            )
        } else {
            trigger = WorkflowTriggerInfo(
                type: "cron",
                cronExpression: result.cronExpression
            )
        }

        let detail = WorkflowDetail(
            id: result.id,
            name: result.name,
            description: result.description,
            enabled: true,
            trigger: trigger,
            steps: steps,
            notifyOnStart: false,
            notifyOnComplete: true,
            notifyOnError: true,
            notifyOnStepComplete: false
        )
        createWorkflow(detail)
        builderResult = nil
    }

    // MARK: - Message Routing

    func handleMessage(_ msg: WSMessage) {
        switch msg.type {
        case WSMessageType.status:
            loadWorkflows()

        case WSMessageType.workflowList:
            handleWorkflowList(msg)

        case WSMessageType.workflowDetail:
            handleWorkflowDetail(msg)

        case WSMessageType.workflowCreated:
            handleWorkflowCreated(msg)

        case WSMessageType.workflowUpdated:
            handleWorkflowUpdated(msg)

        case WSMessageType.workflowDeleted:
            handleWorkflowDeleted(msg)

        case WSMessageType.workflowExecutionStarted:
            handleExecutionStarted(msg)

        case WSMessageType.workflowStepUpdate:
            handleStepUpdate(msg)

        case WSMessageType.workflowExecutionDone:
            handleExecutionDone(msg)

        case WSMessageType.executionList:
            handleExecutionList(msg)

        case WSMessageType.executionDetail:
            handleExecutionDetail(msg)

        case WSMessageType.workflowNotification:
            handleNotification(msg)

        case WSMessageType.mcpToolsListResult:
            handleMCPToolsListResult(msg)

        case WSMessageType.parseScheduleResult:
            handleParseScheduleResult(msg)

        case WSMessageType.buildWorkflowResult:
            handleBuildWorkflowResult(msg)

        case WSMessageType.analyzeWorkflowResult:
            handleAnalyzeWorkflowResult(msg)

        case WSMessageType.enhanceWorkflowResult:
            handleEnhanceWorkflowResult(msg)

        case WSMessageType.enhanceTestProgress:
            handleEnhanceTestProgress(msg)

        case WSMessageType.enhanceTestDone:
            handleEnhanceTestDone(msg)

        case WSMessageType.validateWorkflowResult:
            break // Validation results consumed by UI directly via enhance result

        case WSMessageType.refineWorkflowResult:
            handleRefineWorkflowResult(msg)

        case WSMessageType.error:
            handleError(msg)

        default:
            break
        }
    }

    // MARK: - Private Handlers

    private func handleWorkflowList(_ msg: WSMessage) {
        isLoading = false
        guard case .array(let items) = msg.metadata?["workflows"] else {
            return
        }

        let dateFormatter = ISO8601DateFormatter()
        var loaded: [WorkflowItem] = []

        for item in items {
            guard case .object(let dict) = item else { continue }
            guard let id = dict["id"]?.stringValue,
                  let name = dict["name"]?.stringValue else { continue }

            let description = dict["description"]?.stringValue ?? ""
            let enabled = dict["enabled"]?.boolValue ?? true
            let triggerType = dict["triggerType"]?.stringValue ?? "cron"
            let triggerDetail = dict["triggerDetail"]?.stringValue ?? ""
            let stepCount = dict["stepCount"]?.intValue ?? 0
            let lastRunStatus = dict["lastRunStatus"]?.stringValue

            var lastRunAt: Date?
            if let dateStr = dict["lastRunAt"]?.stringValue,
               let date = dateFormatter.date(from: dateStr) {
                lastRunAt = date
            }

            loaded.append(WorkflowItem(
                id: id,
                name: name,
                description: description,
                enabled: enabled,
                triggerType: triggerType,
                triggerDetail: triggerDetail,
                stepCount: stepCount,
                lastRunStatus: lastRunStatus,
                lastRunAt: lastRunAt
            ))
        }

        workflows = loaded
    }

    private func handleWorkflowDetail(_ msg: WSMessage) {
        isLoading = false
        guard let meta = msg.metadata else { return }
        guard let id = meta["id"]?.stringValue,
              let name = meta["name"]?.stringValue else { return }

        // Trigger may be nested under "trigger" key or flat at top level
        let trigger: WorkflowTriggerInfo
        if case .object(_) = meta["trigger"] {
            trigger = parseTriggerInfo(meta["trigger"])
        } else {
            // Flat keys from daemon's encodeWorkflowToMetadata
            var parsedInputParams: [InputParamInfo]?
            if case .array(let items) = meta["inputParams"] {
                parsedInputParams = items.compactMap { item -> InputParamInfo? in
                    guard case .object(let dict) = item,
                          let name = dict["name"]?.stringValue,
                          let label = dict["label"]?.stringValue else { return nil }
                    return InputParamInfo(name: name, label: label, placeholder: dict["placeholder"]?.stringValue)
                }
            }
            trigger = WorkflowTriggerInfo(
                type: meta["triggerType"]?.stringValue ?? "cron",
                cronExpression: meta["cronExpression"]?.stringValue,
                eventSource: meta["eventSource"]?.stringValue,
                eventType: meta["eventType"]?.stringValue,
                inputParams: parsedInputParams
            )
        }
        let steps = parseSteps(meta["steps"])

        var detail = WorkflowDetail(
            id: id,
            name: name,
            description: meta["description"]?.stringValue ?? "",
            enabled: meta["enabled"]?.boolValue ?? true,
            trigger: trigger,
            steps: steps,
            notifyOnStart: meta["notifyOnStart"]?.boolValue ?? false,
            notifyOnComplete: meta["notifyOnComplete"]?.boolValue ?? true,
            notifyOnError: meta["notifyOnError"]?.boolValue ?? true,
            notifyOnStepComplete: meta["notifyOnStepComplete"]?.boolValue ?? false
        )

        // Apply pending toggle if one exists
        if let newEnabled = pendingToggles.removeValue(forKey: id) {
            detail.enabled = newEnabled
            updateWorkflow(detail)
        }

        currentWorkflow = detail
    }

    private func handleError(_ msg: WSMessage) {
        let errorMessage = msg.content ?? msg.metadata?["message"]?.stringValue ?? "Unknown error"
        // Clear any in-progress states
        if isBuilding {
            isBuilding = false
            builderError = errorMessage
        }
        if isLoadingTools {
            isLoadingTools = false
        }
        if isParsingSchedule {
            isParsingSchedule = false
        }
        if isLoading {
            isLoading = false
        }
    }

    private func handleWorkflowCreated(_ msg: WSMessage) {
        guard let meta = msg.metadata else { return }
        let id = msg.id ?? meta["id"]?.stringValue
        let name = meta["name"]?.stringValue
        guard let id, let name else { return }

        let item = WorkflowItem(
            id: id,
            name: name,
            description: meta["description"]?.stringValue ?? "",
            enabled: meta["enabled"]?.boolValue ?? true,
            triggerType: meta["triggerType"]?.stringValue ?? "cron",
            triggerDetail: meta["triggerDetail"]?.stringValue ?? "",
            stepCount: meta["stepCount"]?.intValue ?? 0,
            lastRunStatus: nil,
            lastRunAt: nil
        )
        workflows.insert(item, at: 0)
    }

    private func handleWorkflowUpdated(_ msg: WSMessage) {
        guard let meta = msg.metadata else { return }
        guard let id = meta["id"]?.stringValue else { return }

        if let index = workflows.firstIndex(where: { $0.id == id }) {
            if let name = meta["name"]?.stringValue {
                workflows[index].name = name
            }
            if let description = meta["description"]?.stringValue {
                workflows[index].description = description
            }
            if let enabled = meta["enabled"]?.boolValue {
                workflows[index].enabled = enabled
            }
            if let triggerType = meta["triggerType"]?.stringValue {
                workflows[index].triggerType = triggerType
            }
            if let triggerDetail = meta["triggerDetail"]?.stringValue {
                workflows[index].triggerDetail = triggerDetail
            }
            if let stepCount = meta["stepCount"]?.intValue {
                workflows[index].stepCount = stepCount
            }
        }

        // Also update currentWorkflow if it matches
        if currentWorkflow?.id == id {
            loadWorkflow(id: id)
        }
    }

    private func handleWorkflowDeleted(_ msg: WSMessage) {
        let id = msg.id ?? msg.metadata?["workflowId"]?.stringValue
        if let id {
            workflows.removeAll { $0.id == id }
            if currentWorkflow?.id == id {
                currentWorkflow = nil
            }
        }
    }

    private func handleExecutionStarted(_ msg: WSMessage) {
        guard let meta = msg.metadata else { return }
        guard let execId = meta["executionId"]?.stringValue,
              let workflowId = meta["workflowId"]?.stringValue else { return }

        let workflowName = meta["workflowName"]?.stringValue ?? ""
        let triggerInfo = meta["triggerInfo"]?.stringValue ?? "manual"

        let execution = ExecutionItem(
            id: execId,
            workflowId: workflowId,
            workflowName: workflowName,
            status: "running",
            startedAt: Date(),
            completedAt: nil,
            triggerInfo: triggerInfo,
            steps: parseExecutionSteps(meta["steps"])
        )

        executions.insert(execution, at: 0)

        // Update the workflow's last run status
        if let index = workflows.firstIndex(where: { $0.id == workflowId }) {
            workflows[index].lastRunStatus = "running"
            workflows[index].lastRunAt = Date()
        }
    }

    private func handleStepUpdate(_ msg: WSMessage) {
        guard let meta = msg.metadata else { return }
        guard let execId = meta["executionId"]?.stringValue,
              let stepId = meta["stepId"]?.stringValue,
              let status = meta["status"]?.stringValue else { return }

        let dateFormatter = ISO8601DateFormatter()

        guard let execIndex = executions.firstIndex(where: { $0.id == execId }) else { return }
        guard let stepIndex = executions[execIndex].steps.firstIndex(where: { $0.id == stepId }) else { return }

        executions[execIndex].steps[stepIndex].status = status

        // Haptics for step transitions
        if status == "running" {
            HapticManager.stepStarted()
        } else if status == "success" || status == "error" {
            HapticManager.stepCompleted()
        }

        if let startStr = meta["startedAt"]?.stringValue,
           let date = dateFormatter.date(from: startStr) {
            executions[execIndex].steps[stepIndex].startedAt = date
        }
        if let endStr = meta["completedAt"]?.stringValue,
           let date = dateFormatter.date(from: endStr) {
            executions[execIndex].steps[stepIndex].completedAt = date
        }
        if let output = meta["output"]?.stringValue {
            executions[execIndex].steps[stepIndex].output = output
        }
        if let error = meta["error"]?.stringValue {
            executions[execIndex].steps[stepIndex].error = error
        }

        // Update currentExecution if it matches
        if currentExecution?.id == execId {
            currentExecution = executions[execIndex]
        }
    }

    private func handleExecutionDone(_ msg: WSMessage) {
        guard let meta = msg.metadata else { return }
        guard let execId = meta["executionId"]?.stringValue,
              let status = meta["status"]?.stringValue else { return }

        let dateFormatter = ISO8601DateFormatter()

        if let index = executions.firstIndex(where: { $0.id == execId }) {
            executions[index].status = status
            if let endStr = meta["completedAt"]?.stringValue,
               let date = dateFormatter.date(from: endStr) {
                executions[index].completedAt = date
            }

            HapticManager.workflowCompleted()

            // Update the workflow's last run status
            let workflowId = executions[index].workflowId
            if let wfIndex = workflows.firstIndex(where: { $0.id == workflowId }) {
                workflows[wfIndex].lastRunStatus = status
            }

            // Update currentExecution if it matches
            if currentExecution?.id == execId {
                currentExecution = executions[index]
            }
        }
    }

    private func handleExecutionList(_ msg: WSMessage) {
        isLoading = false
        guard case .array(let items) = msg.metadata?["executions"] else {
            return
        }

        let dateFormatter = ISO8601DateFormatter()
        var loaded: [ExecutionItem] = []

        for item in items {
            guard case .object(let dict) = item else { continue }
            guard let id = dict["id"]?.stringValue,
                  let workflowId = dict["workflowId"]?.stringValue,
                  let status = dict["status"]?.stringValue else { continue }

            let workflowName = dict["workflowName"]?.stringValue ?? ""
            let triggerInfo = dict["triggerInfo"]?.stringValue ?? ""

            var startedAt = Date()
            if let dateStr = dict["startedAt"]?.stringValue,
               let date = dateFormatter.date(from: dateStr) {
                startedAt = date
            }

            var completedAt: Date?
            if let dateStr = dict["completedAt"]?.stringValue,
               let date = dateFormatter.date(from: dateStr) {
                completedAt = date
            }

            let steps = parseExecutionSteps(dict["steps"])

            loaded.append(ExecutionItem(
                id: id,
                workflowId: workflowId,
                workflowName: workflowName,
                status: status,
                startedAt: startedAt,
                completedAt: completedAt,
                triggerInfo: triggerInfo,
                steps: steps
            ))
        }

        executions = loaded
    }

    private func handleExecutionDetail(_ msg: WSMessage) {
        isLoading = false
        guard let meta = msg.metadata else { return }
        guard let id = meta["id"]?.stringValue,
              let workflowId = meta["workflowId"]?.stringValue,
              let status = meta["status"]?.stringValue else { return }

        let dateFormatter = ISO8601DateFormatter()
        let workflowName = meta["workflowName"]?.stringValue ?? ""
        let triggerInfo = meta["triggerInfo"]?.stringValue ?? ""

        var startedAt = Date()
        if let dateStr = meta["startedAt"]?.stringValue,
           let date = dateFormatter.date(from: dateStr) {
            startedAt = date
        }

        var completedAt: Date?
        if let dateStr = meta["completedAt"]?.stringValue,
           let date = dateFormatter.date(from: dateStr) {
            completedAt = date
        }

        let steps = parseExecutionSteps(meta["steps"])

        currentExecution = ExecutionItem(
            id: id,
            workflowId: workflowId,
            workflowName: workflowName,
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            triggerInfo: triggerInfo,
            steps: steps
        )
    }

    private func handleNotification(_ msg: WSMessage) {
        guard let meta = msg.metadata else { return }
        guard let title = meta["title"]?.stringValue,
              let body = meta["body"]?.stringValue else { return }

        notification = WorkflowNotification(
            title: title,
            body: body,
            workflowId: meta["workflowId"]?.stringValue ?? "",
            executionId: meta["executionId"]?.stringValue ?? "",
            type: meta["notificationType"]?.stringValue ?? ""
        )
    }

    private func handleMCPToolsListResult(_ msg: WSMessage) {
        isLoadingTools = false
        guard case .array(let items) = msg.metadata?["tools"] else { return }

        var loaded: [MCPToolItem] = []
        for item in items {
            guard case .object(let dict) = item else { continue }
            guard let name = dict["name"]?.stringValue else { continue }

            let outputType = ToolIOType(rawValue: dict["outputType"]?.stringValue ?? "any") ?? .any
            var acceptsInputTypes: [ToolIOType] = [.any]
            if case .array(let typesArr) = dict["acceptsInputTypes"] {
                acceptsInputTypes = typesArr.compactMap { ToolIOType(rawValue: $0.stringValue ?? "") }
                if acceptsInputTypes.isEmpty { acceptsInputTypes = [.any] }
            }

            // Parse inputSchema properties
            var schemaProps: [SchemaProperty] = []
            if case .object(let schema) = dict["inputSchema"],
               case .object(let properties) = schema["properties"] {
                var requiredNames: Set<String> = []
                if case .array(let reqArr) = schema["required"] {
                    requiredNames = Set(reqArr.compactMap(\.stringValue))
                }
                for (propName, propValue) in properties {
                    guard case .object(let propDict) = propValue else { continue }
                    let propType = propDict["type"]?.stringValue ?? "string"
                    let propDesc = propDict["description"]?.stringValue ?? ""
                    var enumVals: [String]?
                    if case .array(let enumArr) = propDict["enum"] {
                        enumVals = enumArr.compactMap(\.stringValue)
                    }
                    schemaProps.append(SchemaProperty(
                        name: propName,
                        type: propType,
                        description: propDesc,
                        isRequired: requiredNames.contains(propName),
                        enumValues: enumVals
                    ))
                }
                schemaProps.sort { ($0.isRequired ? 0 : 1, $0.name) < ($1.isRequired ? 0 : 1, $1.name) }
            }

            loaded.append(MCPToolItem(
                name: name,
                description: dict["description"]?.stringValue ?? "",
                serverName: dict["serverName"]?.stringValue ?? "",
                outputType: outputType,
                acceptsInputTypes: acceptsInputTypes,
                schemaProperties: schemaProps
            ))
        }
        availableTools = loaded
    }

    private func handleParseScheduleResult(_ msg: WSMessage) {
        isParsingSchedule = false
        guard let meta = msg.metadata else { return }
        let success = meta["success"]?.boolValue ?? false
        parsedSchedule = ParsedSchedule(
            success: success,
            cron: meta["cron"]?.stringValue,
            description: meta["description"]?.stringValue,
            message: meta["message"]?.stringValue
        )
    }

    private func handleBuildWorkflowResult(_ msg: WSMessage) {
        isBuilding = false
        guard let meta = msg.metadata else {
            builderError = "No response from AI"
            return
        }

        let success = meta["success"]?.boolValue ?? false
        if !success {
            builderError = meta["error"]?.stringValue ?? "Failed to build workflow"
            return
        }

        var steps: [BuilderStepResult] = []
        if case .array(let stepItems) = meta["steps"] {
            for item in stepItems {
                guard case .object(let dict) = item else { continue }
                var stepInputs: [String: String] = [:]
                if case .object(let inputsDict) = dict["inputs"] {
                    for (key, val) in inputsDict {
                        if let str = val.stringValue {
                            stepInputs[key] = str
                        }
                    }
                }
                var stepDependsOn: [String]?
                if case .array(let deps) = dict["dependsOn"] {
                    stepDependsOn = deps.compactMap { $0.stringValue }
                }
                steps.append(BuilderStepResult(
                    id: dict["id"]?.stringValue ?? UUID().uuidString,
                    name: dict["name"]?.stringValue ?? "Step",
                    toolName: dict["toolName"]?.stringValue ?? "",
                    serverName: dict["serverName"]?.stringValue ?? "",
                    needsConfiguration: dict["needsConfiguration"]?.boolValue ?? false,
                    inputs: stepInputs,
                    dependsOn: stepDependsOn,
                    preferredProvider: dict["preferredProvider"]?.stringValue
                ))
            }
        }

        let triggerType = meta["triggerType"]?.stringValue ?? "cron"
        var inputParams: [InputParamInfo]?
        if case .array(let paramsArr) = meta["inputParams"] {
            inputParams = paramsArr.compactMap { item -> InputParamInfo? in
                guard case .object(let dict) = item,
                      let name = dict["name"]?.stringValue,
                      let label = dict["label"]?.stringValue else { return nil }
                return InputParamInfo(name: name, label: label, placeholder: dict["placeholder"]?.stringValue)
            }
        }

        builderResult = BuilderWorkflowResult(
            id: meta["id"]?.stringValue ?? UUID().uuidString,
            name: meta["name"]?.stringValue ?? "Untitled Workflow",
            description: meta["description"]?.stringValue ?? "",
            cronExpression: meta["cronExpression"]?.stringValue ?? "0 * * * *",
            scheduleDescription: meta["scheduleDescription"]?.stringValue ?? "Every hour",
            steps: steps,
            needsConfiguration: meta["needsConfiguration"]?.boolValue ?? false,
            triggerType: triggerType,
            inputParams: inputParams
        )
    }

    // MARK: - Encoding Helpers

    private func encodeWorkflowDetail(_ detail: WorkflowDetail) -> [String: MetadataValue] {
        var meta: [String: MetadataValue] = [
            "id": .string(detail.id),
            "name": .string(detail.name),
            "description": .string(detail.description),
            "enabled": .bool(detail.enabled),
            "notifyOnStart": .bool(detail.notifyOnStart),
            "notifyOnComplete": .bool(detail.notifyOnComplete),
            "notifyOnError": .bool(detail.notifyOnError),
            "notifyOnStepComplete": .bool(detail.notifyOnStepComplete),
        ]

        // Encode trigger — flat keys to match daemon's decodeWorkflowFromMetadata
        meta["triggerType"] = .string(detail.trigger.type)
        if let cron = detail.trigger.cronExpression {
            meta["cronExpression"] = .string(cron)
        }
        if let source = detail.trigger.eventSource {
            meta["eventSource"] = .string(source)
        }
        if let eventType = detail.trigger.eventType {
            meta["eventType"] = .string(eventType)
        }
        if let filter = detail.trigger.eventFilter {
            var filterDict: [String: MetadataValue] = [:]
            for (key, value) in filter {
                filterDict[key] = .string(value)
            }
            meta["eventFilter"] = .object(filterDict)
        }
        if let inputParams = detail.trigger.inputParams {
            meta["inputParams"] = .array(inputParams.map { param in
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

        // Encode steps
        var stepsArray: [MetadataValue] = []
        for step in detail.steps {
            var stepDict: [String: MetadataValue] = [
                "id": .string(step.id),
                "name": .string(step.name),
                "toolName": .string(step.toolName),
                "serverName": .string(step.serverName),
                "onError": .string(step.onError),
            ]

            var inputsDict: [String: MetadataValue] = [:]
            for (key, value) in step.inputs {
                inputsDict[key] = .string(value)
            }
            stepDict["inputTemplate"] = .object(inputsDict)

            if let deps = step.dependsOn {
                stepDict["dependsOn"] = .array(deps.map { .string($0) })
            }

            if let provider = step.preferredProvider {
                stepDict["preferredProvider"] = .string(provider)
            }

            stepsArray.append(.object(stepDict))
        }
        meta["steps"] = .array(stepsArray)

        return meta
    }

    // MARK: - Parsing Helpers

    private func parseTriggerInfo(_ value: MetadataValue?) -> WorkflowTriggerInfo {
        guard case .object(let dict) = value else {
            return WorkflowTriggerInfo(type: "cron")
        }

        var eventFilter: [String: String]?
        if case .object(let filterDict) = dict["eventFilter"] {
            var parsed: [String: String] = [:]
            for (key, val) in filterDict {
                if let str = val.stringValue {
                    parsed[key] = str
                }
            }
            eventFilter = parsed
        }

        var inputParams: [InputParamInfo]?
        if case .array(let paramsArr) = dict["inputParams"] {
            inputParams = paramsArr.compactMap { item -> InputParamInfo? in
                guard case .object(let paramDict) = item,
                      let name = paramDict["name"]?.stringValue,
                      let label = paramDict["label"]?.stringValue else { return nil }
                return InputParamInfo(name: name, label: label, placeholder: paramDict["placeholder"]?.stringValue)
            }
        }

        return WorkflowTriggerInfo(
            type: dict["type"]?.stringValue ?? "cron",
            cronExpression: dict["cronExpression"]?.stringValue,
            eventSource: dict["eventSource"]?.stringValue,
            eventType: dict["eventType"]?.stringValue,
            eventFilter: eventFilter,
            inputParams: inputParams
        )
    }

    private func parseSteps(_ value: MetadataValue?) -> [WorkflowStepInfo] {
        guard case .array(let items) = value else { return [] }

        var steps: [WorkflowStepInfo] = []
        for item in items {
            guard case .object(let dict) = item else { continue }
            guard let id = dict["id"]?.stringValue,
                  let name = dict["name"]?.stringValue else { continue }

            var inputs: [String: String] = [:]
            // Try both "inputTemplate" (from daemon) and "inputs" (legacy)
            let inputSource = dict["inputTemplate"] ?? dict["inputs"]
            if case .object(let inputsDict) = inputSource {
                for (key, val) in inputsDict {
                    if let str = val.stringValue {
                        inputs[key] = str
                    }
                }
            }

            var dependsOn: [String]?
            if case .array(let deps) = dict["dependsOn"] {
                dependsOn = deps.compactMap { $0.stringValue }
            }

            steps.append(WorkflowStepInfo(
                id: id,
                name: name,
                toolName: dict["toolName"]?.stringValue ?? "",
                serverName: dict["serverName"]?.stringValue ?? "",
                inputs: inputs,
                dependsOn: dependsOn,
                onError: dict["onError"]?.stringValue ?? "stop",
                preferredProvider: dict["preferredProvider"]?.stringValue
            ))
        }

        return steps
    }

    private func parseExecutionSteps(_ value: MetadataValue?) -> [ExecutionStepItem] {
        guard case .array(let items) = value else { return [] }

        let dateFormatter = ISO8601DateFormatter()
        var steps: [ExecutionStepItem] = []

        for item in items {
            guard case .object(let dict) = item else { continue }
            guard let id = dict["id"]?.stringValue,
                  let stepName = dict["stepName"]?.stringValue else { continue }

            var startedAt: Date?
            if let dateStr = dict["startedAt"]?.stringValue,
               let date = dateFormatter.date(from: dateStr) {
                startedAt = date
            }

            var completedAt: Date?
            if let dateStr = dict["completedAt"]?.stringValue,
               let date = dateFormatter.date(from: dateStr) {
                completedAt = date
            }

            steps.append(ExecutionStepItem(
                id: id,
                stepName: stepName,
                status: dict["status"]?.stringValue ?? "pending",
                startedAt: startedAt,
                completedAt: completedAt,
                output: dict["output"]?.stringValue,
                error: dict["error"]?.stringValue
            ))
        }

        return steps
    }

    // MARK: - Analysis & Enhancement Handlers

    private func handleAnalyzeWorkflowResult(_ msg: WSMessage) {
        isAnalyzing = false
        guard let meta = msg.metadata else { return }

        let issues = parseIssues(meta["issues"])
        let missingElements = parseMissingElements(meta["missingElements"])
        let recommendations = parseRecommendations(meta["recommendations"])

        analysisResult = WorkflowAnalysisInfo(
            workflowId: meta["workflowId"]?.stringValue ?? "",
            workflowName: meta["workflowName"]?.stringValue ?? "",
            overallHealth: meta["overallHealth"]?.stringValue ?? "unknown",
            healthScore: meta["healthScore"]?.intValue ?? 0,
            issues: issues,
            missingElements: missingElements,
            recommendations: recommendations
        )
    }

    private func handleEnhanceWorkflowResult(_ msg: WSMessage) {
        isEnhancing = false
        guard let meta = msg.metadata else {
            enhanceError = "No response from daemon"
            return
        }

        let issues = parseIssues(meta["issues"])

        var fixes: [WorkflowFixInfo] = []
        if case .array(let fixItems) = meta["fixesApplied"] {
            for item in fixItems {
                guard case .object(let dict) = item else { continue }
                fixes.append(WorkflowFixInfo(
                    description: dict["description"]?.stringValue ?? "",
                    affectedStep: dict["affectedStep"]?.stringValue,
                    suggestion: dict["suggestion"]?.stringValue ?? ""
                ))
            }
        }

        let enhanced = meta["enhanced"]?.boolValue ?? false

        enhanceResult = WorkflowEnhanceInfo(
            workflowId: meta["workflowId"]?.stringValue ?? "",
            workflowName: meta["workflowName"]?.stringValue ?? "",
            healthScore: meta["healthScore"]?.intValue ?? 0,
            overallHealth: meta["overallHealth"]?.stringValue ?? "unknown",
            issues: issues,
            fixesApplied: fixes,
            fixCount: meta["fixCount"]?.intValue ?? 0,
            enhanced: enhanced
        )

        // Reload workflow list to reflect changes
        if enhanced {
            loadWorkflows()
            if let wfId = meta["workflowId"]?.stringValue {
                loadWorkflow(id: wfId)
            }
        }
    }

    private func parseIssues(_ value: MetadataValue?) -> [WorkflowIssueInfo] {
        guard case .array(let items) = value else { return [] }
        return items.compactMap { item -> WorkflowIssueInfo? in
            guard case .object(let dict) = item else { return nil }
            return WorkflowIssueInfo(
                id: dict["id"]?.stringValue ?? UUID().uuidString,
                severity: dict["severity"]?.stringValue ?? "suggestion",
                category: dict["category"]?.stringValue ?? "",
                message: dict["message"]?.stringValue ?? "",
                affectedStepId: dict["affectedStepId"]?.stringValue,
                affectedStepName: dict["affectedStepName"]?.stringValue,
                suggestion: dict["suggestion"]?.stringValue ?? "",
                fixed: dict["fixed"]?.boolValue ?? false
            )
        }
    }

    private func parseMissingElements(_ value: MetadataValue?) -> [WorkflowMissingElement] {
        guard case .array(let items) = value else { return [] }
        return items.compactMap { item -> WorkflowMissingElement? in
            guard case .object(let dict) = item else { return nil }
            return WorkflowMissingElement(
                id: dict["id"]?.stringValue ?? UUID().uuidString,
                elementType: dict["elementType"]?.stringValue ?? "",
                description: dict["description"]?.stringValue ?? "",
                recommendedValue: dict["recommendedValue"]?.stringValue
            )
        }
    }

    private func parseRecommendations(_ value: MetadataValue?) -> [WorkflowRecommendation] {
        guard case .array(let items) = value else { return [] }
        return items.compactMap { item -> WorkflowRecommendation? in
            guard case .object(let dict) = item else { return nil }
            return WorkflowRecommendation(
                id: dict["id"]?.stringValue ?? UUID().uuidString,
                title: dict["title"]?.stringValue ?? "",
                description: dict["description"]?.stringValue ?? "",
                category: dict["category"]?.stringValue ?? ""
            )
        }
    }

    // MARK: - Enhance & Test Handlers

    private func handleEnhanceTestProgress(_ msg: WSMessage) {
        guard let meta = msg.metadata else { return }
        enhanceTestPhase = meta["phase"]?.stringValue ?? ""
        enhanceTestIteration = meta["iteration"]?.intValue ?? 0
        enhanceTestMaxIterations = meta["maxIterations"]?.intValue ?? 0
        enhanceTestMessage = meta["message"]?.stringValue ?? ""

        if enhanceTestPhase == "cancelled" {
            isEnhanceTestRunning = false
        }
    }

    private func handleEnhanceTestDone(_ msg: WSMessage) {
        isEnhanceTestRunning = false
        guard let meta = msg.metadata else { return }

        var iterations: [EnhanceTestIterationInfo] = []
        if case .array(let items) = meta["iterations"] {
            for item in items {
                guard case .object(let dict) = item else { continue }
                var fixDescs: [String] = []
                if case .array(let descs) = dict["fixDescriptions"] {
                    fixDescs = descs.compactMap(\.stringValue)
                }
                iterations.append(EnhanceTestIterationInfo(
                    id: dict["iteration"]?.intValue ?? 0,
                    preFixHealthScore: dict["preFixHealthScore"]?.intValue ?? dict["healthScore"]?.intValue ?? 0,
                    postFixHealthScore: dict["postFixHealthScore"]?.intValue ?? dict["healthScore"]?.intValue ?? 0,
                    issuesFound: dict["issuesFound"]?.intValue ?? 0,
                    issuesFixed: dict["issuesFixed"]?.intValue ?? 0,
                    fixDescriptions: fixDescs,
                    executionStatus: dict["executionStatus"]?.stringValue ?? "unknown",
                    failedStepName: dict["failedStepName"]?.stringValue,
                    failedStepError: dict["failedStepError"]?.stringValue
                ))
            }
        }

        enhanceTestResult = EnhanceTestResultInfo(
            converged: meta["converged"]?.boolValue ?? false,
            iterations: iterations,
            finalHealthScore: meta["finalHealthScore"]?.intValue ?? 0,
            totalIterations: meta["totalIterations"]?.intValue ?? 0,
            totalFixesApplied: meta["totalFixesApplied"]?.intValue ?? 0
        )

        loadWorkflows()
        if let wfId = meta["workflowId"]?.stringValue {
            loadWorkflow(id: wfId)
        }
    }

    private func handleRefineWorkflowResult(_ msg: WSMessage) {
        isRefining = false
        guard let meta = msg.metadata else {
            refinementError = "No response from daemon"
            return
        }

        guard meta["success"]?.boolValue == true else {
            refinementError = "Refinement failed"
            return
        }

        // Parse refine result into builder format
        var steps: [BuilderStepResult] = []
        if case .array(let stepItems) = meta["steps"] {
            for item in stepItems {
                guard case .object(let dict) = item else { continue }
                var inputs: [String: String] = [:]
                if case .object(let inputDict) = dict["inputs"] {
                    for (key, val) in inputDict {
                        inputs[key] = val.stringValue ?? ""
                    }
                }
                var deps: [String]? = nil
                if case .array(let depArr) = dict["dependsOn"] {
                    deps = depArr.compactMap(\.stringValue)
                }
                steps.append(BuilderStepResult(
                    id: dict["id"]?.stringValue ?? UUID().uuidString,
                    name: dict["name"]?.stringValue ?? "",
                    toolName: dict["toolName"]?.stringValue ?? "",
                    serverName: dict["serverName"]?.stringValue ?? "",
                    needsConfiguration: false,
                    inputs: inputs,
                    dependsOn: deps,
                    preferredProvider: dict["preferredProvider"]?.stringValue
                ))
            }
        }

        builderResult = BuilderWorkflowResult(
            id: meta["workflowId"]?.stringValue ?? UUID().uuidString,
            name: meta["name"]?.stringValue ?? "",
            description: meta["description"]?.stringValue ?? "",
            cronExpression: meta["cronExpression"]?.stringValue ?? "",
            scheduleDescription: "",
            steps: steps,
            needsConfiguration: false,
            triggerType: meta["triggerType"]?.stringValue ?? "manual",
            inputParams: nil
        )

        loadWorkflows()
        if let wfId = meta["workflowId"]?.stringValue {
            loadWorkflow(id: wfId)
        }
    }
}
