import Foundation

struct DaemonConfig: Sendable {
    let port: UInt16
    let model: String
    let apiKey: String?
    let mcpConfigPath: String
    let conversationsDirectory: String
    let workflowsDirectory: String
    let executionsDirectory: String
    let skillsDirectory: String
    let systemPrompt: String
    let daemonVersion: String

    static let defaultPort: UInt16 = 9200
    static let defaultModel = "claude-sonnet-4-5-20250929"
    static let defaultSystemPrompt = "You are love.Me, a personal AI assistant. You have access to tools to execute tasks on the user's computer. Be concise and helpful."
    static let version = "0.1.0"

    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let basePath = "\(homeDir)/.love-me"

        // Parse command-line arguments
        var port = Self.defaultPort
        let args = CommandLine.arguments
        for i in 0..<args.count {
            if args[i] == "--port", i + 1 < args.count, let p = UInt16(args[i + 1]) {
                port = p
            }
        }

        self.port = port
        self.model = Self.defaultModel
        self.apiKey = Self.loadAPIKey(basePath: basePath)
        self.mcpConfigPath = "\(basePath)/mcp.json"
        self.conversationsDirectory = "\(basePath)/conversations"
        self.workflowsDirectory = "\(basePath)/workflows"
        self.executionsDirectory = "\(basePath)/executions"
        self.skillsDirectory = "\(basePath)/skills"
        self.systemPrompt = Self.defaultSystemPrompt
        self.daemonVersion = Self.version
    }

    /// Load API key from env var or ~/.love-me/.env file
    private static func loadAPIKey(basePath: String) -> String? {
        // 1. Check environment variable first
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
           !envKey.isEmpty {
            return envKey
        }
        // 2. Check .env file in basePath
        let envFile = "\(basePath)/.env"
        if let contents = try? String(contentsOfFile: envFile, encoding: .utf8) {
            for line in contents.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("ANTHROPIC_API_KEY=") {
                    let value = String(trimmed.dropFirst("ANTHROPIC_API_KEY=".count))
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !value.isEmpty { return value }
                }
            }
        }
        return nil
    }

    /// Creates required directories if they don't exist
    func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [conversationsDirectory, workflowsDirectory, executionsDirectory, skillsDirectory] {
            if !fm.fileExists(atPath: dir) {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
        }
        // Ensure base directory exists for mcp.json
        let baseDir = (mcpConfigPath as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: baseDir) {
            try fm.createDirectory(atPath: baseDir, withIntermediateDirectories: true)
        }
    }
}
