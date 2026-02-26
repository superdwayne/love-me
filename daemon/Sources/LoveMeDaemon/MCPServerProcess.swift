import Foundation

/// Thread-safe state container for MCP server process
private final class MCPState: @unchecked Sendable {
    private let lock = NSLock()
    var nextRequestId: Int = 1
    var pendingRequests: [Int: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    var readBuffer = Data()
    var discoveredTools: [MCPToolInfo] = []
    var isRunning = false

    func withLock<T>(_ body: (MCPState) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(self)
    }
}

/// Wraps an individual MCP server child process communicating via JSON-RPC over stdio
final class MCPServerProcess: Sendable {
    let name: String
    private let config: MCPServerConfig
    private let state = MCPState()
    // These are set once during start() and never mutated after
    private nonisolated(unsafe) var process: Process?
    private nonisolated(unsafe) var stdinPipe: Pipe?
    private nonisolated(unsafe) var stdoutPipe: Pipe?
    private nonisolated(unsafe) var stderrPipe: Pipe?

    init(name: String, config: MCPServerConfig) {
        self.name = name
        self.config = config
    }

    /// Launch the MCP server process and perform initialization
    func start() async throws {
        let proc = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        guard let command = config.command else {
            throw MCPError.serverNotRunning
        }
        proc.executableURL = URL(fileURLWithPath: command)
        proc.arguments = config.args ?? []
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        var env = ProcessInfo.processInfo.environment
        if let configEnv = config.env {
            for (key, value) in configEnv {
                env[key] = value
            }
        }
        proc.environment = env

        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        self.process = proc
        state.withLock { $0.isRunning = true }

        let stateRef = state
        proc.terminationHandler = { _ in
            let pending = stateRef.withLock { s -> [Int: CheckedContinuation<JSONRPCResponse, Error>] in
                s.isRunning = false
                let p = s.pendingRequests
                s.pendingRequests.removeAll()
                return p
            }
            for (_, continuation) in pending {
                continuation.resume(throwing: MCPError.serverCrashed)
            }
        }

        try proc.run()
        Logger.info("MCP server '\(name)' started (PID: \(proc.processIdentifier))")

        // Read stdout on a dedicated background thread
        let readHandle = stdout.fileHandleForReading
        let serverName2 = name
        Thread.detachNewThread {
            Logger.info("MCP[\(serverName2)] read thread started")
            while true {
                let chunk = readHandle.availableData
                if chunk.isEmpty { break } // EOF
                Logger.info("MCP[\(serverName2)] received \(chunk.count) bytes")
                stateRef.withLock { s in
                    s.readBuffer.append(chunk)
                    MCPServerProcess.processBuffer(state: s, serverName: serverName2)
                }
            }
            Logger.info("MCP[\(serverName2)] stdout EOF")
        }

        // Log stderr on a dedicated thread
        let serverName = name
        let stderrHandle = stderr.fileHandleForReading
        Thread.detachNewThread {
            while true {
                let data = stderrHandle.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    Logger.error("MCP[\(serverName)] stderr: \(text)")
                }
            }
        }

        // Initialize with timeout (npx cold starts can take 30-60s)
        _ = try await withTimeout(seconds: 60) { [self] in
            try await self.sendRequest(
                method: "initialize",
                params: .object([
                    "protocolVersion": .string("2024-11-05"),
                    "capabilities": .object([:]),
                    "clientInfo": .object([
                        "name": .string("love.Me"),
                        "version": .string(DaemonConfig.version)
                    ])
                ])
            )
        }
        Logger.info("MCP server '\(name)' initialized")

        // Send initialized notification (fire-and-forget, no response expected)
        sendNotification(method: "notifications/initialized", params: .object([:]))
    }

    /// Discover available tools from the server
    func discoverTools() async throws -> [MCPToolInfo] {
        let response = try await withTimeout(seconds: 10) { [self] in
            try await self.sendRequest(method: "tools/list", params: .object([:]))
        }

        guard case .object(let resultObj) = response.result,
              case .array(let toolsArray) = resultObj["tools"] else {
            Logger.error("MCP server '\(name)' returned invalid tools/list response")
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
            tools.append(MCPToolInfo(
                name: toolName,
                description: toolDesc,
                inputSchema: inputSchema,
                serverName: name
            ))
        }

        state.withLock { $0.discoveredTools = tools }
        Logger.info("MCP server '\(name)' discovered \(tools.count) tools")
        return tools
    }

