import Foundation

// MARK: - OpenAI-Compatible Request/Response Types (for Ollama)

private struct OllamaRequest: Codable, Sendable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool
    let tools: [OllamaToolDef]?
    let max_tokens: Int?

    init(model: String, messages: [OllamaChatMessage], stream: Bool = true,
         tools: [OllamaToolDef]? = nil, max_tokens: Int? = 16384) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.tools = tools
        self.max_tokens = max_tokens
    }
}

private struct OllamaChatMessage: Codable, Sendable {
    let role: String
    let content: String?
    let tool_calls: [OllamaToolCallResult]?
    let tool_call_id: String?

    init(role: String, content: String? = nil, tool_calls: [OllamaToolCallResult]? = nil, tool_call_id: String? = nil) {
        self.role = role
        self.content = content
        self.tool_calls = tool_calls
        self.tool_call_id = tool_call_id
    }
}

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

private struct OllamaToolCallResult: Codable, Sendable {
    let id: String
    let type: String
    let function: OllamaFunctionCall

    init(id: String, function: OllamaFunctionCall) {
        self.id = id
        self.type = "function"
        self.function = function
    }
}

private struct OllamaFunctionCall: Codable, Sendable {
    let name: String
    let arguments: String
}

// MARK: - SSE Chunk Types (OpenAI format)

private struct OllamaSSEChunk: Codable, Sendable {
    let choices: [OllamaSSEChoice]?
}

private struct OllamaSSEChoice: Codable, Sendable {
    let index: Int?
    let delta: OllamaSSEDelta?
    let finish_reason: String?
}

private struct OllamaSSEDelta: Codable, Sendable {
    let role: String?
    let content: String?
    let tool_calls: [OllamaSSEToolCall]?
}

private struct OllamaSSEToolCall: Codable, Sendable {
    let index: Int?
    let id: String?
    let type: String?
    let function: OllamaSSEFunctionCall?
}

private struct OllamaSSEFunctionCall: Codable, Sendable {
    let name: String?
    let arguments: String?
}

// MARK: - Non-streaming response

private struct OllamaNonStreamResponse: Codable, Sendable {
    let choices: [OllamaNonStreamChoice]?
}

private struct OllamaNonStreamChoice: Codable, Sendable {
    let message: OllamaNonStreamMessage?
}

private struct OllamaNonStreamMessage: Codable, Sendable {
    let content: String?
}

// MARK: - Pending Tool Call Accumulator

private struct OllamaPendingToolCall: Sendable {
    var id: String
    var name: String
    var argumentsJSON: String
}

// MARK: - Text-based Tool Call Parsing (fallback for models without native function calling)

private struct TextToolCall: Codable {
    let name: String
    let arguments: [String: AnyCodableValue]?
}

/// Flexible JSON value type for parsing arbitrary tool call arguments
private enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if container.decodeNil() { self = .null }
        else if let v = try? container.decode([AnyCodableValue].self) { self = .array(v) }
        else if let v = try? container.decode([String: AnyCodableValue].self) { self = .object(v) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported value") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }

    /// Convert to Any for JSONSerialization
    var toAny: Any {
        switch self {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .null: return NSNull()
        case .array(let v): return v.map { $0.toAny }
        case .object(let v): return v.mapValues { $0.toAny }
        }
    }
}

// MARK: - Ollama API Client

enum OllamaAPIError: Error, Sendable {
    case unreachable(String)
    case invalidResponse
    case apiError(statusCode: Int, message: String)
}

