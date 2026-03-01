import Foundation

/// Manages MCP server lifecycle and tool routing
actor MCPManager {
    private let config: DaemonConfig
    private var stdioServers: [String: MCPServerProcess] = [:]
    private var httpServers: [String: MCPHTTPServerProcess] = [:]
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
                if serverConfig.isStdio {
                    await startStdioServer(name: name, config: serverConfig)
                } else if serverConfig.url != nil {
                    await startHTTPServer(name: name, config: serverConfig)
                } else {
                    Logger.info("MCP server '\(name)' has no command or url - skipping")
                }
            }

            let totalServers = stdioServers.count + httpServers.count
            Logger.info("MCP Manager: \(totalServers) server(s) started, \(allTools.count) tool(s) available")
        } catch {
            Logger.error("Failed to load MCP config: \(error)")
        }
    }

    /// Start a stdio-based MCP server
    private func startStdioServer(name: String, config: MCPServerConfig) async {
        let process = MCPServerProcess(name: name, config: config)

        do {
            try await process.start()
            stdioServers[name] = process

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

    /// Start an HTTP/SSE-based MCP server
    private func startHTTPServer(name: String, config: MCPServerConfig) async {
        guard let url = config.url else { return }

        let process = MCPHTTPServerProcess(name: name, url: url)

        do {
            try await withTimeout(seconds: 30) {
                try await process.start()
            }
            httpServers[name] = process

            let tools = try await withTimeout(seconds: 15) {
                try await process.discoverTools()
            }
            for tool in tools {
                allTools.append(tool)
                toolToServer[tool.name] = name
            }
        } catch MCPError.timeout {
            Logger.error("MCP HTTP server '\(name)' timed out during startup - skipping")
            process.stop()
        } catch {
            Logger.error("Failed to start MCP HTTP server '\(name)': \(error)")
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
        guard let serverName = toolToServer[name] else {
            throw MCPError.toolNotFound(name)
        }

        if let stdioServer = stdioServers[serverName] {
            return try await stdioServer.callTool(name: name, arguments: arguments)
        }
        if let httpServer = httpServers[serverName] {
            return try await httpServer.callTool(name: name, arguments: arguments)
        }

        throw MCPError.toolNotFound(name)
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
        Set(stdioServers.keys).union(httpServers.keys)
    }

    /// Stop all MCP servers
    func stopAll() async {
        for (name, server) in stdioServers {
            server.stop()
            Logger.info("MCP server '\(name)' shut down")
        }
        for (name, server) in httpServers {
            server.stop()
            Logger.info("MCP HTTP server '\(name)' shut down")
        }
        stdioServers.removeAll()
        httpServers.removeAll()
        allTools.removeAll()
        toolToServer.removeAll()
    }
}
