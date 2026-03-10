import Foundation

/// Accumulated tool call data during streaming
private struct PendingToolCall: Sendable {
    let id: String
    let name: String
    var inputJSON: String
}

enum ClaudeAPIError: Error, Sendable {
    case noAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
}

/// Claude API client with SSE streaming support, conforming to LLMProvider
actor ClaudeAPIClient: LLMProvider {
    private let config: DaemonConfig
    private let session: URLSession
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    nonisolated let modelOverride: String?
    nonisolated let thinkingBudgetOverride: Int?

    // MARK: - LLMProvider Properties

    nonisolated let providerName = "Claude"
    nonisolated var modelName: String { modelOverride ?? config.claudeModel }
    nonisolated let supportsThinking = true
    nonisolated let supportsTools = true

    init(config: DaemonConfig, modelOverride: String? = nil, thinkingBudgetOverride: Int? = nil) {
        self.config = config
        self.modelOverride = modelOverride
        self.thinkingBudgetOverride = thinkingBudgetOverride
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
        guard let apiKey = config.apiKey else {
            return AsyncThrowingStream { continuation in
                continuation.yield(.error("No ANTHROPIC_API_KEY configured"))
                continuation.finish()
            }
        }

        // Build structured system prompt blocks for prompt caching
        let systemBlocks = buildSystemBlocks(from: systemPrompt ?? config.systemPrompt)

        // Mark last tool with cache_control so the entire tool set is cached
        var effectiveTools: [ToolDefinition]? = nil
        if !tools.isEmpty {
            var toolsCopy = tools
            let lastIdx = toolsCopy.count - 1
            let lastTool = toolsCopy[lastIdx]
            toolsCopy[lastIdx] = ToolDefinition(
                name: lastTool.name,
                description: lastTool.description,
                input_schema: lastTool.input_schema,
                cache_control: CacheControl()
            )
            effectiveTools = toolsCopy
        }

        // Adaptive thinking budget
        let thinkingBudget: Int
        if let override = thinkingBudgetOverride {
            thinkingBudget = override
        } else if tools.isEmpty && messages.count <= 2 {
            thinkingBudget = 2048  // Simple chat
        } else {
            thinkingBudget = 6144  // Tool selection or multi-turn
        }

        Logger.info("[Cost] thinking_budget=\(thinkingBudget) tools=\(tools.count) messages=\(messages.count)")

        let request = ClaudeRequest(
            model: modelName,
            max_tokens: 16384,
            messages: messages,
            system: systemBlocks,
            stream: true,
            tools: effectiveTools,
            thinking: ThinkingConfig(budget_tokens: thinkingBudget)
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.executeStream(
                        request: request,
                        apiKey: apiKey,
                        continuation: continuation
                    )
                } catch let urlError as URLError where urlError.code == .timedOut {
                    continuation.yield(.error("Response timed out — tap to retry"))
                    continuation.finish()
                } catch {
                    continuation.yield(.error("Stream error: \(error.localizedDescription)"))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Split system prompt into blocks for prompt caching.
    /// The last block gets cache_control so the full system prompt is cached.
    private func buildSystemBlocks(from prompt: String) -> [SystemBlock] {
        // Split at "# Expert Instructions" or "# Agent Plan System" boundary if present
        // This separates the stable base prompt from dynamic per-conversation content
        let markers = ["# Expert Instructions", "# Agent Plan System"]
        for marker in markers {
            if let range = prompt.range(of: marker) {
                let base = String(prompt[prompt.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let dynamic = String(prompt[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !base.isEmpty && !dynamic.isEmpty {
                    return [
                        SystemBlock(text: base, cacheControl: CacheControl()),
                        SystemBlock(text: dynamic, cacheControl: CacheControl())
                    ]
                }
            }
        }

        // Single block if no split point found
        return [SystemBlock(text: prompt, cacheControl: CacheControl())]
    }

    func singleRequest(
        messages: [MessageParam],
        systemPrompt: String
    ) async throws -> String {
        guard let apiKey = config.apiKey else {
            throw ClaudeAPIError.noAPIKey
        }

        // Enable prompt caching for single requests — benefits repeated calls with the same system prompt
        let request = ClaudeRequest(
            model: modelName,
            max_tokens: 8192,
            messages: messages,
            system: [SystemBlock(text: systemPrompt, cacheControl: CacheControl())],
            stream: false,
            tools: nil,
            thinking: nil
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(request)

        var urlRequest = URLRequest(url: apiURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = bodyData

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeAPIError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        struct ClaudeResponse: Codable {
            let content: [ResponseBlock]
        }
        struct ResponseBlock: Codable {
            let type: String
            let text: String?
        }

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        let text = decoded.content.compactMap { $0.text }.joined()
        return text
    }

    // MARK: - Private

    private func executeStream(
        request: ClaudeRequest,
        apiKey: String,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation
    ) async throws {
        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(request)

        var urlRequest = URLRequest(url: apiURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = bodyData
        urlRequest.timeoutInterval = 180  // 180s per-chunk timeout for streaming (extended thinking may take >60s)

        Logger.info("API request: \(bodyData.count) bytes to \(apiURL)")

        let (asyncBytes, response) = try await session.bytes(for: urlRequest)

        Logger.info("API response received")

        guard let httpResponse = response as? HTTPURLResponse else {
            continuation.yield(.error("Invalid response"))
            continuation.finish()
            return
        }

        Logger.info("API HTTP status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in asyncBytes.lines {
                errorBody += line
            }
            Logger.error("API error body: \(errorBody)")
            continuation.yield(.error("API error \(httpResponse.statusCode): \(errorBody)"))
            continuation.finish()
            return
        }

        var currentEventType: String?
        var dataBuffer = ""
        var pendingToolCalls: [Int: PendingToolCall] = [:]
        var currentBlockTypes: [Int: String] = [:]

        for try await line in asyncBytes.lines {
            if line.hasPrefix("event: ") {
                if !dataBuffer.isEmpty, let eventType = currentEventType {
                    processSSEEvent(
                        type: eventType,
                        data: dataBuffer,
                        continuation: continuation,
                        pendingToolCalls: &pendingToolCalls,
                        currentBlockTypes: &currentBlockTypes
                    )
                }
                currentEventType = String(line.dropFirst(7))
                dataBuffer = ""
                continue
            }

            if line.hasPrefix("data: ") {
                dataBuffer = String(line.dropFirst(6))
                continue
            }

            if line.isEmpty, !dataBuffer.isEmpty, let eventType = currentEventType {
                processSSEEvent(
                    type: eventType,
                    data: dataBuffer,
                    continuation: continuation,
                    pendingToolCalls: &pendingToolCalls,
                    currentBlockTypes: &currentBlockTypes
                )
                currentEventType = nil
                dataBuffer = ""
            }
        }

        if !dataBuffer.isEmpty, let eventType = currentEventType {
            processSSEEvent(
                type: eventType,
                data: dataBuffer,
                continuation: continuation,
                pendingToolCalls: &pendingToolCalls,
                currentBlockTypes: &currentBlockTypes
            )
        }

        continuation.yield(.messageComplete)
        continuation.finish()
    }

    private func processSSEEvent(
        type: String,
        data: String,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation,
        pendingToolCalls: inout [Int: PendingToolCall],
        currentBlockTypes: inout [Int: String]
    ) {
        guard let jsonData = data.data(using: .utf8) else { return }
        let decoder = JSONDecoder()

        switch type {
        case "message_start":
            if let event = try? decoder.decode(SSEMessageStart.self, from: jsonData),
               let usage = event.message.usage {
                continuation.yield(.usage(
                    input: usage.input_tokens ?? 0,
                    output: 0,
                    cacheRead: usage.cache_read_input_tokens ?? 0,
                    cacheCreation: usage.cache_creation_input_tokens ?? 0
                ))
            }

        case "content_block_start":
            guard let event = try? decoder.decode(SSEContentBlockStart.self, from: jsonData) else { return }
            let block = event.content_block
            currentBlockTypes[event.index] = block.type

            switch block.type {
            case "thinking":
                continuation.yield(.thinkingStart)
            case "text":
                continuation.yield(.textStart)
            case "tool_use":
                if let id = block.id, let name = block.name {
                    pendingToolCalls[event.index] = PendingToolCall(id: id, name: name, inputJSON: "")
                    continuation.yield(.toolUseStart(id: id, name: name))
                }
            default:
                break
            }

        case "content_block_delta":
            guard let event = try? decoder.decode(SSEContentBlockDelta.self, from: jsonData) else { return }
            let delta = event.delta

            switch delta.type {
            case "thinking_delta":
                if let thinking = delta.thinking {
                    continuation.yield(.thinkingDelta(thinking))
                }
            case "text_delta":
                if let text = delta.text {
                    continuation.yield(.textDelta(text))
                }
            case "input_json_delta":
                if let partialJSON = delta.partial_json {
                    pendingToolCalls[event.index]?.inputJSON += partialJSON
                    continuation.yield(.toolUseInputDelta(partialJSON))
                }
            default:
                break
            }

        case "content_block_stop":
            guard let event = try? decoder.decode(SSEContentBlockStop.self, from: jsonData) else { return }
            let blockType = currentBlockTypes[event.index]

            switch blockType {
            case "thinking":
                continuation.yield(.thinkingDone)
            case "text":
                continuation.yield(.textDone)
            case "tool_use":
                if let toolCall = pendingToolCalls.removeValue(forKey: event.index) {
                    continuation.yield(.toolUseDone(
                        id: toolCall.id,
                        name: toolCall.name,
                        input: toolCall.inputJSON
                    ))
                }
            default:
                break
            }
            currentBlockTypes.removeValue(forKey: event.index)

        case "message_delta":
            if let event = try? decoder.decode(SSEMessageDelta.self, from: jsonData),
               let usage = event.usage,
               let outputTokens = usage.output_tokens {
                continuation.yield(.usage(
                    input: 0,
                    output: outputTokens,
                    cacheRead: 0,
                    cacheCreation: 0
                ))
            }

        case "message_stop":
            break

        case "ping":
            break

        case "error":
            if let event = try? decoder.decode(SSEError.self, from: jsonData) {
                continuation.yield(.error("API error: \(event.error.message)"))
            }

        default:
            break
        }
    }
}