/// Ollama API client using OpenAI-compatible /v1/chat/completions endpoint
actor OllamaAPIClient: LLMProvider {
    private let endpoint: URL
    private let model: String
    private let apiKey: String?
    private let session: URLSession

    // MARK: - LLMProvider Properties

    nonisolated let providerName = "Ollama"
    nonisolated var modelName: String { model }
    nonisolated let supportsThinking = false
    nonisolated var supportsTools: Bool { true }  // Attempt tools; gracefully degrade if model doesn't support

    init(endpoint: String, model: String, apiKey: String? = nil) {
        self.endpoint = URL(string: endpoint)!
        self.model = model
        self.apiKey = apiKey
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 300
        sessionConfig.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: sessionConfig)
    }

    // MARK: - Health Check

    /// Check if the Ollama endpoint is reachable
    func healthCheck() async -> Bool {
        // Try the /v1/models endpoint (standard OpenAI-compat health check)
        // endpoint is .../v1/chat/completions — go up 3 levels (completions, chat, v1) to reach the base URL
        let baseURL = endpoint.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let healthURL = baseURL.appendingPathComponent("v1/models")

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
        let ollamaMessages = convertMessages(messages, systemPrompt: systemPrompt)
        let ollamaTools = tools.isEmpty ? nil : convertTools(tools)

        let request = OllamaRequest(
            model: model,
            messages: ollamaMessages,
            stream: true,
            tools: ollamaTools
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
        let ollamaMessages = convertMessages(messages, systemPrompt: systemPrompt)

        let request = OllamaRequest(
            model: model,
            messages: ollamaMessages,
            stream: false,
            tools: nil,
            max_tokens: 8192
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(request)

        var urlRequest = URLRequest(url: endpoint)
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
            Logger.error("Ollama model not found (singleRequest): \(request.model) — \(body)")
            throw OllamaAPIError.apiError(
                statusCode: 404,
                message: "Model '\(request.model)' not available. Run `ollama pull \(request.model)` to install it."
            )
        }

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OllamaAPIError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        let decoded = try JSONDecoder().decode(OllamaNonStreamResponse.self, from: data)
        return decoded.choices?.first?.message?.content ?? ""
    }

    // MARK: - Private Streaming

    private func executeStream(
        request: OllamaRequest,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async throws {
        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(request)

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        if let apiKey = apiKey {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = bodyData
        urlRequest.timeoutInterval = 60  // 60s per-chunk timeout for streaming

        Logger.info("Ollama request: \(bodyData.count) bytes to \(endpoint)")

        let (asyncBytes, response) = try await session.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            continuation.yield(.error("Invalid response from Ollama"))
            continuation.finish()
            return
        }

        Logger.info("Ollama HTTP status: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 404 {
            var errorBody = ""
            for try await line in asyncBytes.lines {
                errorBody += line
            }
            Logger.error("Ollama model not found: \(request.model) — \(errorBody)")
            continuation.yield(.error("Model '\(request.model)' not available. Run `ollama pull \(request.model)` to install it."))
            continuation.finish()
            return
        }

        if httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in asyncBytes.lines {
                errorBody += line
            }
            Logger.error("Ollama error: \(errorBody)")
            continuation.yield(.error("Ollama error \(httpResponse.statusCode): \(errorBody)"))
            continuation.finish()
            return
        }

        // Parse SSE stream (OpenAI format: data: {...}\n\n)
        var hasEmittedTextStart = false
        var pendingToolCalls: [Int: OllamaPendingToolCall] = [:]
        var nativeToolCallsDetected = false
        let decoder = JSONDecoder()

        // Text buffer for detecting <tool_call> blocks in model output
        var textBuffer = ""
        var textToolCallIndex = 100  // Start high to avoid collision with native tool call indices

        for try await line in asyncBytes.lines {
            // Skip empty lines and SSE comments
            guard !line.isEmpty, !line.hasPrefix(":") else { continue }

            // Extract data payload
            let payload: String
            if line.hasPrefix("data: ") {
                payload = String(line.dropFirst(6))
            } else {
                payload = line
            }

            // [DONE] marker signals end of stream
            if payload.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                break
            }

            guard let jsonData = payload.data(using: .utf8),
                  let chunk = try? decoder.decode(OllamaSSEChunk.self, from: jsonData) else {
                Logger.error("Ollama malformed SSE chunk: \(payload)")
                continue
            }

            guard let choice = chunk.choices?.first else { continue }
            let delta = choice.delta

            // Handle text content — buffer for tool call detection
            if let content = delta?.content, !content.isEmpty {
                textBuffer += content

                // Check for complete <tool_call> blocks in buffer
                while let toolCallRange = textBuffer.range(of: "<tool_call>"),
                      let endRange = textBuffer.range(of: "</tool_call>") {
                    // Extract any text before the tool call tag and emit it
                    let textBefore = String(textBuffer[textBuffer.startIndex..<toolCallRange.lowerBound])
                    if !textBefore.isEmpty {
                        if !hasEmittedTextStart {
                            continuation.yield(.textStart)
                            hasEmittedTextStart = true
                        }
                        continuation.yield(.textDelta(textBefore))
                    }

                    // Extract the JSON between tags
                    let jsonStr = String(textBuffer[toolCallRange.upperBound..<endRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    // Parse and emit tool call events
                    if let jsonData = jsonStr.data(using: .utf8),
                       let toolJSON = try? JSONDecoder().decode(TextToolCall.self, from: jsonData) {
                        let toolId = "ollama_tc_\(UUID().uuidString.prefix(8))"
                        let argsString: String
                        let argsAny = (toolJSON.arguments ?? [:]).mapValues { $0.toAny }
                        if let argsData = try? JSONSerialization.data(withJSONObject: argsAny),
                           let argsStr = String(data: argsData, encoding: .utf8) {
                            argsString = argsStr
                        } else {
                            argsString = "{}"
                        }

                        pendingToolCalls[textToolCallIndex] = OllamaPendingToolCall(
                            id: toolId, name: toolJSON.name, argumentsJSON: argsString
                        )
                        continuation.yield(.toolUseStart(id: toolId, name: toolJSON.name))
                        continuation.yield(.toolUseDone(id: toolId, name: toolJSON.name, input: argsString))
                        textToolCallIndex += 1

                        Logger.info("Ollama text-based tool call parsed: \(toolJSON.name)")
                    } else {
                        Logger.error("Ollama text tool call parse failed: \(jsonStr)")
                    }

                    // Remove processed portion from buffer
                    textBuffer = String(textBuffer[endRange.upperBound...])
                }

                // If no pending <tool_call> tag in buffer, flush safe text
                if !textBuffer.contains("<tool_call") {
                    if !textBuffer.isEmpty {
                        if !hasEmittedTextStart {
                            continuation.yield(.textStart)
                            hasEmittedTextStart = true
                        }
                        continuation.yield(.textDelta(textBuffer))
                        textBuffer = ""
                    }
                }
                // Otherwise hold the buffer — might be a partial <tool_call> tag
            }

            // Handle native tool calls (OpenAI function calling format)
            if let toolCalls = delta?.tool_calls {
                nativeToolCallsDetected = true
                for tc in toolCalls {
                    let idx = tc.index ?? 0

                    // New tool call starting
                    if let id = tc.id, let name = tc.function?.name {
                        pendingToolCalls[idx] = OllamaPendingToolCall(id: id, name: name, argumentsJSON: "")
                        continuation.yield(.toolUseStart(id: id, name: name))
                    }

                    // Accumulate argument deltas
                    if let args = tc.function?.arguments {
                        pendingToolCalls[idx]?.argumentsJSON += args
                        continuation.yield(.toolUseInputDelta(args))
                    }
                }
            }

            // Check for finish reason
            if let finishReason = choice.finish_reason {
                // Flush any remaining text buffer before finishing
                if !textBuffer.isEmpty {
                    // Check one last time for tool calls
                    if let toolCallRange = textBuffer.range(of: "<tool_call>"),
                       let endRange = textBuffer.range(of: "</tool_call>") {
                        let textBefore = String(textBuffer[textBuffer.startIndex..<toolCallRange.lowerBound])
                        if !textBefore.isEmpty {
                            if !hasEmittedTextStart {
                                continuation.yield(.textStart)
                                hasEmittedTextStart = true
                            }
                            continuation.yield(.textDelta(textBefore))
                        }
                        let jsonStr = String(textBuffer[toolCallRange.upperBound..<endRange.lowerBound])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if let jsonData = jsonStr.data(using: .utf8),
                           let toolJSON = try? JSONDecoder().decode(TextToolCall.self, from: jsonData) {
                            let toolId = "ollama_tc_\(UUID().uuidString.prefix(8))"
                            let argsString: String
                            let argsAny = (toolJSON.arguments ?? [:]).mapValues { $0.toAny }
                        if let argsData = try? JSONSerialization.data(withJSONObject: argsAny),
                               let argsStr = String(data: argsData, encoding: .utf8) {
                                argsString = argsStr
                            } else {
                                argsString = "{}"
                            }
                            pendingToolCalls[textToolCallIndex] = OllamaPendingToolCall(
                                id: toolId, name: toolJSON.name, argumentsJSON: argsString
                            )
                            continuation.yield(.toolUseStart(id: toolId, name: toolJSON.name))
                            continuation.yield(.toolUseDone(id: toolId, name: toolJSON.name, input: argsString))
                            textToolCallIndex += 1
                        }
                        textBuffer = String(textBuffer[endRange.upperBound...])
                    }
                    // Emit any remaining non-tool text
                    let remaining = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !remaining.isEmpty {
                        if !hasEmittedTextStart {
                            continuation.yield(.textStart)
                            hasEmittedTextStart = true
                        }
                        continuation.yield(.textDelta(remaining))
                    }
                    textBuffer = ""
                }

                if hasEmittedTextStart {
                    continuation.yield(.textDone)
                    hasEmittedTextStart = false  // Prevent duplicate textDone
                }

                // Emit completed native tool calls
                if (finishReason == "tool_calls" || finishReason == "stop") && nativeToolCallsDetected {
                    for (_, toolCall) in pendingToolCalls.sorted(by: { $0.key < $1.key }).filter({ $0.key < 100 }) {
                        continuation.yield(.toolUseDone(
                            id: toolCall.id,
                            name: toolCall.name,
                            input: toolCall.argumentsJSON
                        ))
                    }
                }
            }
        }

        // Flush any remaining text buffer at end of stream
        if !textBuffer.isEmpty {
            let remaining = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                if !hasEmittedTextStart {
                    continuation.yield(.textStart)
                    hasEmittedTextStart = true
                }
                continuation.yield(.textDelta(remaining))
            }
        }

        // If text was started but never explicitly done (some models skip finish_reason)
        if hasEmittedTextStart {
            continuation.yield(.textDone)
        }

        // Emit any remaining native tool calls that didn't get a finish_reason
        if nativeToolCallsDetected {
            for (_, toolCall) in pendingToolCalls.sorted(by: { $0.key < $1.key }).filter({ $0.key < 100 }) {
                if !toolCall.argumentsJSON.isEmpty || !toolCall.name.isEmpty {
                    continuation.yield(.toolUseDone(
                        id: toolCall.id,
                        name: toolCall.name,
                        input: toolCall.argumentsJSON
                    ))
                }
            }
        }

        continuation.yield(.messageComplete)
        continuation.finish()
    }

    // MARK: - Message Conversion (Claude -> OpenAI format)

    private func convertMessages(_ messages: [MessageParam], systemPrompt: String?) -> [OllamaChatMessage] {
        var result: [OllamaChatMessage] = []

        // Add system prompt as first message
        if let system = systemPrompt, !system.isEmpty {
            result.append(OllamaChatMessage(role: "system", content: system))
        }

        for msg in messages {
            // Flatten content blocks to text
            var textParts: [String] = []
            var toolUseCalls: [OllamaToolCallResult] = []
            var toolResults: [(id: String, content: String)] = []

            for block in msg.content {
                switch block {
                case .text(let tc):
                    textParts.append(tc.text)
                case .thinking:
                    // Skip thinking blocks — Ollama doesn't support them
                    break
                case .toolUse(let tu):
                    toolUseCalls.append(OllamaToolCallResult(
                        id: tu.id,
                        function: OllamaFunctionCall(
                            name: tu.name,
                            arguments: tu.input.toJSONString()
                        )
                    ))
                case .toolResult(let tr):
                    toolResults.append((id: tr.tool_use_id, content: tr.content))
                case .image:
                    textParts.append("[image attached]")
                case .audio:
                    textParts.append("[voice note attached]")
                }
            }

            if msg.role == "assistant" {
                // Assistant message with tool calls
                let content = textParts.isEmpty ? nil : textParts.joined()
                let calls = toolUseCalls.isEmpty ? nil : toolUseCalls
                result.append(OllamaChatMessage(role: "assistant", content: content, tool_calls: calls))
            } else if !toolResults.isEmpty {
                // Tool results become individual "tool" role messages
                for tr in toolResults {
                    result.append(OllamaChatMessage(role: "tool", content: tr.content, tool_call_id: tr.id))
                }
            } else {
                result.append(OllamaChatMessage(role: msg.role, content: textParts.joined()))
            }
        }

        return result
    }

    // MARK: - Tool Conversion (MCP -> OpenAI function-calling format)

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
