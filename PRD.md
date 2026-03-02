# PRD: Add LumaDream MCP Server & MCP Toggle UI

## Introduction

Two related enhancements to the Solace MCP ecosystem:

1. **Add the LumaDream MCP server** to `~/.solace/mcp.json` so its video/image generation tools become available to Claude.
2. **Add an MCP server list with enable/disable toggles** to the app's Settings view. When a server is disabled, the daemon still loads it but filters its tools out of Claude API calls. The toggle state persists in `mcp.json` via an `"enabled"` field.

## Goals

- Make LumaDream's creative AI tools available to Claude through the existing MCP pipeline
- Give users visibility into which MCP servers are configured
- Allow users to toggle servers on/off without editing JSON files or restarting the daemon
- Persist toggle state in `mcp.json` so it survives daemon restarts

## User Stories

### US-001: Add LumaDream MCP server to config
**Description:** As a user, I want the LumaDream MCP server added to my config so Claude can use its tools.

**Acceptance Criteria:**
- [ ] Add `lumadream` entry to `~/.solace/mcp.json` as an HTTP-type server with `url` and `headers`
- [ ] Daemon discovers LumaDream tools on next restart
- [ ] LumaDream tools appear in workflow tool picker and are available to Claude in chat
- [ ] `swift build` passes

---

### US-002: Add `enabled` field to MCP config model
**Description:** As a developer, I need the MCP config to support an `enabled` field so servers can be toggled without removal.

**Acceptance Criteria:**
- [ ] Add optional `enabled: Bool?` field to `MCPServerConfig` in `MCPTypes.swift` (defaults to `true` when nil)
- [ ] `MCPManager.startAll()` still starts all servers regardless of enabled state — servers are always loaded
- [ ] `MCPManager.getToolDefinitions()` filters out tools from disabled servers
- [ ] `MCPManager.serverForTool()` returns nil for tools from disabled servers (prevents execution)
- [ ] Existing configs without `enabled` field continue to work (backward compatible)
- [ ] `swift build` passes

---

### US-003: Add WebSocket messages for MCP server list and toggle
**Description:** As a developer, I need WebSocket message types so the app can request the server list and toggle servers.

**Acceptance Criteria:**
- [ ] Add `mcp_servers_list` request type and `mcp_servers_list_result` response type to `WSMessageType` in **both** daemon and app `WebSocketMessage.swift`
- [ ] Add `mcp_server_toggle` request type (client sends server name + enabled bool) in **both** files
- [ ] Add `mcp_server_toggle_result` response type (confirms new state) in **both** files
- [ ] `mcp_servers_list_result` payload includes: server name, type (stdio/http), enabled state, tool count per server
- [ ] `swift build` passes

---

### US-004: Implement daemon handlers for MCP server list and toggle
**Description:** As a developer, I need the daemon to handle the new MCP WebSocket messages.

**Acceptance Criteria:**
- [ ] `handleMCPServersList()` in `DaemonApp.swift` returns all configured servers with name, type, enabled state, and tool count
- [ ] `handleMCPServerToggle()` in `DaemonApp.swift` updates the server's enabled state in memory
- [ ] Toggle persists: writes updated config back to `~/.solace/mcp.json` (preserving all other fields)
- [ ] After toggle, daemon re-broadcasts updated status (tool count) to all connected clients
- [ ] Toggling off a server filters its tools from `getToolDefinitions()` immediately (no restart needed)
- [ ] `swift build` passes

---

### US-005: Wire MCP server data through app view model and message routing
**Description:** As a developer, I need the app to handle MCP server list/toggle messages and expose data to the Settings view.

**Acceptance Criteria:**
- [ ] Add `MCPServerInfo` struct (name, type, enabled, toolCount) to app models
- [ ] Add `mcpServers: [MCPServerInfo]` observable property to an appropriate location (e.g. `WebSocketClient` or a new lightweight model)
- [ ] Handle `mcp_servers_list_result` and `mcp_server_toggle_result` in message routing in `SolaceApp.swift`
- [ ] Provide `requestMCPServersList()` and `toggleMCPServer(name:enabled:)` send methods
- [ ] Xcode build succeeds

---

### US-006: Add MCP servers section to Settings view
**Description:** As a user, I want to see my configured MCP servers in Settings and toggle them on/off.

**Acceptance Criteria:**
- [ ] New "MCP Servers" section in `SettingsView.swift` below the existing "About" section
- [ ] Lists each server by name with a toggle switch
- [ ] Shows server type indicator (stdio vs http) as subtle secondary label
- [ ] Toggle sends `mcp_server_toggle` message to daemon via WebSocket
- [ ] List loads on view appear via `mcp_servers_list` request
- [ ] Refreshes after toggle confirmation
- [ ] Uses `SolaceTheme` styling consistent with existing Settings sections
- [ ] Xcode build succeeds

## Non-Goals

- No adding/removing/editing MCP servers from the app UI (config file only)
- No per-tool enable/disable — toggles are at the server level
- No server health/status monitoring (online/offline/error states)
- No drag-to-reorder servers
- No daemon restart from the app

## Technical Considerations

- **Config backward compatibility:** Existing `mcp.json` files without `enabled` field must work — treat missing as `true`
- **Model sync:** `WSMessageType` additions must be added to both daemon and app `WebSocketMessage.swift`
- **Tool filtering approach:** Filter at `getToolDefinitions()` and `serverForTool()` level in `MCPManager` — disabled server tools won't appear in Claude API calls or workflow builder, but server processes remain running
- **Config write safety:** When writing `mcp.json` after toggle, read-modify-write carefully to preserve all existing fields
- **Existing MCP tools flow:** The `mcp_tools_list` / `mcp_tools_list_result` messages used by workflow builder will automatically reflect enabled state since they go through `getToolDefinitions()`
