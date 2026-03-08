# PRD: Fix Ollama MCP Tool Calling

## Introduction

MCP tool calls never execute when using Ollama as the LLM provider. The root cause is a multi-layered failure in `OllamaAPIClient.swift`: native tool calls are silently dropped because most Ollama models return `finish_reason="stop"` instead of `"tool_calls"`, the text-based `<tool_call>` fallback has fragile JSON parsing, neither path falls back to the other, and failures are completely silent — the user never knows a tool was requested but not executed.

This PRD implements a robust three-tier tool calling strategy with model capability detection, a native → text → retry fallback chain, and visible error feedback in the chat UI.

## Goals

- Make MCP tool execution work reliably with Ollama models that support function calling (qwen3, llama3.1+, mistral, glm4)
- Implement graceful degradation: native format → text-based format → auto-retry with reformatted prompt
- Add visible error feedback when tool calls fail to parse, so users aren't left wondering
- Detect model capabilities and route to the best strategy per model
- Maintain backward compatibility with Claude and OpenAI providers (no changes to their code paths)

## User Stories

### US-001: Fix native tool call emission for finish_reason="stop"

**Description:** As a user, I want Ollama native tool calls to work even when the model returns `finish_reason="stop"` instead of `"tool_calls"`, so that models like qwen3 and llama3.3 can execute MCP tools.

**Acceptance Criteria:**
- [ ] In `OllamaAPIClient.executeStream()`, emit `.toolUseDone` for pending native tool calls regardless of `finish_reason` value — if `nativeToolCallsDetected` is true, always emit
- [ ] Remove the `finishReason == "tool_calls" || finishReason == "stop"` guard on line 574; replace with just `nativeToolCallsDetected`
- [ ] Also emit pending native tool calls at end-of-stream (line 604 block) unconditionally when `nativeToolCallsDetected` is true (already does this but confirm no regression)
- [ ] Add a deduplication check: don't emit `.toolUseDone` twice for the same tool call ID (once in finish_reason block, once in end-of-stream block)
- [ ] Daemon builds successfully: `cd daemon && swift build`

### US-002: Implement robust text-based tool call parsing with regex fallback

**Description:** As a user, I want the text-based `<tool_call>` parsing to handle malformed JSON from smaller models, so that tool calls aren't silently dropped when JSON is slightly off.

**Acceptance Criteria:**
- [ ] Add a `repairJSON(_ raw: String) -> String?` helper that attempts to fix common issues:
  - Single quotes instead of double quotes
  - Unquoted keys
  - Trailing commas
  - Missing closing braces
  - Newlines/whitespace within JSON
- [ ] When `JSONDecoder` fails to parse the `<tool_call>` block, try `repairJSON` before giving up
- [ ] As a final fallback, try `JSONSerialization.jsonObject(with:options:.fragmentsAllowed)` which is more lenient than `JSONDecoder`
- [ ] Log the original raw JSON and the repair attempt for debugging
- [ ] Add unit-testable function signature: `static func parseToolCallJSON(_ raw: String) -> TextToolCall?`
- [ ] Daemon builds successfully: `cd daemon && swift build`

### US-003: Implement native-to-text fallback chain

**Description:** As a user, I want the system to try text-based parsing as a fallback when native tool call parsing produces no results, so that tools work with models that output `<tool_call>` blocks instead of using the function calling API.

**Acceptance Criteria:**
- [ ] After the stream loop completes, if `nativeToolCallsDetected` is false AND no text-based tool calls were found, scan the full accumulated text (`fullTextChunks.joined()`) for `<tool_call>` blocks one final time
- [ ] This post-stream scan uses the same robust parsing from US-002
- [ ] If tool calls are found in the text, emit `.toolUseStart` and `.toolUseDone` events, and strip the `<tool_call>` blocks from the text that gets saved as the assistant message
- [ ] Log when fallback parsing finds tool calls that streaming missed
- [ ] Daemon builds successfully: `cd daemon && swift build`

### US-004: Add model capability detection for tool call strategy

**Description:** As a developer, I want the system to know which Ollama models support native function calling vs text-only, so it can choose the best strategy per model and avoid sending native tools to models that can't use them.

**Acceptance Criteria:**
- [ ] Add a `modelSupportsNativeTools(_ modelName: String) -> Bool` method to `OllamaAPIClient`
- [ ] Known native-capable models: qwen3*, llama3.1*, llama3.2*, llama3.3*, mistral*, glm4*, command-r*, firefunction*, nemotron*
- [ ] Match by prefix (e.g. "qwen3" matches "qwen3:8b", "qwen3-coder-next")
- [ ] For unknown models, default to `true` (attempt native first, fall back to text)
- [ ] When `modelSupportsNativeTools` returns false, don't include `tools` in the API request body (only use text-based instructions in system prompt)
- [ ] In `DaemonApp.streamLLMResponse()`, use this to decide whether to send native tools array
- [ ] Daemon builds successfully: `cd daemon && swift build`

