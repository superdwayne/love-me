# PRD: Multi-Provider Agent Swarm Orchestration

## Introduction

Enable the Solace daemon to decompose complex natural language requests into structured agent plans, then execute them as a swarm of parallel autonomous agents — each with its own LLM provider, conversation context, and scoped MCP tools. The system resolves a dependency DAG, launches independent agents concurrently, streams per-agent progress over WebSocket, and feeds completed agent outputs into downstream dependents. Agents can recursively spawn sub-agents when they discover tasks need further decomposition.

The iOS app provides plan review/approval, agent editing (reassign models, add/remove agents), and a live agent dashboard showing DAG execution in real-time.

### Problem

Today, Solace handles complex multi-tool requests in a single Claude conversation turn. This is sequential, uses one model for everything (expensive if using Opus), and can't parallelize independent sub-tasks. A request like "Research competitors, generate a logo, and create social templates" runs tools one at a time in a single context window that grows linearly.

### Solution

A planning layer that decomposes requests into an agent DAG, assigns cost-optimal providers per agent (Haiku for research, Sonnet for creative, Opus for complex reasoning, Ollama for private data, OpenAI for diversity), and executes independent agents in parallel via Swift TaskGroups. Each agent is an isolated multi-turn conversation with scoped tools.

## Goals

- Decompose complex requests into parallel agent plans with dependency resolution
- Assign cost-optimal LLM providers per agent based on task complexity
- Support Claude (Haiku/Sonnet/Opus), OpenAI (GPT-4o/mini), and Ollama (any local model) in the same plan
- Execute independent agents concurrently (up to configurable limit)
- Stream real-time per-agent progress to the iOS app over WebSocket
- Allow users to review, edit, and approve plans before execution
- Support recursive sub-agent spawning with cost guardrails
- Feed completed agent outputs as context into downstream dependent agents

## User Stories

---

### US-001: Agent Plan Data Models (Daemon)

**Description:** As a developer, I need the core data structures for agent plans so that all other components have a shared type system to build on.

**New file:** `daemon/Sources/SolaceDaemon/Models/AgentPlanTypes.swift`

**Acceptance Criteria:**
- [ ] `AgentProviderSpec` struct with `provider` enum (`.claude(model:)`, `.ollama(model:)`, `.openai(model:)`), `thinkingBudget: Int?`, `maxTokens: Int`, `temperature: Double?`
- [ ] `AgentProviderSpec` conforms to `Codable, Sendable`
- [ ] `AgentTask` struct with fields: `id: String`, `name: String`, `objective: String`, `systemPrompt: String`, `requiredTools: [String]`, `requiredServers: [String]`, `dependsOn: [String]?`, `maxTurns: Int`, `providerSpec: AgentProviderSpec`, `outputSchema: JSONValue?`
- [ ] `AgentPlan` struct with fields: `id: String`, `name: String`, `description: String`, `agents: [AgentTask]`, `createdFrom: String?` (original prompt), `estimatedCost: Double?`, `created: Date`
- [ ] `AgentExecution` struct with fields: `id: String`, `planId: String`, `planName: String`, `status: AgentExecutionStatus`, `startedAt: Date`, `completedAt: Date?`, `agentResults: [AgentResult]`, `parentAgentId: String?` (for nesting), `totalCost: Double?`
- [ ] `AgentExecutionStatus` enum: `.pending`, `.running`, `.completed`, `.failed`, `.cancelled`
- [ ] `AgentResult` struct with fields: `agentId: String`, `agentName: String`, `status: AgentResultStatus`, `provider: String`, `model: String`, `startedAt: Date?`, `completedAt: Date?`, `output: String?`, `error: String?`, `turnCount: Int`, `toolCallCount: Int`, `childExecutionId: String?` (for nesting)
- [ ] `AgentResultStatus` enum: `.pending`, `.running`, `.success`, `.error`, `.cancelled`, `.spawning` (for sub-agent creation)
- [ ] All types conform to `Codable, Sendable`
- [ ] `swift build` succeeds

