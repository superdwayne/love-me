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
    var originalPrompt: String?
    var enhancedPrompt: String?
    /// History of enhancements made to this workflow
    var enhancementHistory: [EnhancementStep]?

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String = "",
        enabled: Bool = true,
        trigger: WorkflowTrigger,
        steps: [WorkflowStep],
        notificationPrefs: NotificationPrefs = NotificationPrefs(),
        created: Date = Date(),
        updated: Date = Date(),
        originalPrompt: String? = nil,
        enhancedPrompt: String? = nil,
        enhancementHistory: [EnhancementStep]? = nil
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
        self.originalPrompt = originalPrompt
        self.enhancedPrompt = enhancedPrompt
        self.enhancementHistory = enhancementHistory
    }
}

// MARK: - Enhancement History

/// Represents a single enhancement step in a workflow's history
struct EnhancementStep: Codable, Sendable {
    let id: String
    let timestamp: Date
    let enhancementType: EnhancementType
    let issuesIdentified: [CritiqueIssue]
    let issuesFixed: [CritiqueIssue]
    let enhancedPrompt: String?
    let originalPrompt: String?

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        enhancementType: EnhancementType,
        issuesIdentified: [CritiqueIssue],
        issuesFixed: [CritiqueIssue],
        enhancedPrompt: String? = nil,
        originalPrompt: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.enhancementType = enhancementType
        self.issuesIdentified = issuesIdentified
        self.issuesFixed = issuesFixed
        self.enhancedPrompt = enhancedPrompt
        self.originalPrompt = originalPrompt
    }
}

/// Types of enhancements that can be applied to a workflow
enum EnhancementType: String, Codable, Sendable {
    case missingInputs = "missing_inputs"
    case missingSteps = "missing_steps"
    case wrongTools = "wrong_tools"
    case dataFlowIssues = "data_flow_issues"
    case parameterErrors = "parameter_errors"
    case triggerType = "trigger_type"
    case userFeedback = "user_feedback"
    case autoOptimization = "auto_optimization"
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
    /// Optional per-step LLM routing. Format: "provider:model" (e.g. "claude:sonnet", "ollama:qwen3.5", "openai:gpt-4o").
    /// When set, auto-fix and any LLM reasoning for this step will use this provider instead of the default.
    /// Parsed via `AgentProviderSpec.from(providerString:)`.
    var preferredProvider: String?

