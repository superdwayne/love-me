# PRD: Workflow Orchestration Engine

## Introduction

Add a workflow orchestration engine to love.Me that lets users define automated multi-step workflows across any MCP server. Workflows can be triggered by time (cron schedules) or events (MCP server activity), execute a sequence of tool calls across multiple MCP servers, and send native iOS push notifications on status changes (started, step completed, finished, errored).

Example workflows:
- "Every morning at 9am, check my email for invoices and save attachments to ~/Documents/invoices/"
- "When a new file appears in ~/Downloads/, rename it and move to the right folder"
- "Every hour, check my website analytics and notify me if traffic spikes"

## Architecture

```
┌─────────────────┐       WebSocket        ┌──────────────────────────────┐
│  iOS App         │◄─────────────────────►│  macOS Daemon                 │
│                  │                        │                               │
│  • Workflow List │                        │  • WorkflowStore              │
│  • Workflow Edit │                        │  • WorkflowScheduler (cron)   │
│  • Execution Log │                        │  • WorkflowExecutor (DAG)     │
│  • Notifications │                        │  • EventBus (MCP events)      │
└─────────────────┘                        │  • NotificationService (APNs) │
         ▲                                  └──────────────────────────────┘
         │ APNs                                       │
         │                                            ▼
┌────────┴────────┐                        ┌──────────────────┐
│  Apple Push      │                        │  MCP Servers      │
│  Notification    │                        │  (any configured) │
│  Service         │                        └──────────────────┘
└─────────────────┘
```

## Goals

- Define reusable workflows as sequences of MCP tool calls with variable passing between steps
- Support cron-based scheduling ("every day at 9am", "every 30 minutes")
- Support event-based triggers (file changes, new emails, custom MCP events)
- Execute workflows across any configured MCP server — fully generic/pluggable
- Send native iOS push notifications (APNs) on workflow lifecycle events
- Persist workflow definitions, execution history, and logs
- Show real-time workflow execution progress in the iOS app

## User Stories

### US-001: Workflow Definition Model
**Description:** As a developer, I need data models for workflow definitions so the system can store and execute them.

**Acceptance Criteria:**
- [ ] `WorkflowDefinition` struct with: id (UUID), name, description, enabled (bool), trigger, steps[], notificationPrefs
- [ ] `WorkflowTrigger` enum: `.cron(expression: String)`, `.event(source: String, eventType: String, filter: [String: String]?)`
- [ ] `WorkflowStep` struct with: id, name, toolName, serverName, inputTemplate ([String: StringOrVariable]), dependsOn ([StepID]?), onError (stop|skip|retry)
- [ ] `StringOrVariable` enum: `.literal(String)`, `.variable(stepId: String, jsonPath: String)` — enables passing output of step A as input to step B
- [ ] `NotificationPrefs` struct: notifyOnStart (bool), notifyOnComplete (bool), notifyOnError (bool), notifyOnStepComplete (bool)
- [ ] All types conform to `Codable`
- [ ] Add models to `daemon/Sources/LoveMeDaemon/Models/WorkflowTypes.swift`
- [ ] Typecheck passes

---

### US-002: Workflow Execution Model
**Description:** As a developer, I need models to track workflow execution state and history.

**Acceptance Criteria:**
- [ ] `WorkflowExecution` struct: id (UUID), workflowId, status (pending|running|completed|failed|cancelled), startedAt, completedAt, trigger (what caused this run), stepResults[]
- [ ] `StepResult` struct: stepId, status (pending|running|success|error|skipped), startedAt, completedAt, output (String?), error (String?)
- [ ] `WorkflowExecutionStatus` enum: pending, running, completed, failed, cancelled
- [ ] All types conform to `Codable`
- [ ] Add to `daemon/Sources/LoveMeDaemon/Models/WorkflowTypes.swift`
- [ ] Typecheck passes

---

### US-003: Workflow Store (Persistence)
**Description:** As a developer, I need to persist workflow definitions and execution history to disk.

