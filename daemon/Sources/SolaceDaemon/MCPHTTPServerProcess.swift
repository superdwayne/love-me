import Foundation

/// Wraps an MCP server accessible via Streamable HTTP transport (POST JSON-RPC to a URL endpoint)
///
/// Conforms to MCPTransport protocol for unified transport abstraction.
/// Communicates with remote MCP server via HTTP POST with Server-Sent Events for streaming responses.
final class MCPHTTPServerProcess: MCPTransport {
    let name: String
    private let endpointURL: URL
    private let customHeaders: [String: String]
    private let session: URLSession
    private let state: MCPHTTPState

    init(name: String, url: String, headers: [String: String]? = nil) {
        self.name = name
        self.endpointURL = URL(string: url)!
        self.customHeaders = headers ?? [:]
        self.state = MCPHTTPState()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    /// Initialize the MCP connection
    func start() async throws {
        let response = try await sendJSONRPC(
            method: "initialize",
            params: .object([
                "protocolVersion": .string("2024-11-05"),
                "capabilities": .object([:]),
                "clientInfo": .object([
                    "name": .string("Solace"),
                    "version": .string(DaemonConfig.version)
                ])
            ])
        )

        if let sessionId = response.sessionId {
            state.withLock { $0.sessionId = sessionId }
        }

        Logger.info("MCP HTTP server '\(name)' initialized")

        // Send initialized notification
        try? await sendJSONRPCNotification(
            method: "notifications/initialized",
            params: .object([:])
        )
    }

    /// Discover available tools
    func discoverTools() async throws -> [MCPToolInfo] {
        let response = try await sendJSONRPC(
            method: "tools/list",
            params: .object([:])
        )

        guard case .object(let resultObj) = response.rpcResponse.result,
              case .array(let toolsArray) = resultObj["tools"] else {
            Logger.error("MCP HTTP server '\(name)' returned invalid tools/list response")
            return []
        }

        var tools: [MCPToolInfo] = []
        for toolValue in toolsArray {
            guard case .object(let toolObj) = toolValue,
                  case .string(let toolName) = toolObj["name"] else {
                continue
            }
            let toolDesc: String
            if case .string(let desc) = toolObj["description"] {
                toolDesc = desc
            } else {
                toolDesc = ""
            }
            let inputSchema = toolObj["inputSchema"] ?? .object(["type": .string("object")])
            let inferred = ToolTypeInference.infer(name: toolName, description: toolDesc, inputSchema: inputSchema)
            tools.append(MCPToolInfo(
                name: toolName,
                description: toolDesc,
                inputSchema: inputSchema,
                serverName: name,
                outputType: inferred.output,
                acceptsInputTypes: inferred.accepts
            ))
        }

        Logger.info("MCP HTTP server '\(name)' discovered \(tools.count) tools")
        return tools
    }

    /// Call a tool
    func callTool(name toolName: String, arguments: JSONValue) async throws -> MCPToolCallResult {
        let response = try await sendJSONRPC(
            method: "tools/call",
            params: .object([
                "name": .string(toolName),
                "arguments": arguments
            ])
        )

        let rpc = response.rpcResponse
        if let error = rpc.error {
            return MCPToolCallResult(content: "Error: \(error.message)", isError: true)
        }

        guard case .object(let resultObj) = rpc.result else {
            return MCPToolCallResult(content: "No result", isError: true)
        }

        var resultText = ""
        let isError: Bool
        if case .bool(let err) = resultObj["isError"] { isError = err } else { isError = false }

        if case .array(let contentArray) = resultObj["content"] {
            for item in contentArray {
                guard case .object(let contentObj) = item else { continue }

                let contentType: String
                if case .string(let t) = contentObj["type"] { contentType = t } else { contentType = "text" }

                switch contentType {
                case "text":
                    if case .string(let text) = contentObj["text"] {
                        if !resultText.isEmpty { resultText += "\n" }
                        resultText += text
                    }
                case "image":
                    let mimeType: String
                    if case .string(let m) = contentObj["mimeType"] { mimeType = m } else { mimeType = "image/png" }
                    // Save base64 image to disk and return a serveable URL
                    if case .string(let b64Data) = contentObj["data"] {
                        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
                        let generatedDir = "\(homeDir)/.solace/generated"
                        if let filename = ImageFileHelper.saveBase64Image(data: b64Data, mimeType: mimeType, directory: generatedDir) {
                            if !resultText.isEmpty { resultText += "\n" }
                            resultText += "http://localhost:9201/images/\(filename)"
                        } else {
                            if !resultText.isEmpty { resultText += "\n" }
                            resultText += "[Image returned: \(mimeType) — failed to save]"
                        }
                    } else {
                        if !resultText.isEmpty { resultText += "\n" }
                        resultText += "[Image returned: \(mimeType)]"
                    }
                case "resource":
                    if case .object(let resource) = contentObj["resource"],
                       case .string(let uri) = resource["uri"] {
                        if !resultText.isEmpty { resultText += "\n" }
                        resultText += "[Resource: \(uri)]"
                    }
                default:
                    if case .string(let text) = contentObj["text"] {
                        if !resultText.isEmpty { resultText += "\n" }
                        resultText += text
                    }
                }
            }
        }

        if resultText.isEmpty {
            let json = (rpc.result ?? .null).toJSONString()
            resultText = json.count > 10_000 ? String(json.prefix(10_000)) + "\n[...truncated]" : json
        }

        return MCPToolCallResult(content: resultText, isError: isError)
    }

    func stop() {
        session.invalidateAndCancel()
        Logger.info("MCP HTTP server '\(name)' stopped")
    }

    // MARK: - HTTP Transport

    private struct HTTPResponse {
        let rpcResponse: JSONRPCResponse
        let sessionId: String?
    }

    private func sendJSONRPC(method: String, params: JSONValue?) async throws -> HTTPResponse {
        let requestId = state.withLock { s -> Int in
            let id = s.nextRequestId
            s.nextRequestId += 1
            return id
        }

        let rpcRequest = JSONRPCRequest(id: requestId, method: method, params: params)
        let body = try JSONEncoder().encode(rpcRequest)

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

        // Apply custom headers (e.g. API keys for authenticated MCP servers)
        for (key, value) in customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let sessionId = state.withLock({ $0.sessionId }) {
            request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }

        Logger.info("MCP HTTP[\(name)] sending \(method) id=\(requestId)")

        let (data, urlResponse) = try await session.data(for: request)

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw MCPError.invalidResponse
        }

        let sessionId = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id")

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            Logger.error("MCP HTTP[\(name)] error \(httpResponse.statusCode): \(body)")
            throw MCPError.invalidResponse
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""

        if contentType.contains("text/event-stream") {
            let rpc = try parseSSEResponse(data: data, requestId: requestId)
            return HTTPResponse(rpcResponse: rpc, sessionId: sessionId)
        } else {
            let rpc = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
            return HTTPResponse(rpcResponse: rpc, sessionId: sessionId)
        }
    }

