import Foundation

/// Factory that creates LLMProvider instances on demand for agent tasks.
/// Each agent in a plan gets its own provider instance based on its AgentProviderSpec.
actor ProviderPool {
    private let config: DaemonConfig

    init(config: DaemonConfig) {
        self.config = config
    }

    /// Create a provider instance for the given spec.
    /// Each call returns a new, independent provider instance.
    func provider(for spec: AgentProviderSpec) throws -> any LLMProvider {
        switch spec.provider {
        case .claude(let model):
            guard config.apiKey != nil else {
                throw ProviderPoolError.missingAPIKey("claude", "ANTHROPIC_API_KEY")
            }
            return ClaudeAPIClient(
                config: config,
                modelOverride: model,
                thinkingBudgetOverride: spec.thinkingBudget
            )

        case .ollama(let model):
            guard let ollamaConfig = config.ollamaConfig else {
                throw ProviderPoolError.missingAPIKey("ollama", "Ollama endpoint not configured in providers.json")
            }
            return OllamaAPIClient(
                endpoint: ollamaConfig.endpoint,
                model: model,
                apiKey: config.ollamaApiKey
            )

        case .openai(let model):
            guard let apiKey = config.openaiApiKey else {
                throw ProviderPoolError.missingAPIKey("openai", "OPENAI_API_KEY")
            }
            return OpenAIAPIClient(
                model: model,
                apiKey: apiKey
            )
        }
    }

    /// Returns a list of provider names that are currently configured (have API keys / endpoints).
    func availableProviders() -> [String] {
        var providers: [String] = []
        if config.apiKey != nil {
            providers.append("claude")
        }
        if config.ollamaConfig != nil {
            providers.append("ollama")
        }
        if config.openaiApiKey != nil {
            providers.append("openai")
        }
        return providers
    }
}

// MARK: - Errors

enum ProviderPoolError: Error, LocalizedError {
    case missingAPIKey(String, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider, let detail):
            return "Provider '\(provider)' not available: \(detail)"
        }
    }
}
