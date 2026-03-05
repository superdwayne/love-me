# PRD: Solace Visual Redesign — Serene AI Wellness Aesthetic

## Introduction

Complete visual redesign of the Solace iOS app inspired by the [AI mental health app design on Dribbble](https://dribbble.com/shots/25234933-Ai-mental-health-app-design). The reference design features a soft, serene, wellness-focused aesthetic with light pastel gradient washes (pink → lavender → light blue), clean white cards with generous rounded corners, mixed-weight serif+sans-serif typography, a pearlescent 3D orb, minimal navigation, emoji/mood elements, and abundant whitespace. The result should feel **calm, therapeutic, premium, and alive** — a stark departure from the current warm-orange tech-forward look.

## Reference Design Analysis

**Source:** [Dribbble Shot #25234933 — AI Mental Health App Design](https://dribbble.com/shots/25234933-Ai-mental-health-app-design)

### Key Visual Elements Observed:
- **Backgrounds**: Soft gradient washes — pastel pink/lavender/lilac fading to light blue/white. Not solid colors — subtle, cloud-like gradient backgrounds
- **Cards**: Clean white cards with very large rounded corners (20-24pt), minimal or no borders, soft drop shadows
- **Typography**: Mix of serif (for emotional/emphasis words like "Self-Belief", "Exhale") and sans-serif (for body/UI). Bold words mixed inline with light weight ("Inhale **Exhale** for Balance")
- **Color palette**: Muted pastels — soft pink (#F4D4E4), lavender (#E8D5F0), light blue (#D4E8F8), sage green (#D4E8D4), warm beige/cream. No bright saturated accents
- **Pill chips**: Category selectors in pill shapes with subtle borders (not filled)
- **3D element**: Pearlescent/glass orb on the breathing screen — translucent, milky white sphere with subtle reflections
- **Illustrations**: Muted, hand-drawn style figures in soft earth tones and pastels
- **Mood row**: Emoji-style mood faces in soft-outlined circles
- **CTA icons**: Small arrow-up-right icons in circular containers on cards
- **Navigation**: Minimal — clean top bar with avatar circle + search icon, no visible tab bar in reference
- **Overall spacing**: Extremely generous whitespace. Cards breathe. Nothing feels cramped.
- **Mood**: Calm, therapeutic, premium, serene, human, warm

## Goals

### Color System Overhaul
- Replace warm orange (#FA5D29) primary with soft muted palette
- New primary accent: Soft lavender (#B8A9D4) for buttons, selections
- Secondary accent: Soft sage (#9BC5A3) for success/active states
- Tertiary accent: Soft rose (#D4A0B0) for highlights, notifications
- Background: Pastel gradient wash (not solid) — pink-lavender-blue cloud
- Cards: Pure white (#FFFFFF) light mode, warm dark (#1C1B1F) dark mode
- Text: Warm charcoal (#2C2C2C) primary, soft grey (#8E8E93) secondary
- Functional colors muted: sage green success, warm amber warning, dusty rose error

### Typography Overhaul
- Add a serif font (e.g., "Playfair Display" or system serif) for display/emotional text
- Keep Inter for UI/body text
- Replace Space Grotesk with serif for display headings
- Mixed-weight inline patterns: "Your personal **AI** assistant"
- Larger display sizes for key headings (36-48pt)

### Card System
- Much larger corner radius: 20-24pt (up from 12-16pt)
- No visible borders on cards — rely on elevation shadow only
- Softer shadows: spread-based, not offset-based
- Cards should feel like they float on the gradient background

### Background System
- Replace solid `appBackground` with animated gradient wash
- Soft color pools that slowly shift (pink → lavender → blue)
- More prominent than current shimmer — actual visible gradient, not subtle
- Reduce motion: static gradient instead of animated

### Navigation Redesign
- Consider floating tab bar or bottom pill navigation
- Softer icons — SF Symbols with thinner weight
- Avatar-based header (user profile circle top-left)
- Search icon top-right

### Welcome Screen
- Full-screen gradient background
- Large serif heading: "Gain **Self-Belief**" or "Your **Solace** Awaits"
- Illustrated or 3D orb centerpiece instead of current crystal
- Feature pills/chips instead of feature cards
- Soft CTA button (rounded pill, lavender fill, white text)

### Chat Screen
- Conversation blocks with larger radius cards on gradient background
- Softer bubble styling — no left accent borders
- Input bar as a floating pill with very rounded ends
- Typing indicator with gentle pulse animation

### Workflow Screen
- Cards with illustrated elements or gradient accent strips
- Pill-shaped status badges in pastel colors
- Step pipeline in muted tones

### Settings & Email
- Inset grouped list with larger card radius
- Section headers in serif font
- Pastel accent icons instead of coral

## User Stories

### US-001: New Color Palette — Serene Pastels
**Description:** As a user, I want the app to use a calming pastel palette so it feels serene and therapeutic.

**Acceptance Criteria:**
- [x] Replace all brand colors in Theme.swift with new serene palette
- [x] Primary accent: Soft lavender `#B8A9D4`
- [x] Secondary: Sage green `#9BC5A3`
- [x] Tertiary: Soft rose `#D4A0B0`
- [x] Warm accent: Cream/peach `#F0DCC8`
- [x] Background light: `#FAF7F5` (warm off-white, not cool grey)
- [x] Background dark: `#1C1B1F` (warm near-black)
- [x] Surface light: `#FFFFFF`, dark: `#262529`
- [x] Surface elevated light: `#FAF7F5`, dark: `#302E33`
- [x] Text primary light: `#2C2C2C`, dark: `#F0EDEB`
- [x] Text secondary: `#8E8E93` both modes
- [x] Dividers: `#E8E5E1` light, `#3A3840` dark
- [x] Functional success: `#7CB686` (muted sage)
- [x] Functional warning: `#D4A96A` (warm amber)
- [x] Functional error: `#C47E7E` (dusty rose)
- [x] Functional info: `#7EA8C4` (soft blue)
- [x] User bubble: `#B8A9D4` (lavender) light, `#4A4160` dark
- [x] Shimmer accent: `#D4C1E8` (light purple shimmer)
- [x] Code background: `#F5F0EB` light, `#1E1D21` dark
- [x] Update AccentColor.colorset to `#B8A9D4`
- [x] All legacy aliases resolve correctly
- [x] Typecheck passes

### US-002: Add Serif Display Font
**Description:** As a user, I want emotional/display text in a serif font so the app feels warm and human, not tech-corporate.

**Acceptance Criteria:**
- [x] Add "Playfair Display" font files (Regular, Medium, SemiBold, Bold) to `app/Resources/Fonts/`
- [x] Register fonts in Info.plist
- [x] Add `Font.playfair(size:weight:)` helper in Theme.swift
- [x] Replace `displayLarge` with Playfair Display 44pt Medium
- [x] Replace `displayTitle` with Playfair Display 28pt SemiBold
- [x] Replace `displaySubtitle` with Playfair Display 22pt Medium
- [x] Replace `emptyStateTitle` with Playfair Display 28pt Medium
- [x] Keep `navTitle` as Inter (UI element, not emotional)
- [x] Keep all body/caption/code fonts as Inter/System Mono
- [x] Typecheck passes

### US-003: Gradient Background System
**Description:** As a user, I want soft pastel gradient backgrounds instead of flat solid colors so the app feels dreamy and alive.

**Acceptance Criteria:**
- [x] Rewrite `AmbientBackgroundView` to render a soft multi-color gradient wash
- [x] Gradient uses 3-4 pastel colors: soft pink, lavender, light blue, cream
- [x] Animated mode: colors slowly shift and blend (8-12 second cycle, very gentle)
- [x] Gradient feels like soft clouds or watercolor, not harsh linear bands
- [x] Use `MeshGradient` (iOS 18) or radial gradient composition for organic feel
- [x] Reduce motion: static version of the gradient (no animation)
- [x] Dark mode: deep muted versions of same gradient (purple-blue-charcoal)
- [x] Intensity levels still work: subtle (chat), standard (empty), prominent (welcome)
- [x] Typecheck passes

### US-004: Updated Card System — Soft & Floating
**Description:** As a user, I want cards that feel soft and floating with larger corners and no harsh borders.

**Acceptance Criteria:**
- [x] Update `GlassBackgroundModifier`: corner radius 20pt, NO border stroke, soft shadow (black@4%, radius 12, y 4)
- [x] Update `GlassElevatedModifier`: corner radius 24pt, NO border, shadow (black@6%, radius 16, y 6)
- [x] Update `GlassInputModifier`: corner radius 20pt, subtle 0.5pt border only when NOT focused, lavender glow when focused
- [x] Update `SolaceTheme.cardRadius` from 12 to 20
- [x] Update `SolaceTheme.bubbleRadius` from 18 to 22
- [x] Update `SolaceTheme.inputFieldRadius` from 20 to 24
- [x] Update `SolaceTheme.conversationBlockRadius` from 20 to 24
- [x] Shimmer modifier updated to use new accent colors
- [x] Ripple modifier uses lavender tones instead of aqua
- [x] Typecheck passes

### US-005: Welcome Screen Redesign
**Description:** As a user, I want a serene, inviting welcome screen that sets the calming tone for the entire app.

**Acceptance Criteria:**
- [x] Full gradient background (prominent intensity)
- [x] Large serif heading: "Your **Solace** Awaits" (mixed weight — "Your" regular, "Solace" bold, "Awaits" regular)
- [x] Subtitle in Inter: "A calm space for your mind"
- [x] SpiritGuide rendered with pearlescent/milky white tones (update if needed)
- [x] Feature section uses horizontal pill chips instead of stacked cards ("Chat", "Workflows", "Agent Mail" as tappable pills)
- [x] Connection status with soft green dot (muted sage)
- [x] CTA button: full-width pill shape, lavender fill, white text, 24pt corner radius
- [x] Staggered entrance animation preserved but with softer spring (less bounce, more ease)
- [x] Typecheck passes

### US-006: Chat Screen Redesign
**Description:** As a user, I want the chat experience to feel calm and spacious with softer conversation blocks.

**Acceptance Criteria:**
- [x] Conversation blocks use 24pt radius cards on gradient background
- [x] Remove left accent border on user messages — use subtle lavender left bar or no bar
- [x] User bubble background: soft lavender (`#B8A9D4` at 15% opacity) instead of solid orange
- [x] Assistant text renders on white/surface card with no accent border
- [x] Block divider: thin, muted, with more vertical spacing around it
- [x] Toolbar: "Solace" in serif font, connection dot in sage green, provider badge in soft pill
- [x] Tool cards use pastel accent colors (soft blue border instead of coral)
- [x] Thinking panel pulse uses lavender tones
- [x] "New messages" pill uses lavender background instead of coral
- [x] Typecheck passes

### US-007: Input Bar Redesign
**Description:** As a user, I want a soft, floating input bar that matches the serene aesthetic.

**Acceptance Criteria:**
- [x] Input pill uses warm off-white fill with very subtle border
- [x] Focused state: soft lavender glow border (1pt lavender at 40% opacity)
- [x] Send button: lavender circle with white arrow
- [x] Stop button: dusty rose circle with white stop icon
- [x] Mic button: soft grey circle (muted)
- [x] Plus/attach button: muted grey icon
- [x] Reply preview bar: lavender left accent instead of coral
- [x] Recording indicator: dusty rose dot instead of bright red
- [x] Speech waveform icon: lavender instead of coral
- [x] Typecheck passes

### US-008: Conversation List Redesign
**Description:** As a user, I want the conversation sidebar to feel organized and calm.

**Acceptance Criteria:**
- [x] Conversation avatars use pastel lavender circles instead of coral
- [x] Selected conversation highlight: lavender at 10% opacity (not coral)
- [x] Selected conversation ring: lavender border instead of coral
- [x] Email conversations use soft blue circles instead of bright info blue
- [x] "New Conversation" button: lavender fill, white text, pill shape
- [x] Empty state icon: muted lavender tones
- [x] Plus toolbar button: lavender instead of coral
- [x] Typecheck passes

### US-009: Workflow List Redesign
**Description:** As a user, I want workflow cards to feel like calm, organized task cards.

**Acceptance Criteria:**
- [x] Workflow cards: 20pt radius, no top color strip (remove status color bar)
- [x] Status icons use muted pastel versions of functional colors
- [x] Trigger badges: soft pastel fills (not bright)
- [x] Step pipeline dots: muted sage (success), soft blue (running), dusty rose (error)
- [x] "New Workflow" button: lavender fill pill
- [x] Empty state uses muted lavender icon cluster (not coral)
- [x] Skeleton loading uses warm beige tones instead of surfaceElevated
- [x] Staggered entrance with gentler spring animation
- [x] Typecheck passes

### US-010: Settings & Email Views Redesign
**Description:** As a user, I want settings and email screens to match the serene palette.

**Acceptance Criteria:**
- [x] Section headers in serif font (Playfair Display) at smaller size
- [x] All `.coral` accent references in SettingsView → `.lavender` (our new accent name or direct color)
- [x] Toggle tint: lavender instead of coral
- [x] Ambient music leaf icon: sage green instead of coral
- [x] Agent Mail connection icon: sage green for connected
- [x] Email approval badges: lavender counts instead of coral
- [x] "Connect Agent Mail" button: lavender fill
- [x] All section tracking headers: same style but with new palette
- [x] Typecheck passes

### US-011: Tab Bar Redesign
**Description:** As a user, I want a softer tab bar that blends with the serene aesthetic.

**Acceptance Criteria:**
- [x] Tab bar background: slightly translucent white/surface with blur (`.regularMaterial`)
- [x] Selected tab icon: lavender color
- [x] Unselected tab icon: muted grey (#8E8E93)
- [x] Selected tab text: lavender, semibold
- [x] Tab bar top border: none or very subtle divider
- [x] Badge color on Agent Mail tab: soft rose instead of red
- [x] Overall tint: lavender throughout
- [x] Typecheck passes

### US-012: SpiritGuide Visual Update
**Description:** As a user, I want the 3D spirit guide to feel pearlescent and ethereal, matching the wellness aesthetic.

**Acceptance Criteria:**
- [x] Update SpiritGuideView colors to use pearlescent/milky white tones
- [x] Idle state: soft lavender-white gradient
- [x] Thinking state: gentle lavender pulse
- [x] Success state: sage green glow
- [x] Tinkering particles: pastel lavender, rose, and sage particles
- [x] Drag rotation sensitivity unchanged
- [x] Typecheck passes

### US-013: Empty State & Connection Banner Updates
**Description:** As a user, I want empty states and banners to use the new serene palette.

**Acceptance Criteria:**
- [x] EmptyStateView icon: muted lavender tones
- [x] EmptyStateView CTA button: lavender pill
- [x] ConnectionBanner: softer styling — dusty rose for disconnected, warm amber for connecting, sage for connected
- [x] Link preview cards: soft blue accent instead of info blue
- [x] Voice note player: lavender progress bar/buttons instead of coral
- [x] Typecheck passes

### US-014: Animation & Motion Updates
**Description:** As a user, I want animations to feel gentler and more calming.

**Acceptance Criteria:**
- [x] Reduce spring bounce from 0.15 to 0.08 across entrance animations
- [x] Increase spring duration from 0.4s to 0.5s for smoother easing
- [x] Welcome screen entrance: slower, more gradual reveal (1.8s total instead of 2.2s, but each phase slower)
- [x] Shimmer effect: use new gradient colors (lavender/rose/blue wash instead of aqua/skyblue)
- [x] Breathing animation on welcome dot: unchanged duration but uses lavender
- [x] Update `SolaceTheme` animation constants as needed
- [x] Typecheck passes

## Non-Goals

- No new screens or features — this is purely a visual redesign
- No changes to the daemon/backend code (only app-side)
- No changes to WebSocket message types or data models
- No layout restructuring — keep existing view hierarchy and navigation patterns
- No changes to app functionality or business logic
- No changes to the Xcode project structure

## Technical Considerations

### Font Addition
- Playfair Display is a Google Font (OFL license, free for commercial use)
- Download Regular, Medium, SemiBold, Bold weights
- Add to `app/Resources/Fonts/` and register in Info.plist `UIAppFonts` array
- Size: ~200KB per weight file

### Gradient Background Performance
- `MeshGradient` (iOS 18+) provides best organic gradient with minimal CPU
- Fallback for iOS 17: composition of 3-4 radial gradients with animated positions
- Use `.drawingGroup()` to flatten gradient rendering
- Consider reducing animation frame rate to 15fps for battery (gentle movement doesn't need 30fps)

### Color Strategy
- Rename semantic colors where needed (e.g., `coral` → keep name but change value, or introduce new names)
- Since views use semantic tokens (`.coral`, `.surface`, etc.), changing values propagates automatically
- Legacy aliases continue to resolve — no rename churn needed
- Consider introducing `.accent` as the new primary instead of `.coral` to be palette-agnostic

### Testing
- Test all screens in both light and dark mode
- Test with Dynamic Type (especially serif font scaling)
- Test with Reduce Motion enabled
- Test gradient background performance on older devices (iPhone 12 minimum)
