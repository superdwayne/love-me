import Foundation

// MARK: - OpenAI Request/Response Types

private struct OpenAIRequest: Codable, Sendable {
    let model: String
    let messages: [OpenAIChatMessage]
    let stream: Bool
    let tools: [OpenAIToolDef]?
    let max_tokens: Int?

    init(model: String, messages: [OpenAIChatMessage], stream: Bool = true,
         tools: [OpenAIToolDef]? = nil, max_tokens: Int? = 16384) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.tools = tools
        self.max_tokens = max_tokens
    }
}

private struct OpenAIChatMessage: Codable, Sendable {
    let role: String
    let content: String?
    let tool_calls: [OpenAIToolCallResult]?
    let tool_call_id: String?

    init(role: String, content: String? = nil, tool_calls: [OpenAIToolCallResult]? = nil, tool_call_id: String? = nil) {
        self.role = role
        self.content = content
        self.tool_calls = tool_calls
        self.tool_call_id = tool_call_id
    }
}

private struct OpenAIToolDef: Codable, Sendable {
    let type: String
    let function: OpenAIFunctionDef

    init(function: OpenAIFunctionDef) {
        self.type = "function"
        self.function = function
    }
}

private struct OpenAIFunctionDef: Codable, Sendable {
    let name: String
    let description: String
    let parameters: JSONValue
}

private struct OpenAIToolCallResult: Codable, Sendable {
    let id: String
    let type: String
    let function: OpenAIFunctionCall

    init(id: String, function: OpenAIFunctionCall) {
        self.id = id
        self.type = "function"
        self.function = function
    }
}

private struct OpenAIFunctionCall: Codable, Sendable {
    let name: String
    let arguments: String
}

// MARK: - SSE Chunk Types

private struct OpenAISSEChunk: Codable, Sendable {
    let choices: [OpenAISSEChoice]?
}

private struct OpenAISSEChoice: Codable, Sendable {
    let index: Int?
    let delta: OpenAISSEDelta?
    let finish_reason: String?
}

private struct OpenAISSEDelta: Codable, Sendable {
    let role: String?
    let content: String?
    let tool_calls: [OpenAISSEToolCall]?
}

private struct OpenAISSEToolCall: Codable, Sendable {
    let index: Int?
    let id: String?
    let type: String?
    let function: OpenAISSEFunctionCall?
}

private struct OpenAISSEFunctionCall: Codable, Sendable {
    let name: String?
    let arguments: String?
}

// MARK: - Non-streaming response

private struct OpenAINonStreamResponse: Codable, Sendable {
    let choices: [OpenAINonStreamChoice]?
}

private struct OpenAINonStreamChoice: Codable, Sendable {
    let message: OpenAINonStreamMessage?
}

private struct OpenAINonStreamMessage: Codable, Sendable {
    let content: String?
}

// MARK: - Pending Tool Call Accumulator

private struct OpenAIPendingToolCall: Sendable {
    var id: String
    var name: String
    var argumentsJSON: String
}

// MARK: - OpenAI API Client

enum OpenAIAPIError: Error, Sendable {
    case missingAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
}

