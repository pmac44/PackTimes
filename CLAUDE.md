# PackTimes — project guide for Claude

This file is loaded automatically whenever we work in this folder. Its job is to get me up to speed on PackTimes fast, so we don't burn time rediscovering the structure on every task.

Peter, if anything below goes stale, tell me and I'll update this file rather than carrying on with wrong assumptions.

---

## What PackTimes is

PackTimes is an ultra-cycling and bikepacking route planner **and ride recorder**, shipped as an installable PWA. A rider loads a route file (GPX / TCX / KML / FIT), and the app plans the ride — pace by surface type, stops (food, water, sleep, fuel, accommodation), weather and daylight along the way, a printable mission brief, and a Live "Ride" tab with GPS tracking, turn beeps, off-route alerts, and adaptive pace calibration. Since July 2026 it also **records rides** (movement-based GPS sampling, crash recovery, screen-off gap reconstruction along the route), lists them in a Rides card on the Route tab, exports FIT/GPX, and **auto-uploads finished rides to Strava**.

- Deployed at https://pmac44.github.io/PackTimes (GitHub Pages).
- Repo: https://github.com/pmac44/PackTimes.
- Works offline after first install **since v335** (service worker `sw.js` caches app + fonts + map tiles).
  Before v335 offline NEVER worked — see the v335 changelog entry. `sw.js` must stay a real file.
- Optional Dropbox sync of plans across devices.

<!-- REFERENCE — durable. Everything above the version log stays put. -->

## Architecture in one sentence

**Everything lives in `index.html`.** HTML, CSS, and JS are all in that one ~13,600-line file. There is no build step, no bundler, no framework — it's vanilla JS with IndexedDB for storage and Canvas for maps and elevation. Edits are made directly to `index.html` and pushed to GitHub; Pages serves it.

### Files in the repo

