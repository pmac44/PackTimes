# Handoff: Packtimes Restyle — Paper & Graphite Themes

## Overview
A visual restyle of the Packtimes PWA (bikepacking / ultra-racing ride planner and cycle computer). This package defines two switchable themes — **Paper** (warm light, day) and **Graphite** (dark, night / OLED-friendly) — plus typography and layout rules for the Ride screen and, by extension, the whole app. The layout and features of the existing app are unchanged; this is a re-skin plus a small set of structural refinements listed below.

## About the Design Files
The files in this bundle are **design references created in HTML** — prototypes showing intended look and behavior, not production code to copy directly. The task is to **apply these designs to the existing Packtimes PWA codebase** using its established patterns: replace hardcoded colors/fonts with the CSS custom properties in `tokens.css`, and adjust component markup/CSS where the structural rules below require it. Do not ship the HTML mockups.

## Fidelity
**High-fidelity.** Colors, typography, sizes, and spacing in the mockups and `tokens.css` are final values. The canonical screens are:
- `Packtimes Ride Explorations.dc.html` → the mockup labeled **4b** (Paper Ride screen, floating paired cells) and **5a** (same layout, Graphite theme).
- `Packtimes Style Guide.dc.html` → the written rules, palettes, and type specimens.
Other labeled options in the explorations file (1a–3b, 4a, 5b–5d, 2a–2c) are earlier explorations — reference only.

## Implementation strategy (PWA)
1. Add `tokens.css`; set `<html data-theme="paper">`.
2. Sweep existing stylesheets: replace hardcoded colors with `var(--…)` tokens. The app's current "green monospace everywhere" becomes: green (`--accent`) only for active tab, progress, and primary values; mono font only for fast-changing digits.
3. Add a Settings toggle writing `data-theme` (`paper` / `graphite`); optionally auto-switch at sunset. A max-battery variant is `--surface: #000` on graphite.
4. Apply the structural refinements below.

## Screens / Views

### Ride screen (canonical: 4b / 5a)
Top-to-bottom stack:
- **Tab bar**: 6 tabs (Route, Stops, Supplies, Mission, Ride, Settings), icon above an 11.5px label, full-column hit areas ≥ 44px. Active tab: accent color + 2px underline; inactive: muted, icons desaturated.
- **Chevron progress bar** (existing signature element — keep exactly as-is): full-width, 16px tall, filled portion in accent chevrons.
- **Progress row**: `distance to go` (36px, accent, left) · `km ridden` (19px, center) · `total km` (36px, right). Font: Space Grotesk (slow numbers). `white-space: nowrap`.
- **Map**: full-bleed OSM raster tiles (tiles are unmodifiable — all chrome must win contrast against standard OSM cartography via borders + shadows).
- **Floating paired data cells**: 2 rows × 3 columns overlaid on the map top, 8px gaps, 10px screen margin. See "Paired data cells".
- **Map control rail**: single vertical pill (44px wide) on the right, BELOW the cell grid — sensor indicator, fullscreen, OSM layer toggle. Never scattered individual buttons.
- **Temp badge**: small floating cell, bottom-left above the elevation strip.
- **Turn card**: centered above elevation strip. Turn arrow (warm color, 24px) + distance (34px, Space Grotesk) + street name (11.5px muted). Raised surface, 1.5px border in accent/strong-border, radius 14px.
- **Elevation strip**: ~78px tall, semi-opaque sunken surface over map bottom; terrain silhouette, day-split band in accent, left: current altitude + grade (14px), right: ascent/descent remaining.
- **Next-stop rows** (footer): one row per upcoming stop. Outlined semantic tag (FOOD/SLEEP/WATER, 10px caps) + emoji + stop name (14.5px semibold) + right-aligned ETA (14.5px Space Grotesk bold, accent, `nowrap`).