    init(
        id: String = UUID().uuidString,
        name: String,
        toolName: String,
        serverName: String,
        inputTemplate: [String: StringOrVariable] = [:],
        dependsOn: [String]? = nil,
        onError: ErrorPolicy = .autofix,
        preferredProvider: String? = nil
    ) {
        self.id = id
        self.name = name
        self.toolName = toolName
        self.serverName = serverName
        self.inputTemplate = inputTemplate
        self.dependsOn = dependsOn
        self.onError = onError
        self.preferredProvider = preferredProvider
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
    case autofix
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
    case fixing
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

// MARK: - Workflow Analysis

/// Result of analyzing a workflow for issues
struct WorkflowAnalysisResult: Codable, Sendable {
    let workflowId: String
    let workflowName: String
    let overallHealth: HealthScore
    let issues: [WorkflowIssue]
    let missingElements: [MissingElement]
    let recommendations: [Recommendation]
    let analyzedAt: Date

    /// Calculate overall health score (0-100)
    var healthScore: Int {
        let criticalCount = issues.filter { $0.severity == .critical }.count
        let warningCount = issues.filter { $0.severity == .warning }.count
        let suggestionCount = issues.filter { $0.severity == .suggestion }.count

        // Deduct points for issues
        var score = 100
        score -= criticalCount * 25
        score -= warningCount * 10
        score -= suggestionCount * 3
        return max(0, min(100, score))
    }
}

/// Health score for a workflow
enum HealthScore: String, Codable, Sendable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"

    init(from score: Int) {
        if score >= 90 {
            self = .excellent
        } else if score >= 70 {
            self = .good
        } else if score >= 50 {
            self = .fair
        } else {
            self = .poor
        }
    }

    var description: String {
        switch self {
        case .excellent: "Excellent - Workflow is ready to run"
        case .good: "Good - Minor improvements recommended"
        case .fair: "Fair - Several issues need attention"
        case .poor: "Poor - Critical issues must be fixed"
        }
    }
}

/// A single issue found during workflow analysis
struct WorkflowIssue: Codable, Sendable, Identifiable {
    let id: String
    let severity: IssueSeverity
    let category: IssueCategory
    let message: String
    let affectedStepId: String?
    let affectedStepName: String?
    let suggestion: String
    var fixed: Bool = false
}

/// Severity levels for workflow issues
enum IssueSeverity: String, Codable, Sendable {
    case critical = "critical"  // Workflow will fail without fix
    case warning = "warning"    // Workflow may have issues
    case suggestion = "suggestion"  // Improvement opportunity
}

/// Categories of workflow issues
enum IssueCategory: String, Codable, Sendable {
    case missingInputs = "missing_inputs"
    case missingSteps = "missing_steps"
    case wrongTool = "wrong_tool"
    case dataFlow = "data_flow"
    case parameterError = "parameter_error"
    case triggerType = "trigger_type"
    case performance = "performance"
    case security = "security"
}

/// A missing element that should be added to the workflow
struct MissingElement: Codable, Sendable, Identifiable {
    let id: String
    let elementType: MissingElementType
    let description: String
    let recommendedValue: String?
    let stepId: String?
    var actionTaken: Bool = false
}

/// Types of missing elements
enum MissingElementType: String, Codable, Sendable {
    case inputParameter = "input_parameter"
    case workflowStep = "workflow_step"
    case dataConnection = "data_connection"
    case errorHandling = "error_handling"
    case notificationSetting = "notification_setting"
    case description = "description"
}

/// A recommendation for improving the workflow
struct Recommendation: Codable, Sendable {
    let id: String
    let title: String
    let description: String
    let category: RecommendationCategory
    var actionTaken: Bool = false
}

/// Categories of recommendations
enum RecommendationCategory: String, Codable, Sendable {
    case automation = "automation"
    case optimization = "optimization"
    case reliability = "reliability"
    case userExperience = "user_experience"
}

// MARK: - Enhance & Test Loop

/// Record for a single iteration of the enhance-and-test loop
struct EnhanceTestIteration: Codable, Sendable {
    let iteration: Int
    let preFixHealthScore: Int
    let postFixHealthScore: Int
    let issuesFound: Int
    let issuesFixed: Int
    let fixDescriptions: [String]
    let executionStatus: String  // completed, failed, cancelled
    let failedStepName: String?
    let failedStepError: String?
}

/// Final result of the enhance-and-test loop
struct EnhanceTestResult: Codable, Sendable {
    let converged: Bool
    let iterations: [EnhanceTestIteration]
    let finalHealthScore: Int
    let totalIterations: Int
    let totalFixesApplied: Int
}

// MARK: - Workflow Validation

struct WorkflowValidationResult: Codable, Sendable {
    let workflowId: String
    let valid: Bool
    let stepResults: [StepValidationResult]

    var errorCount: Int {
        stepResults.flatMap(\.issues).filter { $0.severity == .error }.count
    }
    var warningCount: Int {
        stepResults.flatMap(\.issues).filter { $0.severity == .warning }.count
    }
}

struct StepValidationResult: Codable, Sendable {
    let stepId: String
    let stepName: String
    let valid: Bool
    let issues: [StepValidationIssue]
}

struct StepValidationIssue: Codable, Sendable {
    let field: String
    let severity: ValidationSeverity
    let message: String
    let suggestion: String?
}

enum ValidationSeverity: String, Codable, Sendable {
    case error
    case warning
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
