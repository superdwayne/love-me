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

        let trigger = parseTriggerInfo(meta["trigger"])
        let steps = parseSteps(meta["steps"])

        currentWorkflow = WorkflowDetail(
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
    }

    private func handleWorkflowCreated(_ msg: WSMessage) {
        guard let meta = msg.metadata else { return }
        guard let id = meta["id"]?.stringValue,
              let name = meta["name"]?.stringValue else { return }

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
        if let id = msg.metadata?["workflowId"]?.stringValue {
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

        // Encode trigger
        var triggerDict: [String: MetadataValue] = [
            "type": .string(detail.trigger.type)
        ]
        if let cron = detail.trigger.cronExpression {
            triggerDict["cronExpression"] = .string(cron)
        }
        if let source = detail.trigger.eventSource {
            triggerDict["eventSource"] = .string(source)
        }
        if let eventType = detail.trigger.eventType {
            triggerDict["eventType"] = .string(eventType)
        }
        if let filter = detail.trigger.eventFilter {
            var filterDict: [String: MetadataValue] = [:]
            for (key, value) in filter {
                filterDict[key] = .string(value)
            }
            triggerDict["eventFilter"] = .object(filterDict)
        }
        meta["trigger"] = .object(triggerDict)

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
            stepDict["inputs"] = .object(inputsDict)

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
            if case .object(let inputsDict) = dict["inputs"] {
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
