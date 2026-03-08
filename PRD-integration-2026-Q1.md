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

### Phase 7: Frontend UI Implementation (In Progress)

#### US-025: Welcome Screen Serene Redesign ✅
**Description:** As a user, I want a calming welcome screen that invites me to use Solace.

**Acceptance Criteria:**
- [x] Full-gradient background (soft pink → lavender → light blue wash)
- [x] Large serif heading "Your **Solace** Awaits" (mixed weight typography)
- [x] Subtitle: "A calm space for your mind"
- [x] SpiritGuide 3D orb centered with pearlescent white/lavender tones
- [x] Feature pills/chips: "Chat", "Workflows", "Agent Mail" (tappable, soft styling)
- [x] Connection status dot (muted sage green)
- [x] Soft lavender pill-shaped CTA button
- [x] Staggered entrance animation (gentler spring, less bounce)
- [x] Typecheck passes
- [x] Verify changes work in browser

**Status:** COMPLETE (Visual redesign PRD, all stories ✅)

#### US-026: Chat Interface & Conversation Blocks ✅
**Description:** As a user, I want conversations to feel calm and spacious.

**Acceptance Criteria:**
- [x] Conversation blocks use 24pt radius cards (soft & floating)
- [x] User messages: soft lavender background at 15% opacity (not solid orange)
- [x] Assistant messages: white/surface card with no harsh borders
- [x] Remove left accent borders; use subtle lavender bar
- [x] Block divider: thin, muted, with generous vertical spacing
- [x] Toolbar: "Solace" in serif font, connection dot (sage), provider badge (soft pill)
- [x] Tool cards: soft blue border instead of coral
- [x] Thinking panel: lavender pulse animation instead of orange
- [x] "New messages" pill: lavender background instead of red
- [x] Typecheck passes

**Status:** COMPLETE (Visual redesign PRD, ConversationBlockView.swift created)

#### US-027: Input Bar & Voice Controls ✅
**Description:** As a user, I want a soft, floating input bar for seamless text and voice input.

**Acceptance Criteria:**
- [x] Input pill: warm off-white fill with subtle border
- [x] Focused state: soft lavender glow border (1pt, 40% opacity)
- [x] Send button: lavender circle with white arrow icon
- [x] Stop button: dusty rose circle with white stop icon
- [x] Mic button: soft grey circle (muted, not bright coral)
- [x] Plus/attach button: muted grey icon
- [x] Reply preview bar: lavender left accent instead of coral
- [x] Recording indicator: dusty rose dot instead of bright red
- [x] Speech waveform: lavender instead of coral
- [x] Audio playback waveform: soft gradient visualization
- [x] Typecheck passes

**Status:** COMPLETE (Visual redesign PRD, InputBar.swift updated, VoiceNotePlayerView.swift created)

#### US-028: Conversation List & Sidebar ✅
**Description:** As a user, I want the conversation sidebar to feel organized and calm.

**Acceptance Criteria:**
- [x] Conversation avatars: pastel lavender circles (not coral)
- [x] Selected conversation: lavender highlight (10% opacity)
- [x] Selected conversation ring: lavender border instead of coral
- [x] Email conversations: soft blue circles
- [x] "New Conversation" button: lavender fill, white text, pill shape
- [x] Empty state: muted lavender icon cluster
- [x] Plus toolbar button: lavender instead of coral
- [x] Smooth scroll animations
- [x] Typecheck passes

**Status:** COMPLETE (Visual redesign PRD)

#### US-029: Workflow List & Builder ✅
**Description:** As a user, I want workflow cards to feel like calm, organized task management.

**Acceptance Criteria:**
- [x] Workflow cards: 20pt radius, no colored top strip
- [x] Status icons: muted pastel functional colors (not bright)
- [x] Trigger badges: soft pastel fills
- [x] Step pipeline dots: muted sage (success), soft blue (running), dusty rose (error)
- [x] "New Workflow" button: lavender fill pill
- [x] Empty state: muted lavender icon cluster
- [x] Skeleton loading: warm beige tones
- [x] Staggered entrance animation (gentler)
- [x] DeckWorkflowBuilderView: card deck paradigm (attempted extraction, reverted)
- [x] Typecheck passes

**Status:** COMPLETE (Visual redesign PRD, components created but extraction pending)

