import Foundation

// MARK: - Agent Provider Specification

enum AgentProvider: Codable, Sendable {
    case claude(model: String)
    case ollama(model: String)
    case openai(model: String)

    private enum CodingKeys: String, CodingKey {
        case type, model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let model = try container.decode(String.self, forKey: .model)
        switch type {
        case "claude":
            self = .claude(model: model)
        case "ollama":
            self = .ollama(model: model)
        case "openai":
            self = .openai(model: model)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown agent provider type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .claude(let model):
            try container.encode("claude", forKey: .type)
            try container.encode(model, forKey: .model)
        case .ollama(let model):
            try container.encode("ollama", forKey: .type)
            try container.encode(model, forKey: .model)
        case .openai(let model):
            try container.encode("openai", forKey: .type)
            try container.encode(model, forKey: .model)
        }
    }
}

struct AgentProviderSpec: Codable, Sendable {
    let provider: AgentProvider
    let thinkingBudget: Int?
    let maxTokens: Int
    let temperature: Double?

    init(
        provider: AgentProvider,
        thinkingBudget: Int? = nil,
        maxTokens: Int = 16384,
        temperature: Double? = nil
    ) {
        self.provider = provider
        self.thinkingBudget = thinkingBudget
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    /// Human-readable provider name (e.g. "claude", "ollama", "openai")
    var providerName: String {
        switch provider {
        case .claude: return "claude"
        case .ollama: return "ollama"
        case .openai: return "openai"
        }
    }

    /// Human-readable model name (e.g. "claude-sonnet-4-5-20250929", "llama3", "gpt-4o")
    var modelName: String {
        switch provider {
        case .claude(let model): return model
        case .ollama(let model): return model
        case .openai(let model): return model
        }
    }

    /// Parse a "provider:model" string like "claude:sonnet" into an AgentProviderSpec.
    ///
    /// Supported shortcuts:
    /// - "claude:haiku"   -> .claude(model: "claude-haiku-4-5-20251001")
    /// - "claude:sonnet"  -> .claude(model: "claude-sonnet-4-5-20250929")
    /// - "claude:opus"    -> .claude(model: "claude-opus-4-6")
    /// - "ollama:{model}" -> .ollama(model: model)
    /// - "openai:{model}" -> .openai(model: model)
    /// - Unknown defaults to .claude(model: "claude-sonnet-4-5-20250929")
    static func from(providerString: String) -> AgentProviderSpec {
        let parts = providerString.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return AgentProviderSpec(provider: .claude(model: "claude-sonnet-4-5-20250929"))
        }

        let providerType = parts[0].lowercased()
        let modelAlias = parts[1]

        switch providerType {
        case "claude":
            let resolvedModel: String
            switch modelAlias.lowercased() {
            case "haiku":
                resolvedModel = "claude-haiku-4-5-20251001"
            case "sonnet":
                resolvedModel = "claude-sonnet-4-5-20250929"
            case "opus":
                resolvedModel = "claude-opus-4-6"
            default:
                resolvedModel = modelAlias
            }
            return AgentProviderSpec(provider: .claude(model: resolvedModel))

        case "ollama":
            return AgentProviderSpec(provider: .ollama(model: modelAlias))

        case "openai":
            return AgentProviderSpec(provider: .openai(model: modelAlias))

        default:
            return AgentProviderSpec(provider: .claude(model: "claude-sonnet-4-5-20250929"))
        }
    }
}

// MARK: - Agent Task

struct AgentTask: Codable, Sendable {
    let id: String
    let name: String
    let objective: String
    let systemPrompt: String
    let requiredTools: [String]
    let requiredServers: [String]
    let dependsOn: [String]?
    let maxTurns: Int
    let providerSpec: AgentProviderSpec
    let outputSchema: JSONValue?

    init(
        id: String = UUID().uuidString,
        name: String,
        objective: String,
        systemPrompt: String = "",
        requiredTools: [String] = [],
        requiredServers: [String] = [],
        dependsOn: [String]? = nil,
        maxTurns: Int = 10,
        providerSpec: AgentProviderSpec,
        outputSchema: JSONValue? = nil
    ) {
        self.id = id
        self.name = name
        self.objective = objective
        self.systemPrompt = systemPrompt
        self.requiredTools = requiredTools
        self.requiredServers = requiredServers
        self.dependsOn = dependsOn
        self.maxTurns = maxTurns
        self.providerSpec = providerSpec
        self.outputSchema = outputSchema
    }
}

// MARK: - Agent Plan

struct AgentPlan: Codable, Sendable {
    let id: String
    let name: String
    let description: String
    let agents: [AgentTask]
    let createdFrom: String?
    let estimatedCost: Double?
    let created: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String,
        agents: [AgentTask],
        createdFrom: String? = nil,
        estimatedCost: Double? = nil,
        created: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.agents = agents
        self.createdFrom = createdFrom
        self.estimatedCost = estimatedCost
        self.created = created
    }
}

// MARK: - Agent Execution

enum AgentExecutionStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

struct AgentExecution: Codable, Sendable {
    let id: String
    let planId: String
    let planName: String
    var status: AgentExecutionStatus
    let startedAt: Date
    var completedAt: Date?
    var agentResults: [AgentResult]
    let parentAgentId: String?
    var totalCost: Double?

    init(
        id: String = UUID().uuidString,
        planId: String,
        planName: String,
        status: AgentExecutionStatus = .pending,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        agentResults: [AgentResult] = [],
        parentAgentId: String? = nil,
        totalCost: Double? = nil
    ) {
        self.id = id
        self.planId = planId
        self.planName = planName
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.agentResults = agentResults
        self.parentAgentId = parentAgentId
        self.totalCost = totalCost
    }
}

// MARK: - Agent Result

enum AgentResultStatus: String, Codable, Sendable {
    case pending
    case running
    case success
    case error
    case cancelled
    case spawning
}

struct AgentResult: Codable, Sendable {
    let agentId: String
    let agentName: String
    var status: AgentResultStatus
    let provider: String
    let model: String
    var startedAt: Date?
    var completedAt: Date?
    var output: String?
    var error: String?
    var turnCount: Int
    var toolCallCount: Int
    var childExecutionId: String?

    init(
        agentId: String,
        agentName: String,
        status: AgentResultStatus = .pending,
        provider: String,
        model: String,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        output: String? = nil,
        error: String? = nil,
        turnCount: Int = 0,
        toolCallCount: Int = 0,
        childExecutionId: String? = nil
    ) {
        self.agentId = agentId
        self.agentName = agentName
        self.status = status
        self.provider = provider
        self.model = model
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.output = output
        self.error = error
        self.turnCount = turnCount
        self.toolCallCount = toolCallCount
        self.childExecutionId = childExecutionId
    }
}

// MARK: - Agent Update Events

enum AgentUpdate: Sendable {
    case agentStarted(agentId: String, agentName: String, provider: String, model: String)
    case agentProgress(agentId: String, text: String)
    case agentThinking(agentId: String, text: String)
    case agentToolStart(agentId: String, tool: String, server: String)
    case agentToolDone(agentId: String, tool: String, result: String, success: Bool)
    case agentCompleted(agentId: String, output: String)
    case agentFailed(agentId: String, error: String)
    case providerFallback(agentId: String, from: String, to: String, reason: String)
    case agentSpawning(agentId: String, childPlan: AgentPlan)
}