---

### US-002: ClaudeAPIClient Model Override

**Description:** As a developer, I need the Claude API client to accept a model override so that different agents can use different Claude models (Haiku, Sonnet, Opus) without changing the global config.

**Modifies:** `daemon/Sources/SolaceDaemon/ClaudeAPIClient.swift`

**Acceptance Criteria:**
- [ ] Add `private let modelOverride: String?` property
- [ ] Update `init` to accept `modelOverride: String? = nil` parameter (backward compatible)
- [ ] `modelName` computed property returns `modelOverride ?? config.claudeModel`
- [ ] `streamRequest` uses `modelName` instead of `config.claudeModel` in `ClaudeRequest`
- [ ] `singleRequest` uses `modelName` instead of `config.claudeModel` in `ClaudeRequest`
- [ ] Add `thinkingBudgetOverride: Int?` parameter to allow per-agent thinking budget control
- [ ] Existing call sites unchanged (default nil preserves current behavior)
- [ ] `swift build` succeeds

---

### US-003: ProviderPool Actor

**Description:** As a developer, I need a factory that creates LLMProvider instances on demand so that the orchestrator can spin up providers for each agent task independently.

**New file:** `daemon/Sources/SolaceDaemon/ProviderPool.swift`

**Acceptance Criteria:**
- [ ] `ProviderPool` is an `actor`
- [ ] `init(config: DaemonConfig)` stores daemon config for API keys and endpoints
- [ ] `func provider(for spec: AgentProviderSpec) -> any LLMProvider` returns the correct provider:
  - `.claude(model)` creates `ClaudeAPIClient(config:, modelOverride: model)`
  - `.ollama(model)` creates `OllamaAPIClient(endpoint:, model:, apiKey:)`
  - `.openai(model)` creates `OpenAIAPIClient(model:, apiKey:)`
- [ ] Throws a clear error if required API key is missing for the requested provider
- [ ] `func availableProviders() -> [String]` returns list of configured providers (e.g. `["claude", "ollama", "openai"]`) based on which API keys are present
- [ ] `swift build` succeeds

---

### US-004: WebSocket Message Types for Agent Plans

**Description:** As a developer, I need WebSocket message type constants for the full plan lifecycle so that daemon and app can communicate about plans and agent progress.

**Modifies:** `daemon/Sources/SolaceDaemon/Models/WebSocketMessage.swift` (daemon) and `app/Sources/Models/WebSocketMessage.swift` (app — must stay in sync)

**Acceptance Criteria:**
- [ ] Add to `WSMessageType` — Client to Server (Agent Plans):
  - `planApprove = "plan_approve"`
  - `planReject = "plan_reject"`
  - `planEdit = "plan_edit"` (user modifies agents/models before approving)
  - `planCancel = "plan_cancel"` (cancel running plan)
  - `planList = "plan_list"`
  - `planGetExecution = "plan_get_execution"`
- [ ] Add to `WSMessageType` — Server to Client (Agent Plans):
  - `planGenerated = "plan_generated"` (plan ready for review)
  - `planExecutionStarted = "plan_execution_started"`
  - `agentStarted = "agent_started"`
  - `agentProgress = "agent_progress"` (text streaming from agent)
  - `agentThinking = "agent_thinking"` (thinking deltas)
  - `agentToolStart = "agent_tool_start"`
  - `agentToolDone = "agent_tool_done"`
  - `agentCompleted = "agent_completed"`
  - `agentFailed = "agent_failed"`
  - `agentSpawning = "agent_spawning"` (sub-agent creation)
  - `providerFallback = "provider_fallback"` (provider failed, falling back)
  - `planExecutionDone = "plan_execution_done"`
  - `planListResult = "plan_list_result"`
  - `planExecutionDetail = "plan_execution_detail"`
