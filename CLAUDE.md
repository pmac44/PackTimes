# PackTimes — project guide for Claude

This file is loaded automatically whenever we work in this folder. Its job is to get me up to speed on PackTimes fast, so we don't burn time rediscovering the structure on every task.

Peter, if anything below goes stale, tell me and I'll update this file rather than carrying on with wrong assumptions.

---

## What PackTimes is

PackTimes is an ultra-cycling and bikepacking route planner **and ride recorder**, shipped as an installable PWA. A rider loads a route file (GPX / TCX / KML / FIT), and the app plans the ride — pace by surface type, stops (food, water, sleep, fuel, accommodation), weather and daylight along the way, a printable mission brief, and a Live "Ride" tab with GPS tracking, turn beeps, off-route alerts, and adaptive pace calibration. Since July 2026 it also **records rides** (movement-based GPS sampling, crash recovery, screen-off gap reconstruction along the route), lists them in a Rides card on the Route tab, exports FIT/GPX, and **auto-uploads finished rides to Strava**.

- Deployed at https://pmac44.github.io/PackTimes (GitHub Pages).
- Repo: https://github.com/pmac44/PackTimes.
- Works offline after first install (service worker caches app + map tiles).
- Optional Dropbox sync of plans across devices.

## Current status (9 July 2026, v200)

**v200 (9 Jul 2026) — plain-English wording in the fatigue popup.** Replaced
"the model" with "PackTimes" (Peter: "model"/"algorithm" read as jargon to a
non-technical rider) and softened "trims pace" → "slows your pace"; tooltip now
"How the fatigue setting works".

**v199 (9 Jul 2026) — fatigue help moved into a "?" popup.** Stripped all inline
explanatory text from beside the Fatigue setting and put it behind a "?" button
next to the heading (matching the surface-types help pattern). New
`showFatigueHelp()` mirrors `showSurfHelp` (bottom-sheet, z-index 9999 over the
z-998 speed-modal). Popup covers what it does + the one/two/three-night
reliability guide + heat/cooked-legs caveat. The situational amber ">20h without
a sleep stop" warning stays inline. Panel is now just: Fatigue [?] · Off | On.

**v198 (9 Jul 2026) — fatigue limitations explainer.** Added a collapsed "How
reliable is this?" `<details>` under the Fatigue On/Off (superseded by v199's
popup). Figures grounded in `_planning/sleep-fatigue-research.md`.


**v197 (9 Jul 2026) — Strava ride-name sync.** Renaming a recorded ride (save
prompt or detail-modal Rename) now pushes the new title to Strava without
delaying or re-doing the upload. Upload stays immediate and top-priority; the
sync is a name-only PUT to `/activities/{id}` (never re-sends the FIT/route),
marked `stravaNamePending` and retried by the queue if it fails. See the STRAVA
row in the code map and the "Ride name stays in sync" behaviour note below.
Written + syntax-checked, not yet ride-tested.


