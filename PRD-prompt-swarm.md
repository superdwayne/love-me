# PRD: Workflow Prompt Enhancement Swarm

## Introduction

Currently, when a user creates a workflow, their description is sent as a single prompt to `buildWorkflowFromPrompt()`, which makes one LLM call to generate the workflow JSON. This works but produces brittle workflows from vague descriptions — the AI guesses at tool parameters, misses edge cases, and can't research the user's actual environment.

This feature introduces a **multi-agent prompt enhancement pipeline** that transforms a rough user description into a robust, research-backed prompt before it reaches the workflow builder. Agents research available tools via MCP, decompose vague instructions into specific actions, critique the plan for gaps, and synthesize a detailed final prompt — all transparently on the daemon side.

## Goals

- Transform vague workflow descriptions into detailed, actionable prompts that produce better workflows
- Use MCP tools during enhancement to research real context (file structures, API capabilities, available data)
- Run a multi-agent pipeline: Research → Decompose → Critique → Synthesize
- Store both original and enhanced prompts on the workflow for debugging/learning
- Keep the enhancement invisible to the user — they describe a workflow and get a better result

## User Stories

### US-001: Add enhanced prompt storage to WorkflowDefinition
**Description:** As a developer, I need to store the original user prompt and the enhanced prompt on each workflow so the system can learn and debug.

**Acceptance Criteria:**
- [ ] Add `originalPrompt: String?` field to `WorkflowDefinition` in `WorkflowTypes.swift`
- [ ] Add `enhancedPrompt: String?` field to `WorkflowDefinition` in `WorkflowTypes.swift`
- [ ] Both fields are optional and default to nil (backward compatible with existing workflows)
- [ ] Both fields are Codable — existing saved workflows decode without error
- [ ] `buildWorkflowFromPrompt` sets both fields on the returned `WorkflowDefinition`
- [ ] `swift build` succeeds

### US-002: Create PromptEnhancer actor with Research agent
**Description:** As a developer, I need a `PromptEnhancer` actor that runs the first agent in the pipeline — a Research agent that uses MCP tools to gather context relevant to the user's workflow description.

**Acceptance Criteria:**
- [ ] New file `daemon/Sources/SolaceDaemon/PromptEnhancer.swift` with `actor PromptEnhancer`
- [ ] `PromptEnhancer` accepts an `LLMProvider` and an `MCPManager` reference
- [ ] Research agent receives the user prompt + tool catalog and returns structured research findings
- [ ] Research agent can call MCP tools via `mcpManager.callTool()` to gather live context (e.g., listing directories, checking API endpoints, reading configs)
- [ ] Research is bounded: max 5 tool calls per enhancement to avoid runaway costs
- [ ] Research agent's LLM call uses a system prompt that instructs it to gather context, not build the workflow
- [ ] Returns a `ResearchResult` struct with `findings: String` and `toolsUsed: [String]`
- [ ] `swift build` succeeds

### US-003: Add Decomposer agent to PromptEnhancer
**Description:** As a developer, I need a Decomposer agent that takes the user prompt + research findings and breaks the workflow into explicit, unambiguous steps with specific tool selections and parameter values.

**Acceptance Criteria:**
- [ ] New method `decompose(prompt:research:toolCatalog:)` on `PromptEnhancer`
- [ ] Decomposer receives: original prompt, research findings, full tool catalog
- [ ] Decomposer LLM call produces a structured breakdown: ordered steps, each with tool name, server name, specific parameter values, and rationale
- [ ] Decomposer resolves ambiguity — if the user said "search the web", it picks the specific search tool and fills in the query
- [ ] Output is a `DecompositionResult` with `steps: [StepBreakdown]` where each has `toolName`, `serverName`, `inputs`, `rationale`
- [ ] `swift build` succeeds

### US-004: Add Critic agent to PromptEnhancer
**Description:** As a developer, I need a Critic agent that reviews the decomposed plan and identifies gaps, missing error handling, incorrect tool usage, or missing steps.

**Acceptance Criteria:**
- [ ] New method `critique(prompt:decomposition:toolCatalog:)` on `PromptEnhancer`
- [ ] Critic receives: original prompt, decomposition result, tool catalog
- [ ] Critic LLM call identifies: missing steps, wrong tool choices, incomplete parameters, data flow gaps between steps, edge cases
- [ ] Critic can flag issues as `critical` (must fix) or `suggestion` (nice to have)
- [ ] Output is a `CritiqueResult` with `issues: [CritiqueIssue]` each having `severity`, `description`, `affectedStep`, `suggestion`
- [ ] If no issues found, returns empty issues array (pipeline continues without re-decomposition)
- [ ] `swift build` succeeds

### US-005: Add Synthesizer agent and full pipeline orchestration
**Description:** As a developer, I need a Synthesizer agent that combines all prior agent outputs into a single, highly detailed prompt, and I need the full pipeline wired together as one `enhance()` method.

