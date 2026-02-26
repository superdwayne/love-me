# PRD: Visual Workflow Builder

## Introduction

The current workflow editor requires users to manually type MCP server names, tool names, cron expressions, and wire up step dependencies — a developer-level experience that's hostile to creative users. This feature replaces that with a **conversational workflow builder** where users describe what they want in plain English ("every 5 minutes, generate a 3D asset in Blender, then render an image of it"), and the AI constructs the workflow automatically. The iOS editor also gets upgraded with visual step cards and natural language scheduling, so users can tweak AI-generated workflows without touching raw config.

## Goals

- Users can create workflows by describing them in natural language via chat
- AI maps plain-English step descriptions to the correct MCP server + tool
- Schedule triggers accept natural language ("every 5 minutes", "daily at 9am") instead of cron expressions
- Visual step cards replace raw text fields for server/tool names
- Steps are linear-only (top-to-bottom sequence) for simplicity
- Generated workflows can be reviewed and tweaked visually before saving

## User Stories

### US-001: Add MCP tool catalog endpoint to daemon
**Description:** As the AI builder, I need to know what MCP tools are available so I can map user descriptions to real tools.

**Acceptance Criteria:**
- [ ] New `mcp_tools_list` WebSocket message type that returns all available tools across all connected MCP servers
- [ ] Response includes for each tool: serverName, toolName, description, input schema (parameter names + types)
- [ ] Tools are fetched live from MCPManager's connected servers (not hardcoded)
- [ ] Returns empty array gracefully if no MCP servers are connected
- [ ] Typecheck passes (`swift build`)

### US-002: Add natural language to cron parser in daemon
**Description:** As a user, I want to type "every 5 minutes" or "daily at 9am" and have it converted to a cron expression so I don't need to learn cron syntax.

**Acceptance Criteria:**
- [ ] New `NaturalScheduleParser` utility that converts common phrases to cron expressions
- [ ] Supports: "every N minutes", "every N hours", "every day at H:MM AM/PM", "every hour", "hourly", "every weekday at H", "weekly on [day]", "every monday/tuesday/etc at H"
- [ ] Returns `nil` for unrecognized input (fallback to raw cron still available)
- [ ] New `parse_schedule` WebSocket message: input `{ "text": "every 5 minutes" }` → response `{ "cron": "*/5 * * * *", "description": "Every 5 minutes" }`
- [ ] Typecheck passes (`swift build`)

### US-003: Add AI workflow builder endpoint to daemon
**Description:** As a user, I want to describe a workflow in plain English and have the AI construct it for me, mapping my descriptions to real MCP tools.

**Acceptance Criteria:**
- [ ] New `build_workflow` WebSocket message type
- [ ] Input: `{ "prompt": "every 5 minutes generate a 3D asset in blender then render an image of it" }`
- [ ] Daemon sends the prompt + available MCP tool catalog to Claude API as a system-prompted request
- [ ] System prompt instructs Claude to output a structured workflow JSON matching `WorkflowDefinition` schema
- [ ] Response returns a complete `WorkflowDetail` that the iOS app can display for review
- [ ] If no suitable MCP tools exist for a described step, the step is included with a `"needs_configuration": true` flag and a human-readable note
- [ ] Natural language schedule in the prompt is parsed to cron via `NaturalScheduleParser` (or by the AI)
- [ ] Typecheck passes (`swift build`)

### US-004: Add workflow builder chat view to iOS app
**Description:** As a user, I want a chat-like interface where I describe my workflow and see the AI-generated result, so I can create workflows conversationally.

**Acceptance Criteria:**
- [ ] New `WorkflowBuilderView` accessible from the Workflows tab (new "Build with AI" button alongside the existing + button)
- [ ] Simple chat interface: text input at bottom, messages scroll up
- [ ] User types a description, it sends `build_workflow` to daemon
- [ ] While waiting, show a loading indicator with "Building your workflow..."
- [ ] On response, display the generated workflow as a visual preview (name, schedule description, list of step cards)
- [ ] Each step card shows: step name, tool description (human-readable), and a status indicator (green = mapped to real tool, amber = needs configuration)
- [ ] "Save Workflow" button at the bottom of the preview to save and dismiss
- [ ] "Try Again" button to re-prompt with modifications
- [ ] Typecheck passes (`swift build`)
- [ ] Verify changes work in browser/simulator

