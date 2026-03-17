import Foundation

// MARK: - Provider Configuration Types

struct ProviderConfig: Codable, Sendable {
    let defaultProvider: String  // "claude", "ollama", or "openai"
    let ollama: OllamaProviderConfig?
    let claude: ClaudeProviderConfig?
    let openai: OpenAIProviderConfig?

    static let `default` = ProviderConfig(
        defaultProvider: "claude",
        ollama: nil,
        claude: ClaudeProviderConfig(model: DaemonConfig.defaultModel),
        openai: nil
    )

    enum CodingKeys: String, CodingKey {
        case defaultProvider = "default"
        case ollama
        case claude
        case openai
    }
}

struct OllamaProviderConfig: Codable, Sendable {
    let endpoint: String
    let model: String
    let pinnedTools: [String]?

    init(endpoint: String, model: String, pinnedTools: [String]? = nil) {
        self.endpoint = endpoint
        self.model = model
        self.pinnedTools = pinnedTools
    }

    static let `default` = OllamaProviderConfig(
        endpoint: "http://localhost:11434/api/chat",
        model: "qwen3.5"
    )
}

struct ClaudeProviderConfig: Codable, Sendable {
    let model: String
}

struct OpenAIProviderConfig: Codable, Sendable {
    let model: String

    static let `default` = OpenAIProviderConfig(model: "gpt-4o")
}

// MARK: - Daemon Config

struct DaemonConfig: Sendable {
    let port: UInt16
    let model: String
    let apiKey: String?
    let ollamaApiKey: String?
    let openaiApiKey: String?
    let mcpConfigPath: String
    let conversationsDirectory: String
    let workflowsDirectory: String
    let executionsDirectory: String
    let skillsDirectory: String
    let generatedImagesDirectory: String
    let systemPrompt: String
    let daemonVersion: String
    let providerConfig: ProviderConfig
    let providersConfigPath: String

    static let defaultPort: UInt16 = 9200
    static let defaultModel = "claude-sonnet-4-5-20250929"
    static let defaultSystemPrompt = """
        You are Solace, a personal AI agent. You execute real work on the user's computer using connected tools — but you never list or enumerate your tools, capabilities, or MCP servers in conversation. \
        The user already knows what you can do.

        Voice rules:
        - Speak in first person ("I") — you are a single agent, not a team or company.
        - Be warm but brief. Every word earns its place.
        - Never use "oops", "uh oh", filler phrases, or excessive emoji.
        - Show calm competence: state what happened and what you're doing about it.
        - When greeted casually, respond concisely and naturally — do NOT introduce yourself with a capability list.

        When the user asks you to do something, just do it. When they say hello, just say hello back.
        """
    static let version = "0.1.0"

    /// The model to use for Claude API requests
    var claudeModel: String {
        providerConfig.claude?.model ?? Self.defaultModel
    }

    /// The active default provider name
    var defaultProvider: String {
        providerConfig.defaultProvider
    }

    /// Ollama configuration (if any)
    var ollamaConfig: OllamaProviderConfig? {
        providerConfig.ollama
    }

    /// OpenAI configuration (if any)
    var openaiConfig: OpenAIProviderConfig? {
        providerConfig.openai
    }

    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let basePath = "\(homeDir)/.solace"

        // Parse command-line arguments
        var port = Self.defaultPort
        let args = CommandLine.arguments
        for i in 0..<args.count {
            if args[i] == "--port", i + 1 < args.count, let p = UInt16(args[i + 1]) {
                port = p
            }
        }

        self.port = port
        self.apiKey = Self.loadEnvVar("ANTHROPIC_API_KEY", basePath: basePath)
        self.ollamaApiKey = Self.loadEnvVar("OLLAMA_API_KEY", basePath: basePath)
        self.openaiApiKey = Self.loadEnvVar("OPENAI_API_KEY", basePath: basePath)
        self.mcpConfigPath = "\(basePath)/mcp.json"
        self.conversationsDirectory = "\(basePath)/conversations"
        self.workflowsDirectory = "\(basePath)/workflows"
        self.executionsDirectory = "\(basePath)/executions"
        self.skillsDirectory = "\(basePath)/skills"
        self.generatedImagesDirectory = "\(basePath)/generated"
        self.systemPrompt = Self.defaultSystemPrompt
        self.daemonVersion = Self.version
        self.providersConfigPath = "\(basePath)/providers.json"

        // Load provider config
        self.providerConfig = Self.loadProviderConfig(path: "\(basePath)/providers.json")
        self.model = self.providerConfig.claude?.model ?? Self.defaultModel
    }

    /// Load a specific env var from environment or ~/.solace/.env file
    private static func loadEnvVar(_ name: String, basePath: String) -> String? {
        // 1. Check environment variable first
        if let envVal = ProcessInfo.processInfo.environment[name],
           !envVal.isEmpty {
            return envVal
        }
        // 2. Check .env file in basePath
        let envFile = "\(basePath)/.env"
        if let contents = try? String(contentsOfFile: envFile, encoding: .utf8) {
            for line in contents.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("\(name)=") {
                    let value = String(trimmed.dropFirst("\(name)=".count))
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !value.isEmpty { return value }
                }
            }
        }
        return nil
    }

    /// Load provider configuration from ~/.solace/providers.json
    private static func loadProviderConfig(path: String) -> ProviderConfig {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let config = try? JSONDecoder().decode(ProviderConfig.self, from: data) else {
            return ProviderConfig.default
        }
        return config
    }

    /// Creates required directories if they don't exist
    func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [conversationsDirectory, workflowsDirectory, executionsDirectory, skillsDirectory, generatedImagesDirectory] {
            if !fm.fileExists(atPath: dir) {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
        }
        // Ensure base directory exists for mcp.json
        let baseDir = (mcpConfigPath as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: baseDir) {
            try fm.createDirectory(atPath: baseDir, withIntermediateDirectories: true)
        }
        // Secure sensitive config files (API keys, tokens)
        for sensitiveFile in [mcpConfigPath, providersConfigPath, "\(baseDir)/.env", "\(baseDir)/email.json"] {
            if fm.fileExists(atPath: sensitiveFile) {
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sensitiveFile)
            }
        }
    }

    /// Save updated provider config to disk
    static func saveProviderConfig(_ config: ProviderConfig, path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
}