- [ ] Both daemon and app `WebSocketMessage.swift` files contain identical additions
- [ ] `swift build` succeeds (daemon)
- [ ] App project builds in Xcode

---

### US-005: AgentPlanStore Actor

**Description:** As a developer, I need persistent storage for agent plans and their executions so that plan history survives daemon restarts.

**New file:** `daemon/Sources/SolaceDaemon/AgentPlanStore.swift`

**Acceptance Criteria:**
- [ ] `AgentPlanStore` is an `actor`
- [ ] `init(plansDirectory: String, executionsDirectory: String)` creates directories if needed
- [ ] `func savePlan(_ plan: AgentPlan) async throws` persists plan as JSON to `{plansDirectory}/{plan.id}.json`
- [ ] `func getPlan(_ id: String) async -> AgentPlan?` loads from disk
- [ ] `func listPlans() async -> [AgentPlan]` returns all plans sorted by creation date descending
- [ ] `func deletePlan(_ id: String) async throws` removes plan file
- [ ] `func saveExecution(_ execution: AgentExecution) async throws` persists execution state
- [ ] `func getExecution(_ id: String) async -> AgentExecution?` loads execution
- [ ] `func updateExecution(_ id: String, mutate: (inout AgentExecution) -> Void) async throws` atomic update + persist
- [ ] `func listExecutions(planId: String?) async -> [AgentExecution]` filtered listing
- [ ] Uses ISO8601 date encoding consistent with existing WorkflowStore
- [ ] `swift build` succeeds

---

### US-006: AgentOrchestrator — Core DAG Execution

**Description:** As a developer, I need an orchestrator that resolves agent dependencies and executes independent agents in parallel using Swift TaskGroups.

**New file:** `daemon/Sources/SolaceDaemon/AgentOrchestrator.swift`

**Acceptance Criteria:**
- [ ] `AgentOrchestrator` is an `actor`
- [ ] `init(providerPool: ProviderPool, mcpManager: MCPManager, planStore: AgentPlanStore)` stores dependencies
- [ ] `func execute(plan: AgentPlan, onUpdate: @Sendable (AgentUpdate) async -> Void) async throws -> AgentExecution` is the main entry point
- [ ] `AgentUpdate` enum covers all progress events: `.agentStarted`, `.agentProgress(text:)`, `.agentThinking(text:)`, `.agentToolStart(tool:)`, `.agentToolDone(tool:result:)`, `.agentCompleted(output:)`, `.agentFailed(error:)`, `.providerFallback(from:to:reason:)`, `.agentSpawning(childPlan:)`
- [ ] Topological sort of agents using Kahn's algorithm (reuse pattern from WorkflowExecutor)
- [ ] Detects circular dependencies and throws an error before execution
- [ ] Launches independent agents (no unresolved dependencies) concurrently via `withTaskGroup`
- [ ] Waits for each wave to complete before launching next wave of unblocked agents
- [ ] Configurable `maxConcurrentAgents: Int` (default 5) to limit parallel API calls
- [ ] Stores completed agent outputs in `[String: String]` dictionary for downstream context injection
- [ ] Checks `Task.isCancelled` between agent launches for cancellation support
- [ ] Creates and persists `AgentExecution` via `planStore` throughout lifecycle
- [ ] `swift build` succeeds

---

### US-007: AgentOrchestrator — Single Agent Runner

**Description:** As a developer, I need the orchestrator to run individual agents as isolated multi-turn conversations with scoped MCP tools.

**Modifies:** `daemon/Sources/SolaceDaemon/AgentOrchestrator.swift`