### US-005: Upgrade schedule input in WorkflowEditorView to natural language
**Description:** As a user, I want to type schedules like "every 5 minutes" instead of `*/5 * * * *` when creating or editing workflows.

**Acceptance Criteria:**
- [ ] Replace the cron expression `TextField` with a natural language text field (placeholder: "e.g. every 5 minutes, daily at 9am")
- [ ] On text change (debounced 500ms), send `parse_schedule` to daemon
- [ ] Display parsed result below: green checkmark + "Every 5 minutes (*/5 * * * *)" or red X + "Couldn't parse — enter a cron expression" with a toggle to raw cron input
- [ ] Raw cron fallback: small "Use cron syntax" link that switches to the old text field
- [ ] Saved workflow still stores the cron expression (natural language is a UI convenience, not a storage format)
- [ ] Typecheck passes (`swift build`)
- [ ] Verify changes work in browser/simulator

### US-006: Upgrade step cards in WorkflowEditorView with tool picker
**Description:** As a user, I want to pick tools from a visual list instead of typing raw server/tool names.

**Acceptance Criteria:**
- [ ] On editor appear, fetch MCP tool catalog via `mcp_tools_list`
- [ ] Replace the server name + tool name text fields with a single "Choose Tool" button per step
- [ ] Tapping "Choose Tool" opens a sheet listing available tools grouped by MCP server
- [ ] Each tool shows: tool name (human-readable), server name (subtitle), and first line of description
- [ ] Searching/filtering by keyword within the tool picker sheet
- [ ] Selected tool auto-fills the step's serverName and toolName
- [ ] Step card displays the selected tool name prominently (not raw identifiers)
- [ ] Fallback: if no MCP servers connected, show "No tools available — connect an MCP server" message
- [ ] Typecheck passes (`swift build`)
- [ ] Verify changes work in browser/simulator

### US-007: Add workflow preview card component
**Description:** As a user, I want a clean visual summary of a workflow (used in both the builder and the list view) so workflows feel tangible, not like raw JSON.

**Acceptance Criteria:**
- [ ] New `WorkflowPreviewCard` SwiftUI component
- [ ] Shows: workflow name, schedule in plain English, step count badge
- [ ] Shows linear step pipeline: vertical stack of connected step pills (icon → name → arrow → next step)
- [ ] Step pills use color coding: blue for tool steps, amber for steps needing config
- [ ] Enabled/disabled state visually distinct (opacity for disabled)
- [ ] Used in `WorkflowBuilderView` for the AI-generated preview
- [ ] Typecheck passes (`swift build`)
- [ ] Verify changes work in browser/simulator

## Non-Goals

- No drag-and-drop node graph / canvas editor (v2 consideration)
- No DAG / branching / parallel step support in the visual builder (linear only for v1)
- No input template editing in the visual builder (AI generates sensible defaults; power users edit JSON directly)
- No MCP server installation or management from within the app
- No step-to-step variable wiring UI (AI handles variable references automatically)
- No workflow versioning or undo history

## Technical Considerations

- The daemon already has `MCPManager` with `listTools()` capability per server — US-001 aggregates across all servers
- `ClaudeAPIClient` already handles Claude API calls with streaming — US-003 can reuse this for the builder prompt (non-streaming single response is simpler here)
- `WorkflowTypes.swift` already defines the full data model — AI output must conform to existing `WorkflowDefinition` schema
- The iOS `WorkflowViewModel` already handles 18+ WebSocket message types — new messages follow the same pattern
- Linear-only constraint means `dependsOn` arrays are always `[previousStepId]` or empty for step 0, simplifying both AI generation and visual display
- Natural language parsing is done daemon-side so the logic lives in one place (not duplicated in iOS)
