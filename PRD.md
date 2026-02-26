# PRD: love.Me — AI Personal Assistant App

## Introduction

love.Me is a native iOS app that serves as a dedicated AI personal assistant. Unlike OpenClaw (which piggybacks on WhatsApp/Telegram), love.Me has its own purpose-built chat interface with full visibility into the AI's thinking process and tool execution. When you message love.Me, a local agent daemon running on your Mac uses Claude API + MCP servers to actually do the work — write code, manage files, run commands — and streams its reasoning and actions back to you in real-time.

## Architecture Overview

```
┌─────────────────┐       WebSocket        ┌──────────────────────┐
│  iOS App (SwiftUI)│◄─────────────────────►│  macOS Agent Daemon   │
│                   │   (local network)     │                      │
│  • Chat UI        │                       │  • Claude API client  │
│  • Thinking panel │                       │  • MCP server host    │
│  • Tool feed      │                       │  • Task executor      │
└─────────────────┘                        └──────────────────────┘
                                                     │
                                                     ▼
                                            ┌──────────────────┐
                                            │  MCP Servers      │
                                            │  • Filesystem     │
                                            │  • Shell          │
                                            │  • Custom tools   │
                                            └──────────────────┘
```

## Goals

- Provide a standalone iOS chat interface for communicating with an AI assistant
- Execute real work on the user's Mac via a local agent daemon
- Show Claude's extended thinking in a collapsible panel
- Display live MCP tool calls and results as they happen
- Stream all responses in real-time via WebSocket
- Support MCP server connections for extensible tool use

## User Stories

### US-001: Xcode Project & App Shell
**Description:** As a developer, I need the iOS project scaffolded so I can start building features.

**Acceptance Criteria:**
- [ ] Xcode project created with SwiftUI lifecycle (iOS 17+)
- [ ] App launches to a placeholder screen with "love.Me" branding
- [ ] Project compiles with zero warnings
- [ ] Folder structure: `Models/`, `Views/`, `Services/`, `ViewModels/`
- [ ] Typecheck passes

---

### US-002: Agent Daemon Scaffold (macOS)
**Description:** As a developer, I need a local macOS daemon process that the iOS app can connect to.

**Acceptance Criteria:**
- [ ] Swift Package or macOS command-line target created in the same workspace
- [ ] Daemon starts and listens on a configurable local port (default: 9200)
- [ ] Daemon logs startup message to stdout
- [ ] Daemon can be started/stopped from Terminal
- [ ] Typecheck passes

---

### US-003: WebSocket Communication Layer
**Description:** As a developer, I need the iOS app and daemon to exchange messages over WebSocket so they can communicate in real-time.

**Acceptance Criteria:**
- [ ] Daemon hosts a WebSocket server on the configured port
- [ ] iOS app connects to daemon via WebSocket using `URLSessionWebSocketTask`
- [ ] Define JSON message protocol: `{ "type": "...", "payload": {...} }`
- [ ] Message types: `user_message`, `assistant_message`, `thinking`, `tool_call`, `tool_result`, `error`, `status`
- [ ] Connection status shown in app (connected/disconnected indicator)
- [ ] Auto-reconnect on disconnect with exponential backoff
- [ ] Typecheck passes

---

### US-004: Chat UI — Message List & Input
**Description:** As a user, I want a clean chat interface to send messages and see responses.

**Acceptance Criteria:**
- [ ] ScrollView with message bubbles (user = right/accent, assistant = left/secondary)
- [ ] Text input bar at bottom with send button
- [ ] Send button disabled when input is empty
- [ ] Messages auto-scroll to bottom on new message
- [ ] Keyboard avoidance works correctly
- [ ] Empty state: centered love.Me logo + "Send a message to get started"
- [ ] Typecheck passes
- [ ] Verify changes work in Simulator

---

### US-005: Claude API Integration in Daemon
**Description:** As a developer, I need the daemon to call Claude API with streaming so it can generate responses.

**Acceptance Criteria:**
- [ ] Claude API key read from environment variable `ANTHROPIC_API_KEY`
- [ ] Uses `claude-sonnet-4-5-20250929` model by default (configurable)
- [ ] Streaming enabled via SSE (`stream: true`)
- [ ] Extended thinking enabled (`thinking: { type: "enabled", budget_tokens: 10000 }`)
- [ ] System prompt: "You are love.Me, a personal AI assistant. You have access to tools to execute tasks on the user's computer."
- [ ] Streamed tokens forwarded to iOS app via WebSocket as they arrive
- [ ] Typecheck passes

---

### US-006: End-to-End Chat Flow
**Description:** As a user, I want to send a message and see the AI's response stream in real-time.

**Acceptance Criteria:**
- [ ] User types message → sent via WebSocket to daemon
- [ ] Daemon forwards to Claude API with conversation history
- [ ] Response tokens stream back and appear word-by-word in chat
- [ ] Typing indicator shown while response is streaming
- [ ] Conversation history maintained in-memory (daemon side)
- [ ] Typecheck passes
- [ ] Verify changes work in Simulator

---

### US-007: Thinking Panel (Collapsible)
**Description:** As a user, I want to see what the AI is thinking so I understand its reasoning.

