import Foundation

// MARK: - Agent Provider Specification

enum AgentProvider: Codable {
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

struct AgentProviderSpec: Codable {
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

// MARK: - iOS Display Helpers

extension AgentProviderSpec {
    var displayName: String {
        switch provider {
        case .claude(let model):
            if model.contains("haiku") { return "Claude Haiku" }
            if model.contains("opus") { return "Claude Opus" }
            return "Claude Sonnet"
        case .ollama(let model): return "Ollama \(model)"
        case .openai(let model): return model.uppercased().replacingOccurrences(of: "-", with: " ")
        }
    }

    var providerIcon: String {
        switch provider {
        case .claude: return "brain.head.profile"
        case .ollama: return "desktopcomputer"
        case .openai: return "sparkles"
        }
    }

    var providerColor: String {
        switch provider {
        case .claude(let model):
            if model.contains("haiku") { return "blue" }
            if model.contains("opus") { return "purple" }
            return "orange"
        case .ollama: return "gray"
        case .openai: return "green"
        }
    }
}

// MARK: - Agent Task

struct AgentTask: Codable {
    let id: String
    let name: String
    let objective: String
    let systemPrompt: String
    let requiredTools: [String]
    let requiredServers: [String]
    let dependsOn: [String]?
    let maxTurns: Int
    let providerSpec: AgentProviderSpec
    let outputSchema: String?  // Flexible: accepts String or JSON object from daemon (serialized to String)

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
        outputSchema: String? = nil
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        objective = try container.decode(String.self, forKey: .objective)
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        requiredTools = try container.decodeIfPresent([String].self, forKey: .requiredTools) ?? []
        requiredServers = try container.decodeIfPresent([String].self, forKey: .requiredServers) ?? []
        dependsOn = try container.decodeIfPresent([String].self, forKey: .dependsOn)
        maxTurns = try container.decodeIfPresent(Int.self, forKey: .maxTurns) ?? 10
        providerSpec = try container.decode(AgentProviderSpec.self, forKey: .providerSpec)
        // Handle outputSchema as either String or JSON object from daemon
        if let str = try? container.decodeIfPresent(String.self, forKey: .outputSchema) {
            outputSchema = str
        } else if let jsonData = try? container.decodeIfPresent(AnyCodable.self, forKey: .outputSchema) {
            if let data = try? JSONSerialization.data(withJSONObject: jsonData.value, options: []),
               let str = String(data: data, encoding: .utf8) {
                outputSchema = str
            } else {
                outputSchema = nil
            }
        } else {
            outputSchema = nil
        }
    }
}

/// Helper for flexible JSON decoding (handles any JSON value)
private struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else if let str = try? container.decode(String.self) {
            value = str
        } else if let num = try? container.decode(Double.self) {
            value = num
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let str = value as? String { try container.encode(str) }
        else if let num = value as? Double { try container.encode(num) }
        else if let bool = value as? Bool { try container.encode(bool) }
        else { try container.encodeNil() }
    }
}

// MARK: - Agent Plan

struct AgentPlan: Codable {
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

enum AgentExecutionStatus: String, Codable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

struct AgentExecution: Codable {
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

enum AgentResultStatus: String, Codable {
    case pending
    case running
    case success
    case error
    case cancelled
    case spawning
}

struct AgentResult: Codable {
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

// MARK: - Plan Dependency Waves

extension AgentPlan {
    /// Group agents into parallel execution waves based on dependency resolution
    var dependencyWaves: [[AgentTask]] {
        var waves: [[AgentTask]] = []
        var completed = Set<String>()
        var remaining = agents

        while !remaining.isEmpty {
            let wave = remaining.filter { task in
                guard let deps = task.dependsOn, !deps.isEmpty else { return true }
                return deps.allSatisfy { completed.contains($0) }
            }

            if wave.isEmpty {
                // Remaining tasks have unresolvable dependencies -- add them all as final wave
                waves.append(remaining)
                break
            }

            waves.append(wave)
            let waveIds = Set(wave.map { $0.id })
            completed.formUnion(waveIds)
            remaining.removeAll { waveIds.contains($0.id) }
        }

        return waves
    }
}

// MARK: - Execution Convenience

extension AgentExecution {
    var activeAgentCount: Int {
        agentResults.filter { $0.status == .running || $0.status == .spawning }.count
    }

    var completedAgentCount: Int {
        agentResults.filter { $0.status == .success }.count
    }

    var failedAgentCount: Int {
        agentResults.filter { $0.status == .error }.count
    }
}