**Acceptance Criteria:**
- [ ] `WorkflowStore` actor in `daemon/Sources/LoveMeDaemon/WorkflowStore.swift`
- [ ] Workflow definitions stored as JSON files in `~/.love-me/workflows/{uuid}.json`
- [ ] Execution history stored in `~/.love-me/executions/{uuid}.json`
- [ ] CRUD operations: `create()`, `get()`, `update()`, `delete()`, `listAll()`
- [ ] `listExecutions(workflowId:)` returns execution history for a workflow
- [ ] `getExecution(id:)` returns single execution record
- [ ] `saveExecution()` persists execution state (called during execution for real-time updates)
- [ ] Auto-creates directories on first use
- [ ] Typecheck passes

---

### US-004: Workflow Scheduler (Cron Triggers)
**Description:** As a developer, I need a scheduler that fires workflows on cron schedules.

**Acceptance Criteria:**
- [ ] `WorkflowScheduler` actor in `daemon/Sources/LoveMeDaemon/WorkflowScheduler.swift`
- [ ] Parses cron expressions (minute, hour, day-of-month, month, day-of-week) — support standard 5-field cron
- [ ] On daemon startup, loads all enabled workflows with cron triggers and schedules them
- [ ] Uses Swift `Task.sleep` with calculated next-fire-date (no external dependencies)
- [ ] When cron fires, calls `WorkflowExecutor.execute(workflow:trigger:)`
- [ ] `add(workflow:)` and `remove(workflowId:)` for dynamic management
- [ ] `nextFireDate(for cronExpression:)` utility method
- [ ] Handles daemon restarts gracefully (recalculates next fire from current time)
- [ ] Typecheck passes

---

### US-005: Workflow Executor
**Description:** As a developer, I need an executor that runs workflow steps in order, passing outputs between steps via MCP tool calls.

**Acceptance Criteria:**
- [ ] `WorkflowExecutor` actor in `daemon/Sources/LoveMeDaemon/WorkflowExecutor.swift`
- [ ] Takes `WorkflowDefinition` + trigger context, creates `WorkflowExecution`
- [ ] Resolves step dependency order (topological sort for DAG)
- [ ] Steps with no dependencies can run in parallel; steps with `dependsOn` wait
- [ ] For each step: resolve `inputTemplate` variables by substituting from previous step outputs using jsonPath
- [ ] Calls `MCPManager.callTool(serverName:toolName:arguments:)` for each step
- [ ] Captures step output/error and updates `StepResult`
- [ ] Respects `onError` policy: `.stop` aborts remaining steps, `.skip` continues, `.retry` retries once
- [ ] Persists execution state to `WorkflowStore` after each step completes
- [ ] Returns completed `WorkflowExecution`
- [ ] Typecheck passes

---

### US-006: Notification Service (APNs)
**Description:** As a developer, I need to send push notifications to the iOS app when workflow events occur.

**Acceptance Criteria:**
- [ ] `NotificationService` actor in `daemon/Sources/LoveMeDaemon/NotificationService.swift`
- [ ] Sends notifications via WebSocket to connected iOS app (local push — no Apple server needed for local network)
- [ ] Falls back to `UserNotifications` framework local notifications on iOS side for when app is backgrounded
- [ ] Notification types: workflowStarted, workflowCompleted, workflowFailed, stepCompleted
- [ ] Each notification includes: workflow name, status, optional detail message
- [ ] Respects per-workflow `NotificationPrefs` (only send enabled notification types)
- [ ] WebSocket message type: `workflow_notification` with metadata for title, body, workflowId, executionId
- [ ] Typecheck passes

---

### US-007: iOS Local Notification Registration
**Description:** As a user, I want to receive push notifications even when the app is in the background.

**Acceptance Criteria:**
- [ ] Request notification permission on first launch (`UNUserNotificationCenter.requestAuthorization`)
- [ ] Register for `.alert`, `.sound`, `.badge` notification types
- [ ] Handle notification tap to deep-link to workflow execution view
- [ ] Add notification handling in `LoveMeApp.swift` (app delegate adapter or scene delegate)
- [ ] Typecheck passes
- [ ] Verify changes work in Simulator

---

