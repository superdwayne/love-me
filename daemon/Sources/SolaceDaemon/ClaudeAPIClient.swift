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

    // MARK: - LLMProvider Properties

    nonisolated let providerName = "Claude"
    nonisolated var modelName: String { config.claudeModel }
    nonisolated let supportsThinking = true
    nonisolated let supportsTools = true

    init(config: DaemonConfig) {
        self.config = config
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

        let request = ClaudeRequest(
            model: config.claudeModel,
            max_tokens: 16384,
            messages: messages,
            system: systemPrompt ?? config.systemPrompt,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            thinking: ThinkingConfig(budget_tokens: 10000)
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

    func singleRequest(
        messages: [MessageParam],
        systemPrompt: String
    ) async throws -> String {
        guard let apiKey = config.apiKey else {
            throw ClaudeAPIError.noAPIKey
        }

        let request = ClaudeRequest(
            model: config.claudeModel,
            max_tokens: 8192,
            messages: messages,
            system: systemPrompt,
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
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = bodyData
        urlRequest.timeoutInterval = 60  // 60s per-chunk timeout for streaming

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
            break

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
            break

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
