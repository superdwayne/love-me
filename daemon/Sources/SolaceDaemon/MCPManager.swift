import Foundation

/// Manages MCP server lifecycle and tool routing
actor MCPManager {
    private let config: DaemonConfig
    /// Unified server storage: all transports (stdio, HTTP, etc.) conform to MCPTransport protocol
    private var servers: [String: MCPTransport] = [:]
    private var allTools: [MCPToolInfo] = []
    private var toolToServer: [String: String] = [:]
    private var enabledState: [String: Bool] = [:]
    private var ollamaEnabledState: [String: Bool] = [:]
    private var externalHandlers: [String: @Sendable (String, JSONValue) async throws -> MCPToolCallResult] = [:]

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
                // Initialize enabled state from config (default true)
                enabledState[name] = serverConfig.isEnabled
                ollamaEnabledState[name] = serverConfig.ollamaEnabled

                if serverConfig.isStdio {
                    await startStdioServer(name: name, config: serverConfig)
                } else if serverConfig.url != nil {
                    await startHTTPServer(name: name, config: serverConfig)
                } else {
                    Logger.info("MCP server '\(name)' has no command or url - skipping")
                }
            }

            Logger.info("MCP Manager: \(servers.count) server(s) started, \(allTools.count) tool(s) available")
        } catch {
            Logger.error("Failed to load MCP config: \(error)")
        }
    }

    /// Start a stdio-based MCP server
    private func startStdioServer(name: String, config: MCPServerConfig) async {
        let transport: MCPTransport = MCPServerProcess(name: name, config: config)

        do {
            try await transport.start()
            servers[name] = transport

            let tools = try await transport.discoverTools()
            for tool in tools {
                allTools.append(tool)
                toolToServer[tool.name] = name
            }
        } catch MCPError.timeout {
            Logger.error("MCP server '\(name)' timed out during startup - skipping")
            transport.stop()
        } catch {
            Logger.error("Failed to start MCP server '\(name)': \(error)")
        }
    }

    /// Start an HTTP/SSE-based MCP server
    private func startHTTPServer(name: String, config: MCPServerConfig) async {
        guard let url = config.url else { return }

        let transport: MCPTransport = MCPHTTPServerProcess(name: name, url: url, headers: config.headers)

        do {
            try await withTimeout(seconds: 30) {
                try await transport.start()
            }
            servers[name] = transport

            let tools = try await withTimeout(seconds: 15) {
                try await transport.discoverTools()
            }
            for tool in tools {
                allTools.append(tool)
                toolToServer[tool.name] = name
            }
        } catch MCPError.timeout {
            Logger.error("MCP HTTP server '\(name)' timed out during startup - skipping")
            transport.stop()
        } catch {
            Logger.error("Failed to start MCP HTTP server '\(name)': \(error)")
        }
    }

    /// Get tool definitions filtered for Ollama (excludes tools from globally disabled OR Ollama-disabled servers)
    func getToolDefinitionsForOllama() -> [ToolDefinition] {
        var seen = Set<String>()
        var defs: [ToolDefinition] = []
        for tool in allTools where isServerEnabled(tool.serverName) && isOllamaServerEnabled(tool.serverName) {
            if seen.insert(tool.name).inserted {
                defs.append(ToolDefinition(
                    name: tool.name,
                    description: tool.description,
                    input_schema: tool.inputSchema
                ))
            }
        }
        return defs
    }

    /// Get all discovered tools as Claude API ToolDefinitions (excludes tools from disabled servers, deduplicates by name)
    func getToolDefinitions() -> [ToolDefinition] {
        var seen = Set<String>()
        var defs: [ToolDefinition] = []
        for tool in allTools where isServerEnabled(tool.serverName) {
            if seen.insert(tool.name).inserted {
                defs.append(ToolDefinition(
                    name: tool.name,
                    description: tool.description,
                    input_schema: tool.inputSchema
                ))
            } else {
                Logger.info("MCP: skipping duplicate tool '\(tool.name)' from server '\(tool.serverName)'")
            }
        }
        return defs
    }

    /// Get the list of all discovered tools (excludes tools from disabled servers, deduplicates by name)
    func getTools() -> [MCPToolInfo] {
        var seen = Set<String>()
        return allTools.filter { isServerEnabled($0.serverName) && seen.insert($0.name).inserted }
    }

    /// Call a tool by name, routing to the correct server (rejects tools from disabled servers)
    func callTool(name: String, arguments: JSONValue) async throws -> MCPToolCallResult {
        guard let serverName = toolToServer[name] else {
            Logger.error("MCP Manager: tool '\(name)' not found in any server")
            throw MCPError.toolNotFound(name)
        }

        guard isServerEnabled(serverName) else {
            Logger.error("MCP Manager: tool '\(name)' rejected — server '\(serverName)' is disabled")
            throw MCPError.toolNotFound(name)
        }

        let startTime = Date()
        Logger.info("MCP Manager: routing tool '\(name)' to server '\(serverName)'")

        let result: MCPToolCallResult
        if let transport = servers[serverName] {
            result = try await transport.callTool(name: name, arguments: arguments)
        } else if let handler = externalHandlers[serverName] {
            result = try await handler(name, arguments)
        } else {
            throw MCPError.toolNotFound(name)
        }

        let duration = Date().timeIntervalSince(startTime)
        Logger.info("MCP Manager: tool '\(name)' on '\(serverName)' finished in \(String(format: "%.2f", duration))s (isError: \(result.isError))")
        return result
    }

    /// Get the server name that hosts a given tool (returns nil for disabled servers)
    func serverForTool(name: String) -> String? {
        guard let serverName = toolToServer[name], isServerEnabled(serverName) else {
            return nil
        }
        return serverName
    }

    /// The total number of available tools (from enabled servers only)
    var toolCount: Int {
        allTools.filter { isServerEnabled($0.serverName) }.count
    }

    /// The names of all active (started) MCP servers
    var activeServerNames: Set<String> {
        Set(servers.keys)
    }

    // MARK: - Server Enabled State

    /// Check if a server is enabled (defaults to true for unknown servers)
    func isServerEnabled(_ name: String) -> Bool {
        enabledState[name] ?? true
    }

    /// Set the enabled state for a server
    func setServerEnabled(_ name: String, _ enabled: Bool) {
        enabledState[name] = enabled
    }

    // MARK: - Ollama Server Enabled State

    /// Check if a server is enabled for Ollama (defaults to true for unknown servers)
    func isOllamaServerEnabled(_ name: String) -> Bool {
        ollamaEnabledState[name] ?? true
    }

    /// Set the Ollama-enabled state for a server
    func setOllamaServerEnabled(_ name: String, _ enabled: Bool) {
        ollamaEnabledState[name] = enabled
    }

    /// Get info about all servers (name, type, enabled state, tool count)
    func getServerInfoList() -> [(name: String, isStdio: Bool, enabled: Bool, ollamaEnabled: Bool, toolCount: Int)] {
        return Set(servers.keys).sorted().map { name in
            let transport = servers[name]
            // Determine type by checking if it's a stdio transport (MCPServerProcess) vs HTTP
            let isStdio = transport is MCPServerProcess
            let enabled = isServerEnabled(name)
            let ollamaEnabled = isOllamaServerEnabled(name)
            let count = allTools.filter { $0.serverName == name }.count
            return (name: name, isStdio: isStdio, enabled: enabled, ollamaEnabled: ollamaEnabled, toolCount: count)
        }
    }

    /// Get server statuses for health endpoint
    func serverStatuses() -> [(name: String, running: Bool, toolCount: Int)] {
        return Set(servers.keys).sorted().map { name in
            let enabled = isServerEnabled(name)
            let count = allTools.filter { $0.serverName == name }.count
            return (name: name, running: enabled, toolCount: count)
        }
    }

    /// Register tools from an external handler (e.g. built-in email server)
    func registerExternalTools(
        serverName: String,
        tools: [MCPToolInfo],
        handler: @escaping @Sendable (String, JSONValue) async throws -> MCPToolCallResult
    ) {
        enabledState[serverName] = true
        externalHandlers[serverName] = handler
        for tool in tools {
            allTools.append(tool)
            toolToServer[tool.name] = serverName
        }
        Logger.info("MCP Manager: registered \(tools.count) external tool(s) from '\(serverName)'")
    }

    /// Add a new server at runtime, start it, discover tools, return tool count
    func addServer(name: String, config: MCPServerConfig) async throws -> Int {
        guard servers[name] == nil else {
            throw MCPError.serverAlreadyExists(name)
        }

        if config.isStdio {
            guard config.command != nil else {
                throw MCPError.invalidConfig("Stdio server requires a command")
            }
            let transport: MCPTransport = MCPServerProcess(name: name, config: config)
            do {
                try await transport.start()
                servers[name] = transport
                let tools = try await transport.discoverTools()
                var registered = 0
                for tool in tools {
                    if let existingServer = toolToServer[tool.name] {
                        Logger.info("MCP Manager: tool '\(tool.name)' from server '\(name)' conflicts with existing tool from server '\(existingServer)' — skipping duplicate")
                    } else {
                        allTools.append(tool)
                        toolToServer[tool.name] = name
                        registered += 1
                    }
                }
                enabledState[name] = true
                ollamaEnabledState[name] = true
                return registered
            } catch {
                transport.stop()
                throw MCPError.serverStartFailed(error.localizedDescription)
            }
        } else if config.url != nil {
            let transport: MCPTransport = MCPHTTPServerProcess(name: name, url: config.url!, headers: config.headers)
            do {
                try await withTimeout(seconds: 30) {
                    try await transport.start()
                }
                servers[name] = transport
                let tools = try await withTimeout(seconds: 15) {
                    try await transport.discoverTools()
                }
                var registered = 0
                for tool in tools {
                    if let existingServer = toolToServer[tool.name] {
                        Logger.info("MCP Manager: tool '\(tool.name)' from server '\(name)' conflicts with existing tool from server '\(existingServer)' — skipping duplicate")
                    } else {
                        allTools.append(tool)
                        toolToServer[tool.name] = name
                        registered += 1
                    }
                }
                enabledState[name] = true
                ollamaEnabledState[name] = true
                return registered
            } catch {
                transport.stop()
                throw MCPError.serverStartFailed(error.localizedDescription)
            }
        } else {
            throw MCPError.invalidConfig("Server must have either a command (stdio) or url (http)")
        }
    }

    /// Remove a server: stop transport, clean up all state
    func removeServer(name: String) async {
        if let transport = servers.removeValue(forKey: name) {
            transport.stop()
        }
        let toolNames = allTools.filter { $0.serverName == name }.map(\.name)
        allTools.removeAll { $0.serverName == name }
        for toolName in toolNames {
            toolToServer.removeValue(forKey: toolName)
        }
        enabledState.removeValue(forKey: name)
        ollamaEnabledState.removeValue(forKey: name)
        Logger.info("MCP Manager: removed server '\(name)'")
    }

    /// Get the server name for each tool (for relevance scoring)
    func getToolServerMap() -> [String: String] {
        return toolToServer
    }

    // MARK: - Pinned Tools Support

    /// Get Ollama-eligible tools with their pinned state for the settings UI
    func getOllamaToolsWithPinnedState(pinnedNames: Set<String>) -> [(name: String, serverName: String, description: String, pinned: Bool)] {
        var seen = Set<String>()
        var results: [(name: String, serverName: String, description: String, pinned: Bool)] = []
        for tool in allTools where isServerEnabled(tool.serverName) && isOllamaServerEnabled(tool.serverName) {
            if seen.insert(tool.name).inserted {
                results.append((
                    name: tool.name,
                    serverName: tool.serverName,
                    description: tool.description,
                    pinned: pinnedNames.contains(tool.name)
                ))
            }
        }
        return results
    }

    /// Get ToolDefinitions for only the specified pinned tool names (skips missing/disabled)
    func getPinnedToolDefinitions(names: Set<String>) -> [ToolDefinition] {
        var seen = Set<String>()
        var defs: [ToolDefinition] = []
        for tool in allTools where names.contains(tool.name) && isServerEnabled(tool.serverName) && isOllamaServerEnabled(tool.serverName) {
            if seen.insert(tool.name).inserted {
                defs.append(ToolDefinition(
                    name: tool.name,
                    description: tool.description,
                    input_schema: tool.inputSchema
                ))
            }
        }
        return defs
    }

    /// Stop all MCP servers
    func stopAll() async {
        for (name, transport) in servers {
            transport.stop()
            Logger.info("MCP server '\(name)' shut down")
        }
        servers.removeAll()
        allTools.removeAll()
        toolToServer.removeAll()
        enabledState.removeAll()
        ollamaEnabledState.removeAll()
    }
}
