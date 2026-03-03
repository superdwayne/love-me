# PRD: Production Hardening & Performance Optimization

## Introduction

Solace has grown rapidly with features (chat, MCP tools, workflows, email, multi-provider LLM) but hasn't had a dedicated performance and stability pass. The app feels slow in places, and the codebase has accumulated patterns that could cause crashes, memory leaks, or degraded UX under real-world use. This PRD covers a systematic audit and fix pass across both the daemon (Swift server) and iOS app to reach TestFlight/beta quality — stable enough for external users.

The audit identified issues across four categories: **memory management**, **concurrency safety**, **error recovery**, and **UI responsiveness**. Fixes are ordered by blast radius (daemon stability first, then app performance).

## Goals

- Eliminate memory leaks and unbounded growth in daemon conversation/message stores
- Add proper timeouts and error recovery for LLM streaming (both Claude and Ollama)
- Harden WebSocket connection lifecycle (daemon server + app client)
- Fix iOS app UI jank from unnecessary re-renders and missing caching
- Ensure graceful degradation when external services fail (MCP servers, Ollama, email API)
- Make the app stable enough for TestFlight beta distribution

## User Stories

### US-001: Fix DaemonApp Actor Blocking During LLM Streaming (Critical)
**Description:** As a user, I want the daemon to remain responsive while an LLM response is streaming so other operations (tool calls, status updates, new messages) aren't blocked.

**Acceptance Criteria:**
- [x] Remove `await task.value` at DaemonApp.swift:376 — this blocks the entire DaemonApp actor for the duration of every LLM stream, serializing all WebSocket message handling
- [x] Let the generation Task run independently; rely on cleanup in the task body (`removeGenerationTask`) instead of awaiting completion
- [ ] Verify: while one conversation is streaming, sending a `getStatus` or `getConversations` message gets an immediate response (not delayed until stream finishes)
- [ ] Verify: starting a second conversation while one is streaming works without queueing
- [x] `swift build` succeeds

### US-002: Add Streaming Timeout and Recovery for LLM Providers
**Description:** As a user, I want the app to recover if an LLM provider hangs mid-stream so I'm not stuck waiting forever.

**Acceptance Criteria:**
- [x] Add a per-chunk streaming timeout (60s between chunks) to `ClaudeAPIClient.streamRequest`
- [x] Add the same per-chunk timeout to `OllamaAPIClient.streamRequest`
- [x] If timeout fires, cancel the stream and send an error message to the client: "Response timed out — tap to retry"
- [x] Clean up `activeGenerationTasks` entry on timeout so the conversation isn't stuck
- [ ] Verify: start a stream, kill the LLM endpoint mid-response — app shows error within 60s
- [x] `swift build` succeeds

### US-003: Fix O(n²) String Concatenation During Streaming
**Description:** As a developer, I need efficient string building during LLM streaming so long responses don't cause CPU spikes.

**Acceptance Criteria:**
- [x] Replace `fullText += chunk` and `fullThinking += chunk` in DaemonApp.swift:462-545 with an array of chunks joined at the end (or use a `[String]` buffer with final `.joined()`)
- [x] Same pattern for any other `+=` string accumulation in the streaming loop
- [ ] Verify: stream a 10,000-char response — CPU usage stays flat (not quadratic growth)
- [x] `swift build` succeeds

### US-004: Bound Conversation History Size
**Description:** As a developer, I need conversation history to have a size limit so the daemon doesn't consume unbounded memory during long sessions.

**Acceptance Criteria:**
- [ ] Add a configurable max message count per conversation (default: 200 messages)
- [ ] When limit is reached, trim oldest messages (keep system prompt + last N messages)
- [ ] Trimmed messages are still persisted on disk, just not held in memory
- [ ] LLM requests use a context window budget (e.g., last 50 messages) rather than full history
- [ ] Log when trimming occurs: "Trimmed conversation {id} from {old} to {new} messages"
- [ ] `swift build` succeeds

### US-005: Fix WebSocket Broadcast Resilience
**Description:** As a developer, I need WebSocket broadcasts to not block on slow/dead clients so one bad connection doesn't stall everyone.

