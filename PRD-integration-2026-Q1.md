# PRD: Solace Integration & Architecture Consolidation — Q1 2026

## Introduction

This PRD consolidates the active refactoring and integration work happening across Solace's daemon backend and iOS app. The project has completed visual redesign (Q4 2025) and is now executing on core infrastructure improvements:

1. **Email Integration Upgrade**: Replace Gmail OAuth with AgentMail REST API for simpler OAuth-free authentication
2. **MCP Transport Unification**: Consolidate MCPServerProcess (stdio) and MCPHTTPServerProcess into a unified protocol-based architecture
3. **Daemon Architecture Hardening**: Implement WorkflowQueue, ExecutorPool, and real-time state propagation for concurrent workflow execution
4. **Workflow Automation Enhancements**: Auto-fix broken workflows, multi-agent prompt refinement, and LLM tool overflow fix
5. **Audio & Ambient Features**: Background listening, ambient music, and voice recording support
6. **UI Polish & Component Extraction**: Refactor view layers with reusable components and consistent theming

This work spans both daemon (backend) and app (iOS frontend) simultaneously, with tight synchronization around WebSocket message types and shared models.

---

## Goals

### Email & Integration
- ✅ Replace Gmail OAuth with AgentMail API (simpler, no redirect flow)
- ✅ Auto-trigger workflows from email briefs using AI-generated trigger rules
- Stabilize email polling and conversation bridging
- Support email attachments (PDFs, images, documents)

### Daemon Architecture
- ✅ Implement WorkflowQueue for fair resource allocation (fix memory leaks, prevent runaway execution)
- ✅ Decouple WorkflowExecutor from DaemonApp using EventBus for cleaner separation of concerns
- Implement real-time workflow state push (WebSocket messages on step completion)
- Add workflow execution observability (queue status, execution times, retry metrics)
- Enable graceful workflow cancellation and automatic retry with exponential backoff

### MCP Transport Abstraction
- ✅ Create MCPTransport protocol to unify stdio and HTTP transport mechanisms
- ✅ Consolidate MCPServerProcess and MCPHTTPServerProcess under single protocol
- ✅ Simplify MCPManager to use single transport dictionary (not separate stdio/http storage)
- Reduce code duplication and improve maintainability
- Enable future transport types (WebSockets, IPC) without rewriting dispatch logic

### Workflow Automation
- ✅ Fix OpenAI GPT models failing due to too many tools being sent
- Implement auto-fix feature to repair broken workflows without user intervention
- Add multi-agent prompt refinement system (Claude + secondary agents improving prompts)
- Enable workflow templates and reusable step patterns

### Audio & Voice
- Add ambient listening (background voice detection, always-on microphone with permission)
- Integrate ambient music system (AI-curated background music)
- Voice recording with auto-transcription to text
- Audio playback and waveform visualization

### UI/UX
- ✅ Complete visual redesign (pastels, serif fonts, soft cards, gradient backgrounds)
- Extract reusable view components (DeckCardItemView, DeckFanCardsView, etc.)
- Consistent workflow builder UI with card deck paradigm
- Email management views (triggers, connections, conversation details)
- Settings and configuration consolidation

---

## Current Status (Uncommitted Changes)

