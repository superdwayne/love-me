# PRD: Solace Visual Identity Overhaul — "Calm Sanctuary"

## Introduction

Solace is a place of relaxation where your AI agent seamlessly moves between applications on your behalf. The current visual identity (Heart Red accent, system fonts, dark blue surfaces) feels functional but doesn't embody the calm, meditative sanctuary the brand promises. This redesign transforms every visual touchpoint — colors, typography, lighting, logo, character, and glassmorphism — into a cohesive experience that feels like stepping into a tranquil space.

**Inspiration**: [MiniTap AI](https://minitap.ai/) — deep purples, frosted glass, ethereal atmosphere, premium calm.

**Character Direction**: A geometric spirit guide — a calm crystalline/lotus shape with subtle glow and pulse animations. Not a mascot, but a presence.

## Goals

- Replace the current color palette with a deep purple/lavender scheme that evokes calm and premium quality
- Introduce custom display typography (Space Grotesk headlines + Inter body) for a distinctive, branded feel
- Add glassmorphism (frosted glass) effects to key surfaces for depth and softness
- Design a geometric spirit guide character that appears in Welcome, Empty State, and loading moments
- Redesign the app icon/logo to match the new purple/lavender identity
- Maintain excellent dark/light mode support with the new palette
- Preserve all existing functionality — this is purely visual

## Color Palette

### New Brand Colors
| Name | Dark Mode | Light Mode | Hex (Dark) | Usage |
|------|-----------|------------|------------|-------|
| **Twilight** | Deep indigo | — | `#16132B` | Primary background |
| **Mist** | — | Warm off-white | `#F5F0FA` | Light mode background |
| **Amethyst** | Rich purple | — | `#8B5CF6` | Primary accent (buttons, highlights) |
| **Lavender** | Soft purple | — | `#C4B5FD` | Secondary accent, borders |
| **Glow** | Warm peach | — | `#FFA984` | Warm accent, notifications, active states |
| **Moonlight** | Pale lavender | — | `#E8E0F0` | Dark mode text primary |
| **Dusk** | Muted purple-gray | — | `#7C6F9B` | Secondary text |

### New Surface Colors (Glassmorphic)
| Name | Dark Mode | Light Mode | Usage |
|------|-----------|------------|-------|
| **Glass** | `#1E1A3A` @ 80% opacity + blur | `#FFFFFF` @ 70% opacity + blur | Cards, bubbles |
| **Glass Elevated** | `#2A2450` @ 85% opacity + blur | `#F8F4FF` @ 80% opacity + blur | Modals, popovers |
| **Glass Input** | `#120F24` @ 90% opacity + blur | `#FFFFFF` @ 85% opacity + blur | Input fields |

### Functional Colors (Refined)
| Name | Color | Usage |
|------|-------|-------|
| **Success** | `#34D399` (sage green — keep) | Connected, completed |
| **Warning** | `#FBBF24` (warm amber) | Loading, connecting |
| **Error** | `#F87171` (soft coral) | Errors, disconnected |
| **Info** | `#818CF8` (indigo) | Running tools, active |

## Typography

### Font Selection
- **Display/Headlines**: **Space Grotesk** (Medium, SemiBold) — geometric, calm, modern. SIL Open Font License.
- **Body/UI**: **Inter** (Regular, Medium) — optimized for screen readability. SIL Open Font License.
- **Code/Technical**: System monospaced (keep current)

### Type Scale
| Token | Font | Size | Weight | Usage |
|-------|------|------|--------|-------|
| `displayLarge` | Space Grotesk | 48pt | Medium | Welcome "Solace." |
| `displayTitle` | Space Grotesk | 28pt | SemiBold | Section headers |
| `displaySubtitle` | Space Grotesk | 20pt | Medium | Sub-headers |
| `navTitle` | Space Grotesk | 18pt | SemiBold | Navigation titles |
| `body` | Inter | 16pt | Regular | Chat messages, general text |
| `bodyMedium` | Inter | 16pt | Medium | Emphasized body |
| `caption` | Inter | 13pt | Regular | Timestamps, metadata |
| `small` | Inter | 11pt | Medium | Badges, labels |
| `code` | System Mono | 14pt | Regular | Code blocks, tool details |
| `codeSm` | System Mono | 12pt | Regular | Inline code |

## Spirit Guide Character

A **geometric crystalline form** — imagine a softly glowing polyhedron (icosahedron-like) with translucent facets that catch light. It communicates state through:

- **Idle/Resting**: Gentle slow rotation, soft purple glow, breathing pulse on opacity
- **Thinking/Processing**: Faster rotation, facets shimmer with Amethyst → Lavender gradient
- **Success/Greeting**: Brief warm Glow (peach) wash across facets, gentle scale bounce
- **Ambient**: Subtle floating motion (vertical sine wave), soft particle trail

### Where It Appears
- **Welcome View**: Large (120pt), center stage with entrance animation
- **Empty State**: Medium (80pt), floating above suggestion text
- **Loading/Connecting**: Small (40pt), in status area with thinking animation
- **Chat Header**: Tiny (24pt), static icon next to "Solace" wordmark

### Implementation Approach
- Built with SwiftUI shapes, gradients, and animations (no 3D framework needed)
- Use overlapping rotated polygons with varying opacity for faceted look
- Gradient fills that shift based on state
- `TimelineView` for smooth continuous animation

## Logo & App Icon

### Wordmark
- "Solace" in Space Grotesk Medium, with the period "." rendered as a small geometric crystal (the spirit guide in miniature) in Amethyst
- Alternatively: "." as a glowing Amethyst dot with soft radial gradient

### App Icon (1024x1024)
- Dark Twilight (`#16132B`) background with subtle radial gradient toward center
- Centered geometric crystal form (the spirit guide) rendered with Amethyst/Lavender gradients
- Soft glow effect around the crystal
- Clean, recognizable at small sizes

## User Stories

### US-001: Update SolaceTheme Color Palette
**Description:** As a user, I want the app to use the new purple/lavender color scheme so the app feels calm and premium from the moment I open it.

**Acceptance Criteria:**
- [x] Replace all brand colors in Theme.swift: `heart` → `amethyst`, `deepInk` → `twilight`, `soul` → `mist`, `trust` → `dusk`
- [x] Update all adaptive surface colors to new Glass values with proper dark/light variants
- [x] Update functional colors: `electricBlue` → `info` (#818CF8), `amberGlow` → `warning` (#FBBF24), `softRed` → `error` (#F87171), keep `sageGreen` as `success`
- [x] Add new color tokens: `lavender`, `glow`, `moonlight`
- [x] Update all ShapeStyle extensions to match new color names
- [x] Add `divider` updated to purple-tinted values
- [x] `swift build` succeeds in daemon (no dependency on app colors)
- [x] App builds without errors in Xcode

### US-002: Add Custom Fonts (Space Grotesk + Inter)
**Description:** As a user, I want to see distinctive, branded typography so Solace feels like a crafted experience, not a generic system app.

**Acceptance Criteria:**
- [x] Download Space Grotesk (Medium, SemiBold, Bold) .ttf files and add to app bundle
- [x] Download Inter (Regular, Medium, SemiBold) .ttf files and add to app bundle
- [x] Register all fonts in Info.plist under `UIAppFonts`
- [x] Create Font extension helpers: `.spaceGrotesk(size:weight:)` and `.inter(size:weight:)` with fallback to system fonts
- [x] Update all Font tokens in Theme.swift to use new custom fonts per the type scale
- [x] Verify fonts render correctly — test with a simple preview or build
- [x] App builds without errors in Xcode

### US-003: Add Glassmorphism Modifiers
**Description:** As a developer, I need reusable glassmorphism view modifiers so all surfaces can consistently use frosted glass effects.

**Acceptance Criteria:**
- [x] Create `.glassBackground(opacity:cornerRadius:)` ViewModifier that applies: semi-transparent background + `.ultraThinMaterial` blur + subtle border (Lavender @ 15% opacity) + corner radius
- [x] Create `.glassElevated(cornerRadius:)` variant with slightly more opacity and stronger blur
- [x] Modifiers adapt correctly between dark and light mode
- [x] Add to Theme.swift or a new GlassModifiers.swift file
- [x] App builds without errors in Xcode

### US-004: Redesign WelcomeView with New Theme
**Description:** As a new user, I want the welcome screen to immediately convey calm and beauty so I feel invited into the Solace experience.

**Acceptance Criteria:**
- [x] Background uses Twilight with subtle radial gradient (center lighter, edges darker)
- [x] "Solace." wordmark uses Space Grotesk Medium at 48pt, period in Amethyst with soft glow
- [x] Feature rows use Amethyst-tinted icon badges instead of Heart Red
- [x] "Get Started" button uses Amethyst background with soft rounded corners
- [x] Feature descriptions use Inter font
- [x] Pulsing connection indicator uses Amethyst/Lavender instead of red/green
- [x] All existing animations preserved (entrance, pulse, etc.)
- [x] App builds without errors in Xcode
- [ ] Verify changes work in Xcode preview or simulator

### US-005: Build Spirit Guide Component
**Description:** As a user, I want to see a calming geometric crystal companion that gives Solace a living, ambient personality.

**Acceptance Criteria:**
- [x] Create `SpiritGuideView` component with configurable size parameter (`.small`, `.medium`, `.large`)
- [x] Renders as overlapping rotated hexagons/polygons with Amethyst → Lavender gradient fills at varying opacities
- [x] Supports state parameter: `.idle`, `.thinking`, `.success` with different animation behaviors
- [x] Idle: slow continuous rotation + gentle vertical float + breathing opacity pulse
- [x] Thinking: faster rotation + shimmer gradient shift
- [x] Success: brief warm Glow color wash + subtle scale bounce
- [x] Uses `TimelineView(.animation)` for smooth 60fps animation
- [x] Respects `accessibilityReduceMotion` — falls back to static with no animation
- [x] App builds without errors in Xcode
- [ ] Verify animations work in Xcode preview or simulator

### US-006: Redesign EmptyStateView
**Description:** As a user opening a new conversation, I want to see the spirit guide and feel invited to start chatting, not stare at a blank screen.

**Acceptance Criteria:**
- [x] Spirit guide (medium size) centered above the "Solace." wordmark
- [x] Wordmark uses new Space Grotesk styling with Amethyst period
- [x] Suggestion chips use glass background (`.glassBackground`) instead of solid `surfaceElevated`
- [x] Chip icons tinted Amethyst instead of Heart Red
- [x] Connection status uses new color tokens (Success/Warning/Error)
- [x] Overall background inherits from parent (no separate background needed)
- [x] App builds without errors in Xcode
- [ ] Verify changes work in Xcode preview or simulator

### US-007: Update ChatView & Message Bubbles
**Description:** As a user reading conversations, I want message bubbles and the chat interface to use the new glass aesthetic so the whole experience feels cohesive.

**Acceptance Criteria:**
- [x] Assistant message bubbles use `.glassBackground` instead of solid surface color
- [x] User message bubbles use Amethyst background (replacing Heart) with white text
- [x] Tool cards use Info color (#818CF8) for left border when running, Success for completed, Error for failed
- [x] Thinking panel uses glass background with Lavender-tinted text
- [x] Streaming dots animation uses Lavender color instead of Trust Blue
- [x] Search bar uses glass input background
- [x] All text uses Inter for body content, Space Grotesk for any headers
- [x] App builds without errors in Xcode
- [ ] Verify changes work in Xcode preview or simulator

### US-008: Update InputBar
**Description:** As a user composing messages, I want the input area to feel integrated with the glass design language.

**Acceptance Criteria:**
- [x] Input field uses glass input background with Lavender border on focus
- [x] Send button uses Amethyst color (replacing Heart Red) when active, Dusk when disabled
- [x] Reply preview bar uses Amethyst left border instead of Heart Red
- [x] Attachment indicators (image, voice) use Amethyst tints
- [x] Placeholder text uses Dusk color
- [x] App builds without errors in Xcode
- [ ] Verify changes work in Xcode preview or simulator

### US-009: Update ContentView & Navigation
**Description:** As a user navigating the app, I want tab bars, navigation headers, and the settings view to match the new visual identity.

**Acceptance Criteria:**
- [x] Tab bar uses glass background (blur + semi-transparent)
- [x] Selected tab icon uses Amethyst, unselected uses Dusk
- [x] Navigation bar titles use Space Grotesk
- [x] Settings view headers and toggles use new color tokens
- [x] Workflow view cards use glass backgrounds
- [x] Any remaining Heart Red references replaced with Amethyst
- [x] App builds without errors in Xcode
- [ ] Verify changes work in Xcode preview or simulator

### US-010: Redesign App Icon
**Description:** As a user, I want the app icon on my home screen to reflect the new purple/lavender brand identity and the spirit guide motif.

**Acceptance Criteria:**
- [ ] Create new 1024x1024 app icon: Twilight background with centered geometric crystal in Amethyst/Lavender gradients
- [ ] Soft outer glow effect around the crystal
- [ ] Icon is recognizable and clean at 60x60 (smallest rendered size)
- [ ] Replace `icon_1024.png` in `AppIcon.appiconset`
- [x] Update `AccentColor.colorset` to use Amethyst (#8B5CF6) instead of current orange (#E86B44)
- [x] App builds without errors in Xcode

### US-011: Final Polish — Ambient Background Effects
**Description:** As a user, I want subtle ambient effects (soft gradient shifts, gentle particle-like dots) in the background that make the app feel alive and breathing.

**Acceptance Criteria:**
- [x] Create `AmbientBackgroundView` with slowly animating gradient blobs (large circles with heavy blur, shifting position over ~10s cycles)
- [x] Uses Amethyst, Lavender, and subtle Glow (peach) colors at low opacity (5-15%)
- [x] Applied behind main content on Welcome, Empty State, and Chat views
- [x] Performance: uses `drawingGroup()` or `Canvas` to avoid layout overhead
- [x] Respects `accessibilityReduceMotion` — disables animation, shows static gradient
- [x] Does not interfere with scrolling or interaction performance
- [x] App builds without errors in Xcode
- [ ] Verify ambient effects visible in Xcode preview or simulator

## Non-Goals

- No changes to daemon/backend code — this is purely an app-side visual redesign
- No changes to WebSocket message types or data models
- No functional changes to chat, workflows, email, or MCP features
- No 3D rendering framework (SceneKit, RealityKit) — spirit guide built with SwiftUI 2D
- No server-side rendering of the icon — designed as static asset
- No changes to app architecture, view model patterns, or navigation structure
- No dark-mode-only design — must maintain full light mode support
- No animation library dependencies — use native SwiftUI animations only

## Technical Considerations

- **Font Licensing**: Space Grotesk and Inter are both SIL Open Font License — free for commercial use, must include license files in bundle
- **Font Loading**: Register in Info.plist, use PostScript names in `.custom()` calls, provide system font fallbacks
- **Glassmorphism Performance**: `.ultraThinMaterial` is GPU-accelerated on iOS; avoid stacking multiple blur layers in scroll views
- **Spirit Guide Animation**: `TimelineView(.animation)` with `Canvas` for best performance; avoid `Timer`-based approaches
- **Color Migration**: Many views reference `.heart`, `.deepInk`, etc. directly — a find-and-replace pass will be needed after Theme.swift is updated; consider keeping old names as `@available(*, deprecated)` aliases during transition
- **Asset Generation**: App icon will need to be created — can use SwiftUI preview rendering, Figma, or a design tool
- **Accessibility**: Ensure all new colors meet WCAG AA contrast ratios (4.5:1 for body text, 3:1 for large text). Moonlight on Twilight = ~12:1 (excellent). Amethyst on Twilight = ~4.8:1 (passes AA).

## Dependency Order

```
US-001 (Colors) ──→ US-003 (Glass Modifiers) ──→ US-004 (Welcome)
                                                ──→ US-006 (Empty State)
                                                ──→ US-007 (Chat/Bubbles)
                                                ──→ US-008 (Input Bar)
                                                ──→ US-009 (Navigation)
                                                ──→ US-011 (Ambient BG)
US-002 (Fonts)   ──→ US-004 (Welcome)
                 ──→ US-006 (Empty State)
                 ──→ US-007 (Chat/Bubbles)
                 ──→ US-009 (Navigation)
US-005 (Spirit Guide) ──→ US-006 (Empty State)
                      ──→ US-004 (Welcome)
US-010 (App Icon) — Independent, can run anytime
```
