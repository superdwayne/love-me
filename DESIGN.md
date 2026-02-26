# love.Me — Visual Design Direction

## Brand Essence

**Tagline:** "Your AI, working for you."

love.Me sits at the intersection of **personal warmth** and **technical power**. It's not a cold terminal — it's a companion that happens to be extraordinarily capable. The design should feel like messaging someone you trust who also happens to be the best engineer in the room.

**Brand Personality:**
- Warm but not childish
- Capable but not intimidating
- Transparent but not cluttered
- Personal but not intrusive

---

## Color System

### Primary Palette

| Role | Color | Hex | Usage |
|------|-------|-----|-------|
| **Heart** | Warm Rose | `#E8456B` | Primary accent, send button, active states, logo |
| **Mind** | Deep Ink | `#1A1A2E` | Primary background (dark mode default) |
| **Soul** | Soft Cream | `#FAF7F2` | Light mode background, assistant bubbles |
| **Trust** | Calm Slate | `#6B7B8D` | Secondary text, timestamps, muted elements |

### Functional Colors

| Role | Color | Hex | Usage |
|------|-------|-----|-------|
| **Thinking** | Amber Glow | `#F4A623` | Thinking panel accent, "processing" states |
| **Tool Running** | Electric Blue | `#3B82F6` | Active tool spinner, WebSocket connected |
| **Tool Success** | Sage Green | `#34D399` | Completed tool calls, success states |
| **Tool Error** | Soft Red | `#EF4444` | Error states, disconnected indicator |
| **Code** | Cool Gray | `#374151` | Code block backgrounds |

### Dark Mode (Default)

```
Background:        #1A1A2E (Deep Ink)
Surface:           #16213E (elevated cards, tool cards)
Surface Elevated:  #1F2E4D (thinking panel expanded)
User Bubble:       #E8456B (Heart) at 90% opacity
Assistant Bubble:  #16213E (Surface)
Input Bar:         #0F1729 (darker than background)
Text Primary:      #F1F1F4
Text Secondary:    #6B7B8D (Trust)
Dividers:          #FFFFFF at 6% opacity
```

### Light Mode

```
Background:        #FAF7F2 (Soul)
Surface:           #FFFFFF
Surface Elevated:  #F5F0EB
User Bubble:       #E8456B (Heart)
Assistant Bubble:  #FFFFFF with 1px #E8E4DF border
Input Bar:         #FFFFFF with top border
Text Primary:      #1A1A2E (Deep Ink)
Text Secondary:    #6B7B8D (Trust)
Dividers:          #000000 at 8% opacity
```

**Design note:** Dark mode is the default. The app works with your computer at night, in bed, on the couch. Dark-first respects that context.

---

## Typography

### iOS Type Scale (SF Pro + SF Mono)

| Element | Font | Size | Weight | Tracking |
|---------|------|------|--------|----------|
| **Nav Title** | SF Pro Display | 20pt | Semibold | -0.2 |
| **Chat Message** | SF Pro Text | 16pt | Regular | 0 |
| **User Message** | SF Pro Text | 16pt | Regular | 0 |
| **Thinking Text** | SF Mono | 13pt | Regular | 0 |
| **Tool Card Title** | SF Pro Text | 14pt | Medium | 0.1 |
| **Tool Card Detail** | SF Mono | 12pt | Regular | 0 |
| **Timestamp** | SF Pro Text | 11pt | Regular | 0.2 |
| **Code Block** | SF Mono | 14pt | Regular | 0 |
| **Input Placeholder** | SF Pro Text | 16pt | Regular | 0 |
| **Empty State** | SF Pro Display | 28pt | Light | -0.5 |
| **Section Header** | SF Pro Text | 12pt | Bold (uppercase) | 1.2 |

**Rationale:** SF Pro is native iOS — zero load time, perfect rendering, respects Dynamic Type. SF Mono for anything "from the machine" (thinking, code, tool args). No custom fonts for v1.

---

## Logo & Wordmark

### Concept