/// OpenAI API client using the /v1/chat/completions endpoint
actor OpenAIAPIClient: LLMProvider {
    private static let defaultEndpoint = "https://api.openai.com/v1/chat/completions"

    private let endpoint: URL
    private let model: String
    private let apiKey: String
    private let session: URLSession

    // MARK: - LLMProvider Properties

    nonisolated let providerName = "OpenAI"
    nonisolated var modelName: String { model }
    nonisolated let supportsThinking = false
    nonisolated var supportsTools: Bool { true }

    init(model: String, apiKey: String, endpoint: String? = nil) {
        self.endpoint = URL(string: endpoint ?? Self.defaultEndpoint)!
        self.model = model
        self.apiKey = apiKey
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 300
        sessionConfig.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: sessionConfig)
    }

    // MARK: - LLMProvider Methods

    func streamRequest(
        messages: [MessageParam],
        tools: [ToolDefinition],
        systemPrompt: String? = nil
    ) async -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let openaiMessages = convertMessages(messages, systemPrompt: systemPrompt)
        // OpenAI enforces a 128 tool limit per request
        let cappedTools = tools.count > 128 ? Array(tools.prefix(128)) : tools
        let openaiTools = cappedTools.isEmpty ? nil : convertTools(cappedTools)

        let request = OpenAIRequest(
            model: model,
            messages: openaiMessages,
            stream: true,
            tools: openaiTools
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.executeStream(request: request, continuation: continuation)
                } catch let urlError as URLError where urlError.code == .timedOut {
                    Logger.error("OpenAI request timed out: \(urlError)")
                    continuation.yield(.error("Response timed out — tap to retry"))
                    continuation.finish()
                } catch {
                    continuation.yield(.error("OpenAI stream error: \(error.localizedDescription)"))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func singleRequest(
        messages: [MessageParam],
        systemPrompt: String
    ) async throws -> String {
        let openaiMessages = convertMessages(messages, systemPrompt: systemPrompt)

        let request = OpenAIRequest(
            model: model,
            messages: openaiMessages,
            stream: false,
            tools: nil,
            max_tokens: 8192
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(request)

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = bodyData

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIAPIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIAPIError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        let decoded = try JSONDecoder().decode(OpenAINonStreamResponse.self, from: data)
        return decoded.choices?.first?.message?.content ?? ""
    }

    // MARK: - Private Streaming

    private func executeStream(
        request: OpenAIRequest,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async throws {
        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(request)

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = bodyData
        urlRequest.timeoutInterval = 60

        Logger.info("OpenAI request: \(bodyData.count) bytes to \(endpoint)")

        let (asyncBytes, response) = try await session.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            continuation.yield(.error("Invalid response from OpenAI"))
            continuation.finish()
            return
        }

        Logger.info("OpenAI HTTP status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in asyncBytes.lines {
                errorBody += line
            }
            Logger.error("OpenAI error: \(errorBody)")
            continuation.yield(.error("OpenAI error \(httpResponse.statusCode): \(errorBody)"))
            continuation.finish()
            return
        }

        // Parse SSE stream
        var hasEmittedTextStart = false
        var pendingToolCalls: [Int: OpenAIPendingToolCall] = [:]
        var toolCallsDetected = false
        let decoder = JSONDecoder()

        for try await line in asyncBytes.lines {
            guard !line.isEmpty, !line.hasPrefix(":") else { continue }

            let payload: String
            if line.hasPrefix("data: ") {
                payload = String(line.dropFirst(6))
            } else {
                payload = line
            }

            if payload.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                break
            }

            guard let jsonData = payload.data(using: .utf8),
                  let chunk = try? decoder.decode(OpenAISSEChunk.self, from: jsonData) else {
                continue
            }

            guard let choice = chunk.choices?.first else { continue }
            let delta = choice.delta

            // Handle text content
            if let content = delta?.content, !content.isEmpty {
                if !hasEmittedTextStart {
                    continuation.yield(.textStart)
                    hasEmittedTextStart = true
                }
                continuation.yield(.textDelta(content))
            }

            // Handle tool calls
            if let toolCalls = delta?.tool_calls {
                toolCallsDetected = true
                for tc in toolCalls {
                    let idx = tc.index ?? 0

                    if let id = tc.id, let name = tc.function?.name {
                        pendingToolCalls[idx] = OpenAIPendingToolCall(id: id, name: name, argumentsJSON: "")
                        continuation.yield(.toolUseStart(id: id, name: name))
                    }

                    if let args = tc.function?.arguments {
                        pendingToolCalls[idx]?.argumentsJSON += args
                        continuation.yield(.toolUseInputDelta(args))
                    }
                }
            }

            // Check for finish reason
            if let _ = choice.finish_reason {
                if hasEmittedTextStart {
                    continuation.yield(.textDone)
                    hasEmittedTextStart = false
                }

                // Emit completed tool calls
                if toolCallsDetected {
                    for (_, toolCall) in pendingToolCalls.sorted(by: { $0.key < $1.key }) {
                        continuation.yield(.toolUseDone(
                            id: toolCall.id,
                            name: toolCall.name,
                            input: toolCall.argumentsJSON
                        ))
                    }
                }
            }
        }

        // Flush any remaining state
        if hasEmittedTextStart {
            continuation.yield(.textDone)
        }

        if toolCallsDetected {
            for (_, toolCall) in pendingToolCalls.sorted(by: { $0.key < $1.key }) {
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

    /// Convert Claude-format messages to OpenAI chat format.
    ///
    /// OpenAI requires strict sequencing:
    ///   1. assistant message with `tool_calls`
    ///   2. one `tool` message per call, each referencing a `tool_call_id`
    ///
    /// Claude bundles toolUse into assistant messages and toolResult into user
    /// messages. A single Claude "user" message may contain both text *and*
    /// toolResult blocks. This method splits them so OpenAI sees:
    ///   - tool messages first (paired with their preceding assistant tool_calls)
    ///   - then a user message for any remaining text
    private func convertMessages(_ messages: [MessageParam], systemPrompt: String?) -> [OpenAIChatMessage] {
        var result: [OpenAIChatMessage] = []

        if let system = systemPrompt, !system.isEmpty {
            result.append(OpenAIChatMessage(role: "system", content: system))
        }

        for msg in messages {
            var textParts: [String] = []
            var toolUseCalls: [OpenAIToolCallResult] = []
            var toolResults: [(id: String, content: String)] = []

            for block in msg.content {
                switch block {
                case .text(let tc):
                    textParts.append(tc.text)
                case .thinking:
                    break
                case .toolUse(let tu):
                    toolUseCalls.append(OpenAIToolCallResult(
                        id: tu.id,
                        function: OpenAIFunctionCall(
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
                // Assistant messages may contain text, tool_calls, or both
                let content = textParts.isEmpty ? nil : textParts.joined()
                let calls = toolUseCalls.isEmpty ? nil : toolUseCalls
                result.append(OpenAIChatMessage(role: "assistant", content: content, tool_calls: calls))
            } else {
                // User messages may contain tool results, text, or both.
                // OpenAI requires tool results as separate "tool" role messages
                // that follow an assistant message with matching tool_calls.
                // Emit tool results first, then any text as a user message.
                if !toolResults.isEmpty {
                    // Verify the preceding message is an assistant with tool_calls.
                    // If not, we need to insert a synthetic assistant message so OpenAI
                    // doesn't reject the tool messages as orphans.
                    let lastIsAssistantWithCalls = result.last.map {
                        $0.role == "assistant" && $0.tool_calls != nil && !($0.tool_calls?.isEmpty ?? true)
                    } ?? false

                    if !lastIsAssistantWithCalls {
                        // Build synthetic assistant tool_calls from the tool result IDs
                        let syntheticCalls = toolResults.map { tr in
                            OpenAIToolCallResult(
                                id: tr.id,
                                function: OpenAIFunctionCall(
                                    name: "_tool_call",
                                    arguments: "{}"
                                )
                            )
                        }
                        result.append(OpenAIChatMessage(
                            role: "assistant",
                            content: nil,
                            tool_calls: syntheticCalls
                        ))
                    }

                    for tr in toolResults {
                        result.append(OpenAIChatMessage(role: "tool", content: tr.content, tool_call_id: tr.id))
                    }
                }

                // Emit any text content as a separate user message
                let textContent = textParts.joined()
                if !textContent.isEmpty {
                    result.append(OpenAIChatMessage(role: msg.role, content: textContent))
                }
            }
        }

        // Final validation: ensure no "tool" message appears without a preceding
        // assistant message that contains matching tool_calls
        return sanitizeToolMessages(result)
    }

    /// Remove orphaned tool messages that don't have a preceding assistant
    /// message with matching tool_calls. OpenAI rejects these with a 400 error.
    private func sanitizeToolMessages(_ messages: [OpenAIChatMessage]) -> [OpenAIChatMessage] {
        var sanitized: [OpenAIChatMessage] = []
        var activeToolCallIds: Set<String> = []

        for msg in messages {
            if msg.role == "assistant", let calls = msg.tool_calls {
                // Track which tool_call IDs this assistant message declares
                activeToolCallIds = Set(calls.map { $0.id })
                sanitized.append(msg)
            } else if msg.role == "tool" {
                if let callId = msg.tool_call_id, activeToolCallIds.contains(callId) {
                    // Valid tool response — matches a preceding assistant tool_call
                    sanitized.append(msg)
                    activeToolCallIds.remove(callId)
                } else {
                    // Orphaned tool message — skip it to prevent OpenAI 400 error
                    Logger.error("OpenAI: dropping orphaned tool message (tool_call_id: \(msg.tool_call_id ?? "nil")) — no matching assistant tool_calls")
                }
            } else {
                // Non-tool message clears the active tool call tracking
                activeToolCallIds.removeAll()
                sanitized.append(msg)
            }
        }

        return sanitized
    }

    // MARK: - Tool Conversion (MCP -> OpenAI function-calling format)

    private func convertTools(_ tools: [ToolDefinition]) -> [OpenAIToolDef] {
        tools.map { tool in
            OpenAIToolDef(function: OpenAIFunctionDef(
                name: tool.name,
                description: tool.description,
                parameters: tool.input_schema
            ))
        }
    }
}
