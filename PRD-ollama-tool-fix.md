# PRD: Fix Ollama MCP Tool Calling — Full Pipeline Rewrite

## Introduction

Ollama models never call MCP tools. When users send messages that should trigger tool use (e.g., "search for X", "check my email"), Ollama models just answer the question in plain text without attempting any tool calls. Claude handles the same tools flawlessly. This is a blocking issue that makes the Ollama integration effectively useless for any tool-dependent workflow.

**Root cause analysis:** The daemon uses Ollama's OpenAI-compatible `/v1/chat/completions` endpoint, which has unreliable tool calling support across models. The native `/api/chat` endpoint has significantly better tool calling support and doesn't require `tool_choice` hacks. The current codebase also has excessive workarounds (text-based `<tool_call>` fallback, auto-retry, JSON repair) that add complexity without solving the core issue. The fix is to switch to the native API, simplify the pipeline, and remove the accumulated workaround layers.

## Goals

- Ollama models reliably call MCP tools the same way Claude does
- Switch to Ollama's native `/api/chat` endpoint for robust tool calling
- Remove all text-based tool call workarounds (`<tool_call>` parsing, auto-retry, JSON repair)
- Simplify tool schemas so smaller Ollama models can handle them
- Clean diagnostic logging to debug tool call issues when they occur

## User Stories

### US-001: Rewrite OllamaAPIClient to use native `/api/chat` endpoint

**Description:** As a developer, I need to switch from Ollama's OpenAI-compatible endpoint to its native endpoint so that tool calling works reliably across all models.