**Acceptance Criteria:**
- [ ] New method `synthesize(prompt:research:decomposition:critique:)` on `PromptEnhancer`
- [ ] Synthesizer produces a detailed natural language prompt that includes: specific tool names, parameter values, step ordering, data flow between steps, error handling notes, and context from research
- [ ] The synthesized prompt is what gets passed to `buildWorkflowFromPrompt()` instead of the raw user input
- [ ] Top-level `enhance(prompt:)` method orchestrates the full pipeline: research → decompose → critique → synthesize
- [ ] If critique has critical issues, re-run decompose with critique feedback (max 1 retry to prevent loops)
- [ ] Pipeline returns an `EnhancementResult` with `enhancedPrompt: String`, `research: ResearchResult`, `decomposition: DecompositionResult`, `critique: CritiqueResult`
- [ ] `swift build` succeeds

### US-006: Integrate PromptEnhancer into DaemonApp workflow generation
**Description:** As a user, when I describe a workflow, the system should automatically enhance my prompt before generating the workflow — producing better results without any changes to my experience.

**Acceptance Criteria:**
- [ ] `DaemonApp` creates and holds a `PromptEnhancer` instance (initialized with `llmProvider` and `mcpManager`)
- [ ] `buildWorkflowFromPrompt()` calls `promptEnhancer.enhance(prompt:)` before the existing workflow generation LLM call
- [ ] The enhanced prompt replaces the raw user prompt in the workflow generation system prompt's user message
- [ ] The returned `WorkflowDefinition` has `originalPrompt` set to the user's raw input and `enhancedPrompt` set to the synthesizer output
- [ ] All existing callers of `buildWorkflowFromPrompt` (WS handler, email bridge, auto-flow) benefit automatically
- [ ] If enhancement fails for any reason, fall back to the original prompt (no degradation)
- [ ] `swift build` succeeds
- [ ] Daemon starts and can generate workflows

### US-007: Add enhancement logging for observability
**Description:** As a developer, I need to see what the swarm is doing so I can debug and tune the agents.

**Acceptance Criteria:**
- [ ] Each agent phase logs start/completion via `Logger.info` (e.g., "PromptEnhancer: Research phase started", "PromptEnhancer: Research found 3 relevant tools")
- [ ] Research agent logs which MCP tools it called and a summary of findings
- [ ] Total enhancement time is logged at completion
- [ ] Errors in any agent phase are logged via `Logger.error` with the phase name
- [ ] Log output is concise — no dumping full prompts/responses, just summaries
- [ ] `swift build` succeeds

## Non-Goals

- No UI changes — the swarm is invisible to the user (daemon-side only)
- No user-facing toggle between "quick" and "enhanced" modes (all workflows get enhanced)
- No persistent learning across workflows — each enhancement is independent
- No parallel agent execution — agents run sequentially (research → decompose → critique → synthesize)
- No streaming of agent progress to the app
- No changes to the workflow execution engine or step execution logic

## Technical Considerations

### Architecture
- **Single new file:** `daemon/Sources/SolaceDaemon/PromptEnhancer.swift` keeps the entire swarm self-contained
- **Actor model:** `PromptEnhancer` is an actor for thread safety, consistent with codebase patterns (`MCPManager`, `AgentMailClient`, etc.)
- **All agent prompts live in the actor** as static/computed properties for easy tuning

### LLM Costs
- The pipeline adds 4-5 `singleRequest` calls per workflow generation:
  1. Research agent (+ up to 5 MCP tool calls)
  2. Decomposer agent
  3. Critic agent
  4. (Optional) Re-decompose if critical issues found
  5. Synthesizer agent
  6. Final `buildWorkflowFromPrompt` generation call (existing)
- All use `singleRequest` (non-streaming) — no UI updates needed

### MCP Tool Access
- Research agent needs `mcpManager.callTool(serverName:toolName:arguments:)` to invoke tools
- The research agent LLM decides which tools to call based on the tool catalog
- Implementation: research agent returns tool call requests, `PromptEnhancer` executes them and feeds results back in a multi-turn loop (bounded at 5 turns)

### Fallback Safety
- If any agent throws, catch and return the original prompt unchanged
- Never let enhancement failure prevent workflow creation
- Log the failure for debugging

### Backward Compatibility
- New `WorkflowDefinition` fields (`originalPrompt`, `enhancedPrompt`) are optional with nil defaults
- Existing saved workflow JSON files decode without error
- No changes to WebSocket message types or app-side code

### Existing Code Reuse
- `buildWorkflowFromPrompt` already builds a `toolCatalog` string — extract and share with `PromptEnhancer` to avoid duplicate work
- `LLMProvider.singleRequest` is the only LLM interface needed
- `MCPManager.callTool` is the only MCP interface needed
