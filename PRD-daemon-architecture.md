# PRD: Daemon Architecture Enhancement for Concurrent Workflow Management

## Introduction

The Solace daemon currently executes workflows independently without coordinated resource management, potentially leading to performance degradation under high concurrency. This PRD outlines improvements to the daemon's backend architecture, inspired by cmux's approach to managing parallel processes, to enable:

1. Efficient concurrent workflow execution through actor-based task pooling
2. Real-time state propagation via WebSocket push (vs. polling)
3. Full external tool integration (CLI, scripts, IDE plugins) with same control as iOS app
4. Resilient task queuing, prioritization, and resource management

## Goals

- Enable daemon to safely execute 10+ concurrent workflows without performance degradation
- Implement real-time state synchronization (push, not poll) for instant app feedback
- Build external automation API allowing CLI/scripts to trigger, monitor, and control workflows
- Reduce memory footprint through actor pooling and resource recycling
- Provide observability: monitor background task queue, execution times, resource usage

## User Stories

### US-001: Define Workflow Execution Queue
**Description:** As a daemon, I need a bounded task queue to manage concurrent workflow executions so that resources are allocated fairly and the system doesn't get overwhelmed.

**Acceptance Criteria:**
- [ ] Create `WorkflowQueue` actor with max concurrent workflow limit (e.g., 5 concurrent)
- [ ] Queue stores pending workflows with priority field (high/normal/low)
- [ ] High-priority workflows jump queue (e.g., email-triggered → high priority)
- [ ] New workflows enqueue instead of spawning unlimited tasks
- [ ] Dequeue removes oldest high-priority item when slot available
- [ ] Typecheck passes

### US-002: Implement Actor Pool for Workflow Execution
**Description:** As a daemon, I want to reuse a fixed pool of execution actors instead of creating new ones per workflow, so I conserve memory and improve performance.

**Acceptance Criteria:**
- [ ] Create `WorkflowExecutor` actor pool (size: 3-5 executors)
- [ ] Pool is initialized on daemon startup
- [ ] WorkflowQueue assigns work to available executors from pool
- [ ] Executors signal completion; queue assigns next workflow
- [ ] Executor resets state between workflows (clears temporary data)
- [ ] Typecheck passes

### US-003: Implement Real-Time Workflow State Push via WebSocket
**Description:** As the daemon, I want to push state changes to connected clients (not wait for polling) so users see updates instantly.

**Acceptance Criteria:**
- [ ] Add `WorkflowStateChange` message type (started, step_updated, completed, errored, needs_approval)
- [ ] When workflow state changes, daemon emits message to all connected clients
- [ ] Include workflow ID, new state, timestamp, and relevant metadata (current step, error details)
- [ ] Clients receive and update UI without polling
- [ ] Multiple clients connected simultaneously all receive updates
- [ ] Typecheck passes

### US-004: Create External Automation API Endpoint
**Description:** As an external tool (CLI, script, IDE plugin), I want to trigger workflows with same power as the iOS app so I can integrate Solace into my workflow.

**Acceptance Criteria:**
- [ ] Add HTTP `/api/workflows` POST endpoint (auth via API key)
- [ ] Endpoint accepts: workflow_id, parameters, priority, origin_source (cli/script/plugin)
- [ ] Returns workflow execution ID immediately (async)
- [ ] CLI can call: `solace run <workflow_id> --param foo=bar`
- [ ] Typecheck passes

### US-005: Implement External Tool Monitoring API
**Description:** As an external tool, I want to monitor a workflow's execution status so I can wait for completion or take action on errors.

**Acceptance Criteria:**
- [ ] Add HTTP `/api/executions/<id>` GET endpoint returning execution state
- [ ] Returns: status (queued/running/completed/errored), current_step, progress, result
- [ ] Add WebSocket subscription: `subscribe_execution(id)` for real-time updates
- [ ] External tool can poll or subscribe without polling the app
- [ ] Typecheck passes

### US-006: Add Workflow Priority Management
**Description:** As the daemon, I want to prioritize certain workflows (email → high, chat → normal) so important tasks execute first during backlog.

**Acceptance Criteria:**
- [ ] Email-triggered workflows default to "high" priority
- [ ] Chat-initiated workflows default to "normal" priority
- [ ] Scheduled/recurring workflows default to "low" priority
- [ ] Queue reorders on enqueue to respect priority
- [ ] User can manually override priority via iOS app (future: via CLI)
- [ ] Typecheck passes

### US-007: Implement Workflow Execution Observability
**Description:** As the daemon operator, I want visibility into background queue and execution metrics so I can monitor system health.

**Acceptance Criteria:**
- [ ] Add `/api/status` endpoint returning: queue_length, executing_count, avg_execution_time, error_rate
- [ ] Track per-workflow: execution_time, retry_count, last_error
- [ ] Log queue events: enqueue, dequeue, start, complete (structured logs)
- [ ] iOS app can display: "3 workflows queued, 2 executing, avg 2.3s"
- [ ] Typecheck passes

### US-008: Add Graceful Workflow Cancellation
**Description:** As a user/external tool, I want to cancel queued or running workflows so I can stop long-running operations.