**Acceptance Criteria:**
- [ ] `WebSocketServer.broadcast()` sends to each client concurrently using `TaskGroup` instead of sequential loop
- [ ] Add a per-client send timeout (5s) — if a client doesn't accept the message, skip it and log a warning
- [ ] Failed sends trigger client cleanup (close connection, remove from clients dict)
- [ ] Verify: with 2 clients connected, one client hanging doesn't delay messages to the other
- [ ] `swift build` succeeds

### US-006: Add MCP Tool Call Timeout and Error Propagation
**Description:** As a user, I want to know when an MCP tool call fails or times out rather than the UI spinning forever.

**Acceptance Criteria:**
- [ ] MCP tool calls already have a 60s timeout — verify it propagates as an error message to the chat
- [ ] If an MCP server process crashes mid-tool-call, pending continuations are resumed with an error (not leaked)
- [ ] Tool error results are displayed in the ToolCard UI with the actual error message
- [ ] Daemon logs include tool name, server name, and duration for every tool call (success or failure)
- [ ] `swift build` succeeds

### US-007: Fix Markdown Re-Parsing During Streaming (Critical)
**Description:** As a user, I want streaming responses to render smoothly without frame drops caused by re-parsing the entire message on every character.

**Acceptance Criteria:**
- [x] `MarkdownRenderer.render()` is called on every character append during streaming (MessageBubble.swift:132) — add a debounce/throttle so markdown is re-parsed at most every 100ms during streaming
- [x] Cache the rendered `AttributedString` and only re-render when content changes by more than a threshold (e.g., new line or 100+ chars since last render)
- [x] During active streaming, show raw text for the current chunk and render markdown on completion or pause
- [ ] Verify: stream a 2000-char response — no dropped frames on iPhone 13 or later
- [x] Xcode project builds successfully

### US-008: Fix iOS Chat View Rendering Performance
**Description:** As a user, I want the chat to scroll smoothly without jank, even during LLM streaming.

**Acceptance Criteria:**
- [x] Replace `ForEach(Array(chatVM.messages.enumerated()), id: \.element.id)` with `ForEach(chatVM.messages)` using the existing `Identifiable` conformance — eliminates array copy on every render
- [x] During streaming, only the last message bubble should re-render (not the entire list)
- [x] Move `DateFormatter` and `RelativeDateTimeFormatter` allocations to shared static instances (MessageBubble.swift:179-183 creates new DateFormatter per message, EmailApprovalView.relativeDate() creates new RelativeDateTimeFormatter per cell)
- [x] Throttle auto-scroll during streaming — `onChange(of: streamingContentLength)` fires per character, batch scroll updates to every 100ms
- [ ] Verify: scroll through 50+ messages during active streaming — no dropped frames
- [x] Xcode project builds successfully

### US-009: Add Image Caching for MCP-Generated Images
**Description:** As a user, I want images in tool results to load once and stay cached so scrolling back doesn't re-fetch them.

**Acceptance Criteria:**
- [ ] Replace `AsyncImage` in `ToolCard` with a caching image loader (URLSession cache or NSCache-backed)
- [ ] Images persist in memory cache for the session lifetime
- [ ] Scrolling past and back to an image card shows the image instantly (no loading spinner)
- [ ] Memory cache has a size limit (50MB) to prevent OOM on image-heavy conversations
- [ ] Xcode project builds successfully

### US-010: Move JSON Decoding Off Main Thread
**Description:** As a user, I want the app to stay responsive during rapid WebSocket message delivery (e.g., streaming).

**Acceptance Criteria:**
- [ ] Move `JSONDecoder().decode(WSMessage.self, from: data)` in `WebSocketClient.handleReceivedMessage` (line 179) to a background Task
- [ ] Dispatch decoded messages to ViewModels on `@MainActor` after decoding
- [ ] Add selective message routing — only dispatch messages to relevant ViewModels (e.g., `toolCallDone` only goes to ChatViewModel, not all 5 VMs)
- [ ] Verify: rapid streaming (50+ chunks/sec) does not block UI input
- [ ] Xcode project builds successfully

