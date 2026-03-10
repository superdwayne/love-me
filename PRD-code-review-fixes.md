# PRD: Code Review Fixes — Cost Optimization, Pinned Tools, MCP Server Management

## Introduction

This PRD addresses 12 issues identified during code review of recent Solace changes spanning prompt caching, usage tracking, smart tool filtering, pinned tools, MCP server CRUD, and auto-screenshot features. Issues range from silent failures and data inconsistencies to UX gaps and code duplication. Fixing these hardens the new features for production use.

## Goals

- Eliminate silent failures in auto-screenshot node ID parsing
- Ensure MCP server config persistence includes all relevant flags
- Remove duplicated status broadcast logic via a shared helper
- Reduce noise in tool relevance scoring with stopword filtering
- Add debounce to pinned tool toggling to prevent I/O churn
- Surface parsing errors to users in the Add MCP Server sheet
- Prevent duplicate tools in MCPManager when servers share tool names
- Expose usage tracking data to the iOS app
- Fix misleading cache hit rate metric
- Regenerate hand-crafted PBX IDs via Xcode

## User Stories

### US-001: Persist `enabled` and `ollamaEnabled` in `persistNewServer`

**Description:** As a developer, I want newly added MCP servers to explicitly write `enabled: true` and `ollamaEnabled: true` to `mcp.json` so that the config file is self-documenting and resilient to future decoder changes.

**Acceptance Criteria:**
- [ ] `persistNewServer` in `DaemonApp.swift` writes `"enabled": true` and `"ollamaEnabled": true` into the `configDict`
- [ ] `handleMCPServerAdd` passes these flags through to `configDict` for both stdio and HTTP server types
- [ ] After adding a server via the app, inspect `~/.solace/mcp.json` and confirm both flags are present
- [ ] Daemon restart loads the server with both flags as `true`
- [ ] `swift build` passes

### US-002: Make auto-screenshot node ID parsing robust with logging

**Description:** As a developer, I want the Pencil auto-screenshot feature to handle unexpected `batch_design` output formats and log when parsing fails, so that failures are diagnosable.

**Acceptance Criteria:**
- [ ] When no `nodeId` can be extracted from `batch_design` result, log a warning: `"Auto-screenshot skipped: could not extract node ID from batch_design result"`
- [ ] Log the first 200 chars of the result content in the warning for debugging
- [ ] Node ID parsing handles IDs containing dots (`.`) and colons (`:`) in addition to letters, numbers, underscores, hyphens
- [ ] If `batch_design` result contains JSON, attempt to extract node IDs from JSON keys/values before falling back to line-by-line parsing
- [ ] Existing happy-path behavior (simple `binding=ID` lines) continues to work
- [ ] `swift build` passes

### US-003: Add `cacheControl` to `singleRequest` system blocks

**Description:** As a developer, I want `singleRequest` to apply `cache_control` to system prompt blocks consistently with `streamRequest`, so that one-off requests also benefit from prompt caching.

**Acceptance Criteria:**
- [ ] `singleRequest` in `ClaudeAPIClient.swift` wraps the system prompt in `[SystemBlock(text: prompt, cacheControl: CacheControl())]`
- [ ] Add a code comment explaining that caching benefits single requests when the same system prompt is reused across calls
- [ ] `swift build` passes

### US-004: Add stopword filtering to tool relevance scoring

**Description:** As a developer, I want the keyword extraction in `filterToolsByRelevance` to exclude common English stopwords so that noise words like "the", "and", "can" don't inflate tool relevance scores.

**Acceptance Criteria:**
- [ ] Add a static stopword set containing at minimum: `"the", "and", "can", "use", "for", "with", "this", "that", "are", "was", "has", "not", "but", "from", "have", "will", "been", "its", "all", "any", "how", "get", "set", "let"`
- [ ] Keyword extraction filters out stopwords before scoring
- [ ] Minimum keyword length remains 3 characters (stopwords handle the rest)
- [ ] Log output still shows filtered keyword sample for debugging
- [ ] `swift build` passes

### US-005: Debounce pinned tool toggle WebSocket messages

**Description:** As a user, I want rapid tool pin/unpin toggles to be batched before sending to the daemon, so that the system doesn't write to `providers.json` on every individual toggle.

**Acceptance Criteria:**
- [ ] `togglePinnedTool` in `SettingsViewModel.swift` updates local `ollamaTools` state immediately for responsive UI
- [ ] WebSocket message sending is debounced with a 500ms timer — only the final state is sent
- [ ] If the user toggles 3 tools within 500ms, only 1 WS message is sent containing all 3 changes
- [ ] `clearAllPinnedTools` sends immediately (no debounce) since it's a deliberate bulk action
- [ ] `pinnedToolsCount` updates immediately on each toggle for accurate UI counter
- [ ] `swift build` passes (Xcode project)

### US-006: Show validation feedback for malformed header lines

**Description:** As a user, I want the Add MCP Server sheet to warn me when header lines don't contain a colon separator, so that typos like `Authorization Bearer xxx` are caught before submission.

**Acceptance Criteria:**
- [ ] After the user finishes editing the headers field, lines without a `:` separator show an inline warning below the field
- [ ] Warning text: `"Line N is not valid (expected 'Key: Value' format)"`
- [ ] Warning uses `.softRed` color consistent with existing error styling
- [ ] The "Add" button remains enabled — the warning is informational, not blocking (user may intend single-word headers)
- [ ] Valid lines are still parsed correctly alongside invalid ones
- [ ] `swift build` passes (Xcode project)