**Acceptance Criteria:**
- [ ] iOS app: long-press workflow card → "Cancel" option
- [ ] External API: PUT `/api/executions/<id>/cancel`
- [ ] Queued workflows removed immediately
- [ ] Running workflows: send cancellation signal to executor
- [ ] Executor cleans up resources, logs cancellation
- [ ] Typecheck passes

### US-009: Implement Retry Logic with Exponential Backoff
**Description:** As the daemon, I want failed workflows to retry automatically with backoff so transient errors don't cause permanent failures.

**Acceptance Criteria:**
- [ ] On workflow error, check if retryable (network, timeout, MCP tool failure)
- [ ] Requeue with exponential backoff: 1s, 2s, 4s, 8s, 16s (max 5 retries)
- [ ] Non-retryable errors (schema mismatch, LLM context) don't retry
- [ ] Retry state tracked in execution history
- [ ] User can see retry attempt count in app ("Attempt 2/5")
- [ ] Typecheck passes

### US-010: Extend WebSocket Message Protocol for Tool Events
**Description:** As the daemon, I want to broadcast tool execution events (started, success, failure) so external tools and app can monitor MCP activity.

**Acceptance Criteria:**
- [ ] Add message type: `ToolExecutionEvent` (tool_name, arguments, result, duration, error)
- [ ] Emit when MCP tool starts and completes
- [ ] Include in workflow execution details sent to clients
- [ ] External tools can subscribe: `subscribe_tools(workflow_id)`
- [ ] Typecheck passes

### US-011: Implement Bounded Resource Limits
**Description:** As the daemon, I want to enforce memory and timeout limits per workflow so a runaway execution doesn't crash the system.

**Acceptance Criteria:**
- [ ] Each workflow execution has: max_duration (default 5 min), max_retries (default 3)
- [ ] Timeout: if workflow exceeds max_duration, executor kills it and marks errored
- [ ] Memory: monitor executor memory; if threshold exceeded, pause new queuing
- [ ] Configuration in daemon config: `maxConcurrency`, `executionTimeoutSeconds`, `memoryLimitMB`
- [ ] Typecheck passes

### US-012: Add Execution History & Persistence
**Description:** As the daemon, I want to persist execution history so workflow state survives daemon restart and users can review past executions.

**Acceptance Criteria:**
- [ ] Store execution records locally: workflow_id, status, start_time, end_time, result, error
- [ ] Persist to JSON file or SQLite (simple; no external DB)
- [ ] On startup, daemon loads recent executions (last 100)
- [ ] App queries: `get_execution_history(workflow_id, limit=20)`
- [ ] Typecheck passes

## Non-Goals

- No UI changes (visual indicators, badges, rings) in this PRD
- No authentication system (assume API key auth for external tools; scope for later)
- No distributed execution (multi-machine daemon clustering)
- No workflow dependency chains (workflow A triggers workflow B automatically)
- No advanced scheduling (cron-like recurring workflows beyond email polling)
- No rate limiting or quotas per user/app

## Technical Considerations

### Actor Architecture
- **WorkflowQueue**: Single actor managing global queue; all workflow submissions go through it
- **WorkflowExecutor**: Pool of 3-5 actors, each handles one workflow at a time
- **MCPManager**: Already an actor; no changes needed, just ensure thread-safe calls
- **LLMProvider**: Already an actor; ensure PromptEnhancer (if added) also conforms to Sendable

### WebSocket Integration
- Leverage existing `WSMessage` protocol in both daemon and app
- Add new `WSMessageType` cases: `.workflowStateChange`, `.toolExecutionEvent`, `.queueStatus`
- Broadcast messages to all connected WebSocket clients (not just the sender)

### External API
- HTTP endpoints on same daemon port (9200) or separate port (9201)?
- Auth: Bearer token from environment variable or config file
- Consider implementing as MCP server tool instead? (Allows self-serve integration)

### Migration from Current System
- Current: Workflows execute immediately on request
- New: All workflows enqueue → executor picks up
- Compatibility: iOS app continues to work; queue just adds latency (ms)

### Metrics & Monitoring
- Consider shipping structured logs (JSON) for integration with log aggregators
- Add `/api/status` health check endpoint for external monitoring

## Dependencies & Order

Stories should execute in this order:

1. **US-001, US-002** (Queue + Executor Pool) — foundation
2. **US-006** (Priority) — enhances queue
3. **US-003** (Real-time Push) — improves UX
4. **US-007** (Observability) — monitoring & debugging
5. **US-004, US-005** (External API) — external tool integration
6. **US-008, US-009** (Cancellation + Retry) — resilience
7. **US-010, US-011, US-012** (Tool Events + Limits + History) — Polish & completeness

## Success Metrics

- Daemon handles 10+ concurrent workflows without performance degradation
- App receives state updates within 100ms of daemon change (real-time push)
- External CLI tool can run `solace run <id>` and monitor execution
- Failed workflows retry automatically 80% success rate on retryable errors
- Execution history available for last 100 workflows (searchable by ID)

## Questions for Clarification

1. Should queue priority be configurable per user, or hard-coded (email > chat > scheduled)?
2. What's the max execution time before timeout? (Current: unlimited; proposed: 5 min default)
3. Should external API require authentication, or be open (localhost only)?
4. Where to persist execution history? JSON file (~500KB per 100 execs) or lightweight DB?
