import Foundation

// MARK: - Workflow Definition

struct WorkflowDefinition: Codable, Sendable {
    let id: String
    var name: String
    var description: String
    var enabled: Bool
    var trigger: WorkflowTrigger
    var steps: [WorkflowStep]
    var notificationPrefs: NotificationPrefs
    let created: Date
    var updated: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String = "",
        enabled: Bool = true,
        trigger: WorkflowTrigger,
        steps: [WorkflowStep],
        notificationPrefs: NotificationPrefs = NotificationPrefs(),
        created: Date = Date(),
        updated: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.enabled = enabled
        self.trigger = trigger
        self.steps = steps
        self.notificationPrefs = notificationPrefs
        self.created = created
        self.updated = updated
    }
}

// MARK: - Trigger

/// Parameters that a manual-trigger workflow can accept at run time.
struct InputParam: Codable, Sendable {
    let name: String         // e.g. "figma_url"
    let label: String        // e.g. "Figma File URL"
    let placeholder: String? // e.g. "https://www.figma.com/design/..."
}

enum WorkflowTrigger: Codable, Sendable {
    case cron(expression: String)
    case event(source: String, eventType: String, filter: [String: String]?)
    case manual(inputParams: [InputParam]?)

    private enum CodingKeys: String, CodingKey {
        case type, expression, source, eventType, filter, inputParams
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "cron":
            let expression = try container.decode(String.self, forKey: .expression)
            self = .cron(expression: expression)
        case "event":
            let source = try container.decode(String.self, forKey: .source)
            let eventType = try container.decode(String.self, forKey: .eventType)
            let filter = try container.decodeIfPresent([String: String].self, forKey: .filter)
            self = .event(source: source, eventType: eventType, filter: filter)
        case "manual":
            let inputParams = try container.decodeIfPresent([InputParam].self, forKey: .inputParams)
            self = .manual(inputParams: inputParams)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown trigger type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cron(let expression):
            try container.encode("cron", forKey: .type)
            try container.encode(expression, forKey: .expression)
        case .event(let source, let eventType, let filter):
            try container.encode("event", forKey: .type)
            try container.encode(source, forKey: .source)
            try container.encode(eventType, forKey: .eventType)
            try container.encodeIfPresent(filter, forKey: .filter)
        case .manual(let inputParams):
            try container.encode("manual", forKey: .type)
            try container.encodeIfPresent(inputParams, forKey: .inputParams)
        }
    }
}

// MARK: - Workflow Step

struct WorkflowStep: Codable, Sendable {
    let id: String
    var name: String
    var toolName: String
    var serverName: String
    var inputTemplate: [String: StringOrVariable]
    var dependsOn: [String]?
    var onError: ErrorPolicy

    init(
        id: String = UUID().uuidString,
        name: String,
        toolName: String,
        serverName: String,
        inputTemplate: [String: StringOrVariable] = [:],
        dependsOn: [String]? = nil,
        onError: ErrorPolicy = .stop
    ) {
        self.id = id
        self.name = name
        self.toolName = toolName
        self.serverName = serverName
        self.inputTemplate = inputTemplate
        self.dependsOn = dependsOn
        self.onError = onError
    }
}

// MARK: - String or Variable Reference

enum StringOrVariable: Codable, Sendable {
    case literal(String)
    case variable(stepId: String, jsonPath: String)
    /// Template string with `{{stepId.jsonPath}}` placeholders.
    /// Use `$` as jsonPath to inject the entire step output.
    case template(String)

    private enum CodingKeys: String, CodingKey {
        case type, value, stepId, jsonPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "literal":
            let value = try container.decode(String.self, forKey: .value)
            self = .literal(value)
        case "variable":
            let stepId = try container.decode(String.self, forKey: .stepId)
            let jsonPath = try container.decode(String.self, forKey: .jsonPath)
            self = .variable(stepId: stepId, jsonPath: jsonPath)
        case "template":
            let value = try container.decode(String.self, forKey: .value)
            self = .template(value)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown StringOrVariable type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .literal(let value):
            try container.encode("literal", forKey: .type)
            try container.encode(value, forKey: .value)
        case .variable(let stepId, let jsonPath):
            try container.encode("variable", forKey: .type)
            try container.encode(stepId, forKey: .stepId)
            try container.encode(jsonPath, forKey: .jsonPath)
        case .template(let value):
            try container.encode("template", forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }

    /// Resolve to a string value, substituting variables from step outputs
    func resolve(with stepOutputs: [String: String]) -> String {
        switch self {
        case .literal(let value):
            return value
        case .variable(let stepId, let jsonPath):
            guard let output = stepOutputs[stepId] else { return "" }
            return extractJSONPath(from: output, path: jsonPath)
        case .template(let templateString):
            return resolveTemplate(templateString, with: stepOutputs)
        }
    }
}

/// Resolve `{{stepId.jsonPath}}` placeholders in a template string.
/// Use `{{stepId.$}}` to inject the entire output of that step.
private func resolveTemplate(_ template: String, with stepOutputs: [String: String]) -> String {
    // Match {{stepId.jsonPath}} or {{stepId.$}}
    let pattern = #"\{\{([^.}]+)\.([^}]+)\}\}"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return template
    }