### US-007: Deduplicate tools in MCPManager `addServer`

**Description:** As a developer, I want `MCPManager.addServer` to prevent duplicate tool names in `allTools`, so that tool routing is deterministic when multiple servers expose same-named tools.

**Acceptance Criteria:**
- [ ] In `addServer`, before appending a tool to `allTools`, check if a tool with the same name already exists
- [ ] If a duplicate exists, log a warning: `"MCP Manager: tool 'X' from server 'Y' conflicts with existing tool from server 'Z' — skipping duplicate"`
- [ ] The first-registered tool wins (existing tool is kept, new duplicate is skipped)
- [ ] `toolToServer` map is not overwritten for duplicates
- [ ] The returned tool count from `addServer` reflects only the tools that were actually registered (excluding duplicates)
- [ ] `swift build` passes

### US-008: Extract shared `buildStatusMetadata` helper

**Description:** As a developer, I want a single method that builds the status metadata dictionary, so that `sendStatus(to:)`, `handleMCPServerToggle`, and `broadcastStatus` all produce consistent payloads.

**Acceptance Criteria:**
- [ ] New private method `buildStatusMetadata() async -> [String: MetadataValue]` that returns all status fields including `activeProvider` and `activeModel`
- [ ] `sendStatus(to:)` calls `buildStatusMetadata()` and sends to the single client
- [ ] `broadcastStatus()` calls `buildStatusMetadata()` and broadcasts to all clients
- [ ] The inline status-building code in `handleMCPServerToggle` is replaced with a call to `broadcastStatus()`
- [ ] All status messages now consistently include `activeProvider` and `activeModel` fields
- [ ] `swift build` passes

### US-009: Make default Ollama model configurable with fallback

**Description:** As a user, I want the default model placeholder to reflect that it's just a suggestion, not a requirement, so that I'm not confused when `qwen3.5` isn't available locally.

**Acceptance Criteria:**
- [ ] `OllamaProviderConfig.default` model remains `"qwen3.5"` (current value)
- [ ] `SettingsView.swift` placeholder text changes from `"qwen3.5"` to `"e.g. qwen3.5"` to signal it's a suggestion
- [ ] When the model picker is populated from Ollama's model list, the first available model is auto-selected if the configured model isn't found locally
- [ ] `swift build` passes (Xcode project)

### US-010: Expose UsageTracker data via WebSocket

**Description:** As a user, I want to see my API token usage in the app so I can monitor costs.

**Acceptance Criteria:**
- [ ] `UsageTracker` gains a `getSummary() -> UsageSummary` method returning totals and request count
- [ ] New `UsageSummary` struct: `totalInput`, `totalOutput`, `totalCacheCreation`, `totalCacheRead`, `requestCount`, `cacheRatio`
- [ ] New WS message type `usage_status` (request) and `usage_status_result` (response) added to both daemon and app `WebSocketMessage.swift`
- [ ] Daemon handler returns current usage summary as metadata
- [ ] `UsageTracker` gains a `reset()` method for session boundaries
- [ ] `swift build` passes

### US-011: Fix cache hit rate formula and naming

**Description:** As a developer, I want the cache hit rate metric to accurately represent cache effectiveness.

**Acceptance Criteria:**
- [ ] Rename metric from `hit_rate` to `cache_ratio` in log output
- [ ] Formula: `cache_read_tokens / (cache_read_tokens + cache_creation_tokens + non_cached_input_tokens)` — representing "proportion of total input served from cache"
- [ ] Log label reads `cache_ratio` not `hit_rate` to avoid misinterpretation
- [ ] If exposing via WS (US-010), use the corrected formula
- [ ] `swift build` passes

### US-012: Regenerate PBX file IDs via Xcode

**Description:** As a developer, I want the `project.pbxproj` to use Xcode-generated UUIDs instead of hand-crafted `GG`-prefixed IDs.

**Acceptance Criteria:**
- [ ] Open `app/SolaceApp.xcodeproj` in Xcode
- [ ] Remove `AddMCPServerSheet.swift` from the project navigator, then re-add it via File > Add Files
- [ ] Xcode assigns proper UUIDs to the build file, file reference, and group membership entries
- [ ] Verify `GG11223344556677AABB` prefix no longer appears in `project.pbxproj`
- [ ] Project builds successfully in Xcode

## Non-Goals

- No new UI screens for usage tracking (US-010 adds the data pipe only; UI is a future story)
- No per-tool cost attribution (usage is tracked at session level, not per-tool)
- No automated testing for MCP server add/delete (manual verification only for now)
- No changes to the Ollama fallback status message format (line 4730-4735) — it's intentionally minimal

## Technical Considerations

- `MCPServerConfig.isEnabled` already defaults to `true` via `enabled ?? true`, so US-001 is about explicit persistence rather than a runtime bug
- `broadcastStatus` and `handleMCPServerToggle` both miss `activeProvider`/`activeModel` — the shared helper (US-008) fixes this everywhere at once
- Debounce in US-005 should use `Task` with sleep rather than `Timer` for Swift concurrency compatibility in `@Observable` classes
- US-012 is a manual Xcode operation, not a code change — do it last since it touches the project file that other stories may also modify