**Phase 1a (recording + Strava) is essentially complete and field-tested.** The living
step-by-step record is in `_planning/phase-1a-build-plan.md` (progress notes at the top);
the five-phase roadmap is `_planning/architecture-plan.md`. Done and confirmed on real
rides: recording engine, crash-recovery modal, gap detection + route-based fill,
saved-rides view + detail modal (zoomable map, dashed gap-filled sections), FIT/GPX
export, Strava OAuth + auto-upload + retry queue. Strava athlete capacity is raised to
10 — first beta tester connected 9 July. Deliberately deferred: Step 10 ("want to
record?" prompt) and Step 11 (storage expiry warning — mostly moot given auto-upload).
v178–179 added ride naming (save prompt after gap decisions, Rename in detail modal,
"Recorded Rides" card title) and the **calibration feed**: saved rides can enter
`UI.calibRides`, with surface/climb/load auto-read from the followed route
(`_recCalibAuto`) and ride time from the points (`_recMovingH` — the v179 "faff rule":
stops under 15 min count as ride time, longer deliberate breaks are excluded; NOT
strict Strava moving time, deliberately). Live-ride test pending.
**Next big move: Phase 1b, the Capacitor wrap** for true background GPS; the gate is a
couple of clean soak-test rides. Peter is wary of wrapping too early (slower iteration) —
don't push it.

**v189 (8 Jul 2026) — actuals no longer pollute a future-dated plan.** Bug: on a
route planned for the future (Grenfell, start Sat 8 Aug), the Finish time and per-stop
ETAs were anchoring to ~now instead of the planned start. Root cause: `actualStartTime`
(route) and `actualArrival` (per stop) are stamped whenever GPS *tracking* is on near
the loaded route — this is NOT tied to the Record button (recording is the separate
`_rec`/`startRecording` path). A stray fix while planning left a stale stamp, and
`startDT`/`etaAt` then let it override the plan. Agreed principle with Peter: the line
that matters is "riding this now" vs "planning a future run", and the signal is the
**plan's start date** — not record-vs-track. Actuals stay useful mid-trip (e.g. GPS off
in the tent, ETAs projected from the last real arrival), we just stop a *future-dated*
plan from capturing or using them. Fix (all `index.html`): `startDT` ignores an
`actualStartTime` that predates the planned start; new helpers `planStartInFuture(r)` +
`clearRouteActuals(r)`; `etaAt` skips both the `actualArrival` anchor and the
saved-GPS-position anchor when `planStartInFuture`; the GPS watch callback won't stamp
when `planStartInFuture`; and setting a NEW start **date** (date-time picker OK +
`inp-date`, not time-only tweaks) auto-clears the old stamps. `clearRouteActuals` only
touches the plan's anchors — the separate `recordings` store is never affected.

## Architecture in one sentence

**Everything lives in `index.html`.** HTML, CSS, and JS are all in that one ~13,600-line file. There is no build step, no bundler, no framework — it's vanilla JS with IndexedDB for storage and Canvas for maps and elevation. Edits are made directly to `index.html` and pushed to GitHub; Pages serves it.

### Files in the repo

| File | What it is |
|---|---|
| `index.html` | The entire app. ~13,600 lines. |
| `manifest.json` | PWA manifest (name, icons, theme colour, standalone display). |
| `icon-192.png`, `icon-512.png` | PWA icons. |
| `push.bat` | Peter's Windows one-click deploy: `git add . && git commit -m "Update app" && git push`. |
| `_planning/` | Architecture plan, Phase 1a build plan (with progress notes), GPS-fixes log, and the `fit-spike/` FIT-encoder test harness (incl. Garmin SDK for round-trip verification via Node). |
| `PackTimes-style-guide.md` | Styling source of truth — read before UI changes. |
| `backup/` | Pre-restyle backup of index.html. |
| `.git/` | Local git history. Remote: `origin` → GitHub. |

### Deploy flow (Peter's)

1. Edit `index.html` locally (Windows, path `F:\Dropbox\Claude\Work Areas\Apps\PackTimes-project` — the old `C:\Users\peter\Documents\PackTimes` location is retired; `push.bat` was fixed July 2026 to cd to the Dropbox path explicitly).
2. Double-click `push.bat` → commits as "Update app" and pushes to `origin/main`.
3. GitHub Pages picks it up and serves at `pmac44.github.io/PackTimes`.

**Versioning (since v176): bump ONLY `window.APP_VERSION` in the STATE section.** The
service worker's `CACHE_NAME` derives from it, and Settings displays it at the bottom so
Peter can always see what his phone is running. The SW page fetch uses `cache:'no-cache'`
(revalidates with GitHub every load), so a push shows up on the phone's next app-open —
no more 10-minute GitHub-cache lag. Discipline: one step = one version bump = one push.

Commit messages are all "Update app", so `git log` is not a useful context source — don't try to lean on it to understand history. If I need to know why a change was made, I should ask Peter (or check the `_planning/` docs, which since July 2026 double as the change log).

---

## Code map: where things live in `index.html`

