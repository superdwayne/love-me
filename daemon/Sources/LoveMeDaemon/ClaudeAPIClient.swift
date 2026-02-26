import Foundation

/// Events emitted during a Claude API streaming response
enum ClaudeStreamEvent: Sendable {
    case thinkingStart
    case thinkingDelta(String)
    case thinkingDone
    case textStart
    case textDelta(String)
    case textDone
    case toolUseStart(id: String, name: String)
    case toolUseInputDelta(String)
    case toolUseDone(id: String, name: String, input: String)
    case messageComplete
    case error(String)
}

/// Accumulated tool call data during streaming
private struct PendingToolCall: Sendable {
    let id: String
    let name: String
    var inputJSON: String
}

/// Claude API client with SSE streaming support
actor ClaudeAPIClient {
    private let config: DaemonConfig
    private let session: URLSession
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!

    init(config: DaemonConfig) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 300
        sessionConfig.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: sessionConfig)
    }

    /// Send a message to Claude API with streaming, returning events via an AsyncStream.
    /// The returned stream yields ClaudeStreamEvent values.
    /// `messages` is the full conversation history.
    /// `tools` are MCP tool definitions to pass.
    func streamRequest(
        messages: [MessageParam],
        tools: [ToolDefinition],
        systemPrompt: String? = nil
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        guard let apiKey = config.apiKey else {
            return AsyncThrowingStream { continuation in
                continuation.yield(.error("No ANTHROPIC_API_KEY configured"))
                continuation.finish()
            }
        }

        let request = ClaudeRequest(
            model: config.model,
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
                } catch {
                    continuation.yield(.error("Stream error: \(error.localizedDescription)"))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func executeStream(
        request: ClaudeRequest,
        apiKey: String,
        continuation: AsyncThrowingStream<ClaudeStreamEvent, Error>.Continuation
    ) async throws {
        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(request)

        var urlRequest = URLRequest(url: apiURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = bodyData

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

        // Parse SSE stream
        // Note: asyncBytes.lines may skip empty lines, so we trigger
        // event processing when a new "event:" line arrives (flushing
        // any previously buffered event+data pair).
        var currentEventType: String?
        var dataBuffer = ""
        var pendingToolCalls: [Int: PendingToolCall] = [:]
        var currentBlockTypes: [Int: String] = [:]

        for try await line in asyncBytes.lines {
            if line.hasPrefix("event: ") {
                // Flush any pending event before starting a new one
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

            // Empty line or other - flush pending event
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

        // Flush final event if stream ends without trailing empty line
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
        continuation: AsyncThrowingStream<ClaudeStreamEvent, Error>.Continuation,
        pendingToolCalls: inout [Int: PendingToolCall],
        currentBlockTypes: inout [Int: String]
    ) {
        guard let jsonData = data.data(using: .utf8) else { return }
        let decoder = JSONDecoder()

        switch type {
        case "message_start":
            // Message metadata - no action needed for streaming
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
            // Contains stop_reason - the message is ending
            break

        case "message_stop":
            // Final event
            break

        case "ping":
            // Keep-alive from API
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
