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

struct WorkflowTriggerInfo: Sendable {
    var type: String  // "cron" or "event"
    var cronExpression: String?
    var eventSource: String?
    var eventType: String?
    var eventFilter: [String: String]?
}

struct WorkflowStepInfo: Identifiable, Sendable {
    let id: String
    var name: String
    var toolName: String
    var serverName: String
    var inputs: [String: String]
    var dependsOn: [String]?
    var onError: String  // "stop", "skip", "retry"
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

struct MCPToolItem: Identifiable, Sendable {
    var id: String { "\(serverName)_\(name)" }
    let name: String
    let description: String
    let serverName: String
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
}

struct BuilderStepResult: Identifiable, Sendable {
    let id: String
    let name: String
    let toolName: String
    let serverName: String
    let needsConfiguration: Bool
    let inputs: [String: String]
    let dependsOn: [String]?
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

    func runWorkflow(id: String) {
        let msg = WSMessage(
            type: WSMessageType.runWorkflow,
            metadata: ["workflowId": .string(id)]
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
                onError: "stop"
            )
        }

        let detail = WorkflowDetail(
            id: result.id,
            name: result.name,
            description: result.description,
            enabled: true,
            trigger: WorkflowTriggerInfo(
                type: "cron",
                cronExpression: result.cronExpression
            ),
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
            trigger = WorkflowTriggerInfo(
                type: meta["triggerType"]?.stringValue ?? "cron",
                cronExpression: meta["cronExpression"]?.stringValue,
                eventSource: meta["eventSource"]?.stringValue,
                eventType: meta["eventType"]?.stringValue
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
            loaded.append(MCPToolItem(
                name: name,
                description: dict["description"]?.stringValue ?? "",
                serverName: dict["serverName"]?.stringValue ?? ""
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
                    dependsOn: stepDependsOn
                ))
            }
        }

        builderResult = BuilderWorkflowResult(
            id: meta["id"]?.stringValue ?? UUID().uuidString,
            name: meta["name"]?.stringValue ?? "Untitled Workflow",
            description: meta["description"]?.stringValue ?? "",
            cronExpression: meta["cronExpression"]?.stringValue ?? "0 * * * *",
            scheduleDescription: meta["scheduleDescription"]?.stringValue ?? "Every hour",
            steps: steps,
            needsConfiguration: meta["needsConfiguration"]?.boolValue ?? false
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

        return WorkflowTriggerInfo(
            type: dict["type"]?.stringValue ?? "cron",
            cronExpression: dict["cronExpression"]?.stringValue,
            eventSource: dict["eventSource"]?.stringValue,
            eventType: dict["eventType"]?.stringValue,
            eventFilter: eventFilter
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
                onError: dict["onError"]?.stringValue ?? "stop"
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
}