### US-011: Move Image Compression Off Main Thread
**Description:** As a user, I want to attach multiple photos without the app freezing.

**Acceptance Criteria:**
- [ ] Move `UIGraphicsImageRenderer` compression in `InputBar.compressImage` (line 257-259) to a background Task
- [ ] Show a loading indicator on attachment thumbnails while compression runs
- [ ] Limit concurrent compressions to 3 to avoid memory spikes
- [ ] Verify: attach 5 photos — UI stays interactive throughout compression
- [ ] Xcode project builds successfully

### US-012: Harden WebSocket Client Reconnection
**Description:** As a user, I want the app to reliably reconnect after network changes (Wi-Fi switch, sleep/wake) without getting stuck.

**Acceptance Criteria:**
- [ ] Exponential backoff already exists — verify it caps at a reasonable max (30s)
- [ ] Add NWPathMonitor to detect network changes and trigger immediate reconnect on network restoration
- [ ] On app foreground (UIScene `willEnterForeground`), check connection and reconnect if needed
- [ ] Reset retry count on successful connection (already done — verify)
- [ ] Add a manual "Reconnect" button in ConnectionBanner after 3 failed retries
- [ ] Xcode project builds successfully

### US-013: Fix Daemon Graceful Shutdown
**Description:** As a developer, I need the daemon to clean up all resources on shutdown so no zombie processes or leaked file handles remain.

**Acceptance Criteria:**
- [ ] SIGINT/SIGTERM handler cancels: all active generation tasks, workflow executions, cron schedules, email polling, Ollama health check task
- [ ] MCP server processes are sent SIGTERM, then SIGKILL after 5s if still alive
- [ ] WebSocket server closes all client connections with a `.goingAway` close code
- [ ] Log shutdown sequence: "Shutting down... [step]" for each cleanup phase
- [ ] Verify: run daemon, send SIGINT — process exits within 10s with no orphan child processes
- [ ] `swift build` succeeds

### US-014: Add Request Deduplication for Rapid Message Sends
**Description:** As a user, I don't want accidental double-taps to send duplicate messages to the LLM.

**Acceptance Criteria:**
- [ ] Daemon ignores `userMessage` if there's already an active generation task for that conversation
- [ ] App disables send button while streaming is in progress (grey out, not hidden)
- [ ] If user sends while streaming, show brief toast/feedback: "Waiting for response..."
- [ ] Existing "stop generation" flow still works (cancel button replaces send during streaming)
- [ ] `swift build` succeeds
- [ ] Xcode project builds successfully

### US-015: Ollama Provider Error Handling Hardening
**Description:** As a user, I want clear feedback when Ollama-specific issues occur so I know what to fix.

**Acceptance Criteria:**
- [ ] If Ollama returns a model not found error, show: "Model '{name}' not available. Run `ollama pull {name}` to install it."
- [ ] If Ollama endpoint is unreachable, fallback to Claude within 5s (not 60s health check interval)
- [ ] If Ollama returns malformed SSE chunks, log the raw data and send a user-friendly error
- [ ] Connection refused errors during chat show: "Ollama is not running. Falling back to Claude." (not a raw error)
- [ ] Provider fallback is reflected in the app status bar immediately
- [ ] `swift build` succeeds

### US-016: Add Daemon Health Endpoint
**Description:** As a developer, I need a simple health check endpoint so monitoring tools (and the app) can verify daemon status.

**Acceptance Criteria:**
- [ ] Add a `getHealth` WebSocket message type that returns: uptime, active connections, active provider, MCP server statuses, memory usage (RSS)
- [ ] Response includes version string for the daemon
- [ ] App can request health on connect to verify daemon capabilities match
- [ ] Add message types to both daemon and app `WebSocketMessage.swift`
- [ ] `swift build` succeeds

### US-017: Audit and Fix Memory Leaks in Closures and Tasks
**Description:** As a developer, I need to ensure no retain cycles exist in async closures that could cause memory leaks.