**Acceptance Criteria:**
- [ ] Thinking content appears in a collapsible section above the assistant's message
- [ ] Collapsed by default, shows "Thinking..." label with chevron
- [ ] Tap to expand and see full thinking text
- [ ] Thinking text styled differently (monospace, muted color, slightly smaller)
- [ ] Thinking streams in real-time (not just shown after completion)
- [ ] If no thinking block in response, no thinking section shown
- [ ] Typecheck passes
- [ ] Verify changes work in Simulator

---

### US-008: MCP Server Connection in Daemon
**Description:** As a developer, I need the daemon to connect to MCP servers so the AI can use tools.

**Acceptance Criteria:**
- [ ] Daemon reads MCP server config from `~/.love-me/mcp.json`
- [ ] Config format: `{ "servers": { "name": { "command": "...", "args": [...] } } }`
- [ ] Daemon launches configured MCP servers as child processes on startup
- [ ] Communicates with MCP servers via stdio (JSON-RPC)
- [ ] Discovers available tools from each server via `tools/list`
- [ ] Tools passed to Claude API in the `tools` parameter
- [ ] Typecheck passes

---

### US-009: Tool Call Execution & Results
**Description:** As a developer, I need the daemon to execute tool calls from Claude and return results.

**Acceptance Criteria:**
- [ ] When Claude returns a `tool_use` block, daemon routes to correct MCP server
- [ ] Sends `tools/call` JSON-RPC request with tool name and arguments
- [ ] Receives tool result and sends back to Claude as `tool_result`
- [ ] Supports multi-turn tool use (Claude can call multiple tools in sequence)
- [ ] Errors from tool execution sent back to Claude as error results
- [ ] Typecheck passes

---

### US-010: Tool Activity Feed UI
**Description:** As a user, I want to see a live feed of what tools the AI is using so I know what's happening on my machine.

**Acceptance Criteria:**
- [ ] Tool calls appear inline in the chat as compact cards
- [ ] Each card shows: tool name, server name, status (running/done/error)
- [ ] Tap card to expand and see input arguments + result
- [ ] Running state shows spinner animation
- [ ] Done state shows checkmark with execution time
- [ ] Error state shows red indicator with error message
- [ ] Cards appear in real-time as tool calls happen
- [ ] Typecheck passes
- [ ] Verify changes work in Simulator

---

### US-011: Conversation Persistence
**Description:** As a user, I want my conversations saved so I can pick up where I left off.

**Acceptance Criteria:**
- [ ] Conversations saved to `~/.love-me/conversations/` as JSON files
- [ ] Each conversation has a UUID, title (auto-generated from first message), and timestamp
- [ ] Conversation list view accessible from sidebar/navigation
- [ ] Tap conversation to load and continue it
- [ ] "New conversation" button clears chat and starts fresh
- [ ] Typecheck passes
- [ ] Verify changes work in Simulator

---

### US-012: Daemon Connection Setup UI
**Description:** As a user, I need a way to configure how the app connects to my Mac's daemon.

**Acceptance Criteria:**
- [ ] Settings screen accessible from chat view
- [ ] Fields: host (default: local IP), port (default: 9200)
- [ ] "Test Connection" button that pings daemon and shows result
- [ ] Connection settings persisted in UserDefaults
- [ ] QR code display on daemon startup for easy mobile connection
- [ ] Typecheck passes
- [ ] Verify changes work in Simulator

---

### US-013: Markdown Rendering in Chat
**Description:** As a user, I want code blocks and formatted text to render properly in chat.

**Acceptance Criteria:**
- [ ] Assistant messages render Markdown (bold, italic, lists, headings)
- [ ] Code blocks render with syntax highlighting and monospace font
- [ ] Inline code renders with background highlight
- [ ] Links are tappable
- [ ] Uses AttributedString or a lightweight Markdown library
- [ ] Typecheck passes
- [ ] Verify changes work in Simulator

---

### US-014: Daemon Status & System Tray
**Description:** As a user, I want to know the daemon is running and control it easily from my Mac.

**Acceptance Criteria:**
- [ ] Daemon runs as a menu bar app (macOS system tray)
- [ ] Menu bar icon shows connection status (green dot = active client, gray = idle)
- [ ] Menu options: "Show Logs", "Restart", "Quit"
- [ ] Shows connected client count
- [ ] Daemon auto-starts on login (optional, configurable)
- [ ] Typecheck passes

## Non-Goals

- **No WhatsApp/Telegram/SMS integration** — this is a standalone app
- **No cloud hosting of the daemon** — runs locally on user's Mac only
- **No multi-user support** — single user, single Mac
- **No App Store distribution for v1** — developer builds / TestFlight only
- **No iPad/Mac Catalyst UI** — iPhone-first for v1
- **No voice input** — text-only for v1
- **No file/image attachments in chat** — text messages only for v1
- **No authentication/login** — local network trust model for v1

## Technical Considerations

- **iOS 17+** required for modern SwiftUI features (Observable macro, etc.)
- **macOS 14+** for daemon (Sonoma) for modern Swift concurrency
- **Swift 5.9+** with strict concurrency checking
- Use `Codable` for all message serialization
- Claude API: use raw `URLSession` streaming (no SDK dependency for v1)
- MCP communication: JSON-RPC 2.0 over stdio
- Consider using `swift-markdown` for rendering
- WebSocket: `NWListener` (Network.framework) on daemon side for better control
- Conversation storage: JSON files (no database for v1)