**Acceptance Criteria:**
- [ ] Replace `/v1/chat/completions` URL with `/api/chat` in the streaming path
- [ ] Define new request struct matching Ollama native format: `{ model, messages, stream, tools, options: { num_predict } }`
- [ ] Define response struct for NDJSON streaming: `{ model, message: { role, content, tool_calls }, done, done_reason }`
- [ ] Remove `tool_choice` field (native API doesn't need it)
- [ ] Remove `OllamaRequest`, `OllamaSSEChunk`, `OllamaSSEDelta` types (replaced by native types)
- [ ] Keep `OllamaToolDef`, `OllamaFunctionDef` (tool format is the same across both APIs)
- [ ] Keep `OllamaPendingToolCall` and deduplication logic
- [ ] The `streamRequest()` method signature stays the same (returns `AsyncThrowingStream<LLMStreamEvent, Error>`)
- [ ] `swift build` succeeds

### US-002: Rewrite streaming parser for native NDJSON format

**Description:** As a developer, I need to parse Ollama's native streaming format (newline-delimited JSON) instead of OpenAI SSE format so tool calls are detected correctly.

**Acceptance Criteria:**
- [ ] Parse each line as a JSON object (no `data: ` prefix stripping, no `[DONE]` marker)
- [ ] Stream ends when a chunk has `"done": true`
- [ ] Extract text content from `message.content` field
- [ ] Detect tool calls from `message.tool_calls[].function.name` and `message.tool_calls[].function.arguments`
- [ ] Emit `LLMStreamEvent.toolUseStart`, `.toolUseDone` events for each tool call
- [ ] Generate tool call IDs as `"ollama_tc_<uuid>"` (native API may not provide IDs)
- [ ] Remove ALL text-based `<tool_call>` parsing code: the `textBuffer`, `fullTextChunks`, `textToolCallIndex`, `textToolCallsFound` variables, the `OllamaToolCallParser` struct, and the `extractToolCalls()` method
- [ ] Remove the post-stream fallback scan (US-003 from old code)
- [ ] Log tool calls detected: `"Ollama tool call: <name> with <N> args"`
- [ ] Log stream completion: `"Ollama stream complete: <N> tool call(s)"`
- [ ] `swift build` succeeds

### US-003: Update message conversion for native format

**Description:** As a developer, I need to update `convertMessages()` to produce messages in Ollama's native format so multi-turn tool calling works correctly.

**Acceptance Criteria:**
- [ ] System prompt is sent as `{ role: "system", content: "..." }` (same as current)
- [ ] User messages are sent as `{ role: "user", content: "..." }` (same as current)
- [ ] Assistant messages with tool calls include `tool_calls` array with `{ function: { name, arguments } }` where `arguments` is a **dictionary/object**, not a JSON string (this is the key difference from OpenAI format)
- [ ] Tool result messages use `role: "tool"` with `content` as a string (same as current)
- [ ] Keep `sanitizeToolMessages()` — orphan tool message cleanup is still needed
- [ ] Images and audio are converted to text placeholders (same as current)
- [ ] `swift build` succeeds

### US-004: Clean up DaemonApp Ollama workarounds

**Description:** As a developer, I need to remove the accumulated Ollama workarounds in DaemonApp.swift now that the native API handles tool calling properly.

**Acceptance Criteria:**
- [ ] Remove the text-based tool call system prompt augmentation block (current lines ~654-691 that append `# Tool Usage Instructions` with `<tool_call>` format)
- [ ] Remove the `modelSupportsNativeTools()` check and the `effectiveTools = []` branch — native API supports tools for all models
- [ ] Remove the `create_workflow` tool filtering — let all tools through (native API handles complex tools better)
- [ ] Remove the auto-retry logic for malformed tool calls (current lines ~819-856 that check `looksLikeToolAttempt` and retry)
- [ ] Remove the `toolCallFailed` WebSocket message sending for retry exhaustion
- [ ] Keep the model loading indicator logic (lines ~696-707)
- [ ] Keep the tool execution loop (lines ~859+) — this is provider-agnostic and works fine
- [ ] `swift build` succeeds

### US-005: Simplify MCP tool schemas for Ollama

**Description:** As a user, I want Ollama models to understand the available tools so they actually use them, by simplifying complex MCP tool schemas that confuse smaller models.

**Acceptance Criteria:**
- [ ] Add a `simplifyToolsForOllama(_ tools: [ToolDefinition]) -> [ToolDefinition]` method in DaemonApp
- [ ] Cap total tools sent to Ollama at 20 (prioritize tools with descriptions)
- [ ] Flatten schemas deeper than 2 levels of nesting — replace deep objects with a single `string` parameter containing a JSON description
- [ ] Remove `allOf`, `oneOf`, `anyOf` schema constructs — replace with the first option as a simple object
- [ ] Remove tools that have no description (models can't decide when to use them)
- [ ] Call this method in `streamLLMResponse` only when `llmProvider.providerName == "Ollama"`
- [ ] Log: `"Simplified <N> tools for Ollama (removed <M>, flattened <K>)"`
- [ ] `swift build` succeeds

### US-006: Remove OllamaToolCallParser and dead code

**Description:** As a developer, I need to clean up the now-unused text-based tool call parsing infrastructure.

**Acceptance Criteria:**
- [ ] Delete the `OllamaToolCallParser` struct and all its methods (`parseToolCallJSON`, `extractToolCalls`, `repairJSON`)
- [ ] Delete the `TextToolCall` struct
- [ ] Delete the `AnyCodableValue` type if only used by the text parser
- [ ] Delete `nativeToolModelPrefixes` array and `modelSupportsNativeTools()` method
- [ ] Delete any remaining `OllamaSSE*` types not used by the native API
- [ ] Verify no other files reference the deleted types
- [ ] `swift build` succeeds

### US-007: Update non-streaming path for native API

**Description:** As a developer, I need to update the `singleRequest()` method to also use the native `/api/chat` endpoint for consistency.

**Acceptance Criteria:**
- [ ] Change `singleRequest()` to use `/api/chat` instead of `/v1/chat/completions`
- [ ] Use the same native request format as the streaming path
- [ ] Parse the non-streaming native response format: `{ message: { content: "..." }, done: true }`
- [ ] Keep error handling for 404 (model not found) and other HTTP errors
- [ ] `swift build` succeeds

## Non-Goals

- Not building a UI for tool call debugging (logging is sufficient)
- Not adding new Ollama models to a supported list (native API works with all tool-capable models)
- Not changing how Claude API handles tools (it already works)
- Not modifying the MCP tool execution pipeline (it's provider-agnostic and works)
- Not adding `tool_choice: "required"` forcing (models should decide when to use tools)
- Not supporting Ollama's vision/multimodal features in this PRD
- Not changing the LLMProvider protocol or LLMStreamEvent types

## Technical Considerations

- **Ollama native API format reference**: `POST /api/chat` with NDJSON streaming. Each line is a complete JSON object. Stream ends when `done: true`.
- **Tool call arguments**: In native API, `arguments` is a JSON **object**, not a JSON string like OpenAI. This is a critical difference for `convertMessages()`.
- **Tool call IDs**: Native API may not provide `id` fields for tool calls. Generate UUIDs as `"ollama_tc_<8chars>"` (already done in current code).
- **Backward compatibility**: The `LLMProvider` protocol and `LLMStreamEvent` types don't change — only the internal implementation of `OllamaAPIClient` changes.
- **File scope**: Changes are isolated to `OllamaAPIClient.swift` (US-001, 002, 003, 006, 007) and `DaemonApp.swift` (US-004, 005).
- **Existing non-streaming path**: `singleRequest()` is used for model status checks and simple queries. Must also be updated.
- **The `isModelLoaded()` and `getAvailableModels()` methods** use Ollama's native `/api/tags` and `/api/ps` endpoints already — no changes needed there.
