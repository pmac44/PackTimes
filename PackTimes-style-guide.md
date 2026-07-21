# PackTimes — Design System

Ground rules for all UI work on PackTimes. The current `index.html` already
follows this system (restyled July 2026). Companion visual reference:
**PackTimes Design Reference.dc.html**.

---

## Design tokens (source of truth)

All of these live in `:root` in the `<style>` block. **Use the tokens — never
hard-code px sizes, spacing, radii, or category hex again.**

### Type scale — 5 steps only
```
--fs-xs:13px    labels · tags · captions · stat labels · field labels
--fs-sm:15px    meta · secondary text
--fs-base:17px  body · inputs · buttons · SECTION HEADINGS (.ctitle, 600 wt) · banners
--fs-lg:20px    stat values
--fs-xl:26px    hero numbers
```
Fonts: **DM Sans** for UI/prose, **DM Mono** (`--font`) for numbers, labels, metrics.

**Unit symbols follow SI casing, always**: km, m, h, min, s, °C, km/h — never KM, Kms,
Km or KPH. (KM would read as kelvin·mega. Peter's rule, 15 Jul 2026.) Unit symbols
take no plural s and no full stop.

> Hierarchy rule: section heading (17, bold, uppercase) > body/button (17) >
> meta (15) > label/tag (13). Don't shrink section headings to caption size.

### Spacing — 4px grid
```
--sp-1:4px  --sp-2:8px  --sp-3:12px  --sp-4:16px  --sp-5:24px
```
Card/modal padding = `--sp-4`. Between fields = `--sp-3`. List gaps = `--sp-2`.

### Radius — two only
```
--r-ctrl:8px   buttons, inputs, chips, tags, list items
--r-card:12px  cards, modals, upload zones
```

### Category hues — one variable per stop type
```
--cat-town --cat-food --cat-water --cat-shop --cat-sleep --cat-accom
--cat-fuel --cat-hut --cat-camp --cat-caravan --cat-peak --cat-crossing
--cat-wc --cat-stop --cat-church --cat-school --cat-hall --cat-fire --cat-police
```
Dots read the token directly (`.d-food{background:var(--cat-food)}`). Tag chips carry TWO
hue vars: `--c` (the dot/text hue, for the dark wash) and `--cs` (the solid CHIP fill):
```
.t-food{--c:var(--cat-food);--cs:var(--chip-food);}
.tag{background:color-mix(in srgb,var(--c) 15%,transparent);color:var(--c);}  /* wash = DARK look */
```
**Chips are per-theme (v306/v308):** the wash above is the DARK (Graphite) look — bright hues
glowing on a dark card. In **Paper (light)** a single override inverts every chip to a SOLID
fill with white ink, so it reads as a badge on the light Ride strip AND on the dark slate cards
(a 15% wash of a dark hue on a light page is nearly invisible):
```
[data-theme="paper"] .tag{background:var(--cs,var(--c));color:#fff;}
```
**Why a separate `--chip-*` set (not just `--cat-*`) — important:** `--cat-*` is tuned two ways
that both fail as a solid fill. Top-level Paper `--cat-town` is a dark *olive* (tuned as dark
TEXT on the light page) → a dull chip; and inside `[data-theme="paper"] .si` the cats are
rebound to *pastels* (tuned as bright dots/text on the dark stop card) → a washed-out chip. So
solid chips use `--chip-*`: ONE vibrant mid-tone per category, defined in the Paper `:root` and
NOT rebound by `.si`, so the chip is identical and saturated on the strip and the cards. White
text stays legible on every one. `--cat-*` still drives dots and text; `--chip-*` drives chips.

This is the general rule: **colour treatments are chosen per theme, not shared** — and a colour
tuned for text/dots is not automatically right as a fill. Set each in the theme's `:root`.

When you add a new stop category: add `--cat-*` (dot/text) + `--chip-*` (chip fill) + one
`.t-x{--c:…;--cs:…}` line — both themes then just work.

### Card surfaces — the one contrast slate
There is ONE contrast-card colour, `--stop-card-bg` (a mid-dark cool slate on Paper,
already-dark on Graphite). It is the card background across the app: Stops, Mission, **and
(from v305) the Route, Supplies and Settings tabs**. Those three tabs used to sit on a near-
white card that barely lifted off the warm page; they now match the rest.

Cards on those three tabs get the slate by **rebinding the colour tokens on the `.card`
element itself** (see `.content.tab-routes/.tab-food/.tab-settings .card` in `index.html`):

```
--card:var(--stop-card-bg); --card2:var(--slate-card2); --border:var(--stop-card-br);
--text:var(--slate-text); --text2/3:…; --bg3:var(--slate-inset); --accent:var(--slate-accent);
```

Because the tokens are set on the card (not the tab container), the page gaps between cards
stay the normal page colour, and everything INSIDE the card — text, buttons, inputs, stat
boxes — inherits the light-on-slate palette automatically. **Never hard-code a card colour or
its text colour** — tune `--stop-card-bg` or the `--slate-*` tokens (defined per theme in
`:root`) and every card follows. On Graphite the `--slate-*` values mirror the existing dark
card, so it's a near-no-op there.

### Chrome on the light page must be theme-aware, never white-alpha
Controls that overlay the page (e.g. the Stops drag-grip) must NOT use bare
`rgba(255,255,255,…)` — that shows up in dark mode but is invisible on the Paper page. Drive
them from per-theme tokens instead (`--grip-bg`, `--grip-stroke`, …): dark marks on light in
Paper, the white-alpha look in Graphite. Same rule as the deleted `.mhint` (translucent text
over content whose colour we don't control is an invisible label, not a subtle one).

---

## Iconography

- **No emoji in UI chrome.** Tab bar, header logo, and transport controls use
  inline SVG line icons (stroke `currentColor`, `stroke-width:1.5`, 18×18 viewBox).
- Tab icons are built from the shared `_ti` SVG-open string in the `TABS` array.
- Disclosure triangles (▼ / ▶) are intentional typography — keep those.
- **Still emoji (not yet converted — safe follow-ups if wanted):** stop-category
  pins drawn on the canvas map + in list rows (🍴💧😴📍 …), and a few inline tip
  icons (👆 ⭐ 📊). Converting these touches the map's canvas rendering, so it's a
  separate, larger job.

---

## Components (consolidate toward these)

- **Buttons:** one base `.btn` (17px, 8px radius). Variants `.btn-p` (primary/green),
  `.btn-r` (danger), size `.btn-sm` (15px). Hover/active = border+text → `--accent`.
  Retire ad-hoc inline button styles.
- **Inputs:** shared rule, 8px radius, 17px, accent focus ring
  (`box-shadow:0 0 0 3px rgba(74,222,128,.12)`).
- **Stepper (−/value/+):** should be ONE shared component reused in the add-stop,
  edit-stop, and date modals — currently rebuilt 3×. (Not yet refactored.)
- **Modals:** many use one-off inline styles that duplicate `.lbl` / `.ctitle`.
  Prefer the shared classes over re-inlining. (Not yet refactored.)

---

## Not yet done (candidate next steps)
- Category emoji pins on the map/list → SVG (touches canvas rendering).
- Shared stepper + modal-label components (kill duplicated inline styles).
- Inline tip emoji (👆 ⭐ 📊) → icons.