**Acceptance Criteria:**
- [ ] `private func runAgent(_ task: AgentTask, context: String, onUpdate:) async -> String` method
- [ ] Creates provider instance via `providerPool.provider(for: task.providerSpec)`
- [ ] Filters MCP tools to only `task.requiredTools` via `mcpManager.getToolDefinitions()`
- [ ] If provider doesn't support tools (`supportsTools == false`) but task requires tools, injects tool descriptions into system prompt as structured text fallback
- [ ] Builds system prompt with: task objective, task system prompt, context from upstream agents
- [ ] Runs multi-turn conversation loop: stream response, collect tool calls, execute tools, loop until no tool calls or `maxTurns` reached
- [ ] Streams agent progress events via `onUpdate` callback during conversation
- [ ] Executes MCP tool calls via `mcpManager.callTool(name:arguments:)`
- [ ] Returns final text output from agent
- [ ] Handles provider errors with fallback: catches errors, emits `.providerFallback` event, retries with Claude Sonnet as default fallback
- [ ] `swift build` succeeds

---

### US-008: AgentOrchestrator — Recursive Sub-Agent Spawning

**Description:** As a developer, I need agents to be able to spawn sub-agents when they discover a task needs further decomposition, with cost guardrails.

**Modifies:** `daemon/Sources/SolaceDaemon/AgentOrchestrator.swift`

**Acceptance Criteria:**
- [ ] Add `spawn_agents` as a built-in tool available to agents (like `create_workflow` pattern)
- [ ] `spawn_agents` tool schema accepts: `name: String`, `description: String`, `agents: [AgentTask]` (array of sub-agent definitions)
- [ ] When an agent calls `spawn_agents`, orchestrator intercepts the tool call (same pattern as `create_workflow` interception in DaemonApp)
- [ ] Creates a child `AgentPlan` with `parentAgentId` set to the spawning agent's ID
- [ ] Recursively calls `execute(plan:onUpdate:)` for the child plan
- [ ] Child plan results aggregated and returned as the tool result to the parent agent
- [ ] `maxNestingDepth: Int` (default 3) prevents infinite recursion — agents at max depth do not get the `spawn_agents` tool
- [ ] `maxTotalAgents: Int` (default 20) across the entire execution tree prevents cost blowout
- [ ] Emits `.agentSpawning(childPlan:)` update event when sub-agents are created
- [ ] Child execution linked via `AgentExecution.parentAgentId` and `AgentResult.childExecutionId`
- [ ] `swift build` succeeds

---

### US-009: `create_plan` Built-in Tool

**Description:** As a developer, I need Claude to be able to generate agent plans during conversation by calling a `create_plan` tool, following the same interception pattern as `create_workflow`.

**Modifies:** `daemon/Sources/SolaceDaemon/DaemonApp.swift`

**Acceptance Criteria:**
- [ ] Add `create_plan` to the built-in tools injected in `streamLLMResponse()` alongside `create_workflow`
- [ ] Tool schema: `name: String` (plan name), `description: String`, `agents: [object]` where each agent object has: `name`, `objective`, `requiredTools: [String]`, `requiredServers: [String]`, `dependsOn: [String]?`, `provider: String` (e.g. "claude:haiku", "openai:gpt-4o", "ollama:llama3"), `maxTurns: Int?`
- [ ] When Claude calls `create_plan`, intercept in the tool execution switch (before MCP routing)
- [ ] Parse the tool input into an `AgentPlan` with `AgentProviderSpec` derived from the provider string format `"provider:model"`
- [ ] Default `maxTurns` to 10 if not specified, default `thinkingBudget` based on model tier
- [ ] Save plan via `agentPlanStore.savePlan()`
- [ ] Broadcast `plan_generated` WebSocket message with full plan details in metadata
- [ ] Return tool result: `"Plan generated and sent to user for approval. Plan ID: {id}"`
- [ ] Do NOT auto-execute — wait for `plan_approve` from client
- [ ] System prompt includes guidance on when to use `create_plan` vs handling inline: use it when the request involves 3+ distinct tools, multiple MCP servers, or tasks that can be parallelized
- [ ] `swift build` succeeds

---

### US-010: Plan Approval and Execution WebSocket Handlers

**Description:** As a developer, I need WebSocket handlers for plan approval, rejection, editing, and cancellation so the app can control plan lifecycle.