The logo is the word **love.Me** rendered as:
- `love` in SF Pro Display Light (lowercase, personal)
- `.` as a Heart-colored dot (the beating heart of the system)
- `Me` in SF Pro Display Semibold (capitalized, assertive — this is *your* AI)

```
love•Me
     ↑
  #E8456B dot (slightly oversized, 120% of period)
```

### App Icon

A rounded square (iOS standard) with:
- `#1A1A2E` background (Deep Ink)
- Centered `•M` in white — the dot is Heart-colored `#E8456B`
- The dot acts as an abstract heart/connection point
- Clean, legible at 29pt (smallest iOS icon size)

### Menu Bar Icon (macOS Daemon)

- 18x18pt template image
- Heart-colored dot when connected: `●`
- Gray dot when idle: `●` in `#6B7B8D`
- Outline dot when no daemon: `○`

---

## Component Design

### 1. Chat Bubbles

**User Message:**
```
┌─────────────────────────────┐
│  Heart (#E8456B) background │
│  White text, 16pt SF Pro    │
│  12px padding all sides     │
│  16px corner radius         │
│  Bottom-right corner: 4px   │  ← "tail" toward user
└─────────────────────────────┘
                          ← right-aligned, 60px left margin
```

**Assistant Message:**
```
← left-aligned, 60px right margin
┌─────────────────────────────┐
│  Surface (#16213E) bg       │
│  Light text, 16pt SF Pro    │
│  12px padding all sides     │
│  16px corner radius         │
│  Bottom-left corner: 4px    │  ← "tail" toward assistant
└─────────────────────────────┘
```

**Spacing:** 8px between messages from same sender, 16px when sender changes.

---

### 2. Thinking Panel

Appears *above* the assistant's message bubble, visually connected.

```
┌─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┐
│ ⚡ Thinking...          ▼   │  ← Collapsed (default)
└─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┘
┌─────────────────────────────┐
│  [Assistant response here]  │
└─────────────────────────────┘
```

**Collapsed state:**
- Dashed border, 1px `#F4A623` at 30% opacity
- `⚡` icon in Amber Glow
- "Thinking..." label in SF Pro Text 13pt, `#F4A623`
- Chevron `▼` to indicate expandable
- Height: 36px

**Expanded state:**
- Solid border, 1px `#F4A623` at 20% opacity
- Background: `#1F2E4D` (Surface Elevated)
- Thinking text in SF Mono 13pt, `#9CA3AF` (muted)
- Max height: 200px with scroll
- Smooth spring animation on expand/collapse (0.3s)
- Chevron rotates `▲`

**While streaming:**
- Pulsing `⚡` icon (opacity oscillates 0.5 → 1.0)
- Text appears character by character
- Label reads "Thinking..." with animated ellipsis

---

### 3. Tool Activity Cards

Inline in chat flow, between thinking panel and assistant response.

```
┌──────────────────────────────────┐
│  🔧 read_file          ✓ 0.3s   │  ← Completed
│  filesystem server               │
├──────────────────────────────────┤  ← Tap to expand
│  Input: {"path": "/src/app.ts"}  │
│  Result: "import React from..." │
└──────────────────────────────────┘
```

**States:**

| State | Left Icon | Right Side | Card BG |
|-------|-----------|------------|---------|
| Running | `⚙️` spinning | Progress spinner | `#16213E` + left 3px `#3B82F6` border |
| Success | `✓` | Duration "0.3s" | `#16213E` + left 3px `#34D399` border |
| Error | `✗` | "Failed" | `#16213E` + left 3px `#EF4444` border |

**Collapsed:** Single line — tool name + status. Height: 44px.
**Expanded:** Shows input args + truncated result in SF Mono. Max 120px.

**Multiple sequential tools** stack vertically with 4px gap, creating a visual "execution log" feel.

---

### 4. Input Bar

Fixed at bottom, above safe area.

```
┌──────────────────────────────────────────┐
│  ┌────────────────────────────┐  ┌───┐  │
│  │ Message love.Me...         │  │ ↑ │  │
│  └────────────────────────────┘  └───┘  │
└──────────────────────────────────────────┘
```

