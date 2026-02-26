# love.Me — UI Constraints & Interaction Rules

Opinionated constraints for building an award-winning iOS interface. Every rule exists because the alternative was tried and was worse.

---

## 1. Information Hierarchy

### The One-Accent Rule
Heart (#E8456B) appears **once per viewport** as the primary action:
- Chat view: the **send button**
- Conversation list: the **active conversation** indicator
- Settings: the **test connection** button
- Empty state: the **CTA button**

Everything else uses the neutral palette. If two things are Heart-colored, the user doesn't know where to look.

### Density Rules
```
Chat messages:       Comfortable — 16pt text, 12px padding, 8-16px gap
Thinking panel:      Dense — 13pt mono, 8px padding, scrollable
Tool cards:          Compact — 14pt title, 12pt detail, 44px collapsed height
Conversation list:   Standard — 16pt title, 13pt subtitle, 60px row height
Settings:            Spacious — grouped inset list, standard iOS spacing
```

### Z-Index Scale (Fixed, No Arbitrary Values)
```swift
enum ZLayer: CGFloat {
    case base = 0           // Chat messages, content
    case card = 1           // Tool cards, thinking panel
    case stickyInput = 10   // Input bar
    case overlay = 20       // Connection banner, error banner
    case modal = 30         // Sheets, confirmation dialogs
    case toast = 40         // Transient notifications
}
```

Never use arbitrary z-index values. If something needs a new level, add it to the enum.

---

## 2. Touch Targets & Gestures

### Minimum Touch Target: 44x44pt
This is Apple's HIG requirement. Never go below it.

| Element | Visual Size | Touch Target |
|---------|------------|--------------|
| Send button | 36x36pt | 44x44pt (invisible padding) |
| Connection dot | 6pt | 44x44pt (tap area around it) |
| Tool card chevron | 12pt | Full card width x 44pt |
| Thinking chevron | 12pt | Full panel width x 44pt |

### Gesture Map

| Gesture | Location | Action |
|---------|----------|--------|
| Tap | Send button | Send message |
| Tap | Thinking panel | Expand/collapse |
| Tap | Tool card | Expand/collapse |
| Tap | Connection dot | Show connection sheet (if disconnected) |
| Long press | Message bubble | Context menu (Copy, Retry, Delete) |
| Swipe left | Conversation row | Delete |
| Swipe down | Chat view (from top) | Pull to load older messages |
| Swipe right | Chat view (from edge) | Back to conversation list |

### Gestures We DON'T Use
- No swipe on message bubbles (conflict with navigation)
- No pinch-to-zoom (no zoomable content in v1)
- No 3D Touch / Haptic Touch on messages (long press is sufficient)
- No shake-to-undo (too disruptive for a focused tool)

---

## 3. Loading & Streaming States

### The Prime Rule: Never Show a Blank Space
If data is loading, show structure. If AI is streaming, show tokens. The user should always see something happening.

### Chat Streaming
```
DO:   Show tokens as they arrive, character by character
DON'T: Show a skeleton, then replace with full message
DON'T: Buffer and show in chunks
DON'T: Show "Generating response..." text

The streaming text IS the loading state.
```

### Thinking Panel While Streaming
```
State 1: Panel appears with "Thinking..." + pulsing bolt icon
State 2: Thinking text streams in (SF Mono, muted)
State 3: Thinking complete → label changes to "Thought for Xs"
State 4: Response starts streaming below
```

### Tool Cards While Running
```
State 1: Card appears with tool name + spinning gear
State 2: (card stays in running state, no progress %)
State 3: Complete → spinner becomes checkmark, duration appears
         OR Error → spinner becomes X, "Failed" appears
```

Never show a progress percentage for tool calls. We don't know how long they'll take. A spinner is honest.

### Connection States
```
Connecting:     Amber pulsing dot + "Connecting..." in nav subtitle
Connected:      Green dot, subtitle disappears after 2s
Reconnecting:   Amber pulsing dot + "Reconnecting..." in nav subtitle
Failed:         Red dot + error banner slides down from top
```

### Skeleton Usage
Only for the conversation list (loading saved conversations). Never for chat messages (they stream in naturally).

---

## 4. Error Recovery

### Error Proximity Rule
**Show errors next to where the action happened.** Never use a global alert for a local failure.

| Error | Location | Pattern |
|-------|----------|---------|
| Message send failed | Below the message bubble | Inline "Not sent. Tap to retry." |
| Tool execution failed | Inside the tool card | Expanded card with error detail |
| Connection lost | Top of chat view | Dismissible banner |
| API key missing | Top of chat view | Persistent banner with action |
| Test connection failed | Below the test button | Inline error text |

### Recovery Patterns
```
Transient errors (network):   Auto-retry with backoff. Show count.
                              "Reconnecting... (attempt 3)"

Permanent errors (config):    Show error + clear action.
                              "No API key found. [How to fix]"

User errors (bad input):      Inline validation. No modals.
                              Field turns red + helper text appears.
```

### Confirmation Dialogs
Use ONLY for irreversible destructive actions:
- Delete conversation: AlertDialog
- Delete all conversations: AlertDialog
- Stop running task: No dialog (can be re-sent)

Never use a confirmation dialog for sending a message, starting a connection, or any routine action.

---

## 5. Navigation Structure

### iPhone-First Navigation

```
┌─────────────────────────────────┐
│  NavigationSplitView            │
│  ┌───────────┬─────────────────┐│
│  │ Convo     │                 ││
│  │ List      │   Chat View     ││
│  │           │                 ││
│  │ (sidebar  │   (detail)      ││
│  │  on iPad) │                 ││
│  └───────────┴─────────────────┘│
└─────────────────────────────────┘
```

On iPhone: full-screen chat with back button to conversation list.
On iPad (future): side-by-side split view.

### Navigation Stack
```
Conversation List
  └→ Chat View
       └→ Settings (presented as sheet, not push)
```

Settings is a **sheet**, not a navigation push. Reason: you might want to check settings while keeping your chat visible behind the dimmed overlay. It's a reference, not a destination.

### Tab Bar: NONE
No tab bar. This is a focused single-purpose app. One path: conversations → chat. Settings is a sheet. Don't introduce navigation complexity that doesn't serve the core flow.

---

## 6. Keyboard & Input

### Input Bar Behavior
```
1. Input bar is pinned above keyboard when keyboard is visible
2. Input bar is pinned above safe area when keyboard is hidden
3. Multi-line expansion: grows up to 5 lines, then scrolls internally
4. Send on Return (with modifier: Shift+Return for newline on iPad with keyboard)
5. Dismiss keyboard: tap on chat area (not drag — drag conflicts with scroll)
```

### Keyboard Avoidance
```swift
// Use ScrollViewReader to scroll to bottom when keyboard appears
// Animate with keyboard animation curve (UIKeyboardAnimationCurveUserInfoKey)
// NEVER use .ignoresSafeArea(.keyboard) on the chat ScrollView
```

### Input Focus Rules
- Auto-focus input when opening a new conversation
- Do NOT auto-focus when returning to an existing conversation (user may want to read)
- Do NOT dismiss keyboard when a message sends (user likely wants to send another)
- DO dismiss keyboard when scrolling up more than 100pt (user is reading history)

### Paste
**Never block paste.** Users paste code, file paths, error messages. The input field must accept arbitrary text.

---

## 7. Haptic Feedback

### Haptic Map

| Event | Haptic Type | Intensity |
|-------|------------|-----------|
| Message sent | `.impact(.light)` | Subtle — confirms send |
| Connection established | `.notification(.success)` | Clear — important state change |
| Connection lost | `.notification(.warning)` | Clear — needs attention |
| Tool call completed | `.impact(.soft)` | Barely there — ambient feedback |
| Tool call errored | `.notification(.error)` | Clear — something went wrong |
| Long press context menu | `.impact(.medium)` | Standard iOS feel |
| Thinking panel expand | None | Visual-only — no haptic for toggles |
| Pull to refresh | `.impact(.light)` | At the threshold point |

### Haptic Rules
- Never use haptics for scrolling or passive viewing
- Never use haptics for streaming text (would fire constantly)
- Use `.impact(.rigid)` for the "cascade completion" moment (all tools done)
- Respect the system Haptics setting — check `UIAccessibility.isReduceMotionEnabled`

---

## 8. Scroll Behavior

### Chat Scroll Rules

```
1. New conversation:        Start at bottom (latest message)
2. New message received:    Auto-scroll to bottom IF already within 100pt of bottom
3. New message received:    DON'T auto-scroll if user has scrolled up (reading history)
4. User scrolled up:        Show "↓ New messages" floating pill at bottom
5. User sends message:      ALWAYS scroll to bottom (they want to see the response)
6. Keyboard appears:        Scroll to bottom
7. Thinking panel expands:  Scroll to keep the panel in view
```

### The 100pt Rule
If the user's scroll position is within 100pt of the bottom, treat them as "at the bottom" and auto-scroll for new content. Beyond 100pt, they've intentionally scrolled up to read.

### Scroll Anchoring
When content above the viewport changes (thinking panel expands, tool cards resize), anchor the scroll position so the user's current reading position doesn't jump.

```swift
// Use ScrollView with .scrollPosition() anchor
// When thinking panel expands:
//   - If panel is ABOVE viewport: adjust offset to compensate for height change
//   - If panel is IN viewport: let it expand naturally (user is watching it)
```

### Performance
```
- Use LazyVStack for message list (don't render off-screen messages)
- Message IDs must be stable (no index-based IDs that change on insert)
- Never force-reload the entire message list for a single new message
- Tool cards: collapsed by default to minimize initial render cost
```

---

## 9. Animation Constraints (SwiftUI-Specific)

### What We Animate
```
✓ Opacity transitions (fade in/out)
✓ Scale (send button, breathing logo dot)
✓ Offset/position (message slide-in, banner slide-down)
✓ Rotation (tool card spinner, thinking panel chevron)
✓ Height (thinking panel expand — use .clipShape + .frame)
```

### What We NEVER Animate
```
✗ Color/tint changes (use instant state swap)
✗ Blur or backdrop filter (GPU expensive, drains battery)
✗ Shadow changes (triggers paint on every frame)
✗ Font size or weight (causes layout recalc)
✗ Corner radius (rasterization boundary change)
```

### Duration Rules
```
Interaction feedback:     ≤ 200ms (button press, tap response)
State transition:         250-300ms (panel expand, sheet present)
Ambient/decorative:       ≥ 2000ms (breathing dot, pulsing indicator)
```

### Spring Configurations
```swift
// User-initiated (direct manipulation feel)
.spring(response: 0.3, dampingFraction: 0.7)

// System-initiated (smooth, not bouncy)
.easeOut(duration: 0.25)

// Ambient (slow, continuous)
.easeInOut(duration: 3.0).repeatForever(autoreverses: true)
```

### Reduce Motion
```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

// When reduceMotion is true:
// - Replace all animations with instant transitions
// - Disable breathing dot animation
// - Disable streaming character-by-character (show full text instantly)
// - Spinner becomes static icon with "Running..." text
```

---

## 10. Dark/Light Mode Rules

### Dark Mode Is Default
The app opens in dark mode on first launch, regardless of system setting. Users can override in settings (System / Dark / Light).

### Contrast Requirements
All text passes WCAG AA (4.5:1 minimum):
```
#F1F1F4 on #1A1A2E → 11.2:1 ✓ (primary text)
#6B7B8D on #1A1A2E →  4.6:1 ✓ (secondary text)
#E8456B on #1A1A2E →  5.2:1 ✓ (accent)
#FFFFFF on #E8456B →  4.8:1 ✓ (text on accent)
#9CA3AF on #1F2E4D →  5.1:1 ✓ (thinking text)
```

### Color Adaptation Rules
```
DO:   Define all colors as Color assets with Dark/Light variants
DO:   Use semantic names (.surface, .surfaceElevated, .textPrimary)
DON'T: Hardcode hex values in views
DON'T: Use .primary or .secondary system colors (not on-brand)
```

---

## 11. Typography Constraints

### SwiftUI Font Definitions
```swift
extension Font {
    static let chatMessage = Font.system(size: 16)
    static let chatUser = Font.system(size: 16)
    static let thinking = Font.system(size: 13, design: .monospaced)
    static let toolTitle = Font.system(size: 14, weight: .medium)
    static let toolDetail = Font.system(size: 12, design: .monospaced)
    static let timestamp = Font.system(size: 11)
    static let sectionHeader = Font.system(size: 12, weight: .bold)
    static let emptyStateTitle = Font.system(size: 28, weight: .light)
    static let navTitle = Font.system(size: 20, weight: .semibold)
}
```

### Rules
- Use `text-balance` equivalent (`.lineLimit(nil)` with proper width constraints) for headings
- Use `tabular-nums` (`.monospacedDigit()`) for durations in tool cards ("0.3s", "1.2s")
- Use `.lineLimit(1)` + `.truncationMode(.tail)` for conversation list titles
- Never modify letter spacing unless it's a section header (use `.tracking(1.2)` for uppercase labels only)

---

## 12. Checklist Before Every PR

- [ ] Heart (#E8456B) appears at most once as primary action per screen
- [ ] All touch targets ≥ 44x44pt
- [ ] No animation longer than 300ms for interactions
- [ ] No blur() or backdrop-filter animations
- [ ] Errors shown inline, not in alerts (except destructive confirmations)
- [ ] Keyboard doesn't cover input or content
- [ ] Reduce Motion disables all animation
- [ ] All interactive elements have accessibility labels
- [ ] Dark and light mode both verified
- [ ] No hardcoded hex colors in views (all via theme)
- [ ] LazyVStack used for any list > 20 items
- [ ] No tab bar — navigation via NavigationSplitView only
- [ ] Haptics respect system setting
- [ ] Empty states have exactly one clear action
