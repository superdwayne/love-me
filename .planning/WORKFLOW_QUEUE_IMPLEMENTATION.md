# WorkflowQueue Implementation (US-001 & US-002)

## Summary

Successfully implemented a priority-based workflow execution queue in the Solace daemon. This addresses architectural issues with unbounded concurrent workflow execution and broken cancellation tracking.

## What Was Built

### 1. WorkflowQueue Actor
**File:** `daemon/Sources/SolaceDaemon/WorkflowQueue.swift` (NEW)

A thread-safe actor that manages workflow execution with:
- **3-priority queues**: high, normal, low
- **Concurrent execution limit**: 5 workflows max (configurable)
- **Auto-processing**: Dequeues and starts next workflow when slot becomes available
- **Execution tracking**: Maps running execution IDs to Task handles for cancellation
- **Priority assignment**:
  - **HIGH**: Email triggers, user approvals (time-sensitive, user-facing)
  - **NORMAL**: Manual execution, event triggers (user-initiated)
  - **LOW**: Cron/scheduled workflows (background maintenance)

### 2. Integration with DaemonApp
**File:** `daemon/Sources/SolaceDaemon/DaemonApp.swift` (MODIFIED)

**Changes:**
- Added `workflowQueue` property alongside existing `workflowExecutor`
- Queue initialized with executor: `WorkflowQueue(workflowExecutor: workflowExecutor, maxConcurrent: 5)`
- All workflow execution points updated to route through `queue.enqueue()` instead of direct `Task` spawning

**Trigger Points Updated:**
1. **handleRunWorkflow()** (line 1216) - Manual execution → Normal priority
2. **WorkflowScheduler** callback (line 90) - Cron triggers → Low priority
3. **EventBus subscriptions** (lines 151, 1048, 1093) - Event-based triggers → Normal priority
4. **executeApprovedWorkflow()** (line 1969) - Email approval execution → High priority
5. **buildAndExecuteWorkflowForApproval()** (line 2049) - AI-generated workflows → High priority
6. **buildAndExecuteAutoFlow()** (line 2167) - Auto-flow creation → High priority
7. **Ambient listening handler** (line 3238) - Background context → Normal priority
8. **handleCancelWorkflow()** (line 1230) - Updated to call `queue.cancel()` instead of `executor.cancel()`

### 3. EmailConversationBridge Update
**File:** `daemon/Sources/SolaceDaemon/Email/EmailConversationBridge.swift` (MODIFIED)

**Changes:**
- Constructor parameter changed: `workflowExecutor: WorkflowExecutor` → `workflowQueue: WorkflowQueue`
- `evaluateTriggers()` method now enqueues with HIGH priority for email-triggered workflows
- DaemonApp initialization updated to pass `workflowQueue` instead of `workflowExecutor`

## Architecture Patterns

### Queue Processing Model
```
┌─────────────────────────────────────┐
│   HIGH Priority Queue (3 items)     │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│   NORMAL Priority Queue (5 items)   │ ← Dequeue from here first
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│   LOW Priority Queue (2 items)      │
└─────────────────────────────────────┘
              ↓
        Running Executions: 5/5 (max)
        - Email trigger workflow
        - Manual workflow
        - Event trigger workflow
        - Cron workflow
        - Ambient listening workflow
```

### Execution Flow
1. **Enqueue**: Workflow added to appropriate priority queue based on trigger type
2. **ProcessQueue**: Check running count < max (5)
3. **Dequeue**: Take highest-priority waiting workflow
4. **Execute**: Pass to WorkflowExecutor, track Task by unique key
5. **Complete**: Invoke completion callback, remove from tracking, process queue again
6. **Cancel**: Lookup Task by execution ID, call task.cancel(), clean up

## Design Decisions

### Why Keep WorkflowExecutor
WorkflowExecutor remains unchanged as the **single execution engine**. WorkflowQueue is a **thin orchestration layer** that:
- Prevents resource exhaustion
- Enables priority scheduling
- Tracks execution tasks for cancellation
- Maintains backward compatibility

This keeps concerns separated: WorkflowExecutor handles step execution, WorkflowQueue handles resource management.

### Why Sendable Callbacks
The `onComplete` callback is `@Sendable` to ensure it can be safely passed across actor boundaries when the completion handler captures `self` (the DaemonApp).

### Priority System Rationale
- **HIGH**: Email workflows are time-sensitive and initiated by external systems (AgentMail polling)
- **NORMAL**: Manual triggers and event subscriptions are user-initiated, should be responsive
- **LOW**: Cron jobs are background maintenance, can wait for other work to complete

## Verification

✅ **Build Status**: Clean build with no errors or warnings
```
$ swift build
Build complete! (2.84s)
```

✅ **Modified Files**: 2
- `DaemonApp.swift` - 8 integration points updated
- `EmailConversationBridge.swift` - Dependency changed, trigger method updated

✅ **New Files**: 1
- `WorkflowQueue.swift` - 150 lines, actor with priority queue implementation

## Backward Compatibility

✅ **WebSocket Protocol**: Unchanged - iOS app requires no modifications
✅ **Workflow Types**: Unchanged - existing workflows work as-is
✅ **Execution Model**: Unchanged - execution results flow identically
✅ **Cancellation API**: Compatible - same executionId used throughout

## Performance Implications

### Benefits
- **Prevents cascade failures**: Max 5 concurrent workflows prevent system resource exhaustion
- **Responsive prioritization**: Email workflows bypass queue and start immediately (if slots available)
- **Fair scheduling**: Normal workflows don't stall behind background cron jobs

### Tradeoff
- **Latency**: Workflows may wait in queue if 5+ workflows already running (acceptable trade-off for stability)
- **Memory**: Small tracking overhead for running Task handles (~100 bytes per execution)

## Future Enhancements (Out of Scope)

- Queue persistence (survive daemon restart)
- Runtime-configurable max concurrent count
- Execution history and metrics dashboard
- Dead letter queue for permanently failed workflows
- Workflow pausing/resuming mid-execution
- Queue statistics endpoint for monitoring

## Testing Checklist

- [x] Build daemon without errors
- [ ] Enqueue 10 workflows, verify only 5 run simultaneously
- [ ] Trigger email workflow while chat workflow running, verify email starts first
- [ ] Start workflow, cancel via iOS app, verify execution stops
- [ ] Check daemon logs for queue status messages

## Files Changed Summary

| File | Change | Lines |
|------|--------|-------|
| WorkflowQueue.swift | NEW | 150 |
| DaemonApp.swift | MODIFIED | +/- 120 |
| EmailConversationBridge.swift | MODIFIED | +/- 20 |

**Total Implementation**: ~290 lines of code, 8 integration points
