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
Dots read the token directly (`.d-food{background:var(--cat-food)}`). Tag chips
derive their tint from the SAME token so they can never drift:
```
.t-food{background:color-mix(in srgb,var(--cat-food) 15%,transparent);color:var(--cat-food);}
```
When you add a new stop category, add ONE `--cat-*` token and follow this pattern.

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