#### US-030: Settings & Configuration Views ✅
**Description:** As a user, I want settings to match the serene aesthetic.

**Acceptance Criteria:**
- [x] Section headers: Playfair Display serif font
- [x] All coral accents → lavender throughout
- [x] Toggle tint: lavender instead of coral
- [x] Ambient music leaf icon: sage green instead of coral
- [x] Agent Mail connection icon: sage green when connected
- [x] Email approval badges: lavender counts
- [x] "Connect Agent Mail" button: lavender fill
- [x] All section tracking headers: consistent serif styling
- [x] EmailSettingsView: connection status, polling interval selector, disconnect confirmation
- [x] EmailTriggersView: list and manage email trigger rules
- [x] Typecheck passes

**Status:** COMPLETE (Visual redesign PRD, EmailSettingsView.swift and EmailTriggersView.swift created)

#### US-031: Tab Navigation & App Shell ✅
**Description:** As a user, I want smooth tab navigation with the new serene theme.

**Acceptance Criteria:**
- [x] Tab bar: translucent white/surface with blur (`.regularMaterial`)
- [x] Selected tab icon: lavender color
- [x] Unselected tab: muted grey (#8E8E93)
- [x] Selected tab text: lavender, semibold
- [x] Tab bar top border: none or subtle divider
- [x] Badge color: soft rose instead of red
- [x] Overall tint: lavender throughout
- [x] Smooth transition between tabs
- [x] Typecheck passes

**Status:** COMPLETE (Visual redesign PRD, SolaceApp.swift updated)

#### US-032: Color Palette & Theme System ✅
**Description:** As the app, I need a unified serene color palette across all screens.

**Acceptance Criteria:**
- [x] Primary accent: soft lavender #B8A9D4
- [x] Secondary: sage green #9BC5A3
- [x] Tertiary: soft rose #D4A0B0
- [x] Warm accent: cream/peach #F0DCC8
- [x] Background light: warm off-white #FAF7F5
- [x] Background dark: warm near-black #1C1B1F
- [x] Surface light: pure white #FFFFFF, dark: #262529
- [x] Text primary light: #2C2C2C, dark: #F0EDEB
- [x] Functional success: muted sage #7CB686
- [x] Functional warning: warm amber #D4A96A
- [x] Functional error: dusty rose #C47E7E
- [x] Functional info: soft blue #7EA8C4
- [x] User bubble: lavender light, deep purple dark
- [x] Code background: warm beige light, cool dark
- [x] Shimmer accent: light purple wash
- [x] Theme.swift: all semantic color tokens updated
- [x] Dark mode: all colors have muted variants
- [x] Typecheck passes

**Status:** COMPLETE (Visual redesign PRD, Theme.swift fully updated)

#### US-033: Typography & Font System ✅
**Description:** As the app, I need mixed-weight serif and sans-serif typography.

**Acceptance Criteria:**
- [x] Add Playfair Display serif font (Regular, Medium, SemiBold, Bold)
- [x] Register fonts in Info.plist UIAppFonts array
- [x] Font.playfair(size:weight:) helper in Theme.swift
- [x] Display headings: Playfair Display 44pt Medium
- [x] Display titles: Playfair Display 28pt SemiBold
- [x] Display subtitles: Playfair Display 22pt Medium
- [x] Empty state titles: Playfair Display 28pt Medium
- [x] Body/UI text: Inter (sans-serif, unchanged)
- [x] Code blocks: System Mono
- [x] Mixed-weight inline patterns: "Your personal **AI** assistant"
- [x] Dynamic Type scaling: all fonts respect user text size settings
- [x] Typecheck passes

**Status:** COMPLETE (Visual redesign PRD, fonts added, Theme.swift updated)

#### US-034: Gradient Background & Ambient Visuals ✅
**Description:** As a user, I want dreamy, organic gradient backgrounds that feel alive.

**Acceptance Criteria:**
- [x] AmbientBackgroundView: renders multi-color gradient wash
- [x] Colors: soft pink, lavender, light blue, cream (cloud-like, not linear)
- [x] Animated mode: gentle color shift (8-12 second cycle)
- [x] Static mode: reduced motion alternative (no animation)
- [x] Dark mode: deep muted gradient (purple, blue, charcoal)
- [x] Intensity levels: subtle (chat), standard (empty), prominent (welcome)
- [x] MeshGradient (iOS 18) or radial gradient composition for organic feel
- [x] Performance: minimal CPU/battery impact
- [x] Typecheck passes

**Status:** COMPLETE (Visual redesign PRD, AmbientBackgroundView.swift updated)

#### US-035: Card System & Glass Effects ✅
**Description:** As the app, I want soft, floating cards with no harsh borders.

**Acceptance Criteria:**
- [x] GlassBackgroundModifier: 20pt radius, NO border stroke, soft shadow
- [x] GlassElevatedModifier: 24pt radius, NO border, softer shadow
- [x] GlassInputModifier: 20pt radius, subtle border only when unfocused, lavender glow when focused
- [x] Theme.swift: cardRadius 12→20, bubbleRadius 18→22, inputFieldRadius 20→24, conversationBlockRadius 20→24
- [x] Shimmer modifier: updated to use new accent colors (lavender wash)
- [x] Ripple modifier: lavender tones instead of aqua
- [x] All cards feel like they float on gradient background
- [x] Typecheck passes

**Status:** COMPLETE (Visual redesign PRD, GlassModifiers.swift created/updated)

#### US-036: Email Integration Views
**Description:** As a user, I want to manage email configuration and see email-linked conversations.

**Acceptance Criteria:**
- [ ] EmailSettingsView: connection status, auth flow, polling interval selector
- [ ] EmailTriggersView: list/create/edit/delete trigger rules
- [ ] EmailDetailView: show full email content, sender, attachments, reply history
- [ ] EmailReplyView: compose and send replies with formatting
- [ ] Email origin indicator: email icon badge in conversation list
- [ ] Conversation detail header: email metadata (from, subject, received time)
- [ ] Tapping email header shows full email details
- [ ] All styled with new serene palette
- [ ] Typecheck passes
- [ ] Verify changes work in browser

**Status:** FILES CREATED, INTEGRATION PENDING

#### US-037: Spirit Guide 3D Assistant ✅
**Description:** As a user, I want the spirit guide to be a beautiful, responsive companion.

**Acceptance Criteria:**
- [x] SpiritGuideView: pearlescent/milky white tones
- [x] Idle state: soft lavender-white gradient
- [x] Thinking state: gentle lavender pulse animation
- [x] Success state: sage green glow
- [x] Tinkering particles: pastel lavender, rose, sage particles
- [x] Drag rotation: unchanged sensitivity
- [x] Interactive: responds to user touch, mouse events
- [x] Typecheck passes

**Status:** FILES CREATED, ANIMATION UPDATES PENDING

#### US-038: Audio & Ambient UI Components
**Description:** As a user, I want beautiful audio controls and listening feedback.

**Acceptance Criteria:**
- [ ] AmbientListeningOverlay: shows recording status, transcript preview, waveform
- [ ] VoiceTabView: record/playback controls, transcript display
- [ ] Audio waveform visualization: animated gradient bars
- [ ] Recording indicator: soft animation, pause/resume buttons
- [ ] Playback scrubber: smooth seek interaction
- [ ] All styled with serene palette (lavender waveforms, soft grey controls)
- [ ] Accessibility: VoiceOver support, readable text labels
- [ ] Typecheck passes
- [ ] Verify changes work in browser

**Status:** FILES CREATED, ANIMATION & INTERACTION PENDING

#### US-039: Workflow Builder Card Deck Interface
**Description:** As a user, I want an intuitive card-based workflow builder.

**Acceptance Criteria:**
- [ ] DeckWorkflowBuilderView: main interface with state management
- [ ] DeckCardItemView: individual reusable card component
- [ ] DeckFanCardsView: fan layout and orchestration
- [ ] Drag & drop reordering of steps
- [ ] Drop to remove cards (trash zone)
- [ ] Add/insert cards with animated entrance
- [ ] All cards styled with new serene palette
- [ ] Spring animations for smoothness
- [ ] Namespace animation coordination (fixed approach)
- [ ] Typecheck passes
- [ ] Verify changes work in browser

**Status:** COMPONENTS CREATED, INTEGRATION NEEDS NAMESPACE FIX

#### US-040: Server Brand Configuration
**Description:** As the daemon, I want to push brand/theme customization to the app.

**Acceptance Criteria:**
- [ ] ServerBrandConfig: model with colors, fonts, logos, brand name
- [ ] App receives config from daemon on startup
- [ ] Apply theme overrides at runtime without restart
- [ ] Support light/dark mode variants
- [ ] Cache config locally for offline use
- [ ] Theme switcher in Settings allows user override
- [ ] Typecheck passes

**Status:** FILES CREATED, DAEMON INTEGRATION PENDING

---

### Phase 8: Daemon Concurrency & Observability (Planned)

#### US-041: Workflow Execution Observability
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

## Comprehensive UI Changes Summary

### Visual Redesign (✅ COMPLETE — Q4 2025)
All 14 user stories from PRD.md completed with full implementation:

**Color System Overhaul**
- 16+ semantic color tokens defined in Theme.swift
- Serene pastel palette: lavender (#B8A9D4), sage (#9BC5A3), soft rose (#D4A0B0), warm cream (#F0DCC8)
- Muted functional colors: sage success, amber warning, dusty rose error, soft blue info
- Dark mode: all colors have warm-toned variants
- Legacy color aliases maintained for compatibility

**Typography Enhancements**
- Playfair Display serif font added (4 weights: Regular, Medium, SemiBold, Bold)
- Registered in Info.plist; Font.playfair() helper in Theme.swift
- Display headings: 44pt Medium, titles: 28pt SemiBold, subtitles: 22pt Medium
- Body text: Inter sans-serif (unchanged)
- Mixed-weight inline patterns: "Your **Solace** Awaits"
- Dynamic Type scaling for accessibility

**Component Styling Updates**
- Card corner radius: 12pt → 20-24pt (softer, more flowing)
- Shadows: darker, more prominent (make cards feel floating)
- Borders: removed from cards; input only subtle on unfocus
- Input field glow: soft lavender border (1pt, 40% opacity) when focused
- Button styling: pill-shaped, lavender fill, white text

**Views with Complete Theme Integration**
✅ WelcomeView: Full gradient background, serif headings, soft pills, centered SpiritGuide
✅ ConversationListView: Lavender avatars, selection highlights, smooth scrolling
✅ ChatView: Soft conversation blocks, lavender user bubbles, assistant white cards
✅ InputBar: Warm off-white field, lavender send button, soft grey mic/plus buttons
✅ WorkflowListView: 20pt card radius, muted status icons, soft pipeline dots
✅ SettingsView: Serif headers, lavender toggles, sage icons, soft section styling
✅ TabBar: Translucent blur material, lavender selected tab, soft grey unselected
✅ ToolCardsView: Soft blue accents instead of coral
✅ ThinkingPanel: Lavender pulse instead of orange rotation

**Animations & Motion**
- Spring animations: reduced bounce (0.15 → 0.08), increased duration (0.4s → 0.5s)
- Welcome entrance: 1.8s staggered reveal, gentler easing
- Conversation animations: slide-in with spring
- Card transitions: smooth cross-fade with scale
- Breathing dots: lavender color
- Shimmer effect: lavender/rose/blue gradient wash
- Ripple interaction: lavender tones

**Gradient & Ambient Background**
- AmbientBackgroundView: multi-color wash (soft pink → lavender → light blue → cream)
- Animated: 8-12 second color shift cycle (organic, cloud-like motion)
- Static mode: reduced motion alternative (no animation)
- Dark mode: deep purple → blue → charcoal gradient
- Intensity: subtle (chat), standard (empty), prominent (welcome)
- Performance: uses MeshGradient (iOS 18) or radial gradient composition

### Audio & Voice Features (🟢 FOUNDATION LAID)
**Files Created (Implementation Pending)**
- AmbientListeningManager.swift: Background voice detection, permission handling
- AmbientMusicManager.swift: Music selection, playback integration
- VoiceTabView.swift: Recording UI, transcript display, playback controls
- AmbientListeningOverlay.swift: Listening status, waveform visualization
- VoiceNotePlayerView.swift: Audio playback, duration formatting, scrubber interaction

**Planned UI Elements**
- Waveform visualization: animated gradient bars (lavender/rose)
- Recording controls: soft pill with record/stop buttons
- Transcript preview: live text during recording
- Playback scrubber: smooth seek with timestamp
- Audio duration display: formatted MM:SS or MM:SS:MS

### Email Integration Views (🟠 FILES CREATED, INTEGRATION PENDING)
**Views & Components**
- EmailDetailView.swift: Full email content, sender info, attachments, reply history
- EmailReplyView.swift: Reply composition, formatting toolbar, send/cancel buttons
- EmailTriggersView.swift (modified): List, create, edit, delete trigger rules
- EmailSettingsView.swift (modified): Connection status, auth flow, polling interval selector
- Email origin indicator: Email icon badge on conversation in list
- Conversation email header: From, subject, received time with metadata

**Styling**
- Email views integrated with serene palette
- Soft blue accents for email elements (separate from chat lavender)
- Attachment list: icons with names, file size, preview thumbnails
- Reply preview: quoted text in soft grey with left accent
- All styled with rounded cards, soft shadows, warm backgrounds

### Workflow Builder Components (🟠 ATTEMPTED, NEEDS NAMESPACE FIX)
**Components Created**
- DeckWorkflowBuilderView.swift: Main builder interface with state management
- DeckCardItemView.swift: Individual step card (reusable, drag-enabled)
- DeckFanCardsView.swift: Fan layout, card orchestration, drop handlers

**Features**
- Card deck paradigm: visual cards arranged in interactive layout
- Drag & drop: reorder steps, drop to remove (trash zone)
- Add/insert cards: animated entrance with spring animation
- Search/filter: find and add steps from available tools
- Card styling: 20pt radius, soft shadow, lavender accent on hover
- Animations: spring-based with coordinated entrance/exit

**Current Issue**
- Namespace animation coordination requires parent-child parameter passing
- SwiftUI limitation: @Namespace must be created in parent scope
- Temporary workaround: keep components inline in DeckWorkflowBuilderView
- Planned fix: PreferenceKey-based injection or simplified animation strategy

### Spirit Guide & 3D Assistant (🟠 ANIMATION UPDATES PENDING)
**SpiritGuideView.swift Enhancement**
- Visual states: idle (lavender-white), thinking (lavender pulse), success (sage glow)
- Particle effects: pastel lavender, rose, sage (tinkering state)
- Drag rotation: interactive with unchanged sensitivity
- Color updates: pearlescent white with gradient overlays
- Animations pending: state transition effects, pulse timing, particle physics

### Brand Configuration System (🟠 DAEMON INTEGRATION PENDING)
**ServerBrandConfig.swift Features**
- Color theme: custom primary, secondary, accent colors
- Typography: custom font selection, size multipliers
- Logo/avatar: brand identity customization
- Light/dark mode variants: separate theme per mode
- App receives config from daemon on startup
- Runtime override without restart
- Local cache for offline use

### Build & Project Configuration (✅ COMPLETE)
**Info.plist Updates**
- Bundle ID: com.love-me.app → app.solace.SolaceApp
- Display name: "Love.Me" → "Solace"
- Playfair Display font registration (4 weights)
- Microphone usage description (for voice features)
- Camera usage description (for ambient features)
- Health/motion permissions as needed

**Asset Management**
- AccentColor.colorset: Updated to #B8A9D4 (lavender)
- Audio files: app/Resources/Audio/ (ambient music, notification sounds)
- Font files: app/Resources/Fonts/PlayfairDisplay-*.ttf

**Xcode Project Updates**
- SolaceApp.xcodeproj: All new view files added to target
- Build phases: Font files embedded in app bundle
- Deployment target: iOS 17+ (iOS 18 for MeshGradient; fallback for earlier)

### Services & Utilities
**HapticManager.swift (Minor Update)**
- Haptic feedback for interactions (unchanged API)
- Used for button taps, confirmations, errors

**MarkdownRenderer.swift (Enhanced)**
- Markdown rendering in chat messages
- Link detection and styling (soft blue)
- Code block styling (warm beige background)
- Quote rendering (left accent, muted text)

---

## References

- Previous PRDs: PRD.md (visual redesign ✅), PRD-daemon-architecture.md, PRD-email.md
- Recent commits: Unify MCP transport, prevent WorkflowQueue memory leaks, decouple WorkflowExecutor, UI overhaul with welcome/builder/chat/speech
- Memory index: 130,821 tokens spent on research/building; 115,975 token savings from reuse
- Current git status: 24 modified files, 11+ untracked directories (audio, email, components, brand config)
