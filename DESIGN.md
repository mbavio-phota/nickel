# Design

Visual system for Nickel (SwiftUI, iOS 17+). Register: product. The shell is
expressive ("Hypelist energy"), the work surfaces are calm developer-tool.

## Color

- **Brand accent**: Conductor orange `#FF5C0A` (`Theme.accent`). Used for primary
  actions, the send button, selection, and as the anchor hue of cover palette 0. Never
  as body-copy color, never on inactive states.
- **Chrome**: system semantic colors only — `systemGroupedBackground` canvas,
  `secondarySystemGroupedBackground` cards, `.primary`/`.secondary` ink. Both light and
  dark mode come free; never hard-code grays.
- **Cover palettes** (`CoverArt.palettes`): six curated duotone gradients, deterministic
  per entity (FNV-1a hash of the entity id). Dark-leaning, saturated mid-tones so white
  overlay text works. Overlaid text additionally sits on a black scrim gradient
  (0.55 → 0 opacity, bottom-up).
- **Status colors** (`Theme.StatusColor`): ready=green, working/transitioning=orange,
  sleeping=indigo, idle=secondary, error=red, archived=gray. Rendered as `StatusChip`
  (dot + word in a tinted capsule), never as a bare dot in the redesigned surfaces.

## Typography

- One family: SF Pro (system). Fixed scale, tight jumps — `.largeTitle.bold()` for
  cover-overlay titles, `.title3/.headline` for card titles, `.subheadline`/`.footnote`
  for meta, `.caption` for timestamps.
- **SF Mono via `Theme.monospace(_:weight:)`** for every identifier: git remotes, branch
  names, model ids, API keys, raw JSON. This is the product's signature contrast: lush
  gradient + mono identifier.
- Overlay titles on covers: white, `.bold()`, shadowed by the scrim (not by text-shadow).

## Components

- **`CoverArtView(seed:)`** — deterministic gradient art: linear duotone base + radial
  highlight whose center is derived from the hash. No two projects look alike; the same
  project always looks the same. Corner radius 20 (continuous) when used as a card.
- **`CoverCard`** (projects list) — full-width cover, height 148, title + mono remote
  overlaid bottom-left on scrim.
- **Immersive header** (project & workspace detail) — full-bleed cover under the status
  bar, back button floating on material, entity name `.largeTitle.bold()` white on
  scrim, meta row (mono chip / status chip) beneath the name.
- **`StatusChip`** — capsule, 8pt dot + status word. Tinted `color.opacity(0.16)`
  background on cards; `.ultraThinMaterial` variant on covers. Pulses opacity while
  transitioning (disabled under Reduce Motion).
- **`FloatingActionPill`** — the Hypelist signature: bottom-center floating capsule,
  `Color.primary` background with `systemBackground` label (adaptive black/white pill),
  orange plus icon, soft shadow. One per screen max; it is the screen's primary action.
- **Standard cards** — `secondarySystemGroupedBackground`, corner radius 16, no border,
  shadow `black.opacity(0.06)` radius 8 y 2 in light mode. Press feedback: scale 0.98,
  150ms ease-out (`PressableCardStyle`).
- **Forms & Settings** — stock SwiftUI `Form`. Precision surfaces stay native.
- **Chat** — unchanged vocabulary: orange user bubbles, material agent bubbles, mono
  event chips. The calm zone.

## Layout

- Screens are `ScrollView` + `LazyVStack(spacing: 12)` with 16pt horizontal insets;
  grouped `List` only where the content is a settings/form surface.
- Floating pill reserves 88pt bottom content inset so the last card never hides.
- Empty states use `ContentUnavailableView` with playful copy (see PRODUCT.md #5).

## Motion

- 150–250ms, ease-out only. Press-scale on cards, opacity pulse on transitioning status,
  default push/sheet transitions elsewhere. No entrance choreography, nothing decorative
  in the transcript. All custom motion gated on `accessibilityReduceMotion`.