**Modifies:** `daemon/Sources/SolaceDaemon/DaemonApp.swift`

**Acceptance Criteria:**
- [ ] Handle `plan_approve` message: load plan from store, start execution via orchestrator, broadcast `plan_execution_started`
- [ ] Orchestrator `onUpdate` callback maps `AgentUpdate` events to corresponding WebSocket broadcasts (`agent_started`, `agent_progress`, `agent_tool_start`, `agent_tool_done`, `agent_completed`, `agent_failed`, `provider_fallback`, `agent_spawning`)
- [ ] Each broadcast includes `metadata` with: `planId`, `executionId`, `agentId`, `agentName`, plus event-specific data
- [ ] Handle `plan_reject` message: delete plan from store, broadcast acknowledgment
- [ ] Handle `plan_edit` message: parse edited plan from message content/metadata, validate, update in store, broadcast updated `plan_generated` with revised plan
- [ ] Handle `plan_cancel` message: cancel the running execution task, set execution status to `.cancelled`, broadcast `plan_execution_done` with cancelled status
- [ ] Handle `plan_list` message: return recent plans and executions via `plan_list_result`
- [ ] Handle `plan_get_execution` message: return execution detail via `plan_execution_detail`
- [ ] Active plan executions tracked in `activeExecutionTasks: [String: Task<Void, Never>]` (same pattern as `activeGenerationTasks`)
- [ ] `swift build` succeeds

---

### US-011: DaemonApp Wiring — Initialize Swarm Components

**Description:** As a developer, I need the DaemonApp to instantiate and wire together the ProviderPool, AgentPlanStore, and AgentOrchestrator on startup.

**Modifies:** `daemon/Sources/SolaceDaemon/DaemonApp.swift`

**Acceptance Criteria:**
- [ ] Add `private let providerPool: ProviderPool` property
- [ ] Add `private let agentPlanStore: AgentPlanStore` property
- [ ] Add `private let agentOrchestrator: AgentOrchestrator` property
- [ ] Add `private var activeExecutionTasks: [String: Task<Void, Never>] = [:]` property
- [ ] Initialize `providerPool` with `config` in DaemonApp `init` or `start()`
- [ ] Initialize `agentPlanStore` with `"{basePath}/agent-plans"` and `"{basePath}/agent-executions"` directories
- [ ] Initialize `agentOrchestrator` with `providerPool`, `mcpManager`, `agentPlanStore`
- [ ] Add `agent-plans` and `agent-executions` to `config.ensureDirectories()` or create separately
- [ ] Route new `plan_*` message types in `handleMessage` switch to appropriate handler methods
- [ ] `swift build` succeeds

---

### US-012: Agent Plan Models (iOS App)

**Description:** As a developer, I need the iOS app to have matching model types for agent plans so it can parse WebSocket messages and display plan data.

**New file:** `app/Sources/Models/AgentPlanTypes.swift`

**Acceptance Criteria:**
- [ ] Mirror all types from daemon's `AgentPlanTypes.swift`: `AgentProviderSpec`, `AgentTask`, `AgentPlan`, `AgentExecution`, `AgentResult`, and all associated enums
- [ ] Types conform to `Codable` (no need for `Sendable` on app side since using `@Observable`)
- [ ] Add computed helpers: `AgentProviderSpec.displayName` (e.g. "Claude Haiku"), `AgentProviderSpec.providerIcon` (SF Symbol name)
- [ ] Add `AgentPlan.dependencyWaves` computed property that returns `[[AgentTask]]` — agents grouped into parallel execution waves based on dependency resolution
- [ ] Add `AgentExecution.activeAgentCount` computed property
- [ ] App builds in Xcode

---

### US-013: AgentPlanViewModel

**Description:** As a developer, I need a view model to manage agent plan state in the iOS app, handling WebSocket messages and exposing reactive state for SwiftUI views.