### Paired data cells (component)
- Card: radius 12px, 1.5px border (`--hairline` / `--border-strong` when highlighted), shadow `--shadow-float`, ~95% opaque.
- **Two-tone split**: top half = live value on dark (`--cell-top`, light text); bottom half = paired/average value on light (`--cell-bottom`, dark text). The light bottom stays light in BOTH themes — the black/white pairing is the legibility feature.
- Digits: **36px primary / 30px secondary**, 700/600 weight, labels 11px/9.5px muted below the number.
- All 6 cell slots are the same size and interchangeable; tap cycles metrics; one cycle state is blank (dashed border, centered "+").
- **Zones**: power and HR cells tint their TOP half with the zone color (`--z1`…`--z7`), white digits, zone tag appended to label ("W · 3 sec · Z2"). Non-zoned cells keep the dark top.
- Unpaired sensor state: bottom half shows "hold to pair" (12.5px, muted).

## Typography
- **Archivo** — UI, labels, body. Never for data digits.
- **IBM Plex Mono** — fast-changing digits (speed, power, cadence, heart rate). Fixed-width so digits don't jump.
- **Space Grotesk** — slow-changing digits (distance, time, stoppage %, ETA).
- Rule of thumb: *mono for physics, proportional for accumulation.*
- Cell values over 5 characters step down one size (36→30px). Only distance triggers this; preferred alternative: drop the decimal above 1,000 km ("1235 km") and never shrink.
- Worst-case widths to test: `99.9` speed · `1234.5` distance · `111.1h` time · 4-digit watts (brief).
- Google Fonts: `IBM+Plex+Mono:wght@500;600;700`, `Space+Grotesk:wght@500;600;700`, `Archivo:wght@400;500;600;700`.

## Design Tokens
All in `tokens.css` (two `data-theme` blocks). Highlights:

Paper: surface `#eae5d5`, raised `#fffef8`, sunken `#dcd5c0`, hairline `#cfc7ae`, text `#2a2721`, muted `#8a8271`, accent olive `#48562f`, warm `#a8622d`, route `#2f5f9e`, cell-top `#2a2721`.
Graphite: surface `#16181d`, raised `#22252b`, sunken `#101216`, hairline `#262a31`, text `#eef1f4`, muted `#8b939e`, accent `#4cd97b`, warm `#ffd166`, route `#5b9bd5`, cell-top `#101216`.
Semantic stops (both themes): SLEEP `#6f5f96`, FOOD `#a8622d`/`#ffd166`, WATER `#46688f`/`#5b9bd5`, FINISH `#a04a38`/`#e06a5a` (paper/graphite).
Zones: Paper `#8a8271 #46688f #5d7a3a #c98a2e #b5501f #a8382c #6f5f96`; Graphite (lifted) `#8b939e #4a7ab5 #6a9955 #d9a03c #d96c2e #cf4b3d #8f7fd0`.
Geometry: card radius 12px, panel radius 14px, borders 1.5px, min hit target 44px.

## Layout & behavior rules
- Max two surface colors per screen; hierarchy via raised/sunken steps + hairlines, never new hues.
- Everything floating over the map needs border + shadow (OSM tiles are light and busy).
- Warm-deep amber must not color power values in zoned contexts (false Z4 read).
- Hit targets ≥ 44px (gloved, one-handed operation is a core requirement).
- Semantic stop colors + emoji icons on planning tabs are kept as-is (good wayfinding).
- Mission/planning tabs: mono reserved for numbers; labels/body switch to Archivo; green demoted to accent (see 2a/2b mockups for reference).

## State Management
- `data-theme` attribute on `<html>`, persisted (localStorage/settings store).
- Cell metric assignments (6 slots × cycle position) — existing behavior, unchanged.
- Zone state per cell derived from sensor value vs. user's zone thresholds.

## Assets
- No new image assets. Emoji icons are used as-is. `uploads/pasted-1784532910240-0.png` in the mockups is a sample OSM screenshot used as a stand-in for the live map — not a shippable asset.

## Files
- `implementation-review.md` — prioritized fix list from v287 desktop screenshots (Mission cards, map legend, ride stop list, residual mono).
- `planning-tabs.md` — spec for Mission/Stops/Supplies: leg rows, stop-card states, contrast rules. Canonical mockups **6a / 6b**.
- `screenshots/4b-paper-ride.png`, `screenshots/5a-graphite-ride.png` — renders of the two canonical screens (2x, 780×1688).
- `Packtimes Ride Explorations.dc.html` — all mockups; **4b and 5a are canonical**.
- `Packtimes Style Guide.dc.html` — human-readable style guide.
- `tokens.css` — production-ready token sheet, both themes.
