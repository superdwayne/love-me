import Foundation

/// Manages MCP server lifecycle and tool routing
actor MCPManager {
    private let config: DaemonConfig
    private var servers: [String: MCPServerProcess] = [:]
    private var allTools: [MCPToolInfo] = []
    private var toolToServer: [String: String] = [:]

    init(config: DaemonConfig) {
        self.config = config
    }

    /// Load MCP server configs and start all servers
    func startAll() async {
        let configPath = config.mcpConfigPath
        let fm = FileManager.default

        guard fm.fileExists(atPath: configPath) else {
            Logger.info("No MCP config found at \(configPath) - running without tools")
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            let mcpConfig = try JSONDecoder().decode(MCPConfigFile.self, from: data)

            for (name, serverConfig) in mcpConfig.mcpServers {
                guard serverConfig.isStdio else {
                    Logger.info("MCP server '\(name)' uses URL transport (not yet supported) - skipping")
                    continue
                }
                await startServer(name: name, config: serverConfig)
            }

            Logger.info("MCP Manager: \(servers.count) server(s) started, \(allTools.count) tool(s) available")
        } catch {
            Logger.error("Failed to load MCP config: \(error)")
        }
    }

    /// Start an individual MCP server with timeout
    private func startServer(name: String, config: MCPServerConfig) async {
        let process = MCPServerProcess(name: name, config: config)

        do {
            try await process.start()
            servers[name] = process

            let tools = try await process.discoverTools()
            for tool in tools {
                allTools.append(tool)
                toolToServer[tool.name] = name
            }
        } catch MCPError.timeout {
            Logger.error("MCP server '\(name)' timed out during startup - skipping")
            process.stop()
        } catch {
            Logger.error("Failed to start MCP server '\(name)': \(error)")
        }
    }

    /// Get all discovered tools as Claude API ToolDefinitions
    func getToolDefinitions() -> [ToolDefinition] {
        allTools.map { tool in
            ToolDefinition(
                name: tool.name,
                description: tool.description,
                input_schema: tool.inputSchema
            )
        }
    }

    /// Get the list of all discovered tools
    func getTools() -> [MCPToolInfo] {
        allTools
    }

    /// Call a tool by name, routing to the correct server
    func callTool(name: String, arguments: JSONValue) async throws -> MCPToolCallResult {
        guard let serverName = toolToServer[name],
              let server = servers[serverName] else {
            throw MCPError.toolNotFound(name)
        }

        return try await server.callTool(name: name, arguments: arguments)
    }

    /// Get the server name that hosts a given tool
    func serverForTool(name: String) -> String? {
        toolToServer[name]
    }

    /// The total number of available tools
    var toolCount: Int {
        allTools.count
    }

    /// The names of all active (started) MCP servers
    var activeServerNames: Set<String> {
        Set(servers.keys)
    }

    /// Stop all MCP servers
    func stopAll() async {
        for (name, server) in servers {
            server.stop()
            Logger.info("MCP server '\(name)' shut down")
        }
        servers.removeAll()
        allTools.removeAll()
        toolToServer.removeAll()
    }
}