**New file:** `app/Sources/ViewModels/AgentPlanViewModel.swift`

**Acceptance Criteria:**
- [ ] `@Observable class AgentPlanViewModel`
- [ ] Published state: `currentPlan: AgentPlan?`, `currentExecution: AgentExecution?`, `agentStreams: [String: String]` (agentId to accumulated text), `agentThinking: [String: String]` (agentId to thinking text), `showPlanReview: Bool`, `isExecuting: Bool`
- [ ] `func handleMessage(_ msg: WSMessage)` routes all `plan_*` and `agent_*` message types
- [ ] `plan_generated` handler: parse plan from metadata, set `currentPlan`, set `showPlanReview = true`
- [ ] `agent_started` handler: update corresponding `AgentResult` status to `.running`
- [ ] `agent_progress` handler: append text delta to `agentStreams[agentId]`
- [ ] `agent_thinking` handler: append to `agentThinking[agentId]`
- [ ] `agent_tool_start` / `agent_tool_done` handler: track tool call state per agent
- [ ] `agent_completed` handler: update result status to `.success`, store output
- [ ] `agent_failed` handler: update result status to `.error`, store error
- [ ] `agent_spawning` handler: track child plan creation
- [ ] `plan_execution_done` handler: set `isExecuting = false`, store final execution
- [ ] `func approvePlan()` sends `plan_approve` WebSocket message
- [ ] `func rejectPlan()` sends `plan_reject` WebSocket message
- [ ] `func cancelExecution()` sends `plan_cancel` WebSocket message
- [ ] App builds in Xcode

---

### US-014: Plan Review & Approval Sheet (iOS App)

**Description:** As a user, I want to review a generated agent plan before it executes so I can verify the approach, see cost estimates, and understand which AI models will be used.

**New file:** `app/Sources/Views/PlanReviewSheet.swift`

**Acceptance Criteria:**
- [ ] Presented as a `.sheet` when `viewModel.showPlanReview == true`
- [ ] Header shows plan name and description
- [ ] Shows estimated cost breakdown by provider tier (if available)
- [ ] Displays agents grouped by dependency wave (parallel groups visually grouped)
- [ ] Each agent card shows: name, objective (truncated), provider badge (e.g. "Haiku" in blue, "Opus" in purple, "GPT-4o" in green, "Ollama" in gray), required tools as chips, dependency arrows or "depends on: Agent X" labels
- [ ] "Approve" button calls `viewModel.approvePlan()` and dismisses sheet
- [ ] "Reject" button calls `viewModel.rejectPlan()` and dismisses sheet
- [ ] "Edit Plan" button navigates to editing view (US-015)
- [ ] Uses `SolaceTheme` colors and glass modifiers consistent with existing app style
- [ ] App builds in Xcode

---

### US-015: Plan Editing View (iOS App)

**Description:** As a user, I want to edit an agent plan before approving — reassign models, modify objectives, add or remove agents — so I have full control over what runs.

**New file:** `app/Sources/Views/PlanEditView.swift`

**Acceptance Criteria:**
- [ ] Full-screen view navigated from PlanReviewSheet
- [ ] List of agents, each expandable to edit: name, objective (text field), provider picker (dropdown: Claude Haiku / Claude Sonnet / Claude Opus / GPT-4o / GPT-4o-mini / Ollama models), max turns (stepper), required tools (multi-select from available MCP tools)
- [ ] Dependency editor: each agent shows "depends on" as selectable chips of other agent names
- [ ] "Add Agent" button appends a new agent task with defaults (Sonnet, 10 turns, no dependencies)
- [ ] Swipe-to-delete removes an agent (with warning if other agents depend on it)
- [ ] "Save & Approve" sends `plan_edit` then `plan_approve` WebSocket messages
- [ ] "Save Draft" sends `plan_edit` only (returns to review sheet)
- [ ] Validates no circular dependencies before saving (show alert if detected)
- [ ] App builds in Xcode