| File | What it is |
|---|---|
| `index.html` | The entire app. ~13,600 lines. |
| `manifest.json` | PWA manifest (name, icons, theme colour, standalone display). |
| `icon-192.png`, `icon-512.png` | PWA icons. |
| `push.bat` | Peter's Windows one-click deploy: `git add . && git commit -m "Update app" && git push`. |
| `.github/workflows/supabase-keepalive.yml` | Scheduled GitHub Action: pings the Supabase backend daily so the free tier never pauses it. Every 3 days was NOT enough — see External services. |
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
| after STRAVA's retry triggers | `INTERVALS.ICU` (v377) | Direct FIT upload to intervals.icu with an API key (basic auth, username `API_KEY`, athlete `0` = key owner): `icuVerifyKey`, `icuQueue`/`icuQueueAll`/`icuUpload`/`icuProcessQueue` (same backoff constant + triggers as Strava), `icuSyncName`/`icuMarkRename`, `_recIcuStatusHTML` (detail modal line), `_recSyncBadgeHTML` (Rides card pills — now also draws the Strava pill). Auto-send fires at the same three points as Strava. Key lives in the `intervalsAuth` KV row. |
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
| end of file | SW registration (2nd `<script>`) | Registers **`sw.js?v='+APP_VERSION`** (real file — blob registration never worked, see v335). Worker logic lives in `sw.js`: cache `'packtimes-'+v` from the query string — **never edit a version there; bump `APP_VERSION` in STATE.** Page fetch network-first w/ 2s leash + `cache:'no-cache'`; fonts cache-first; tile cache `packtimes-tiles-v1` survives updates. |

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
       |'pub'|'church'|'school'|'hall'|'fire'|'police'|'sleep'|'stop'|'hut'|'wc'
       |'bike'|'bikestand'|'vending'|'train',
  name: string,
  lat, lon: number,
  sleepAt: bool,           // overnight at this stop
  auto: bool,              // auto-placed vs user-placed
  ohRaw: string,           // OSM opening-hours source
  ohRules: [{days:Set, ...}],   // parsed; Sets are restored on load
  starred: bool,
  info: string|null,       // v383: short "what's here" line from OSM tags (_stopInfo) — water kind, showers, bike services, vending goods
  waterHere: true|undefined, // v232: MANUAL water assignment (like meals). true=assigned (tile/node 💧 blue, auto-stars); undefined=not assigned. waterAssigned(s)=water===true drives the icons+star; stopHasWater(s)=implied||assigned drives the Ride strip + water filter.
  meals: [{type:'meal'|'snack', name, source, when:'before'|'after', durationMin}],  // planned eat events
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
  icuUploadedAt, icuActivityUrl, icuUploadStatus, icuUploadAttempts, icuNamePending, icuNameError,  // v377: the same six for intervals.icu (icuActivityUrl may be null on a hash-duplicate 200)
}
```

`_recMigrate` handles old-shape rows (e.g. early recordings stored `totalDist` in metres). Finalised recordings are mirrored in the in-memory `RECS[]` cache (loaded in `_recRehydrate`, kept in sync on finalise/undo/delete/recovery) so templates can render synchronously.

### Storage

- **IndexedDB `packtimes` v4**
  - `routes` store, keyed by route id (packed via `packRoute`)
  - `recordings` store, keyed by recording id (raw objects)
  - `kv` store for: `cur`, `dbxToken`, `dbxRefreshToken`, `dbxSavedAt`, **`stravaAuth`** (token/refresh/expiresAt/athlete/autoUpload blob), **`intervalsAuth`** (v377: key/athleteId/athleteName/autoUpload — a secret, never in uiPrefs), `uiPrefs` (big blob, incl. `recId` for mid-ride reload recovery), `lastGpsState`, `sunCache`, `weatherCache`.
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
| intervals.icu API (`intervals.icu/api/v1`) | Ride FIT upload for the Bike Coach project (v377) | **Yes** — user pastes their own API key in Settings (intervals.icu → Settings → Developer Settings). CORS is open to pmac44.github.io. De-dupes by file hash. |
| Weather radar sites per country | External link in Live tab | No |
| Supabase (`iwlgfkedrkajesgorysz.supabase.co`, free tier, Sydney) | Location sharing, PackRide events, PackView. RLS-locked tables, all access via SQL functions in `supabase/schema-v*.sql` | Public key embedded by design |

No analytics, no user accounts. The ONLY backend is Supabase, and only sharing touches it.
**Supabase free tier pauses a project without enough database activity** (warning email
10 Sep 2026 after a week off the bike; actually paused ~18 Sep). The threshold is stricter
than it sounds — Supabase's own wording is "typically **a few user requests to the database
each day** over the previous week", so a ping every 3 days does NOT hold it open: that is
exactly what the first keepalive did, and the project paused anyway between two green runs.
`.github/workflows/supabase-keepalive.yml` now pings `event_info` **daily, 3 times a run**;
opening Settings → Location Sharing on the phone also counts. A paused project can be
resumed from the Supabase dashboard for up to a year, data and config intact — but sharing,
PackRide and PackView stay dead, silently, until someone notices.

---

## Important behaviours & conventions

- **Anything drawn on the map goes ON THE MAP CANVAS inside `drawMap`, NOT as a separate overlay
  (Peter's rule, validated on the v243 turn highlight).** The live map is heading-up (rotated,
  v207). If you draw route-anchored graphics (turn highlights, route emphasis, markers that must
  sit on the line) as an SVG/HTML overlay on top, you have to re-derive the projection AND re-apply
  the rotation by hand — which is fragile and repeatedly misplaced the turn line. Instead draw
  inside `drawMap`, in the already-rotated frame, using the same `px`/`py` as the route: the map's
  own rotation carries your graphic and it can never drift off the line. Let the existing rotation
  do the work; don't compute it yourself. (Blink/animation that needs a faster cadence than natural
  redraws: nudge `redrawMap('live-map')` on a short timer — see the turn-cue block.)
- **Vanilla everything.** No React, no framework, no bundler. Don't suggest adding one — it would break the "one file, one push" deploy model Peter relies on.
- **`render()` vs `updateLive()`.** `render()` rebuilds the current tab's HTML. `updateLive()` patches DOM in place on the Live tab so it doesn't flash during a ride. When editing anything that affects the Ride tab mid-ride, preserve the `updateLive()` path — don't collapse it into a `render()` call.
- **`_render()` uses `requestAnimationFrame`.** Wrapped by `render()` which sets `_rf` to coalesce calls. If something doesn't update, check that the calling code goes through `render()` and not raw DOM writes.
- **Routes are packed for storage.** `packRoute` compresses `points` into 5-element arrays for IDB. `unpackRoute` expands them back and always rebuilds `cumRiding` and `estDuration`. Never trust `estDuration` stored on disk.
- **Australian spelling** throughout user-facing strings ("kilometres", "metre"). Match that when writing new copy.
- **Units are metric.** km / metres / °C / km/h / hours.
- **`console.log` is used sparingly**, `catch(()=>{})` silent-swallow is common on IDB writes. Don't add noisy logging unless debugging.
- **Ship a release by bumping `window.APP_VERSION` in STATE — nothing else.** The SW cache name derives from it and Settings displays it. Never hand-edit `CACHE_NAME`. Since v335 the service worker is a real file (`sw.js`, registered with `?v=` from APP_VERSION) — **never inline it in index.html** (blob-URL SWs are rejected by all browsers and the failure is silent), and after ANY sw.js change run the flight-mode test: online open → flight mode → force-close → reopen → must paint.
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
- **Verify by running, not by reading.** Node v24.19.0 is installed — `node verify.js` before any push. For anything drawn or fetched, extract the shipped function and assert on the real output. The traps and techniques are written up in **`_planning/performance-and-verification-lessons.md`** — read it before any performance, canvas or API work. It also holds the worked detail behind v367–v373.
- **Peter's own designs have beaten mine three times out of three.** When he proposes an alternative, measure it rather than steering back to mine, and give him the numbers rather than a tidy menu of options.

---



## Open questions for Peter (things I'd want to know)

These aren't urgent — just things to clarify when relevant:

- Do you ever work on this on the iPad, or only on the Windows desktop? (Affects whether I should worry about CRLF line endings or path style.)
- Is there a staging/preview branch, or do all commits go straight to `main` → production?
- Is `plan.json` in Dropbox a schema you want kept stable (for backwards compatibility with older app versions), or are you fine with me evolving it?

---

## Settled — do not re-chase these

### DECIDED (27 Sep 2026) — Going native: Android shell app first. Don't reopen "native or never".

Peter: *"I can keep on perfecting the app forever, so we have to move to an app that works with
the screen off."* The old "wait for soak-test rides" gate is dropped. Shape: a thin Capacitor app
that loads `index.html` live from GitHub Pages, so `push.bat` stays the everyday deploy and a
store build is only needed when native plugins change. Every native feature sits behind an
`IS_NATIVE` check so the PWA keeps working. Android first; iOS only after Android is proven.
Full plan and step order: `_planning/PackTimes-Native-Shell_Plan_v1.md`. The shell is built
OUTSIDE Dropbox (`C:\dev\packtimes-native`) — never put the Android project in this folder.

### DEAD END (4 Aug 2026) — "PackTimes" CANNOT be made to appear as the device on Strava. Don't re-research this.

Peter, with a Wahoo activity page in front of him: *"When you upload a ride to Strava, it will
say where the data comes from... Can we say pack times?"* Answer: no, and the investigation is
recorded here so nobody spends another hour on it.

- **That line is NUMBERS, not text.** A FIT file has no "Wahoo ELEMNT BOLT" string in it. It has
  `file_id.manufacturer` and `file_id.product`, both integers, and Strava owns a private lookup
  table turning pairs into names. Strava's upload docs confirm the only file_id fields it reads
  are manufacturer, product and time_created — **`product_name` and the whole `device_info`
  message are NOT read**, so there is no free-text hook anywhere in the file.
- **We write manufacturer 255 / product 1** (`MANUFACTURER_DEVELOPMENT`, ~line 6305). 255 is the
  FIT spec's shared "development" ID that every hobby encoder uses, so it is not unmapped by
  oversight — it is not *ours*, and mapping it would collide with everyone else's home-built file.
- **The "falls back to the upload source" behaviour does NOT apply to us.** That fallback (Strava
  showing e.g. "Samsung Health") is for Strava's official partner integrations. Confirmed against
  a real PackTimes upload — the ride "Hommus", 4 Aug 2026, shows **nothing at all** in that slot,
  only "Bike: Toughroad GX".
- **THE ROUTE IN IS CLOSED, and this is the part worth remembering.** WorkOutDoors — an
  established Apple Watch app with a real user base — has been trying for YEARS. The developer:
  tried every device-name combination he could think of, contacted Strava and got only automated
  replies, searched their developer forums and found the same question unanswered from others,
  and "eventually gave up again," retrying annually. Strava's device list is manually approved
  and there is no self-serve path. A one-person app is not getting added. Do not write to Strava
  about it; do not apply to Garmin for a manufacturer ID on this basis.
- ⚠ **NEVER borrow another manufacturer's ID to force a name.** Misattribution, and Strava has
  been tightening exactly this since the Oct 2025 attribution rollout. It risks the API key.
- **REJECTED SUBSTITUTE, and it was Peter's call:** Strava's `POST /uploads` accepts a
  `description` field which we do not currently send (`stravaUpload` sends only `data_type`,
  `name`, `external_id`, ~line 6910). A line like "Recorded with PackTimes" would render directly
  under the ride title — better placed than the device line. Offered as always-on, as a Settings
  toggle, or not at all. **Peter chose not at all.** Boilerplate on every posted ride wasn't worth
  the attribution to him. The field stays free for his own notes. Don't add it back unasked.

### DEAD END (8 Sep) — PackTimes CANNOT drop files into intervals.icu's Dropbox folder. Don't re-plan it.

The queued plan was to write each ride's FIT into the Dropbox folder intervals.icu watches, using
the Dropbox token PackTimes already holds. It cannot work, and the reason is structural:
- **The PackTimes Dropbox app is APP-FOLDER scoped.** Its token can only write inside
  `/Apps/PackTimes/` — that is why `plan.json` lives at `F:\Dropbox\Apps\PackTimes\plan.json` even
  though the code writes to `/plan.json`. Dropbox does not let you change an app's permission type
  after creation; a Full-Dropbox app would mean a new app key and every device reconnecting.
- **intervals.icu watches ITS OWN app folder**, `/Apps/Intervals.icu/Activities/` — the folder
  exists in Peter's Dropbox. No setting points it anywhere else.
- **The fix that shipped (v377) skips Dropbox entirely:** intervals.icu's own API takes a FIT
  upload with a per-user API key, allows browser calls from pmac44.github.io (preflight checked),
  de-dupes by file hash, and its `device_name` field is free text — so rides show as recorded on
  "PackTimes", which Strava never allowed. Rides already on intervals.icu via Strava are replaced
  by the native upload (same behaviour the Wahoo import showed on 8 Sep).

### NOT A BUG (28 Aug) — "316 km before the Divide line goes dark" is CORRECT. Don't re-chase it.

Peter, on the Divide plan in New Mexico: sleep at 3564 km (arrive 21:36, depart 05:36), and
the line doesn't go dark again until ~3880 km — *"that seems a lot… I suspect timezones."*
Checked end to end against the app's own `sunAt` and the v373 hover tooltip. **Every number
agrees to the minute; the surprise is astronomy, not a clock bug:**
- Torreon NM, ~22 June: sunrise 05:52 · sunset 20:29 · full dark (nautical dusk) **21:37** MDT.
  New Mexico sits at the WESTERN edge of the Mountain zone on DST, so the civil clock runs
  ~70 min ahead of the sun — "dark at 9:30 pm" is genuinely true in June. Stacked on the
  solstice, a dawn start buys ~16 h of ridable light.
- His own checks confirmed it: the zoomed map shows navy INTO the 21:36 arrival (1 min before
  full dark) and stays dark just after the 05:36 depart (16 min BEFORE sunrise — correct);
  the hover at 3880 km reads **20:45** = 17 min past sunset, exactly where the sunset→dusk
  gradient starts reading as "dark" on satellite tiles. Full navy lands ~15 km later.
- 05:36 → 20:45 for 316 km = 20.9 km/h plan average — his 0.64 rider factor on a stop-free
  stretch. The previous day (arrive 3564 at 21:36) is the same ~16 h shape.
**Diagnostic that settled it in one step, keep it:** hover the line where the colour changes
and compare the tooltip's ETA against `sunAt` for that lat/lon — if they agree, the paint is
honest and the question is about the plan's pace, not the sun.

---

## How to write a version log entry

The log is for a future Claude session picking up cold, not for Peter. It answers one
question: what do I need to know before I touch this code again? Keep each entry under
about 120 words, in this shape:

```
### v377 (4 Sep) — one-line summary of what changed
- **Changed:** function or banner section names
- **Why:** one line
- **Watch out:** the constraint a future change could break — omit if there isn't one
- **Verified:** node verify.js / extracted the function and asserted on real output / not yet
```

Long investigations do not belong here. Write them up in `_planning/` and link the file
from the entry — that is what `_planning/performance-and-verification-lessons.md` already
does for v367–v373. Dead ends go in "Settled — do not re-chase these", not the log.

<!-- VERSION-LOG-START — newest first. Only the last 3 live here.
     Older entries are in CLAUDE-log-archive.md. Run `python trim_log.py --write` after
     adding a version and anything past the cut is moved there automatically. -->

## Recent version log

*Older versions: `CLAUDE-log-archive.md`. Do not read it unless you need a version that is not below.*

### v403 (5 Oct) — App GPS no longer dies when the camera (or anything) flashes PackTimes on screen
- **Changed:** GPS: `_gpsRestartWatch(why)` — on `'wake'` in the app it returns if a fix arrived within `GPS_WATCHDOG_MS`; any rebuild now adds the new watch first and removes the old only after (`_nativeWatches.get(new).finally(clear old)`). The visibilitychange handler passes `'wake'`.
- **Why:** 4 Oct 230 km ride: 5 gaps (17.8 min). Lock-screen camera closes → PackTimes visible ~0.1 s → wake rebuild → `removeWatcher` emptied the plugin's list → its foreground service stopped → `addWatcher` arrived after the app was hidden → Android refused the restart (`BFGS denied`) → no GPS or power until the next screen-on. Full write-up: `_planning/Ride-Gaps-Oct4_Notes_v1.md`.
- **Watch out:** in the app, NEVER let the plugin's watcher list go empty mid-ride. Its foreground service can only be (re)started while PackTimes is on screen.
- **Verified:** `node verify.js`; PackTimes dev (-Dev build, v403, recording active): reran the ride's sequence (screen off → wake → double-press power for the camera → screen off). v402: GPS off within 0.4 s and stayed off. v403: service still foreground, fixes still arriving after 2.5 min. Backup `backup/index-v402-pre-v403.html`. NOT pushed (v402 also not pushed).

### v401–v402 (3 Oct) — App sign-ins run in a Chrome Custom Tab, so Google sign-in works
- **Changed:** head script (first `<script>`): bounce page — no Capacitor + OAuth `state` ending `~<app id>` → `document.write` a "Return to PackTimes" page and `location.replace('<app id>://oauth?…')`. Near `_nativeGeo`: `_oaStore` (localStorage), `_nativeBrowser`/`_nativeApp`, `_oauthAppId` (App.getInfo). Near `_oauthPending`: `_oauthStateTail`, `_oauthGo`, `_oauthFromAppUrl` (appUrlOpen + getLaunchUrl), `_initDone`. OAuth state/verifier/return-tab moved sessionStorage → `_oaStore`. v402: return-page wording only.
- **Why:** Google sign-in (Dropbox/Strava pages) dead-ended in external Chrome from the app's web view (1 Oct).
- **Watch out:** needs shell 1.0.1+ (Browser + App plugins, intent-filter scheme `${applicationId}`, host `oauth`); older shells keep the in-view flow because `_oauthStateTail()` is ''. Redirect URIs unchanged (no Dropbox/Strava console changes). Chrome sometimes won't auto-open the app (Dropbox via Google needed the button; Strava returned by itself).
- **Verified:** `node verify.js`; phone, PackTimes dev (1.0.1 debug): Dropbox via Google → button → connected with refresh token; Strava → returned automatically, scope incl. activity:read_all. Pushed v401; v402 NOT pushed. Backups `backup/index-v400-pre-v401.html`, `index-v401-pre-v402.html`.

### v400 (1 Oct) — Strava connect always shows its permission page
- **Changed:** `stravaAuthURL`: `approval_prompt` 'auto' → 'force'.
- **Why:** reconnecting on the Play install skipped Strava's page (prior approval reused), so Peter couldn't see whether "private activities" (activity:read_all, needed since v396) was ticked.
- **Watch out:** Google sign-in on Strava/Dropbox pages leaves the app's WebView and dead-ends in Chrome — see the plan note's MUST FIX; sign in with email + password until the Custom Tab fix ships.
- **Verified:** `node verify.js`; preview: auth URL has approval_prompt=force + read_all. Pushed 1 Oct; on the Play install Peter reconnected and saw the page, private activities ticked. Backup `backup/index-v399-pre-v400.html`.

### v399 (30 Sep) — Saved routes lost their distance precision (100 m steps); now rebuilt on load
- **Changed:** PERSIST: `packRoute` stores point dist to the metre (was `Math.round(dist*10)/10` = 0.1 km). New `_rebuildPointDist(r)` called first thing in `unpackRoute`: cumulative `hav` over the points; kept as-is when within 0.5% of the stored length, else scaled to it; sets `r.totalDist` from it.
- **Why:** 30 Sep ride (v398, Majura Pkwy): alert log showed "Left in 0 metres", missing "turn now" calls and 5 of 21 turns never alerted. Every saved/reloaded route had point distances in 100 m steps, so the live along-route position froze and jumped (replay: 1,400 of 2,381 fixes frozen → 2 after the fix). Affected Chrome too, since packing began.
- **Watch out:** point `dist` is now ALWAYS derived from geometry on load — anything that must survive a save/load goes in its own field, never in `p.dist`. Turn markers moved 0–1 m on the Majura route; 2 of Peter's 39 routes differ from geometry by 1–4% and are scaled instead.
- **Verified:** `node verify.js`; phone, real route + ride: frozen fixes 1,400 → 2, turn drift 0–1 m; preview: old-style rounded route heals to ≤1 m, round trip ≤1 m, estDuration unchanged. Same ride confirmed v398 works: 4,304 of 4,336 intervals 1 s (4,379 of 4,380 s covered), no power gaps > 20 s, 26 alerts logged (screen woke on every screen-off heads-up), Strava + intervals.icu uploaded with links kept. Backup `backup/index-v398-pre-v399.html`. NOT pushed.

### v398 (29 Sep) — True 1 s recording; power meter / HR strap reconnect by themselves
- **Changed:** RECORDING: `_recSec(t)=Math.round(t/1000)` (same rounding as `fitTime`); `_appendPoint` and `_recSensorSample` keep a sample when it lands in a NEW FIT second instead of `>= REC_MIN_TICK_MS` since the last. POWER METER: `connectPowerMeter` = pick + `_powerAttach(dev)`; `_powerOnDisconnect` / `_powerScheduleRetry` (`BLE_RETRY_MS` 3/5/10 then 15 s, forever while `_powerWant`); listeners bound once per characteristic (`_ptBound`); NP kept across a dropout, reset only by `disconnectPowerMeter`. HR: the same (`_hrWant`, `_hrAttach`, `_hrScheduleRetry`). BLE stand-in: one native disconnect listener per device, characteristics cached per service|uuid, native notification listener added once per characteristic.
- **Why:** Peter, 29 Sep: Assiomas dropped on a 5-min descent and needed re-pairing; intervals.icu flagged ~2 s "smart recording" — readings arriving at 980 ms were discarded (28 Sep: 1,516 of 2,795 point gaps were 2 s; 2,747 power samples in 4,380 s).
- **Watch out:** `_recSec` must stay identical to `fitTime`'s rounding or the FIT writer's per-second de-dupe and the sampler disagree. Auto-reconnect retries forever until a deliberate disconnect — on purpose (a head unit behaves the same).
- **Verified:** `node verify.js`; preview with a fake Web Bluetooth power meter: connect (crank 175) → drop (NP kept, retrying) → failed retry → reconnect (crank re-read) → 1 handler call per reading → manual disconnect stops retries and resets NP; arrivals at 0/980/1990/2970/4010 ms all kept. BLE stand-in changes NOT yet tried on the phone. Backup `backup/index-v397-pre-v398.html`. NOT pushed.

### v397 (28 Sep) — Strava/Dropbox sign-in waits for the app to finish loading
- **Changed:** DROPBOX SYNC, the page-load `?code=` dispatcher now only sets `_oauthPending` (stravaHandleRedirect or dbxHandleRedirect); INIT calls it as its last step, after `loadAll`, recovery and `dbxAutoLoad`.
- **Why:** 28 Sep, reconnecting Strava in the app toasted "Connected" but wasn't: the handler ran at script load, raced `loadAll` (seconds with 40 routes), and `loadAll` then restored the old disconnected `stravaAuth` over the new token. Its early `saveAll` could also write prefs before they'd loaded.
- **Watch out:** anything else that must act on a redirect/query param and touches saved state belongs in INIT after `loadAll`, never at script top level.
- **Verified:** `node verify.js`; preview: `?code=dummy&state=strava_…` handled after load (routes present, `_oauthPending` consumed, URL cleaned, Strava's "Bad Request" toast). Pushed 28 Sep; real reconnect on the Pixel stuck: token saved, scope `activity:write,activity:read_all,read`, 40 routes intact. Backup `backup/index-v396-pre-v397.html`.

### v396 (28 Sep) — Alert log in each ride; Strava "Only you" rides no longer lose their link
- **Changed:** RECORDING: `_recCueLog(kind,extra)` → `rec.cues[]` ({t, kind 'turn'|'offroute', stage, km, glyph, remM, said, hidden, wasOn/isOn}); `checkAlerts` passes an entry to `playTurnCue(stage,turn,remM,log)`; `wakeScreen(log)` fills in the ScreenWake result; `showOffRouteAlert` logs too. STRAVA: `STRAVA_SCOPES` + `activity:read_all`; granted scope saved as `UI.stravaScope` (stravaAuth KV `scope`); rename 404 without read_all keeps the link + sets `stravaNameError`; `rec.stravaUploadedName` set on upload, and `stravaMarkRename` skips when the name is unchanged; a pending rename that rode along with the upload is cleared.
- **Why:** 28 Sep soak ride: no way to tell which turns spoke/woke the screen; and the Strava link was dropped — the save prompt's unchanged name fired a PUT, Strava 404'd because Peter's rides are "Only you" and the grant lacked read_all.
- **Watch out:** existing Strava connections keep the old grant until reconnected (Settings → disconnect → connect, and tick the private-activities box). `rec.cues` is not in FIT/GPX and sim rides aren't logged.
- **Verified:** `node verify.js`; browser with stubbed fetch: cue entry written only while a ride is active; 404 w/o read_all → link kept + error; with read_all → cleared as before; unchanged name → 0 fetches; new name → PUT. Backup `backup/index-v395-pre-v396.html`. Pushed 28 Sep; Pixel app confirmed on v396 (Strava not yet reconnected — scope null).

### v395 (28 Sep) — Android killed the app mid-ride: per-call date formatters (35 MB/s native garbage)
- **Changed:** TIME CALC: `_FMT_HM/_FMT_WD/_FMT_DM/_FMT_DMY` (Intl.DateTimeFormat, built once) + `_fmtWith`; `_fmtTRaw`, `fmtDT`, `fmtDTY`, `fmtDTYDev` use them. `updateLive`: the per-stop `eta-<id>` loop only runs if such an element exists. MAP ENGINE: `_canvasFit(cvs,bw,bh)` — resize only on change, else `ctx.reset()`; used by `drawMap`, `_drawElevInner`, desktop elev, `drawElevProfile`.
- **Why:** Peter's 28 Sep soak walk on NSW Divide (1,146 stops): the renderer hit Android's memory.high (3 GB) at 8:07:02 — points stop that second — and the app was killed at 8:07:43. `toLocaleTimeString('en-GB',{…})` builds a new ICU formatter per call (~30 KB native, invisible to the JS heap and the heap profiler); updateLive made 1,156 per tick.
- **Watch out:** never call `toLocale*String(locale,{options})` or `new Intl.*` in anything per-stop or per-tick — reuse a module-level formatter. `performance.memory` and the heap profiler did NOT show this; the proof was renderer RSS (`adb shell ps -o RSS`) with the function swapped live over CDP. The canvas change is hygiene (it was a suspect, not the cause).
- **Also in v395 — ending a ride ends GPS:** new `_recEndGps()` (RECORDING, before `_recStopDelete`), called by `_recStopConfirm` and `_recStopDelete`; `_recStopUndo` calls `startGPS()` if off. Stopping a ride used to leave GPS on at full accuracy (invisible in Chrome; in the app the tracking notification stayed and the battery paid). Sim excluded.
- **Verified:** `node verify.js`; browser: 2,000 dates identical old vs new (incl. Invalid Date), maps + elevation redraw correctly; stubbed-GPS run: start → stop (GPS off, watch cleared) → undo (GPS on) → delete (GPS off). Pixel, live v394 app, ride running, `_fmtTRaw` swapped at runtime: renderer 2.3–2.6 GB churning → flat 697 MB for 36 s; `stopGPS()` → plugin service leaves the foreground, notification gone. Backup `backup/index-v394-pre-v395.html`. Pushed 28 Sep; Pixel app confirmed on v395 with 40 routes.

### v394 (28 Sep) — App status/nav bar strips follow the theme (were white)
- **Changed:** `applyTheme` — after setting `meta[name=theme-color]`, also calls the shell's `Bars.setColor({color:_THEME_STATUS[t]})`. Shell: new `BarsPlugin.java` (window background + decor colour, bar colours below Android 15, light/dark icons by luminance); `MainActivity` registers it and paints `#0d1a0d` from the first frame.
- **Why:** Peter: the app's top and bottom strips were white; Chrome's matched the app. The app view ignores theme-color.
- **Watch out:** Paper theme → light strips (#f2efe9), Graphite → #0a0f0a, same as the meta tag. If Peter wants them always dark, change the colour passed here, not the plugin.
- **Shell gotchas (found on the phone):** `BarsPlugin.apply` in `MainActivity.onCreate` is overwritten by the theme afterwards, so the first-frame colour comes from `styles.xml` (`windowBackground` `@color/packtimes_dark`, light-icon flags off) and Capacitor's own SystemBars would force DARK icons from the phone's light mode unless `capacitor.config.json` sets `plugins.SystemBars.style = "DARK"`. The page's later `Bars.setColor` does stick.
- **Verified:** `node verify.js`; browser unchanged (`_nativePlugin('Bars')` null, no errors). Pixel, live build: strips `#0d1a0d` with light icons at launch; `Bars.setColor` red → red, Paper `#f2efe9` → light strip + dark icons, held after leaving and reopening the app. Page side NOT pushed. Backup `backup/index-v393-pre-v394.html`.

### v393 (27 Sep) — Mission brief prints in the app (Android print screen / Save as PDF)
- **Changed:** `printMission` end: if `_nativePlugin('Printer')`, hand the finished HTML to it instead of `window.open`. Shell: new `PrintPlugin.java` (off-screen WebView, JS off, `PrintManager.print`, A4), registered in `MainActivity`.
- **Why:** the app view can't `window.open` + `print()`.
- **Watch out:** the page is laid out with JavaScript OFF — anything the brief needs must be plain HTML/CSS (its own `window.print()` onload script is inert there, on purpose).
- **Verified:** `node verify.js`; Pixel dev build: `printMission()` → `printspooler PrintActivity`, preview shows the brief, Save as PDF offered. Backup `backup/index-v392-pre-v393.html`. NOT pushed.

<!-- VERSION-LOG-END -->
