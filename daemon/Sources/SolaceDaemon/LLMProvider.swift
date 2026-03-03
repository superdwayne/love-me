import Foundation

// MARK: - Provider-Agnostic Stream Events

/// Events emitted during an LLM streaming response, regardless of provider
enum LLMStreamEvent: Sendable {
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

// MARK: - LLM Provider Protocol

/// Abstraction for LLM backends (Claude, Ollama, etc.)
/// All providers must be actors for thread safety.
protocol LLMProvider: Sendable {
    /// Human-readable provider name (e.g. "Claude", "Ollama")
    var providerName: String { get }

    /// Active model identifier (e.g. "claude-sonnet-4-5-20250929", "llama3")
    var modelName: String { get }

    /// Whether this provider supports extended thinking blocks
    var supportsThinking: Bool { get }

    /// Whether this provider supports tool/function calling
    var supportsTools: Bool { get }

    /// Stream a chat completion with optional tools and system prompt.
    func streamRequest(
        messages: [MessageParam],
        tools: [ToolDefinition],
        systemPrompt: String?
    ) async -> AsyncThrowingStream<LLMStreamEvent, Error>

    /// Single (non-streaming) request returning the full text response.
    func singleRequest(
        messages: [MessageParam],
        systemPrompt: String
    ) async throws -> String
}