The file is organised with clear banner comments (`// ═══...`). Section boundaries are stable and line numbers below are accurate as of 9 July 2026 (v188, ~13,600 lines) — **they WILL drift; grep for the banner comment rather than trusting the number.**

### Top of file

| Lines | What |
|---|---|
| 1–11 | Doc comment & copyright. |
| ~12–600 | `<head>`, CSS (inline `<style>`), and HTML skeleton: header, tab bar, `content-wrap`, and the static modals — edit-stop, add-stop, **rec-recovery-modal** (crash recovery), **rec-detail-modal** (ride detail: map/elev canvases, fill-gaps/Strava/export/copy/delete buttons), **rec-gap-modal** (gap-fill choices), pace modal, etc. |
| ~600 | `<script>` opens — JavaScript starts here. |

### JavaScript sections (banner-delimited; grep the banner, e.g. `//  RECORDING`)

| ~Line | Banner / area | What it owns |
|---|---|---|
| 605 | `INDEXED DB` | `DB` module: `packtimes` IDB **v4**, three stores: `routes`, `kv`, `recordings`. Exposes `put/get/all/del/setKV/getKV` + `putRecording/getRecording/allRecordings/delRecording`. |
| 638 | `STATE` | `window.APP_VERSION` (single source of release version), `ROUTES[]`, `CUR`, `newRoute`, `cur()`, and the big `UI` object (incl. Dropbox + Strava auth state, `settingsExp` — **new Settings sections must be added to this key list or their header won't toggle**). |
| 675 | `PERSIST` | `packRoute/unpackRoute`, `saveAll()` (routes + kv incl. `stravaAuth` blob + `uiPrefs`), `loadAll()`. |
| 827–1420 | Parsers + maths | `GPX/TCX/KML/FIT PARSE`, then (unbannered) geometry helpers (`hav`, `bearing`, `autoDetectTurns`) and the **speed/pace model** (`VAM_BY_SURFACE`, `segTimeH`, `naismith`, `buildCumRiding`, `rebuildPace`) — **the heart of the planner; changes here affect every ETA**. |
| 1421 | `OPENING HOURS PARSER` | `parseOH`, `isOpen`, `fmtOHSummary`. |
| 1475 | `TIME CALC` | `startDT` (prefers `actualStartTime`, but ignores one that predates the planned start), `planStartInFuture(r)` + `clearRouteActuals(r)` (v189 plan-vs-actual guards), sleep/meal totals, `etaAt(distKm, r)` — distance → ETA (skips actual/saved-position anchors when the plan start is in the future). Then date/time formatters (`fmtT/fmtDT/fmtDTY/fmtHM`). |
| 1750 | `STOPS` | `addStop/delStop`, surface categories. |
| 1780 | `OVERPASS` | POI search, Nominatim geocode, Geoapify accommodation, surface fetcher, and `snapTo(r,lat,lon,lastIdx)` → `{idx, dist, off}` (off = km from route). |
| 2406 | `GPS` | `toggleGPS/startGPS/stopGPS`, the watch callback (feeds recording via `_appendPoint`), idle auto-pause, **dead-watch recovery**: `_gpsRestartWatch()` + 30 s watchdog (`GPS_WATCHDOG_MS`) — rebuilds the geolocation watch on wake and whenever fixes stop arriving (the OS silently kills watches during suspension). |
| 2655 | `ADAPTIVE SPEED CALIBRATION` | `runAdaptiveCalibration`, `updateGPSPill`, drift caps. |
| 2779 | `RECORDING` | The whole Phase 1a recording pipeline: movement-based sampler (`_appendPoint`, active/stationary state machine), **gap detection** (>15 s no-fix + ≥100 m moved; ≤2 min auto-fills silently), **gap fill engine** (`_recFillGap`, route/Naismith via `cumRiding` weighting, straight-line fallback, `_synthetic:true` points, `_recRecomputeTotals`), **crash recovery** (`_recRehydrate`, recovery modal, typed-delete), **saved rides** (`RECS` in-memory cache, `_ridesCardHTML`, detail modal incl. `_recAsRoute` route-shaped projection + dashed synthetic overlay), **end-of-ride gap prompt** (`_recGapArm/_recGapMaybeShow`, never mid-ride), export helpers (`exportRecordingAsFIT/GPX`, `_recToast`), stop/undo tap handlers, and the **ride save prompt + calibration feed** (v178–179: `_recDefaultName`, `_recMovingH` ride time via the faff rule (<15 min stops count, longer breaks excluded), `_recCalibAuto` route-derived surface/climb/load, `_recSaveShow` modal, `_recCalibAdd` → `UI.calibRides` entries carrying `src:'rec'`/`recId`/`name`, oldest-recorded eviction when full). |
| 3571 | `FIT WRITER` | Hand-rolled Activity FIT encoder (`encodeActivityFit`), proven against Strava + Garmin SDK (spike harness in `_planning/fit-spike/`). |
| 3968 | `STRAVA` | OAuth (authorization-code; secret embedded — accepted trade-off), `stravaFreshToken` silent refresh, `stravaUpload` (FIT multipart + status polling, `external_id packtimes-<recId>` dedupe), `stravaQueue`/`stravaProcessQueue` retry queue (backoff 30s→daily + online/visibility/GPS-return triggers). Auto-upload fires only AFTER gap decisions. **v197:** `stravaSyncName`/`stravaMarkRename` push a renamed ride's title to Strava via PUT `/activities/{id}` (name only, no re-upload); the queue has a best-effort rename pass so failures retry on the same triggers. Upload FormData `name` now uses `rec.name`. |
| 4280 | `RIDE SIMULATOR` | GPX playback. Gap detection + watchdog + Strava GPS-trigger all skip when sim is running. |
| 4984 | `MAP ENGINE` | Canvas maps: `_ms` per-canvas state, `getTile/drawTiles/drawMap` (stores projection on canvas: `cvs._px/_py`), `redrawMap` (special-cases `rec-detail-map` → `_recDetailRedraw`), `attachMap` (gestures), offline-tile prefetcher. |
| 6363 | `ELEVATION CANVAS` | `drawElev(cvs, r)`. |
| 6406 | `MODAL` / `PACE SEGMENT MODAL` | Stop add/edit + date-time picker; pace overrides. |
| 7218 | `RENDER` + `DESKTOP LAYOUT` | `_render()` central dispatcher (start here for anything visual); `IS_DESKTOP()`, `initDesktop`, `renderDesktopMap`. |
| 7595 | `DROPBOX SYNC` | OAuth PKCE, debounced plan sync. The page-load `?code=` dispatcher (just after this section) routes by `state` prefix: `strava_` → Strava, else Dropbox. |
| 7964 | `SHARE WHOLE RIDE` | Route+plan share file, QR. |
| ~8300–9800 | Tab templates | `tRoutes` (incl. Rides card), `tStopsShell`, `tLiveShell`, `tPlan`, `tGear`, `tFood`, `tSettings` (Strava panel, Dropbox, …, danger zone, version footer), plus weather (Open-Meteo) and sunrise/sunset helpers. No banners here — grep function names. |
| 11478 | `TARGETED LIVE UPDATE` | `updateLive()` — surgical DOM patches on the Live tab; never collapse into `render()` mid-ride. |
| 11826 | `EVENT DELEGATION` | Document-level click delegator — most interaction routes through here (settings headers, ride rows, Strava buttons, route list, …). |
| 13045+ | `BLANK PLAN` / `APPLY GPX` / `DEMO ROUTE` / `POWER METER` | Route creation from files/geocode; BLE sensors. |
| 13545 | `INIT` | `loadAll().finally(...)`: reset sim/GPS, `initDesktop`, `render`, `_recRecoveryShow()` (crash-recovery prompt), `dbxAutoLoad`. |
| 13560+ | Service worker (2nd `<script>`) | Registered from a Blob. `CACHE_NAME='packtimes-'+window.APP_VERSION` — **never edit here; bump `APP_VERSION` in STATE instead.** Page fetch is network-first with `cache:'no-cache'` revalidation; tile cache `packtimes-tiles-v1` survives updates. |

---

## Data model

### `route` object

```js
{
  id: string,              // base36 timestamp + random
  name: string,
  label: string,           // optional display name
  points: [{lat, lon, ele, dist, time}],  // packed as arrays on save
  hasTS: bool,             // true if source file had timestamps
  totalDist: km,
  estDuration: hours,      // rebuilt on load from cumRiding
  startDate: 'YYYY-MM-DD',
  startTime: 'HH:MM',
  actualStartTime: ms,     // set by GPS when ride begins; overrides planned start
  timeFactor: 1.0,         // user multiplier on pace
  baseTimeFactor: 1.0,     // adaptive-calibration baseline
  stops: [stop],
  paceSegs: [{from, to, hours}],  // user pace overrides
  turns: [...],            // detected or manually edited
  adaptiveSpeed: bool,
  riderPreset: 'regular' | ...,   // see RIDER_MULT
  loadPreset: 'moderate' | ...,   // see LOAD_MULT
  daySplitCount: n,
  cumRiding: [hours],      // cumulative riding hours to each point; rebuilt on load
  gearChecklist: null | {...},
}
```

### `stop` object

```js
{
  id: string,              // alphanumeric, migrated on load if short/numeric
  dist: km,
  type: 'food'|'water'|'shop'|'town'|'fuel'|'accom'|'camp'|'caravan'
       |'pub'|'church'|'school'|'hall'|'fire'|'police'|'sleep'|'stop'|'hut'|'wc',
  name: string,
  lat, lon: number,
  sleepAt: bool,           // overnight at this stop
  auto: bool,              // auto-placed vs user-placed
  ohRaw: string,           // OSM opening-hours source
  ohRules: [{days:Set, ...}],   // parsed; Sets are restored on load
  starred: bool,
}
```

Old stop types `rest` and standalone `sleep` are migrated on load to `stop` with `sleepAt:true` — see `unpackRoute`.

### `recording` object (stored raw in the `recordings` store — NOT packed)

```js
{
  id: string,                    // base36 timestamp + random
  name: string|undefined,        // assigned at finalise ("Ride 8 Jul 2026", "(2)" suffix on dupes); Rename in detail modal
  routeId: string|null,          // route loaded when recording started (drives gap fill + Rides grouping)
  status: 'active'|'paused'|'finalised',
  startTS, endTS: ms,            // endTS null until finalised
  points: [{lat, lon, ele, t, accuracy,
            _stop?: true,        // sampler entered stationary mode here
            _resume?: true,      // movement resumed here
            _synthetic?: true}], // gap-fill point (drawn dashed; flagged in GPX)
  gaps: [{startT, endT, startLat, startLon, endLat, endLon,
          fillStrategy: 'none'|'route-naismith'|'route-constant'|'line',
          queued: bool}],        // queued=true → awaiting user's fill decision
  totalDist: km,                 // incremental; recomputed from scratch after any fill
  totalDur: ms,
  stravaUploadedAt: null|ms,
  stravaActivityUrl: null|string,
  stravaUploadStatus: null|'queued',   // 'queued' = in the retry queue
  stravaUploadAttempts: [{at, ok, error?, note?}],
  stravaNamePending: bool,             // v197: a rename needs syncing up to Strava (best-effort, retried by the queue)
}
```

`_recMigrate` handles old-shape rows (e.g. early recordings stored `totalDist` in metres). Finalised recordings are mirrored in the in-memory `RECS[]` cache (loaded in `_recRehydrate`, kept in sync on finalise/undo/delete/recovery) so templates can render synchronously.

### Storage

- **IndexedDB `packtimes` v4**
  - `routes` store, keyed by route id (packed via `packRoute`)
  - `recordings` store, keyed by recording id (raw objects)
  - `kv` store for: `cur`, `dbxToken`, `dbxRefreshToken`, `dbxSavedAt`, **`stravaAuth`** (token/refresh/expiresAt/athlete/autoUpload blob), `uiPrefs` (big blob, incl. `recId` for mid-ride reload recovery), `lastGpsState`, `sunCache`, `weatherCache`.
- **Cache API**
  - `packtimes-v{N}` — app shell; name derives from `APP_VERSION` (v188 as of 9 July 2026).
  - `packtimes-tiles-v1` — prefetched map tiles (survives app updates).

---

## External services

Everything the app talks to:

| Service | Purpose | Needs key? |
|---|---|---|
| Open-Meteo (`api.open-meteo.com/v1/forecast`) | Weather along route | No |
| OSM Overpass (3 mirrors) | POI search + surface types | No |
| OSM Nominatim | Town geocode | No |
| OSM tile servers, ArcGIS World Imagery, CyclOSM, OpenTopoMap | Map tiles | No |
| Geoapify Places | Accommodation search | **Yes** — user supplies `UI.geoapifyKey` in Settings |
| Dropbox API | Plan sync | OAuth PKCE, no secret needed |
| Strava API | Ride upload (OAuth + FIT upload + status polling) | **Yes** — client ID 230638; secret embedded in `index.html` (accepted trade-off, no backend). Athlete capacity raised to 10 (Jul 2026) for beta testers; beyond 10 needs Strava's app review. |
| Weather radar sites per country | External link in Live tab | No |

No analytics, no user accounts, no backend.

---

## Important behaviours & conventions

- **Vanilla everything.** No React, no framework, no bundler. Don't suggest adding one — it would break the "one file, one push" deploy model Peter relies on.
- **`render()` vs `updateLive()`.** `render()` rebuilds the current tab's HTML. `updateLive()` patches DOM in place on the Live tab so it doesn't flash during a ride. When editing anything that affects the Ride tab mid-ride, preserve the `updateLive()` path — don't collapse it into a `render()` call.
- **`_render()` uses `requestAnimationFrame`.** Wrapped by `render()` which sets `_rf` to coalesce calls. If something doesn't update, check that the calling code goes through `render()` and not raw DOM writes.
- **Routes are packed for storage.** `packRoute` compresses `points` into 5-element arrays for IDB. `unpackRoute` expands them back and always rebuilds `cumRiding` and `estDuration`. Never trust `estDuration` stored on disk.
- **Australian spelling** throughout user-facing strings ("kilometres", "metre"). Match that when writing new copy.
- **Units are metric.** km / metres / °C / km/h / hours.
- **`console.log` is used sparingly**, `catch(()=>{})` silent-swallow is common on IDB writes. Don't add noisy logging unless debugging.
- **Ship a release by bumping `window.APP_VERSION` in STATE — nothing else.** The SW cache name derives from it and Settings displays it. Never hand-edit `CACHE_NAME`.
- **Recording is sacred.** Never delete a recording without typed confirmation; every recording state change persists via `DB.putRecording`; the `RECS[]` cache must be kept in sync with any mutation. Gap fill never invents a path — route-snapped or straight line only, always flagged `_synthetic`.
- **Actuals follow the plan's start date (v189).** `actualStartTime` / `actualArrival` are "what really happened on the ride" stamps. They must only ever apply while the route is being ridden — i.e. its start date is today or past. A **future-dated plan** must never capture or use them (`planStartInFuture(r)` gates both the GPS-callback capture and the `etaAt` anchoring). Setting a new start **date** clears old stamps via `clearRouteActuals(r)`. These stamps live on the route/stops, NOT in the `recordings` store — clearing them never affects a saved ride. Note the capture is driven by GPS *tracking* being on, not by the Record button.
- **Auto-upload ordering matters:** Strava upload fires only after gap-fill decisions (`_recGapFinish` / the post-undo timeout), so uploaded FITs include the fills. Recovery-saves and manual re-fills don't auto-upload.
- **Ride name stays in sync with Strava (v197), without blocking the upload.** Upload is unchanged/immediate; renaming a ride (save prompt or detail-modal Rename) calls `stravaMarkRename` → sets `stravaNamePending` (only if the ride is uploaded or queued for Strava) → `stravaSyncName` PUTs just the name to `/activities/{id}`. It never re-sends the FIT/route and never delays the upload; a failed sync stays pending and is retried by the queue's rename pass on the normal triggers. Scope already includes `activity:write`, so no re-auth. If a ride is named *before* upload, the upload just carries `rec.name` up directly.
- **The simulator must stay excluded** from gap detection, the GPS watchdog, and the Strava GPS-return trigger (`UI.simRunning||UI.simPaused` guards) — sim fixes have artificial timing.
- **Dropbox sandbox sync lag (Claude-specific):** the bash sandbox sees a stale, sometimes truncated replica of this folder. Verify `index.html` via the Read tool, never repair from the bash view; syntax-check new code as extracted fragments.
- **Copyright notice** at the top of `index.html` must stay intact.

---

## Design system — READ THE STYLE GUIDE

`PackTimes-style-guide.md` (in this folder) is the source of truth for all UI styling. **Before making any change that touches CSS, HTML structure, or user-facing UI, read that file and follow it.** The short version:

- All sizing, spacing, radii, and category colours come from CSS tokens in `:root` — never hard-code px values or hex colours. Type scale has 5 steps (`--fs-xs` to `--fs-xl`), spacing is a 4px grid (`--sp-1` to `--sp-5`), radius is two values only (`--r-ctrl` 8px, `--r-card` 12px).
- New stop categories get ONE `--cat-*` token; dots and tag chips both derive from it (chips via `color-mix`).
- No emoji in UI chrome — tab bar, header, and transport controls use inline SVG line icons (stroke `currentColor`, 1.5 width, 18×18 viewBox). Map/list category pins are still emoji — that's a known, deliberate exception.
- Buttons use `.btn` / `.btn-p` / `.btn-r` / `.btn-sm`; inputs use the shared input rule with the accent focus ring. Don't invent ad-hoc inline styles.

The current `index.html` was restyled to this system in July 2026 (Peter has a backup of the pre-restyle version).

## How I (Claude) should work on this codebase

Peter has been clear in his global instructions:

- Plain English. No jargon. He's an industrial designer, not a coder — explain choices the way you'd explain them to a smart friend, not to an engineer.
- Be warm but direct. Flag rabbit holes and scope creep.
- Keep it simple. Reliability over performance. Don't build a spaceship when a bicycle will do.
- Never delete / send / overwrite without asking.

Specifically for this repo:

- **Before editing `index.html`, grep for the banner comment of the section you're changing** rather than trusting the line numbers above. They will drift.
- **Prefer `Edit` over `Write`.** The file is huge and one bad overwrite would cost a lot. Verify the `old_string` is unique or include more context.
- **When adding a new function, put it in the right banner section.** If there isn't one, ask before adding a new banner.
- **Don't change the data model casually.** `unpackRoute` has migration logic going back through multiple shape changes — adding another migration is fine, but changing existing shapes risks breaking Peter's existing saved routes. If a change needs a migration, call it out explicitly before writing it.
- **Deploy is just `push.bat`.** No CI, no build. So any change I write lands in production as soon as Peter runs that script — test locally first by opening `index.html` in a browser.
- **For any change that affects ETAs, stops, pace, or time calculations,** think about whether existing saved routes need `rebuildPace` / `buildCumRiding` called on them. Peter cares about reliability — a silent regression in ETA accuracy is exactly the kind of bug he'd hate.
- **Offer options + recommendation.** When there's more than one reasonable approach, give him the options and then say which one I'd pick and why.

---

## Open questions for Peter (things I'd want to know)

These aren't urgent — just things to clarify when relevant:

- Do you ever work on this on the iPad, or only on the Windows desktop? (Affects whether I should worry about CRLF line endings or path style.)
- Is there a staging/preview branch, or do all commits go straight to `main` → production?
- Is `plan.json` in Dropbox a schema you want kept stable (for backwards compatibility with older app versions), or are you fine with me evolving it?
