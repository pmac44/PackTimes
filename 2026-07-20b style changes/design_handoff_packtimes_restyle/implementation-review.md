# Implementation Review — Paper theme, desktop (v287 screenshots)

What's right already: theme switcher (Auto/Paper/Graphite), Route sidebar hierarchy, surface/raised card system, Space Grotesk numbers, chevron bar, Settings accordions. The items below are the remaining deltas, in priority order.

## 1. Mission stop cards — the big one
Current: saturated FILLED cards (solid blue town cards, solid purple bivi card, solid green start) with white/light text.
Spec (planning-tabs.md, mockups 6a/6b): cards are TINTS of the semantic color with normal dark text.
- Town cards: `--card-town-bg` (neutral raised #fffef8 + hairline border) — towns are not a semantic color; the blue fill reads as "water".
- Bivi/sleep card: `--card-sleep-bg` #e6e0ef tint, border #6f5f9666, title in `--text`, NOT white-on-purple.
- The Arrive / Wake / Depart labels on the bivi card are currently olive-on-purple — unreadable. Labels: 11px caps `--text-muted`; values: Space Grotesk `--text`.
- Start card: `--card-start-bg` #e3e7d2 tint. Colored text only via the `--*-deep` tokens.
Rule of thumb: **semantic color goes in the border, dot, and tag — never the card fill, never the text color of body copy.**

## 2. Map overlay legend (layer toggle chips)
Current: dark grey pills with white mono text on the light map — Graphite chrome stranded on a Paper screen, and mono where nothing is numeric.
Fix: float like every other map element — `--surface-raised` at ~95% opacity, 1.5px `--hairline` border, radius 8px, Archivo 11.5px `--text`, colored dot per layer. Disabled layers: dot greyed + text `--text-muted` (no fill change). Group the chips in ONE rounded panel rather than a stack of separate pills.

## 3. Ride tab — upcoming-stops list (right sidebar cards)
Current: dark brown filled cards on Paper.
Fix: same recipe as the Ride footer rows in 4b — `--surface-raised` card, hairline border, outlined semantic tag (TOWN/SLEEP/ACCOM 10px caps in `--*-deep`), name 14.5px Archivo `--text`, ETA right-aligned Space Grotesk `--accent`. The purple ACCOM card has the same filled-card problem as Mission.

## 4. Residual mono on planning tabs
Mono is banned outside fast-changing digits. Still mono in the screenshots: sidebar dates ("Sat 08/08/26 08:00"), stop names/times in the Stops list, "ALL STOPS (165)", legend chips, "Not connected". All of these → Archivo (labels/names) or Space Grotesk (dates, times, distances).

## 5. Small-control polish
- Dark square icon buttons (edit pencil, filter buttons) on Paper → `--surface-raised` + hairline border, icon in `--text-soft`; active state accent border + accent icon.
- "Unknown 17km — try Refresh" pink chip → warning style: `--card-finish-bg` tint, text `--finish-deep`, 1.5px border.
- Stop-card icon rows (star/moon/fork/drop/edit/x): 6 dark boxes is heavy — outlined 32px buttons, hairline border, active = accent.

## 6. Desktop-specific rules (the mockups were 390px mobile)
- Sidebar: `--surface` page bg, cards raised. Map panel: full-bleed, all overlays follow the float recipe (border + shadow + ~95% opacity).
- Top tab bar: active tab keeps icon + label + 2px accent underline; inactive icons desaturated — matches current build, keep it.
- Elevation strip along the bottom of the map should adopt the Ride-screen elevation treatment (sunken surface, accent day-split band) instead of the current saturated blue histogram.