### US-008: WebSocket Protocol — Workflow Messages
**Description:** As a developer, I need WebSocket message types for workflow CRUD and execution status.

**Acceptance Criteria:**
- [ ] New client → server message types: `create_workflow`, `update_workflow`, `delete_workflow`, `list_workflows`, `get_workflow`, `run_workflow`, `cancel_workflow`, `list_executions`, `get_execution`
- [ ] New server → client message types: `workflow_created`, `workflow_updated`, `workflow_deleted`, `workflow_list`, `workflow_detail`, `workflow_execution_started`, `workflow_step_update`, `workflow_execution_done`, `execution_list`, `execution_detail`, `workflow_notification`
- [ ] Add message type constants to `WebSocketMessage.swift` (both daemon and app)
- [ ] Add routing in `DaemonApp.swift` `handleMessage()` for new message types
- [ ] Typecheck passes

---

### US-009: Daemon Workflow Integration
**Description:** As a developer, I need to wire the workflow subsystem into the daemon startup and message handling.

**Acceptance Criteria:**
- [ ] `DaemonApp` initializes `WorkflowStore`, `WorkflowScheduler`, `WorkflowExecutor`, `NotificationService` on startup
- [ ] Scheduler loads all enabled cron workflows on startup
- [ ] Message handler routes workflow messages to appropriate store/executor methods
- [ ] `run_workflow` triggers immediate execution via executor
- [ ] `cancel_workflow` cancels a running execution
- [ ] Workflow execution events (step updates, completion) broadcast to all connected WebSocket clients
- [ ] Typecheck passes

---

### US-010: iOS Workflow List View
**Description:** As a user, I want to see all my workflows in a list so I can manage them.

**Acceptance Criteria:**
- [ ] New `WorkflowListView.swift` in app `Sources/Views/`
- [ ] Accessible from main navigation (new tab or sidebar section)
- [ ] Shows workflow name, trigger type (cron/event), enabled/disabled toggle, last run status
- [ ] Tap workflow to navigate to detail/edit view
- [ ] "+" button to create new workflow
- [ ] Swipe to delete workflow
- [ ] Pull to refresh
- [ ] Empty state: "No workflows yet — tap + to create one"
- [ ] Typecheck passes
- [ ] Verify changes work in Simulator

---

### US-011: iOS Workflow Editor View
**Description:** As a user, I want to create and edit workflows by defining triggers and steps.

**Acceptance Criteria:**
- [ ] New `WorkflowEditorView.swift` in app `Sources/Views/`
- [ ] Form fields: name, description, enabled toggle
- [ ] Trigger section: picker for cron or event, with appropriate fields
  - Cron: text input for expression + human-readable preview ("Every day at 9:00 AM")
  - Event: server picker, event type, optional filter key-value pairs
