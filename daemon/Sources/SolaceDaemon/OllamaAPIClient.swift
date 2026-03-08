import Foundation

// MARK: - Native API Request Types

private struct OllamaNativeRequest: Encodable, Sendable {
    let model: String
    let messages: [OllamaNativeChatMessage]
    let stream: Bool
    let tools: [OllamaToolDef]?
    let options: OllamaRequestOptions?

    init(model: String, messages: [OllamaNativeChatMessage], stream: Bool = true,
         tools: [OllamaToolDef]? = nil, options: OllamaRequestOptions? = nil) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.tools = tools
        self.options = options
    }
}

private struct OllamaRequestOptions: Encodable, Sendable {
    let num_predict: Int?
}

private struct OllamaNativeChatMessage: Encodable, Sendable {
    let role: String
    let content: String?
    let tool_calls: [OllamaNativeToolCallEntry]?

    init(role: String, content: String? = nil, tool_calls: [OllamaNativeToolCallEntry]? = nil) {
        self.role = role
        self.content = content
        self.tool_calls = tool_calls
    }
}

private struct OllamaNativeToolCallEntry: Encodable, Sendable {
    let function: OllamaNativeFunctionEntry
}

private struct OllamaNativeFunctionEntry: Encodable, Sendable {
    let name: String
    let arguments: JSONValue
}

// MARK: - Native API Response Types (NDJSON streaming + non-streaming)

private struct OllamaNativeChunk: Decodable, Sendable {
    let model: String?
    let message: OllamaNativeResponseMessage?
    let done: Bool?
    let done_reason: String?
}

private struct OllamaNativeResponseMessage: Decodable, Sendable {
    let role: String?
    let content: String?
    let tool_calls: [OllamaNativeResponseToolCall]?
}

private struct OllamaNativeResponseToolCall: Decodable, Sendable {
    let function: OllamaNativeResponseFunction?
}

private struct OllamaNativeResponseFunction: Decodable, Sendable {
    let name: String?
    let arguments: JSONValue?
}

// MARK: - Tool Definition Types (same format across both APIs)

private struct OllamaToolDef: Codable, Sendable {
    let type: String
    let function: OllamaFunctionDef

    init(function: OllamaFunctionDef) {
        self.type = "function"
        self.function = function
    }
}

private struct OllamaFunctionDef: Codable, Sendable {
    let name: String
    let description: String
    let parameters: JSONValue
}

// MARK: - Errors

enum OllamaAPIError: Error, Sendable {
    case unreachable(String)
    case invalidResponse
    case apiError(statusCode: Int, message: String)
}

// MARK: - Ollama API Client (Native /api/chat endpoint)