---

### US-016: Agent Dashboard — Live Execution View (iOS App)

**Description:** As a user, I want to see a live dashboard of all running agents so I can monitor progress, see which agents are active, and track the overall plan execution.

**New file:** `app/Sources/Views/AgentDashboardView.swift`

**Acceptance Criteria:**
- [ ] Presented automatically when plan execution starts (after approval)
- [ ] Top bar shows: plan name, overall progress (e.g. "3/8 agents complete"), elapsed time
- [ ] Agent cards arranged in dependency wave rows (wave 1 agents in first row, wave 2 in second, etc.)
- [ ] Each agent card shows: name, status indicator (gray=pending, blue pulse=running, green=done, red=failed, orange=spawning), provider badge, elapsed/completed time
- [ ] Running agents show a streaming text preview (last ~100 chars from `agentStreams`)
- [ ] Running agents show tool call activity (current tool name with spinner)
- [ ] Completed agents show checkmark with output preview
- [ ] Failed agents show error message with red highlight
- [ ] Tap an agent card to navigate to agent detail view (US-017)
- [ ] "Cancel" button in nav bar calls `viewModel.cancelExecution()`
- [ ] Auto-scrolls or highlights newly active agents
- [ ] App builds in Xcode

---

### US-017: Agent Detail View (iOS App)

**Description:** As a user, I want to tap into a specific agent to see its full conversation, tool calls, and output so I can understand what it did and debug issues.

**New file:** `app/Sources/Views/AgentDetailView.swift`

**Acceptance Criteria:**
- [ ] Header shows: agent name, provider + model, status, duration
- [ ] Scrollable conversation view showing the agent's streamed text output
- [ ] Tool call cards inline (similar to existing `ToolCard` component): tool name, input preview, result preview, duration, success/error indicator
- [ ] If agent has thinking content, show expandable thinking panel (reuse `ThinkingPanel` pattern)
- [ ] If agent spawned sub-agents, show a "Sub-agents" section with mini cards linking to the child execution's dashboard
- [ ] Final output section at bottom with full text, copy button
- [ ] If agent failed, show error prominently with the full error message
- [ ] If provider fallback occurred, show a notice: "Switched from {original} to {fallback}: {reason}"
- [ ] App builds in Xcode

---

### US-018: Wire AgentPlanViewModel into SolaceApp

**Description:** As a developer, I need the agent plan view model wired into the app's message routing and view hierarchy so plan events flow from WebSocket to UI.

**Modifies:** `app/Sources/App/SolaceApp.swift`, `app/Sources/Views/ContentView.swift`

**Acceptance Criteria:**
- [ ] Instantiate `AgentPlanViewModel` in `SolaceApp` alongside other view models
- [ ] Route `plan_*` and `agent_*` WebSocket messages to `agentPlanVM.handleMessage(msg)` in the `onMessage` closure
- [ ] Pass `agentPlanVM` to `ContentView` via environment or parameter
- [ ] `ContentView` presents `PlanReviewSheet` when `agentPlanVM.showPlanReview == true`
- [ ] `ContentView` navigates to `AgentDashboardView` when `agentPlanVM.isExecuting == true`
- [ ] Agent plan VM can send WebSocket messages via the shared `WebSocketManager` (same pattern as other VMs)
- [ ] App builds in Xcode

---

### US-019: Plan Generation System Prompt

**Description:** As a developer, I need the daemon's system prompt to guide Claude on when and how to use `create_plan` effectively, including model assignment heuristics.

**Modifies:** `daemon/Sources/SolaceDaemon/DaemonApp.swift` (system prompt construction in `streamLLMResponse`)