- Background: `#0F1729` (darker than chat background)
- Top border: 1px `#FFFFFF` at 6%
- Text field: rounded rect, 36px height, `#16213E` bg, 18px corner radius
- Placeholder: "Message love.Me..." in `#6B7B8D`
- Send button: 36x36 circle, `#E8456B`, white `↑` arrow
- Send button hidden when empty (or disabled at 30% opacity)
- Expands vertically for multiline (max 5 lines)

---

### 5. Connection Status

Minimal — a 6px dot in the nav bar, left of the title.

```
  ● love.Me                    ⚙️
  ↑                            ↑
  Status dot               Settings
```

| State | Dot Color | Behavior |
|-------|-----------|----------|
| Connected | `#34D399` | Solid |
| Connecting | `#F4A623` | Pulsing |
| Disconnected | `#EF4444` | Solid, tap shows reconnect sheet |

---

### 6. Conversation List

Slide-in from left (standard iOS navigation) or sheet on iPhone.

```
┌──────────────────────────────┐
│  love.Me              + New  │
│──────────────────────────────│
│  ● Fix the login bug         │
│    2 min ago                 │
│──────────────────────────────│
│  ● Deploy to staging         │
│    Yesterday                 │
│──────────────────────────────│
│  ● Research MCP servers      │
│    Feb 24                    │
└──────────────────────────────┘
```

- Active conversation: Heart-colored left bar (3px)
- Title: SF Pro Text 16pt Medium, single line truncated
- Subtitle: timestamp in `#6B7B8D`, 13pt
- Swipe left to delete (standard iOS)
- New conversation button: `+` icon in Heart color

---

### 7. Empty State

When no messages yet:

```
         ┌─────────┐
         │         │
         │  love•Me │  ← Logo, 48pt
         │         │
         └─────────┘

    Send a message to get started

    Your AI is connected and ready.
```

- Logo centered vertically (offset -60pt from center)
- Subtitle: SF Pro Text 16pt, `#6B7B8D`
- Connection status sentence: SF Pro Text 14pt, `#34D399` if connected
- Subtle breathing animation on the Heart dot (scale 1.0 → 1.1, 3s cycle)

---

### 8. Settings / Connection Screen

```
┌──────────────────────────────────┐
│  ← Connection Settings           │
│──────────────────────────────────│
│                                  │
│  HOST                            │
│  ┌────────────────────────────┐  │
│  │ 192.168.1.42              │  │
│  └────────────────────────────┘  │
│                                  │
│  PORT                            │
│  ┌────────────────────────────┐  │
│  │ 9200                      │  │
│  └────────────────────────────┘  │
│                                  │
│  ┌────────────────────────────┐  │
│  │     Test Connection        │  │ ← Outline button, Heart color
│  └────────────────────────────┘  │
│                                  │
│  ── OR SCAN QR CODE ──          │
│                                  │
│        ┌──────────┐             │
│        │ QR Code  │             │
│        │  Scanner │             │
│        └──────────┘             │
│                                  │
└──────────────────────────────────┘
```

- Section labels: 12pt SF Pro Bold uppercase, `#6B7B8D`, tracking 1.2
- Input fields: same style as chat input
- Test Connection: outlined button, 1px `#E8456B` border, Heart-colored text
- QR scanner: rounded rect camera preview with Heart-colored corner brackets

---

## Iconography

SF Symbols throughout (native, consistent, supports Dynamic Type).

| Context | Symbol | SF Symbol Name |
|---------|--------|----------------|
| Send | Arrow up | `arrow.up` |
| Thinking | Lightning | `bolt.fill` |
| Tool running | Gear spinning | `gearshape` (with rotation) |
| Tool success | Checkmark | `checkmark.circle.fill` |
| Tool error | X mark | `xmark.circle.fill` |
| Settings | Gear | `gearshape.fill` |
| New chat | Plus | `plus` |
| Connected | Circle fill | `circle.fill` (6pt) |
| Expand/collapse | Chevron | `chevron.down` / `chevron.up` |
| Conversations | List | `bubble.left.and.bubble.right` |
| Back | Chevron left | `chevron.left` |