    let nsTemplate = template as NSString
    let matches = regex.matches(in: template, range: NSRange(location: 0, length: nsTemplate.length))

    var result = template
    // Replace in reverse order to preserve ranges
    for match in matches.reversed() {
        let stepId = nsTemplate.substring(with: match.range(at: 1))
        let jsonPath = nsTemplate.substring(with: match.range(at: 2))
        let fullMatch = nsTemplate.substring(with: match.range)

        guard let output = stepOutputs[stepId] else {
            result = result.replacingOccurrences(of: fullMatch, with: "")
            continue
        }

        let replacement: String
        if jsonPath == "$" {
            replacement = output
        } else {
            replacement = extractJSONPath(from: output, path: jsonPath)
        }
        result = result.replacingOccurrences(of: fullMatch, with: replacement)
    }

    return result
}

// MARK: - Error Policy

enum ErrorPolicy: String, Codable, Sendable {
    case stop
    case skip
    case retry
}

// MARK: - Notification Preferences

struct NotificationPrefs: Codable, Sendable {
    var notifyOnStart: Bool
    var notifyOnComplete: Bool
    var notifyOnError: Bool
    var notifyOnStepComplete: Bool

    init(
        notifyOnStart: Bool = false,
        notifyOnComplete: Bool = true,
        notifyOnError: Bool = true,
        notifyOnStepComplete: Bool = false
    ) {
        self.notifyOnStart = notifyOnStart
        self.notifyOnComplete = notifyOnComplete
        self.notifyOnError = notifyOnError
        self.notifyOnStepComplete = notifyOnStepComplete
    }
}

// MARK: - Workflow Execution

struct WorkflowExecution: Codable, Sendable {
    let id: String
    let workflowId: String
    let workflowName: String
    var status: WorkflowExecutionStatus
    let startedAt: Date
    var completedAt: Date?
    var triggerInfo: String
    var stepResults: [StepResult]

    init(
        id: String = UUID().uuidString,
        workflowId: String,
        workflowName: String,
        status: WorkflowExecutionStatus = .pending,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        triggerInfo: String = "",
        stepResults: [StepResult] = []
    ) {
        self.id = id
        self.workflowId = workflowId
        self.workflowName = workflowName
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.triggerInfo = triggerInfo
        self.stepResults = stepResults
    }
}

enum WorkflowExecutionStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

struct StepResult: Codable, Sendable {
    let stepId: String
    let stepName: String
    var status: StepResultStatus
    var startedAt: Date?
    var completedAt: Date?
    var output: String?
    var error: String?

    init(
        stepId: String,
        stepName: String,
        status: StepResultStatus = .pending,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        output: String? = nil,
        error: String? = nil
    ) {
        self.stepId = stepId
        self.stepName = stepName
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.output = output
        self.error = error
    }
}

enum StepResultStatus: String, Codable, Sendable {
    case pending
    case running
    case success
    case error
    case skipped
}

// MARK: - Workflow Summary (for listing)

struct WorkflowSummary: Codable, Sendable {
    let id: String
    let name: String
    let description: String
    let enabled: Bool
    let triggerType: String
    let triggerDetail: String
    let stepCount: Int
    let lastRunStatus: String?
    let lastRunAt: Date?

    init(from definition: WorkflowDefinition, lastExecution: WorkflowExecution? = nil) {
        self.id = definition.id
        self.name = definition.name
        self.description = definition.description
        self.enabled = definition.enabled
        self.stepCount = definition.steps.count

        switch definition.trigger {
        case .cron(let expression):
            self.triggerType = "cron"
            self.triggerDetail = expression
        case .event(let source, let eventType, _):
            self.triggerType = "event"
            self.triggerDetail = "\(source):\(eventType)"
        case .manual(let inputParams):
            self.triggerType = "manual"
            self.triggerDetail = inputParams.map { "\($0.count) input(s)" } ?? "no inputs"
        }

        self.lastRunStatus = lastExecution?.status.rawValue
        self.lastRunAt = lastExecution?.startedAt
    }
}

// MARK: - JSON Path Helper

/// Simple JSON path extraction (supports dot notation: "key.nested.value")
func extractJSONPath(from jsonString: String, path: String) -> String {
    guard let data = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) else {
        return jsonString
    }

    let components = path.split(separator: ".").map(String.init)
    var current: Any = json

    for component in components {
        if let dict = current as? [String: Any], let next = dict[component] {
            current = next
        } else if let arr = current as? [Any], let index = Int(component), index < arr.count {
            current = arr[index]
        } else {
            return ""
        }
    }

    if let str = current as? String {
        return str
    } else if let data = try? JSONSerialization.data(withJSONObject: current),
              let str = String(data: data, encoding: .utf8) {
        return str
    }
    return "\(current)"
}