**Acceptance Criteria:**
- [ ] When `create_plan` tool is available, append guidance to system prompt explaining:
  - Use `create_plan` when the request involves 3+ distinct MCP tools, multiple servers, or parallelizable sub-tasks
  - Do NOT use `create_plan` for simple single-tool requests or conversational responses
  - Model assignment rules: `claude:haiku` for research/search/parsing, `claude:sonnet` for writing/code/creative, `claude:opus` for complex multi-step reasoning, `ollama:{model}` for private/local data, `openai:gpt-4o` for alternative perspective or specific strengths
  - Always set dependencies correctly — research agents before synthesis agents, data gathering before analysis
  - Keep agent objectives specific and actionable (not vague)
  - Include available MCP tool names grouped by server so Claude can assign tools accurately
- [ ] Include the list of available providers from `providerPool.availableProviders()` so Claude only assigns providers that are configured
- [ ] `swift build` succeeds

---

### US-020: Integration Test — End-to-End Plan Flow

**Description:** As a developer, I need to verify the full plan lifecycle works: generation, review, approval, parallel execution, and completion.

**Acceptance Criteria:**
- [ ] Daemon builds and runs: `cd daemon && swift build && .build/debug/SolaceDaemon`
- [ ] Send a `user_message` that triggers plan creation (e.g. "Research the latest AI news, generate a summary image, and create a social media post")
- [ ] Verify `plan_generated` WebSocket message received with valid plan structure
- [ ] Verify plan contains multiple agents with appropriate provider assignments
- [ ] Send `plan_approve` message
- [ ] Verify `plan_execution_started` received
- [ ] Verify `agent_started` messages received for first wave of agents
- [ ] Verify `agent_progress` / `agent_tool_start` / `agent_tool_done` messages stream during execution
- [ ] Verify `agent_completed` messages received as agents finish
- [ ] Verify dependent agents start only after their dependencies complete
- [ ] Verify `plan_execution_done` received with all agent outputs
- [ ] iOS app displays plan review sheet, agent dashboard updates in real-time
- [ ] `swift build` succeeds

## Non-Goals

- **No automatic execution without approval** — all plans require explicit user approval, no auto-execute threshold
- **No persistent agent memory** — agents do not remember previous plans or executions; each is stateless
- **No inter-agent real-time communication** — agents cannot message each other during execution; they only receive upstream outputs via context injection at start
- **No custom provider plugins** — only Claude, OpenAI, and Ollama are supported initially; no plugin system for adding arbitrary LLM providers
- **No cost billing or metering** — estimated costs are informational only, no hard budget enforcement or spending limits
- **No agent marketplace or sharing** — plans are local to the user, no import/export or community sharing
- **No workflow-to-plan migration** — existing sequential workflows remain as-is; no automatic conversion to agent plans

## Technical Considerations

- **Existing patterns to reuse:** Kahn's topological sort from `WorkflowExecutor`, tool interception pattern from `create_workflow`, `onUpdate` callback pattern from workflow step broadcasting, `activeGenerationTasks` cancellation pattern
- **Actor isolation:** All new components (`ProviderPool`, `AgentPlanStore`, `AgentOrchestrator`) must be actors for thread safety, consistent with existing codebase
- **WebSocket message format:** Use existing `WSMessage` structure with `metadata: [String: MetadataValue]` for all plan/agent data — no structural changes to the message protocol
- **Models must stay in sync:** Daemon `AgentPlanTypes.swift` and App `AgentPlanTypes.swift` must have identical type definitions (same pattern as `WebSocketMessage.swift`)
- **MCP tool scoping:** Use `mcpManager.getToolDefinitions()` filtered by `requiredTools` — agents only see tools they need, reducing prompt token usage
- **Provider fallback chain:** If assigned provider fails, fall back to Claude Sonnet (the default). If Claude Sonnet also fails, report error — don't cascade further
- **Sub-agent cost guardrails:** `maxNestingDepth` and `maxTotalAgents` are the primary controls; these should be configurable via `~/.solace/agent-config.json` in a future iteration
- **Persistence paths:** Plans stored at `~/.solace/agent-plans/`, executions at `~/.solace/agent-executions/`, following existing pattern from workflows