**Acceptance Criteria:**
- [ ] Audit all `Task { }` blocks in DaemonApp for proper `[weak self]` usage where needed
- [ ] Audit all callback closures (onStepUpdate, onExecutionUpdate, onFire) for capture semantics
- [ ] WorkflowExecutor fire-and-forget `Task { await callback(...) }` blocks should not retain the executor
- [ ] EmailConversationBridge polling loop properly cancels on deinit
- [ ] BonjourBrowser.swift: add `deinit` that calls `stopBrowsing()` — currently leaks NetServiceBrowser
- [ ] Silent WebSocket send failures (WebSocketClient.swift:104) — add actual logging instead of dead `_ = description`
- [ ] Verify with Instruments: run daemon for 30 minutes with active chat — RSS stays flat (no steady growth)
- [ ] `swift build` succeeds

## Non-Goals

- **No load testing / multi-user support** — Solace is single-user; we optimize for one active client
- **No HTTP API** — All communication stays over WebSocket; no REST endpoint additions
- **No UI redesign** — This is under-the-hood; no visual changes except the reconnect button and error messages
- **No database migration** — Conversation store stays file-based JSON; no SQLite migration
- **No automated performance benchmarks** — Manual Instruments profiling is sufficient for beta
- **No third-party crash reporting** — We rely on TestFlight crash logs, not Sentry/Crashlytics

## Technical Considerations

- **Markdown streaming optimization:** The key insight is that `MarkdownRenderer.render()` runs full line-by-line parsing + regex on every character during streaming (MessageBubble.swift:132, MarkdownRenderer.swift:5-103). Options: (a) throttle renders to 100ms intervals during streaming, (b) show raw text during streaming and render markdown on completion, (c) incrementally parse only new content. Option (a) gives the best UX/effort tradeoff.
- **Streaming timeout implementation:** Use `AsyncTimerSequence` or a watchdog `Task` that resets on each chunk. Cancel the URLSession task if the timer fires.
- **WebSocket TaskGroup broadcast:** Be careful with actor isolation — `WebSocketServer` is an actor, so the TaskGroup needs to capture client references outside the actor boundary.
- **NWPathMonitor on iOS:** Must run on a dedicated DispatchQueue, not the main queue. Only trigger reconnect on `.satisfied` after a `.unsatisfied` transition (not on every path update).
- **Image caching:** `URLCache` with a custom `URLSessionConfiguration` is simplest. Alternatively, a lightweight `NSCache<NSURL, UIImage>` wrapper avoids the complexity of `AsyncImage` replacement.
- **Conversation trimming:** Keep the full history on disk (`~/.solace/conversations/`), but only load the last N messages into the in-memory array. Use a simple offset when loading.
- **Main thread JSON decoding:** WebSocketClient receives all messages on the URLSession delegate queue but dispatches to `@MainActor` before decoding. Decode first, then dispatch to main.
- **Files to modify (daemon):**
  - `DaemonApp.swift` — Streaming timeout, request dedup, shutdown, health endpoint
  - `ClaudeAPIClient.swift` — Per-chunk timeout
  - `OllamaAPIClient.swift` — Per-chunk timeout, error message improvements
  - `WebSocketServer.swift` — Concurrent broadcast, client timeout
  - `ConversationStore.swift` — History size bounding
  - `MCPServerProcess.swift` — Verify continuation cleanup on crash
  - `Models/WebSocketMessage.swift` — Health message types
- **Files to modify (app):**
  - `Views/ChatView.swift` — ForEach optimization, scroll throttling
  - `Views/MessageBubble.swift` — Markdown render throttling, static DateFormatter
  - `Views/ToolCard.swift` — Image caching
  - `Views/InputBar.swift` — Background image compression
  - `Views/EmailApprovalView.swift` — Static date formatter
  - `Views/ConnectionBanner.swift` — Reconnect button
  - `Services/WebSocketClient.swift` — Background JSON decode, NWPathMonitor, foreground reconnect, selective message routing
  - `Services/BonjourBrowser.swift` — deinit cleanup
  - `Models/WebSocketMessage.swift` — Health message types