### Modified Files (24)
| Category | Files | Status |
|----------|-------|--------|
| **Daemon Core** | DaemonApp.swift, Config.swift | Major: Email integration, API error handling |
| **Email** | AgentMailClient.swift, EmailConversationBridge.swift, EmailMCPServer.swift | Active: AgentMail API, auto-workflow triggers |
| **MCP Transport** | MCPManager.swift, MCPServerProcess.swift, MCPHTTPServerProcess.swift, MCPTypes.swift | Active: Protocol implementation, consolidation |
| **App UI** | SolaceApp.swift, multiple Views/*.swift, ViewModels | Active: Component refactoring, styling updates |
| **Models** | WebSocketMessage.swift (both), StepTemplate.swift, WorkflowTypes.swift, Theme.swift | Active: Message protocol updates, theme refinements |
| **Services** | HapticManager.swift, MarkdownRenderer.swift | Minor updates |
| **Build** | SolaceApp.xcodeproj, Info.plist | Updated bundle ID, font registrations, assets |
| **Docs** | PRD.md (visual redesign) | Completed |

### Untracked New Files (11+ directories)
| Category | Files | Purpose |
|----------|-------|---------|
| **Audio Services** | AmbientListeningManager.swift, AmbientMusicManager.swift | Voice detection, music curation |
| **UI Components** | DeckCardItemView.swift, DeckFanCardsView.swift, WorkflowBuilderWrapperView.swift | Reusable workflow builder components |
| **Email Views** | EmailDetailView.swift, EmailReplyView.swift | Email conversation UI |
| **Ambient UI** | AmbientBackgroundView.swift, AmbientListeningOverlay.swift | Background listening UI |
| **Assistant** | SpiritGuideView.swift, VoiceTabView.swift, ConversationBlockView.swift | AI guide, voice interface, chat blocks |
| **Theme** | ServerBrandConfig.swift | Brand-aware theming |
| **Glass UI** | GlassModifiers.swift | Glass-morphism effects |
| **Infrastructure** | OpenAIAPIClient.swift, PromptEnhancer.swift | Secondary LLM provider, prompt optimization |
| **MCP** | mcp-servers/ directory | Additional MCP server implementations |
| **Audio** | app/Resources/Audio/ | Audio assets for ambient features |
| **Build** | daemon/ai_newsletter.txt, app/build/ | Artifacts |

---

## User Stories (Execution Order by Dependency)

### Phase 1: Daemon Architecture Foundation (Complete the Queue & Pool)

#### US-001: Complete WorkflowQueue Actor Implementation ✅
**Description:** As a daemon, I need a bounded task queue to manage concurrent workflow executions.

**Acceptance Criteria:**
- [x] Create `WorkflowQueue` actor with max concurrent limit (currently 5)
- [x] Queue stores pending workflows with priority field
- [x] High-priority workflows (email-triggered) enqueue first
- [x] Dequeue removes oldest high-priority item when slot available
- [x] Prevent memory leaks through proper task cleanup
- [x] Typecheck passes

**Status:** COMPLETE (recent commit: "prevent memory leaks in WorkflowQueue with proper task cleanup")

#### US-002: Complete WorkflowExecutor Actor Pool ✅
**Description:** As a daemon, I want to reuse a fixed pool of executors instead of creating new ones per workflow.

**Acceptance Criteria:**
- [x] Create `WorkflowExecutor` actor pool (size: 3-5 executors)
- [x] Pool initialized on daemon startup
- [x] Decouple from DaemonApp using EventBus
- [x] Executors signal completion; queue assigns next workflow
- [x] Executor resets state between workflows
- [x] Typecheck passes

**Status:** COMPLETE (recent commit: "decouple WorkflowExecutor from DaemonApp using EventBus")

#### US-003: Implement Real-Time Workflow State Push via WebSocket
**Description:** As the daemon, I want to push state changes to connected clients (not wait for polling).

**Acceptance Criteria:**
- [ ] Add `WorkflowStateChange` message type to WebSocketMessage.swift
- [ ] When workflow state changes, daemon emits message to all connected clients
- [ ] Include workflow ID, new state, timestamp, and relevant metadata
- [ ] Clients receive and update UI without polling
- [ ] Multiple clients connected simultaneously all receive updates
- [ ] Typecheck passes

**Notes:** Foundation in place (WorkflowQueue + EventBus); now needs WebSocket integration

---

### Phase 2: MCP Transport Unification (In Progress)

#### US-004: Create MCPTransport Protocol ✅
**Description:** As the MCP manager, I need a unified protocol for transport mechanisms.

**Acceptance Criteria:**
- [x] Create `MCPTransport` protocol with core methods: `runSTDIO()`, `makeRequest()`, `shutdown()`
- [x] Ensure protocol covers both stdio and HTTP transport requirements
- [x] Typecheck passes

**Status:** COMPLETE (recent commit: "refactor: unify MCP transport implementations via MCPTransport protocol")

#### US-005: Implement MCPTransport in MCPServerProcess ✅
**Description:** As MCPServerProcess, I want to conform to MCPTransport.

**Acceptance Criteria:**
- [x] MCPServerProcess implements MCPTransport protocol
- [x] All existing methods work unchanged
- [x] Typecheck passes

**Status:** COMPLETE

#### US-006: Implement MCPTransport in MCPHTTPServerProcess ✅
**Description:** As MCPHTTPServerProcess, I want to conform to MCPTransport.

**Acceptance Criteria:**
- [x] MCPHTTPServerProcess implements MCPTransport protocol
- [x] HTTP request/response logic works unchanged
- [x] Typecheck passes

**Status:** COMPLETE

#### US-007: Unify MCPManager Storage & Dispatch ✅
**Description:** As MCPManager, I want to use a single transport dictionary instead of separate stdio/http storage.

**Acceptance Criteria:**
- [x] Replace `stdioServers` + `httpServers` dictionaries with single `servers: [String: MCPTransport]`
- [x] Update `startStdioServer()` to add to unified dictionary
- [x] Update `startHTTPServer()` to add to unified dictionary
- [x] Update tool routing logic to use unified dictionary with type checking
- [x] Update `activeServerNames`, `serverStatuses`, `getServerInfoList()` to use unified dictionary
- [x] Remove obsolete type-checking branches, consolidate shutdown logic
- [x] Typecheck passes

**Status:** COMPLETE (recent commits: "Unified Server Storage Using MCPTransport Protocol" + "Simplified Tool Routing" + "Simplified activeServerNames" + "Updated getServerInfoList" + "Simplified serverStatuses" + "Unified Server Shutdown")

---

### Phase 3: Email Integration (In Progress)

#### US-008: Replace Gmail OAuth with AgentMail API ✅
**Description:** As the daemon, I want to replace Gmail OAuth with a simpler AgentMail REST API.

**Acceptance Criteria:**
- [x] Remove Gmail OAuth2 implementation (GmailAuthService, GmailClient)
- [x] Implement AgentMailClient using REST API (api.agentmail.to/v0)
- [x] Auth via Bearer token (API key), no OAuth redirects
- [x] EmailConfig updated with: apiKey, inboxId, emailAddress, pollingIntervalSeconds
- [x] Polling service unchanged interface but uses AgentMail under the hood
- [x] Typecheck passes

**Status:** COMPLETE (recent changes: AgentMailClient.swift, EmailConversationBridge.swift updated)

#### US-009: Auto-Trigger Workflows from Email Briefs
**Description:** As the daemon, I want to automatically generate and execute workflows from email content.

**Acceptance Criteria:**
- [x] EmailConversationBridge calls `buildWorkflowFromPrompt()` on email receipt
- [x] Uses Claude to analyze email and suggest workflow steps
- [x] Automatically saves workflow to ConversationStore
- [x] Executes workflow without user confirmation
- [x] Supports email attachments as workflow input
- [ ] Verify workflow creation and execution in app
- [ ] Typecheck passes

**Status:** IMPLEMENTATION (foundation complete, testing needed)

#### US-010: Email MCP Server with AgentMail
**Description:** As Claude, I need email tools to read, search, and reply to emails via AgentMail.

**Acceptance Criteria:**
- [x] Create `EmailMCPServer` with tools: send_email, reply_to_email, search_emails, get_email
- [x] Register with MCPManager so tools appear in Claude's tool list
- [ ] Test tool invocation during workflow execution
- [ ] Handle attachments in email replies
- [ ] Typecheck passes

**Status:** IMPLEMENTATION (EmailMCPServer.swift created, integration testing needed)

---

### Phase 4: Workflow Automation & LLM Improvements (In Progress)

#### US-011: Fix OpenAI GPT Tool Overflow ✅
**Description:** As a user, I want to use OpenAI GPT models without hitting "too many tools" errors.

**Acceptance Criteria:**
- [x] Identify and fix issue where all MCP tools are sent to OpenAI (exceeds token limit)
- [x] Implement tool filtering: only send tools relevant to current step
- [x] Or implement tool summarization: group tools into categories
- [ ] Verify GPT-4 and GPT-3.5-turbo models work with large tool sets
- [ ] Typecheck passes

**Status:** TESTING (OpenAIAPIClient.swift created, needs verification)

#### US-012: Implement Auto-Fix Workflow Feature
**Description:** As a user, I want broken workflows to automatically attempt repair without manual intervention.

**Acceptance Criteria:**
- [ ] Detect workflow execution errors (API failures, missing tools, syntax errors)
- [ ] Trigger Claude to analyze error and suggest fixes
- [ ] Apply fixes (modify steps, swap tools, adjust parameters)
- [ ] Retry workflow with corrections
- [ ] Log repair attempts for user review
- [ ] Typecheck passes

**Status:** PLANNED

#### US-013: Multi-Agent Prompt Refinement System
**Description:** As a user, I want prompts continuously refined by multiple agents to improve workflow quality.

**Acceptance Criteria:**
- [ ] PromptEnhancer uses secondary Claude agents to improve step prompts
- [ ] Agents check: clarity, specificity, safety, format compliance
- [ ] Iterative refinement loop (max 3 iterations)
- [ ] Cache refined prompts to avoid recomputation
- [ ] Measure improvement (execution success rate, user feedback)
- [ ] Typecheck passes

**Status:** PLANNED (PromptEnhancer.swift skeleton created)

---

### Phase 5: Audio & Ambient Features (In Progress)

#### US-014: Ambient Listening System
**Description:** As a user, I want the app to listen for voice in the background and capture audio notes.

**Acceptance Criteria:**
- [ ] AmbientListeningManager: background microphone access with user permission
- [ ] Voice activity detection (silence vs. speech)
- [ ] Record when speech detected; stop after silence threshold
- [ ] Auto-transcribe using Whisper or on-device speech recognition
- [ ] AmbientListeningOverlay: UI showing recording status and transcript preview
- [ ] Save transcribed audio notes to conversation or workflow
- [ ] Typecheck passes
- [ ] Verify changes work in browser

**Status:** FILES CREATED, IMPLEMENTATION PENDING

#### US-015: Ambient Music System
**Description:** As a user, I want background music tailored to my task or mood.

**Acceptance Criteria:**
- [ ] AmbientMusicManager: integrates with music API or local audio library
- [ ] UI selector: mood or task-based music (focus, relax, energize)
- [ ] Playback controls: play, pause, skip, volume
- [ ] Audio fades in/out smoothly
- [ ] Remember user's last music preference
- [ ] Typecheck passes
- [ ] Verify changes work in browser

**Status:** FILES CREATED, IMPLEMENTATION PENDING

#### US-016: Voice Recording & Transcription
**Description:** As a user, I want to record voice notes and have them transcribed automatically.

**Acceptance Criteria:**
- [ ] VoiceTabView: interface for recording and playback
- [ ] Capture audio from microphone
- [ ] Display waveform during recording
- [ ] Auto-send transcribed text to chat or workflow
- [ ] Store voice notes with timestamps
- [ ] Typecheck passes
- [ ] Verify changes work in browser

**Status:** FILES CREATED, IMPLEMENTATION PENDING

---

### Phase 6: UI Components & Workflow Builder Refactoring (In Progress)

#### US-017: Extract Workflow Builder Components
**Description:** As the app, I want reusable workflow builder components (deck cards, fans) for consistency.

**Acceptance Criteria:**
- [ ] DeckCardItemView: individual card component with drag-and-drop support
- [ ] DeckFanCardsView: fan layout orchestration for multiple cards
- [ ] DeckWorkflowBuilderView: main workflow builder using deck paradigm
- [ ] All components use shared SolaceTheme styling
- [ ] Animations preserved: spring enter, drag reorder, drop remove
- [ ] Typecheck passes
- [ ] Verify changes work in browser

**Status:** ATTEMPTED, REVERTED (component extraction caused namespace issues; will retry with different approach)

#### US-018: Email Management Views
**Description:** As a user, I want to manage email connections and trigger rules from the iOS app.

**Acceptance Criteria:**
- [ ] EmailDetailView: show email content, attachments, reply history
- [ ] EmailReplyView: compose and send email replies
- [ ] EmailTriggersView: list and manage trigger rules
- [ ] Connection status indicator (connected/disconnected)
- [ ] Last poll time and email count displayed
- [ ] Typecheck passes
- [ ] Verify changes work in browser

**Status:** FILES CREATED, VIEW HIERARCHY PENDING

#### US-019: Conversation Block Component
**Description:** As the chat UI, I want structured conversation blocks with styling variants.

**Acceptance Criteria:**
- [ ] ConversationBlockView: handles user/assistant messages with proper styling
- [ ] Support for tool cards, links, and inline media
- [ ] Animations and transitions
- [ ] Dark/light mode styling
- [ ] Typecheck passes
- [ ] Verify changes work in browser

**Status:** FILES CREATED, INTEGRATION PENDING

#### US-020: Spirit Guide Visual Enhancements
**Description:** As a user, I want the 3D spirit guide to be more interactive and responsive.

**Acceptance Criteria:**
- [ ] SpiritGuideView: update colors, animations, interaction states
- [ ] Pearlescent/milky white tones in idle state
- [ ] Lavender pulse in thinking state
- [ ] Sage green glow in success state
- [ ] Drag rotation sensitivity configurable
- [ ] Typecheck passes
- [ ] Verify changes work in browser

**Status:** FILES CREATED, ANIMATION UPDATES PENDING

#### US-021: Brand Configuration System
**Description:** As the app, I want server-driven theming for multi-tenant support.

**Acceptance Criteria:**
- [ ] ServerBrandConfig: model for brand colors, fonts, logos
- [ ] Load config from daemon on app launch
- [ ] Apply theme overrides at runtime without restart
- [ ] Support light/dark mode variants
- [ ] Cache config locally
- [ ] Typecheck passes

**Status:** FILES CREATED, DAEMON INTEGRATION PENDING

---

### Phase 7: Daemon Concurrency & Observability (Planned)

#### US-022: Workflow Execution Observability
**Description:** As the daemon operator, I want visibility into background queue and execution metrics.

**Acceptance Criteria:**
- [ ] Add `/api/status` endpoint returning: queue_length, executing_count, avg_execution_time, error_rate
- [ ] Track per-workflow: execution_time, retry_count, last_error
- [ ] Log queue events: enqueue, dequeue, start, complete (structured logs)
- [ ] iOS app displays: "3 workflows queued, 2 executing, avg 2.3s"
- [ ] Typecheck passes

**Status:** PLANNED

#### US-023: Graceful Workflow Cancellation
**Description:** As a user, I want to cancel queued or running workflows.

**Acceptance Criteria:**
- [ ] iOS app: long-press workflow card → "Cancel" option
- [ ] External API: PUT `/api/executions/<id>/cancel`
- [ ] Queued workflows removed immediately
- [ ] Running workflows: send cancellation signal to executor
- [ ] Executor cleans up resources, logs cancellation
- [ ] Typecheck passes

**Status:** PLANNED

#### US-024: Automatic Retry with Exponential Backoff
**Description:** As the daemon, I want failed workflows to retry automatically with backoff.

**Acceptance Criteria:**
- [ ] On workflow error, check if retryable (network, timeout, MCP tool failure)
- [ ] Requeue with exponential backoff: 1s, 2s, 4s, 8s, 16s (max 5 retries)
- [ ] Non-retryable errors (schema mismatch, LLM context) don't retry
- [ ] Retry state tracked in execution history
- [ ] User can see retry attempt count in app ("Attempt 2/5")
- [ ] Typecheck passes

**Status:** PLANNED

---

## Non-Goals

### Explicitly Out of Scope
- Multi-provider email support (Gmail, Outlook) in v1 — AgentMail only
- Distributed daemon clustering or multi-machine execution
- Advanced workflow scheduling (cron, recurring beyond email polling)
- Email forwarding to arbitrary addresses
- Real-time email push notifications (polling is sufficient)
- Rate limiting or per-user quotas
- Machine learning-based prompt optimization (rule-based refinement only)
- Complete overhaul of existing UI layouts (only component extraction/refactoring)
- Integration with third-party cloud storage (local file storage only)

### Not Addressed in This PRD
- Mobile-only features (Apple Watch, CarPlay)
- Offline mode for iOS app
- End-to-end encryption for stored workflows/conversations
- Advanced analytics and user metrics beyond basic logging
- Admin dashboard or multi-user tenant management

---

## Technical Considerations

### Daemon Architecture
- **Actors**: Extensively used for thread safety (WorkflowQueue, WorkflowExecutor, MCPManager, ConversationStore)
- **EventBus**: Decouples components; used for workflow state changes, email events, tool results
- **WebSocket**: Real-time bidirectional communication between daemon (port 9200) and iOS app
- **Memory Management**: WorkflowQueue cleanup prevents task accumulation; executors reset state between runs

### MCP Transport Abstraction
- **MCPTransport protocol**: Single interface for all transport types (stdio, HTTP, future WebSockets)
- **Tool routing**: Simplified to check transport type and route to appropriate handler
- **Server storage**: Single dictionary `servers: [String: MCPTransport]` replaces separate dictionaries
- **Impact**: ~500 lines of code reduction through consolidation; easier to add new transports

### Email Integration
- **AgentMail API**: Replaces Gmail OAuth2; simpler token-based auth (Bearer token, API key)
- **Polling**: Configurable interval (default 60s); tracks last-seen email to avoid re-processing
- **Triggers**: Rules stored in `~/.solace/email-triggers.json`; evaluated on each email
- **Storage**: Attachments stored in `~/.solace/attachments/`; cleaned up after 30 days

### Workflow Automation
- **Tool filtering for OpenAI**: Only send relevant tools to GPT models to avoid token overflow
- **Auto-fix**: Uses Claude to analyze errors and suggest corrections
- **Prompt refinement**: Secondary agents check clarity, specificity, safety (cached for reuse)

### iOS App Integration
- **Models sync**: WebSocketMessage types must match between daemon/app
- **Theme system**: Semantic tokens (`.lavender`, `.sage`, etc.) propagated from Theme.swift
- **ViewModels**: Each VM has `handleMessage()` to receive WebSocket updates
- **Storage**: Conversations, workflows, drafts stored locally with iCloud sync

### Audio Features
- **Microphone access**: Requires explicit user permission (Info.plist, runtime request)
- **Transcription**: On-device (iOS 17+) or CloudKit Transcription
- **Waveform**: Rendered from audio samples in real-time
- **Battery**: Ambient listening paused when battery < 20%

### UI Components
- **Reusable components**: DeckCardItemView, DeckFanCardsView, ConversationBlockView extracted as standalone views
- **Animations**: Spring-based with configurable damping/stiffness; shared via SolaceTheme
- **Styling**: GlassModifiers (background, elevated, input) with radius/shadow variants
- **Dark mode**: All colors have light/dark variants in Theme.swift

### Build & Deployment
- **Daemon**: Swift Package Manager; `swift build` produces executable at `.build/release/SolaceDaemon`
- **App**: Xcode project; requires iOS 17+ for MeshGradient (fallback to radial gradient for iOS 16)
- **Config**: `~/.solace/` directory stores email.json, mcp.json, .env
- **Bonjour**: Daemon advertises as `_solace._tcp` for local network discovery

---

## Testing & Verification

### Daemon Testing
- [ ] Unit tests for WorkflowQueue (enqueue, dequeue, priority ordering)
- [ ] Unit tests for WorkflowExecutor (state reset, error handling)
- [ ] Integration tests for MCPTransport (both stdio and HTTP)
- [ ] Email polling integration tests (mock API, error scenarios)
- [ ] WebSocket message routing tests

### iOS App Testing
- [ ] Visual regression tests (gradient background, card styling, animations)
- [ ] Email views integration tests
- [ ] Audio recording and transcription flow
- [ ] Workflow builder component tests
- [ ] Dark mode and Dynamic Type tests

### End-to-End Tests
- [ ] Email receipt → auto-workflow creation → execution
- [ ] Workflow queue under concurrent load (10+ simultaneous)
- [ ] MCP tool execution (stdio and HTTP transports)
- [ ] WebSocket real-time updates (multiple clients)
- [ ] Audio recording → transcription → workflow trigger

---

## Rollout Plan

### Week 1: MCP Transport & Daemon Foundation
- Merge MCP transport unification (already complete)
- Test daemon build and WebSocket connectivity
- Verify tool routing with both stdio and HTTP servers

### Week 2: Email Integration
- Complete AgentMail API integration
- Test email polling and conversation creation
- Verify auto-workflow trigger from email briefs

### Week 3: Workflow Automation
- Verify OpenAI GPT tool filtering
- Implement auto-fix feature
- Add multi-agent prompt refinement

### Week 4: Audio Features & UI Polish
- Complete audio recording and ambient listening
- Finish UI component extraction
- Update email management views
- Test all changes in light/dark mode

### Week 5: Integration Testing & Polish
- Full end-to-end testing
- Performance profiling under load
- Bug fixes and refinement
- Documentation and user guides

---

## Success Criteria

- [ ] Daemon handles 10+ concurrent workflows without memory leaks
- [ ] Email → Workflow auto-creation completes within 5 seconds
- [ ] OpenAI GPT models work reliably with full tool set (no overflow)
- [ ] WebSocket real-time updates deliver within 100ms
- [ ] Audio recording and transcription work on iOS 17+
- [ ] All UI components extract and reuse without duplication
- [ ] 95%+ test pass rate across daemon and app
- [ ] Zero app crashes under normal usage
- [ ] Battery impact < 5% per hour with ambient listening enabled

---

## Questions for Clarification

1. **Email auth**: Should app users provide their own AgentMail API key, or delegate to daemon with shared key?
2. **Workflow auto-fix**: Should user be notified of auto-fixes, or silent auto-recovery?
3. **Audio transcription**: On-device transcription (iOS 17+) vs. CloudKit vs. Claude API?
4. **Component extraction**: Retry deck component extraction with different Namespace strategy or use inline for now?
5. **Observability**: Should `/api/status` be accessible without authentication or require Bearer token?
6. **Audio background**: Should ambient listening work in app background, or only when app is open?

---

## References

- Previous PRDs: PRD.md (visual redesign), PRD-daemon-architecture.md, PRD-email.md
- Recent commits: Unify MCP transport, prevent WorkflowQueue memory leaks, decouple WorkflowExecutor, MCP unit tests
- Memory index: 130,821 tokens spent on research/building; 115,975 token savings from reuse
- Current git status: 24 modified files, 11+ untracked directories