    private func sendJSONRPCNotification(method: String, params: JSONValue?) async throws {
        struct Notification: Codable {
            let jsonrpc: String
            let method: String
            let params: JSONValue?
        }

        let notification = Notification(jsonrpc: "2.0", method: method, params: params)
        let body = try JSONEncoder().encode(notification)

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        for (key, value) in customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let sessionId = state.withLock({ $0.sessionId }) {
            request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }

        let (_, _) = try await session.data(for: request)
    }

    /// Parse an SSE response body to extract the JSON-RPC response for our request ID
    private func parseSSEResponse(data: Data, requestId: Int) throws -> JSONRPCResponse {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MCPError.invalidResponse
        }

        // SSE format: lines starting with "data: " contain JSON
        var lastRPCResponse: JSONRPCResponse?

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }

            let jsonStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard !jsonStr.isEmpty, jsonStr != "[DONE]" else { continue }

            guard let jsonData = jsonStr.data(using: .utf8) else { continue }

            if let rpc = try? JSONDecoder().decode(JSONRPCResponse.self, from: jsonData) {
                if rpc.id == requestId {
                    return rpc
                }
                lastRPCResponse = rpc
            }
        }

        if let last = lastRPCResponse {
            return last
        }

        throw MCPError.invalidResponse
    }
}

/// Thread-safe state for HTTP MCP server
private final class MCPHTTPState: @unchecked Sendable {
    private let lock = NSLock()
    var nextRequestId: Int = 1
    var sessionId: String?

    func withLock<T>(_ body: (MCPHTTPState) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(self)
    }
}