actor OllamaAPIClient: LLMProvider {
    private let baseURL: URL
    private let model: String
    private let apiKey: String?
    private let session: URLSession

    // MARK: - LLMProvider Properties

    nonisolated let providerName = "Ollama"
    nonisolated var modelName: String { model }
    nonisolated let supportsThinking = false
    nonisolated var supportsTools: Bool { true }

    init(endpoint: String, model: String, apiKey: String? = nil) {
        // Derive base URL from endpoint (handle legacy /v1/chat/completions format)
        var base = endpoint
        for suffix in ["/v1/chat/completions", "/v1/chat", "/v1", "/api/chat"] {
            if base.hasSuffix(suffix) {
                base = String(base.dropLast(suffix.count))
                break
            }
        }
        while base.hasSuffix("/") { base = String(base.dropLast()) }
        guard let parsedBase = URL(string: base), !base.isEmpty else {
            Logger.error("OllamaAPIClient: Invalid base URL derived from endpoint '\(endpoint)'. Using fallback.")
            self.baseURL = URL(string: "http://localhost:11434")!
            self.model = model
            self.apiKey = apiKey
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = 300
            sessionConfig.timeoutIntervalForResource = 600
            self.session = URLSession(configuration: sessionConfig)
            return
        }
        self.baseURL = parsedBase
        self.model = model
        self.apiKey = apiKey
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 300
        sessionConfig.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: sessionConfig)
    }

    // MARK: - Model Status

    private struct OllamaPSResponse: Codable {
        let models: [OllamaPSModel]?
    }
    private struct OllamaPSModel: Codable {
        let name: String
    }

    func isModelLoaded() async -> Bool {
        let psURL = baseURL.appendingPathComponent("api/ps")
        var request = URLRequest(url: psURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 3

        do {
            let (data, _) = try await session.data(for: request)
            let ps = try JSONDecoder().decode(OllamaPSResponse.self, from: data)
            let loadedNames = ps.models?.map { $0.name.lowercased() } ?? []
            let targetModel = model.lowercased()
            return loadedNames.contains { $0 == targetModel || $0.hasPrefix(targetModel.split(separator: ":").first.map(String.init) ?? targetModel) }
        } catch {
            return true // Assume loaded if we can't check
        }
    }

    // MARK: - Health Check

    func healthCheck() async -> Bool {
        let healthURL = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - LLMProvider Methods

    func streamRequest(
        messages: [MessageParam],
        tools: [ToolDefinition],
        systemPrompt: String? = nil
    ) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let nativeMessages = convertMessages(messages, systemPrompt: systemPrompt)
        let nativeTools = tools.isEmpty ? nil : convertTools(tools)

        let request = OllamaNativeRequest(
            model: model,
            messages: nativeMessages,
            stream: true,
            tools: nativeTools,
            options: OllamaRequestOptions(num_predict: 16384)
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.executeStream(request: request, continuation: continuation)
                } catch let urlError as URLError where urlError.code == .cannotConnectToHost || urlError.code == .cannotFindHost {
                    Logger.error("Ollama connection refused: \(urlError)")
                    continuation.yield(.error("Ollama is not running. Falling back to Claude."))
                    continuation.finish()
                } catch let urlError as URLError where urlError.code == .networkConnectionLost {
                    Logger.error("Ollama connection lost: \(urlError)")
                    continuation.yield(.error("Ollama is not running. Falling back to Claude."))
                    continuation.finish()
                } catch let urlError as URLError where urlError.code == .timedOut {
                    Logger.error("Ollama request timed out: \(urlError)")
                    continuation.yield(.error("Response timed out — tap to retry"))
                    continuation.finish()
                } catch {
                    continuation.yield(.error("Ollama stream error: \(error.localizedDescription)"))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func singleRequest(
        messages: [MessageParam],
        systemPrompt: String
    ) async throws -> String {
        let nativeMessages = convertMessages(messages, systemPrompt: systemPrompt)

        let request = OllamaNativeRequest(
            model: model,
            messages: nativeMessages,
            stream: false,
            options: OllamaRequestOptions(num_predict: 8192)
        )

        let chatURL = baseURL.appendingPathComponent("api/chat")
        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(request)

        var urlRequest = URLRequest(url: chatURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        if let apiKey = apiKey {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = bodyData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError where urlError.code == .cannotConnectToHost || urlError.code == .cannotFindHost || urlError.code == .networkConnectionLost {
            Logger.error("Ollama connection refused (singleRequest): \(urlError)")
            throw OllamaAPIError.unreachable("Ollama is not running. Falling back to Claude.")
        } catch let urlError as URLError where urlError.code == .timedOut {
            Logger.error("Ollama request timed out (singleRequest): \(urlError)")
            throw OllamaAPIError.unreachable("Response timed out — tap to retry")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaAPIError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            let body = String(data: data, encoding: .utf8) ?? ""
            Logger.error("Ollama model not found (singleRequest): \(model) — \(body)")
            throw OllamaAPIError.apiError(
                statusCode: 404,
                message: "Model '\(model)' not available. Run `ollama pull \(model)` to install it."
            )
        }

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OllamaAPIError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        let decoded = try JSONDecoder().decode(OllamaNativeChunk.self, from: data)
        return decoded.message?.content ?? ""
    }

    // MARK: - Private Streaming (NDJSON)

    private func executeStream(
        request: OllamaNativeRequest,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async throws {
        let chatURL = baseURL.appendingPathComponent("api/chat")
        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(request)

        var urlRequest = URLRequest(url: chatURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        if let apiKey = apiKey {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = bodyData
        urlRequest.timeoutInterval = 300

        let toolNames = request.tools?.map { $0.function.name } ?? []
        Logger.info("Ollama stream request: model=\(model), \(bodyData.count) bytes, \(toolNames.count) tools [\(toolNames.joined(separator: ", "))]")

        let (asyncBytes, response) = try await session.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            continuation.yield(.error("Invalid response from Ollama"))
            continuation.finish()
            return
        }

        Logger.info("Ollama HTTP status: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 404 {
            var errorBody = ""
            for try await line in asyncBytes.lines { errorBody += line }
            Logger.error("Ollama model not found: \(model) — \(errorBody)")
            continuation.yield(.error("Model '\(model)' not available. Run `ollama pull \(model)` to install it."))
            continuation.finish()
            return
        }

        if httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in asyncBytes.lines { errorBody += line }
            Logger.error("Ollama error: \(errorBody)")
            continuation.yield(.error("Ollama error \(httpResponse.statusCode): \(errorBody)"))
            continuation.finish()
            return
        }

        // Parse NDJSON stream — each line is a complete JSON object
        var hasEmittedTextStart = false
        var emittedToolCallIDs: Set<String> = []
        let decoder = JSONDecoder()

        for try await line in asyncBytes.lines {
            guard !line.isEmpty else { continue }

            guard let jsonData = line.data(using: .utf8),
                  let chunk = try? decoder.decode(OllamaNativeChunk.self, from: jsonData) else {
                Logger.error("Ollama malformed NDJSON chunk: \(line)")
                continue
            }

            // Handle text content
            if let content = chunk.message?.content, !content.isEmpty {
                if !hasEmittedTextStart {
                    continuation.yield(.textStart)
                    hasEmittedTextStart = true
                }
                continuation.yield(.textDelta(content))
            }

            // Handle tool calls (typically arrive in the final chunk)
            if let toolCalls = chunk.message?.tool_calls {
                // Close text stream before emitting tool calls
                if hasEmittedTextStart {
                    continuation.yield(.textDone)
                    hasEmittedTextStart = false
                }

                for tc in toolCalls {
                    guard let name = tc.function?.name else { continue }
                    let toolId = "ollama_tc_\(UUID().uuidString.prefix(8))"

                    let argsString: String
                    if let args = tc.function?.arguments {
                        argsString = args.toJSONString()
                    } else {
                        argsString = "{}"
                    }

                    continuation.yield(.toolUseStart(id: toolId, name: name))
                    continuation.yield(.toolUseDone(id: toolId, name: name, input: argsString))
                    emittedToolCallIDs.insert(toolId)
                    let argCount = (try? JSONSerialization.jsonObject(with: argsString.data(using: .utf8) ?? Data()) as? [String: Any])?.count ?? 0
                    Logger.info("Ollama tool call: \(name) with \(argCount) args")
                }
            }

            // Stream ends when done is true
            if chunk.done == true {
                break
            }
        }

        // Close text stream if still open
        if hasEmittedTextStart {
            continuation.yield(.textDone)
        }

        Logger.info("Ollama stream complete: \(emittedToolCallIDs.count) tool call(s)")
        continuation.yield(.messageComplete)
        continuation.finish()
    }

    // MARK: - Message Conversion (Claude -> Ollama native format)

    private func convertMessages(_ messages: [MessageParam], systemPrompt: String?) -> [OllamaNativeChatMessage] {
        var result: [OllamaNativeChatMessage] = []

        if let system = systemPrompt, !system.isEmpty {
            result.append(OllamaNativeChatMessage(role: "system", content: system))
        }

        for msg in messages {
            var textParts: [String] = []
            var toolUseCalls: [OllamaNativeToolCallEntry] = []
            var toolResults: [String] = []

            for block in msg.content {
                switch block {
                case .text(let tc):
                    textParts.append(tc.text)
                case .thinking:
                    break // Ollama doesn't support thinking blocks
                case .toolUse(let tu):
                    toolUseCalls.append(OllamaNativeToolCallEntry(
                        function: OllamaNativeFunctionEntry(
                            name: tu.name,
                            arguments: tu.input  // JSONValue object, not string
                        )
                    ))
                case .toolResult(let tr):
                    toolResults.append(tr.content)
                case .image:
                    textParts.append("[image attached]")
                case .audio:
                    textParts.append("[voice note attached]")
                }
            }

            if msg.role == "assistant" {
                let content = textParts.isEmpty ? nil : textParts.joined()
                let calls = toolUseCalls.isEmpty ? nil : toolUseCalls
                result.append(OllamaNativeChatMessage(role: "assistant", content: content, tool_calls: calls))
            } else if !toolResults.isEmpty {
                for tr in toolResults {
                    result.append(OllamaNativeChatMessage(role: "tool", content: tr))
                }
            } else {
                result.append(OllamaNativeChatMessage(role: msg.role, content: textParts.joined()))
            }
        }

        return sanitizeToolMessages(result)
    }

    /// Remove orphaned tool messages without a preceding assistant message with tool_calls.
    private func sanitizeToolMessages(_ messages: [OllamaNativeChatMessage]) -> [OllamaNativeChatMessage] {
        var sanitized: [OllamaNativeChatMessage] = []
        var expectedToolResults = 0

        for msg in messages {
            if msg.role == "assistant" {
                if let calls = msg.tool_calls, !calls.isEmpty {
                    expectedToolResults = calls.count
                } else {
                    expectedToolResults = 0
                }
                sanitized.append(msg)
            } else if msg.role == "tool" {
                if expectedToolResults > 0 {
                    sanitized.append(msg)
                    expectedToolResults -= 1
                } else {
                    Logger.error("Ollama: dropping orphaned tool message — no matching assistant tool_calls")
                }
            } else {
                expectedToolResults = 0
                sanitized.append(msg)
            }
        }

        return sanitized
    }

    // MARK: - Tool Conversion

    private func convertTools(_ tools: [ToolDefinition]) -> [OllamaToolDef] {
        tools.map { tool in
            OllamaToolDef(function: OllamaFunctionDef(
                name: tool.name,
                description: tool.description,
                parameters: tool.input_schema
            ))
        }
    }
}
