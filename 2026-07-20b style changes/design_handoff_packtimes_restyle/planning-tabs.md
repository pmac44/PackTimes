# Packtimes Planning Tabs — Paper & Graphite Spec

Extends README.md + tokens.css to the planning tabs (Mission, Stops, Supplies, Route). Canonical mockup: **6a / 6b** in `Packtimes Ride Explorations.dc.html` (Paper / Graphite stop-card state sheets). Reuses the existing tokens — no parallel palette.

## Page frame (all planning tabs)
- Page bg: `--surface`. Tab bar and type rules identical to Ride screen.
- Page title row: 19px/700 Archivo title + muted count ("Mission · 27 stops"); filter buttons 36×32px, `--surface-raised` + `--hairline` border, radius 8px.
- Timeline spine (Mission): 2px vertical line in `--hairline`, 26px from left edge; cards indented 24px; each card gets a 10px dot on the spine in its semantic color.

## Typography on planning tabs
- Mono (IBM Plex Mono) is BANNED here — nothing changes fast. All numbers: Space Grotesk. All labels/body: Archivo.
- Green/accent is demoted to: active tab, leg distances, ETAs. Never body text.

## Leg-stat rows (between stop cards, no card chrome)
- Label: "DAY 1 · LEG 2" — 11px/700 Archivo caps, letter-spacing .8px, `--text-muted`.
- Distance: 22px/700 Space Grotesk in `--accent`, unit 12px `--text-muted`.
- Stats line (time · km/h · vm · grade): 13px Space Grotesk, `--text-soft`, separated by " · ".
- TOTALS block: same label style; values 15px/500 Space Grotesk `--text`; bivi total colored `--sleep-deep`.

## Stop cards — states
Card: radius 12px, 1.5px border, padding 12px 14px, bg/border per state:

| State | bg token | border token | dot/tag color |
|---|---|---|---|
| start | --card-start-bg | --card-start-br | --accent |
| sleep/bivi | --card-sleep-bg | --card-sleep-br | --sleep / --sleep-deep |
| food/meal | --card-food-bg | --card-food-br | --food / --food-deep |
| water | --card-water-bg | --card-water-br | --water / --water-deep |
| town/cluster | --card-town-bg | --card-town-br | --text-muted |
| finish | --card-finish-bg | --card-finish-br | --finish-deep |

Anatomy:
- Title row: emoji + name, 15px/700 Archivo in `--text` (16px for start/finish); optional supply emojis right-aligned 12px.
- Meta line: km · day/time · stop duration — 13px Space Grotesk `--text-soft`.
- Supply chip (optional): outlined pill, 11.5px, color + border `--food-deep` (or matching -deep), bg transparent on Graphite / faint tint on Paper.
- Town/cluster: neutral card, count badge ("4 stops") 11px/700 in `--text-muted`, chevron affordance right.

## Contrast rule (hard requirement)
- Body/title text on EVERY card tint is `--text` — never white-on-color, never the semantic color. All listed tints keep `--text` ≥ 7:1 (AAA).
- Colored text is allowed ONLY in tags/chips/dots and must use the `--*-deep` tokens, which are chosen to meet ≥ 4.5:1 (AA) on their card tint. On Paper the raw semantic colors FAIL on tints — always use `-deep` there.
- If a new tint is ever added: text = `--text`, derive the tint at ~12% semantic color over `--surface`, verify 4.5:1 for any `-deep` text on it.

## Other planning tabs
- Stops / Supplies lists: same card system without the timeline spine; rows on `--surface-raised` with `--hairline` separators; semantic tags identical to Ride footer (outlined, 10px caps).
- Footer banners (e.g. "Food plan"): `--surface-raised`, 1.5px `--card-food-br` border, title in `--food-deep`, sub in `--text-muted`.
