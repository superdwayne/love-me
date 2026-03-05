import Foundation

/// Abstract protocol for MCP server communication (stdio or HTTP)
///
/// Implementations handle JSON-RPC message exchange with an MCP server.
/// Both stdio-based (Process) and HTTP-based (network) transports conform to this interface.
///
/// Note: Concrete types (JSONRPCError, JSONRPCResponse, MCPError, withTimeout) are defined
/// in MCPServerProcess.swift for now to avoid duplication. This protocol provides a
/// unified interface for all transport implementations.
protocol MCPTransport: Sendable {
    /// Unique identifier for this transport instance
    var name: String { get }

    /// Start the transport and perform MCP initialization
    func start() async throws

    /// Discover available tools from the MCP server
    func discoverTools() async throws -> [MCPToolInfo]

    /// Execute a tool and return the result
    func callTool(name toolName: String, arguments: JSONValue) async throws -> MCPToolCallResult

    /// Stop the transport and clean up resources
    func stop()
}
