import Foundation

// MARK: - JSON-RPC 2.0

struct JSONRPCRequest: Codable, Sendable {
    let jsonrpc: String
    let id: Int
    let method: String
    let params: JSONValue?

    init(id: Int, method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

struct JSONRPCResponse: Codable, Sendable {
    let jsonrpc: String
    let id: Int?
    let result: JSONValue?
    let error: JSONRPCError?
}

struct JSONRPCError: Codable, Sendable {
    let code: Int
    let message: String
    let data: JSONValue?
}

// MARK: - MCP Tool Info

struct MCPToolInfo: Sendable {
    let name: String
    let description: String
    let inputSchema: JSONValue
    let serverName: String
}

// MARK: - MCP Tool Call Result

struct MCPToolCallResult: Sendable {
    let content: String
    let isError: Bool
}

// MARK: - MCP Server Configuration (from mcp.json)

struct MCPConfigFile: Codable, Sendable {
    let mcpServers: [String: MCPServerConfig]
}

struct MCPServerConfig: Codable, Sendable {
    let command: String?
    let args: [String]?
    let env: [String: String]?
    let url: String?  // SSE/HTTP transport (not yet supported)

    /// Whether this is a stdio-based server (has command)
    var isStdio: Bool { command != nil }
}