- [ ] Steps section: ordered list of steps, each with:
  - Step name
  - Server picker (from available MCP servers)
  - Tool picker (from selected server's tools)
  - Input fields (key-value, with option to reference previous step output as `$stepName.path`)
  - Error policy picker (stop/skip/retry)
- [ ] Add/remove/reorder steps
- [ ] Save button sends `create_workflow` or `update_workflow` via WebSocket
- [ ] Typecheck passes
- [ ] Verify changes work in Simulator

---

### US-012: iOS Workflow Execution View
**Description:** As a user, I want to see the live execution progress of a workflow run.

**Acceptance Criteria:**
- [ ] New `WorkflowExecutionView.swift` in app `Sources/Views/`
- [ ] Shows workflow name, trigger info, overall status
- [ ] Step-by-step progress: each step shows status icon (pending/running/success/error), name, duration
- [ ] Running steps show spinner animation
- [ ] Completed steps show output preview (tap to expand)
- [ ] Failed steps show error message in red
- [ ] "Run Now" button on workflow detail to trigger manual execution
- [ ] Execution history list (past runs with timestamps and status)
- [ ] Typecheck passes
- [ ] Verify changes work in Simulator

---

### US-013: iOS Notification Preferences View
**Description:** As a user, I want to control which workflow events send me push notifications.

**Acceptance Criteria:**
- [ ] Notification toggles in workflow editor: on start, on complete, on error, on each step
- [ ] Global notification settings in app Settings view: master enable/disable
- [ ] Notification permission prompt shown if not yet granted
- [ ] Toggles persist as part of workflow definition (sent to daemon)
- [ ] Typecheck passes
- [ ] Verify changes work in Simulator

---

### US-014: Workflow ViewModel
**Description:** As a developer, I need a ViewModel to manage workflow state in the iOS app.

**Acceptance Criteria:**
- [ ] New `WorkflowViewModel.swift` in app `Sources/ViewModels/`
- [ ] `@Observable` class with: `workflows: [WorkflowSummary]`, `currentWorkflow: WorkflowDefinition?`, `executions: [WorkflowExecution]`, `currentExecution: WorkflowExecution?`
- [ ] Methods: `loadWorkflows()`, `createWorkflow()`, `updateWorkflow()`, `deleteWorkflow()`, `runWorkflow()`, `loadExecutions()`, `loadExecution()`
- [ ] Handles incoming WebSocket messages: `workflow_list`, `workflow_created`, `workflow_execution_started`, `workflow_step_update`, `workflow_execution_done`, `workflow_notification`
- [ ] Wired into `LoveMeApp.swift` alongside existing `ChatViewModel`
- [ ] Typecheck passes

---

### US-015: Event Bus for MCP Event Triggers
**Description:** As a developer, I need an event system so MCP servers can emit events that trigger workflows.

**Acceptance Criteria:**
- [ ] `EventBus` actor in `daemon/Sources/LoveMeDaemon/EventBus.swift`
- [ ] MCP servers can emit events via a new `notifications/event` JSON-RPC notification (daemon listens for incoming notifications from MCP server stderr/stdout)
- [ ] Alternative: polling-based event detection — scheduler periodically calls a "check" tool on MCP servers and compares results to previous state
- [ ] `subscribe(source:eventType:handler:)` method for workflow triggers to register
- [ ] When event matches a workflow's trigger filter, calls `WorkflowExecutor.execute()`
- [ ] Event format: `{ source: "serverName", type: "eventType", data: {...} }`
- [ ] Typecheck passes

---

## Non-Goals

- **No visual DAG editor** — steps are a simple ordered list with optional dependencies (not a drag-and-drop node graph)
- **No conditional branching** — v1 workflows are linear sequences with error handling only (no if/else branches)
- **No cross-device sync** — workflows stored locally on the Mac only
- **No cloud execution** — all workflows run on the local daemon
- **No OAuth/API key management per workflow** — MCP servers handle their own auth
- **No workflow marketplace/sharing** — user creates their own workflows
- **No Apple Push Notification Service (remote APNs)** — uses local notifications + WebSocket only
- **No natural language workflow creation** — v1 uses structured form UI (Claude-assisted creation is a future enhancement)

## Technical Considerations

- **Cron parsing:** Implement a lightweight 5-field cron parser in Swift (no external dependency). Only need next-fire-date calculation, not full cron daemon.
- **Step variable resolution:** Use simple `$stepId.jsonPath` syntax. Parse step outputs as JSON and use key-path access (e.g., `$readFile.content`, `$apiCall.response.items[0].name`).
- **Execution isolation:** Each workflow execution runs in its own Task group. Cancellation propagates to in-flight MCP tool calls.
- **Storage consistency:** Existing JSON file pattern from `ConversationStore` works well. Execution files get large over time — consider a `maxExecutionHistory` config (default 100 per workflow).
- **MCP event detection:** Most MCP servers don't natively emit events. Pragmatic v1 approach: use polling with diff detection. The scheduler can run a "check" tool periodically and compare output to cached previous result.
- **Notification delivery:** WebSocket push for foreground app. `UNUserNotificationCenter` local notifications for background/closed app (daemon sends to a lightweight local notification relay, or the app schedules them based on last-known workflow state).
- **Thread safety:** All new components are Swift actors (consistent with existing daemon architecture). No shared mutable state.
- **Reuse existing infrastructure:** `MCPManager.callTool()` for step execution, `WebSocketServer` for status broadcasting, `Config` for settings.