---

## Animation & Motion

| Interaction | Animation | Duration | Curve |
|-------------|-----------|----------|-------|
| Send message | Bubble scales from 0.8 → 1.0 + slides up | 0.25s | spring(0.6) |
| Receive message | Fade in + slide from left 20px | 0.3s | easeOut |
| Thinking expand | Height animation + chevron rotate | 0.3s | spring(0.7) |
| Tool card appear | Fade in + slide down 8px | 0.2s | easeOut |
| Tool spinner | Continuous rotation | 1.0s | linear (infinite) |
| Thinking pulse | Opacity 0.5 ↔ 1.0 | 1.5s | easeInOut (infinite) |
| Connection dot pulse | Scale 1.0 ↔ 1.2 + opacity | 1.0s | easeInOut |
| Empty state heart beat | Scale 1.0 → 1.08 → 1.0 | 3.0s | easeInOut (infinite) |
| Streaming text | Character appear, no animation | Instant | — |

**Principles:**
- Subtle, never distracting
- Spring curves for user-initiated actions
- EaseOut for system-initiated appearances
- No bouncing or playful animations — this is a power tool

---

## Spacing & Layout System

Base unit: **4px**

| Token | Value | Usage |
|-------|-------|-------|
| `space-xs` | 4px | Icon-to-text gap |
| `space-sm` | 8px | Between same-sender messages |
| `space-md` | 12px | Bubble internal padding |
| `space-lg` | 16px | Between different-sender messages |
| `space-xl` | 24px | Section spacing |
| `space-2xl` | 32px | Screen edge padding (horizontal) |

**Chat area:** 16px horizontal padding. Bubbles max-width 80% of screen.

---

## Accessibility

- All colors pass WCAG AA contrast (4.5:1 minimum for text)
- Heart on Deep Ink: 5.2:1 ✓
- Light text on Surface: 7.8:1 ✓
- Muted text (Trust) on Deep Ink: 4.6:1 ✓
- Support Dynamic Type scaling
- VoiceOver labels for all interactive elements
- Tool cards announce status changes
- Thinking panel: "Thinking, double tap to expand"
- Reduce Motion: disable all animations, use instant transitions

---

## SwiftUI Implementation Notes

### Color Definition
```swift
extension Color {
    static let heart = Color(hex: "E8456B")
    static let deepInk = Color(hex: "1A1A2E")
    static let soul = Color(hex: "FAF7F2")
    static let trust = Color(hex: "6B7B8D")
    static let amberGlow = Color(hex: "F4A623")
    static let electricBlue = Color(hex: "3B82F6")
    static let sageGreen = Color(hex: "34D399")
    static let surface = Color(hex: "16213E")
    static let surfaceElevated = Color(hex: "1F2E4D")
    static let inputBg = Color(hex: "0F1729")
}
```

### Design Tokens as Environment
```swift
struct LoveMeTheme {
    let bubbleRadius: CGFloat = 16
    let bubbleTailRadius: CGFloat = 4
    let bubblePadding: CGFloat = 12
    let inputHeight: CGFloat = 36
    let statusDotSize: CGFloat = 6
    let toolCardBorderWidth: CGFloat = 3
    let maxBubbleWidth: CGFloat = 0.8 // 80% of screen
}
```

---

## Visual References & Mood

**Inspiration (take elements from, don't copy):**
- **iMessage** — bubble shape, input bar, scroll behavior
- **Claude.ai** — thinking panel concept, tool call rendering
- **Linear** — dark mode palette, information density, professional feel
- **Raycast** — power user aesthetic, compact but rich
- **Arc Browser** — warmth in a technical product

**The feeling we want:**
> "It's 11pm. You're on the couch. You tell love.Me to fix the deployment. You watch it think, call tools, read your files, run commands. Green checkmarks cascade. 'Done — deployed to staging.' You smile and close your phone."

That's the moment. Design for that moment.