### US-005: Add auto-retry when tool call parsing fails

**Description:** As a user, I want the system to automatically retry once when a tool call fails to parse, reprompting the model with clearer instructions, so that transient formatting issues don't cause permanent failures.

**Acceptance Criteria:**
- [ ] In `DaemonApp.streamLLMResponse()`, after the stream completes: if the assistant text contains tool-like language (mentions a tool name, or contains partial `<tool_call>` syntax) but `pendingToolCalls` is empty, trigger a retry
- [ ] The retry appends the assistant's failed text as an assistant message, then adds a user message: "Your tool call was malformed. Please try again using this exact format:\n\n<tool_call>\n{\"name\": \"tool_name\", \"arguments\": {\"param\": \"value\"}}\n</tool_call>"
- [ ] Only retry once (use a `retryCount` parameter, default 0, max 1)
- [ ] Log the retry attempt
- [ ] Daemon builds successfully: `cd daemon && swift build`

### US-006: Send tool call failure feedback to the chat UI

**Description:** As a user, I want to see a message in the chat when a tool call fails to parse or execute, so I know what happened and can adjust my request.

**Acceptance Criteria:**
- [ ] Define a new `WSMessageType.toolCallFailed` message type in both daemon and app `WebSocketMessage.swift`
- [ ] When text-based tool call parsing fails (after all fallbacks including JSON repair), send a `toolCallFailed` message to the client with metadata: `toolName` (if parseable), `rawContent` (the malformed block), `reason` (e.g. "JSON parse error")
- [ ] When auto-retry (US-005) also fails, send a `toolCallFailed` with reason "Tool call failed after retry"
- [ ] App-side: display `toolCallFailed` as a system bubble in the conversation (styled differently from user/assistant messages — e.g. warning color, smaller text)
- [ ] Include the tool name and a brief explanation in the displayed message
- [ ] Daemon builds successfully: `cd daemon && swift build`
- [ ] App builds successfully via Xcode

### US-007: Add structured logging for tool call debugging

**Description:** As a developer, I want detailed logs for the entire Ollama tool call flow, so I can diagnose issues without guessing what went wrong.

**Acceptance Criteria:**
- [ ] Log when tools are sent to Ollama: count, names, strategy (native vs text-only)
- [ ] Log each native tool call delta as it arrives (tool name, argument chunk length)
- [ ] Log `finish_reason` value when stream ends
- [ ] Log when text-based parsing is attempted and its result (success/failure + raw content on failure)
- [ ] Log when JSON repair is attempted and whether it succeeded
- [ ] Log when fallback chain activates (native → text → retry)
- [ ] All logs use existing `Logger` utility with appropriate levels (`.info` for flow, `.error` for failures, `.debug` for deltas)
- [ ] Daemon builds successfully: `cd daemon && swift build`

## Non-Goals

- No changes to Claude or OpenAI API clients — they work fine
- No model recommendation UI (separate feature)
- No automated model testing/benchmarking harness
- No changes to MCP tool execution itself — the problem is upstream (parsing Ollama's response)
- No Ollama model pull/management features
- No changes to how tools are defined or registered

## Technical Considerations

- **Key files to modify:**
  - `daemon/Sources/SolaceDaemon/OllamaAPIClient.swift` (US-001, US-002, US-003, US-004, US-007)
  - `daemon/Sources/SolaceDaemon/DaemonApp.swift` (US-003, US-004, US-005, US-006, US-007)
  - `daemon/Sources/SolaceDaemon/Models/WebSocketMessage.swift` (US-006)
  - `app/Sources/Models/WebSocketMessage.swift` (US-006)
  - `app/Sources/Views/` conversation view (US-006)

- **Model capability list source:** [Ollama tool calling docs](https://docs.ollama.com/capabilities/tool-calling), [community benchmarks](https://clawdbook.org/blog/openclaw-best-ollama-models-2026)

- **Known model behaviors:**
  - qwen3: Uses `reasoning` field instead of `content` (already handled via `effectiveContent`)
  - Most models return `finish_reason="stop"` even with tool calls
  - Small models (<14B) are unreliable for tool calling — text-based approach is more forgiving

- **Existing code patterns to follow:**
  - `LLMStreamEvent` enum for stream events
  - `WSMessage` + `WSMessageType` for client communication
  - `Logger.info/error/debug` for logging
  - Actor isolation on `OllamaAPIClient`