    /// Call a tool on this MCP server
    func callTool(name toolName: String, arguments: JSONValue) async throws -> MCPToolCallResult {
        let response = try await withTimeout(seconds: 60) { [self] in
            try await self.sendRequest(
                method: "tools/call",
                params: .object([
                    "name": .string(toolName),
                    "arguments": arguments
                ])
            )
        }

        if let error = response.error {
            return MCPToolCallResult(content: "Error: \(error.message)", isError: true)
        }

        guard case .object(let resultObj) = response.result else {
            return MCPToolCallResult(content: "No result", isError: true)
        }

        var resultText = ""
        let isError: Bool
        if case .bool(let err) = resultObj["isError"] { isError = err } else { isError = false }

        if case .array(let contentArray) = resultObj["content"] {
            for item in contentArray {
                guard case .object(let contentObj) = item else { continue }

                // Extract content type
                let contentType: String
                if case .string(let t) = contentObj["type"] { contentType = t } else { contentType = "text" }

                switch contentType {
                case "text":
                    if case .string(let text) = contentObj["text"] {
                        if !resultText.isEmpty { resultText += "\n" }
                        resultText += text
                    }
                case "image":
                    // Don't include raw base64 image data — it bloats context and freezes clients
                    let mimeType: String
                    if case .string(let m) = contentObj["mimeType"] { mimeType = m } else { mimeType = "image/png" }
                    if !resultText.isEmpty { resultText += "\n" }
                    resultText += "[Image returned: \(mimeType)]"
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
            // Fallback: serialize JSON but cap at 10KB to prevent freezing
            let json = (response.result ?? .null).toJSONString()
            resultText = json.count > 10_000 ? String(json.prefix(10_000)) + "\n[...truncated]" : json
        }

        return MCPToolCallResult(content: resultText, isError: isError)
    }

    /// Stop the MCP server process
    func stop() {
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        state.withLock { $0.isRunning = false }
        Logger.info("MCP server '\(name)' stopped")
    }

    var tools: [MCPToolInfo] {
        state.withLock { $0.discoveredTools }
    }

    // MARK: - Private

    /// Send a JSON-RPC notification (no id, no response expected)
    private func sendNotification(method: String, params: JSONValue?) {
        guard let stdinHandle = stdinPipe?.fileHandleForWriting else { return }

        // Notification: no "id" field
        struct JSONRPCNotification: Codable {
            let jsonrpc: String
            let method: String
            let params: JSONValue?
        }
        let notification = JSONRPCNotification(jsonrpc: "2.0", method: method, params: params)
        guard var data = try? JSONEncoder().encode(notification) else { return }
        data.append(contentsOf: "\n".utf8)

        stdinHandle.write(data)
    }

    private func sendRequest(method: String, params: JSONValue?) async throws -> JSONRPCResponse {
        let requestId = state.withLock { s -> Int in
            let id = s.nextRequestId
            s.nextRequestId += 1
            return id
        }

        let request = JSONRPCRequest(id: requestId, method: method, params: params)
        let data = try JSONEncoder().encode(request)

        guard let stdinHandle = stdinPipe?.fileHandleForWriting else {
            throw MCPError.serverNotRunning
        }

        let stateRef = state
        Logger.info("MCP sending request id=\(requestId) method=\(method)")
        var fullData = data
        fullData.append(contentsOf: "\n".utf8)

        let response = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<JSONRPCResponse, Error>) in
            stateRef.withLock { s in
                s.pendingRequests[requestId] = cont
            }
            stdinHandle.write(fullData)
            Logger.info("MCP wrote \(fullData.count) bytes to stdin")
        }

        return response
    }

    /// Process buffered data - called under lock via state.withLock
    /// Supports both newline-delimited JSON and Content-Length framed messages
    private static func processBuffer(state: MCPState, serverName: String = "") {
        while true {
            // Try newline-delimited JSON first (most MCP servers use this)
            if let newlineIndex = state.readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = Data(state.readBuffer[state.readBuffer.startIndex..<newlineIndex])
                // Strip trailing \r if present
                let trimmed: Data
                if lineData.last == UInt8(ascii: "\r") {
                    trimmed = Data(lineData.dropLast())
                } else {
                    trimmed = lineData
                }
                if !trimmed.isEmpty {
                    // Check if this looks like JSON (starts with '{')
                    if trimmed.first == UInt8(ascii: "{") {
                        state.readBuffer = Data(state.readBuffer[(newlineIndex + 1)...])
                        parseResponse(trimmed, state: state, serverName: serverName)
                        continue
                    }
                    // Check if it's a Content-Length header
                    if let headerStr = String(data: trimmed, encoding: .utf8),
                       headerStr.lowercased().hasPrefix("content-length:") {
                        // Content-Length framed: find the blank line separator then read body
                        if let headerEnd = state.readBuffer.range(of: Data("\r\n\r\n".utf8)) {
                            let lengthStr = headerStr.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                            if let contentLength = Int(lengthStr) {
                                let bodyStart = headerEnd.upperBound
                                let available = state.readBuffer.count - (bodyStart - state.readBuffer.startIndex)
                                if available < contentLength { return } // wait for more data
                                let bodyEnd = state.readBuffer.index(bodyStart, offsetBy: contentLength)
                                let bodyData = Data(state.readBuffer[bodyStart..<bodyEnd])
                                state.readBuffer = Data(state.readBuffer[bodyEnd...])
                                parseResponse(bodyData, state: state, serverName: serverName)
                                continue
                            }
                        }
                        return // incomplete header, wait for more data
                    }
                }
                // Empty line or unrecognized - skip it
                state.readBuffer = Data(state.readBuffer[(newlineIndex + 1)...])
                continue
            }
            return // no newline yet, wait for more data
        }
    }

    private static func parseResponse(_ data: Data, state: MCPState, serverName: String = "") {
        if let text = String(data: data, encoding: .utf8) {
            Logger.info("MCP[\(serverName)] parsing: \(String(text.prefix(200)))")
        }
        guard let response = try? JSONDecoder().decode(JSONRPCResponse.self, from: data) else {
            Logger.error("MCP[\(serverName)] failed to decode response")
            return
        }
        if let id = response.id, let continuation = state.pendingRequests.removeValue(forKey: id) {
            Logger.info("MCP[\(serverName)] resolved request \(id)")
            continuation.resume(returning: response)
        } else {
            Logger.info("MCP[\(serverName)] received notification or unknown id=\(response.id ?? -1)")
        }
    }
}

enum MCPError: Error, Sendable {
    case serverNotRunning
    case serverCrashed
    case encodingFailed
    case invalidResponse
    case toolNotFound(String)
    case timeout
}

func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw MCPError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
