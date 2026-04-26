# PackTimes — project guide for Claude

This file is loaded automatically whenever we work in this folder. Its job is to get me up to speed on PackTimes fast, so we don't burn time rediscovering the structure on every task.

Peter, if anything below goes stale, tell me and I'll update this file rather than carrying on with wrong assumptions.

---

## What PackTimes is

PackTimes is an ultra-cycling and bikepacking route planner, shipped as an installable PWA. A rider loads a route file (GPX / TCX / KML / FIT), and the app plans the ride — pace by surface type, stops (food, water, sleep, fuel, accommodation), weather and daylight along the way, a printable mission brief, and a Live "Ride" tab with GPS tracking, turn beeps, off-route alerts, and adaptive pace calibration.

- Deployed at https://pmac44.github.io/PackTimes (GitHub Pages).
- Repo: https://github.com/pmac44/PackTimes.
- Works offline after first install (service worker caches app + map tiles).
- Optional Dropbox sync of plans across devices.

## Architecture in one sentence

**Everything lives in `index.html`.** HTML, CSS, and JS are all in that one ~11,000-line file. There is no build step, no bundler, no framework — it's vanilla JS with IndexedDB for storage and Canvas for maps and elevation. Edits are made directly to `index.html` and pushed to GitHub; Pages serves it.

### Files in the repo

| File | What it is |
|---|---|
| `index.html` | The entire app. ~11,000 lines. |
| `manifest.json` | PWA manifest (name, icons, theme colour, standalone display). |
| `icon-192.png`, `icon-512.png` | PWA icons. |
| `push.bat` | Peter's Windows one-click deploy: `git add . && git commit -m "Update app" && git push`. |
| `.git/` | Local git history. Remote: `origin` → GitHub. |

### Deploy flow (Peter's)

1. Edit `index.html` locally (Windows, path `C:\Users\peter\Documents\PackTimes`).
2. Double-click `push.bat` → commits as "Update app" and pushes to `origin/main`.
3. GitHub Pages picks it up and serves at `pmac44.github.io/PackTimes`.

Commit messages are all "Update app", so `git log` is not a useful context source — don't try to lean on it to understand history. If I need to know why a change was made, I should ask Peter.

---

## Code map: where things live in `index.html`

The file is organised with clear banner comments (`// ═══...`). Section boundaries are stable and line numbers below are accurate as of April 2026 — if they drift, I should grep for the banner comment rather than trust the number.

### Top of file

| Lines | What |
|---|---|
| 1–11 | Doc comment & copyright. |
| 12–483 | `<head>`, CSS (all inline in a `<style>` block), and HTML skeleton (header, tab bar, `content-wrap`). |
| 484 | `<script>` opens — JavaScript starts here. |

### JavaScript sections (banner-delimited)

| Lines | Banner | What it owns |
|---|---|---|
| 486–509 | `INDEXED DB` | `DB` module: opens `packtimes` IDB (v3), two stores: `routes` (keyPath `id`) and `kv` (keyPath `k`). Exposes `put/get/all/del/setKV/getKV`. |
| 511–537 | `STATE` | Globals: `ROUTES[]`, `CUR` (current route index), `newRoute(name)`, `cur()`, and the big `UI` object (tab, GPS state, ride-avg accumulators, Dropbox tokens, settings expand state, live pill config, etc.). |
| 539–672 | `PERSIST` | `packRoute/unpackRoute` (compress points to arrays for storage; unpack rebuilds `cumRiding`, migrates old stop types and IDs, restores `ohRules` Sets). `saveAll()` writes every route + UI prefs. `loadAll()` restores routes, UI prefs, last GPS state, sun cache, weather cache. |
| 674–760 | `GPX PARSE` + `TCX PARSE` | `parseGPX(txt)`, `parseTCX(txt)`. |
| 762–810 | `KML PARSE` | `parseKML(txt)`. |
| 812–898 | `FIT PARSE` | Binary Garmin `.fit` parser. Extracts record messages (lat/lon/alt/timestamp). Custom-written, no library. |
| 899–1059 | Geometry helpers | `hav` (haversine), `bearing`, `angleDiff`, `autoDetectTurns` (main turn detector with tunables like `MIN_TURN_DEG`, `RECOVERY_TOL`), `elevGain`, `durationFromTS`, `tsSpeedSanity`. |
| 1060–1208 | Speed/pace model | Calibrated constants: `VAM_BY_SURFACE`, `FLAT_KMH_BY_SURFACE`, `DESC_FACTOR`, `MAX_DESC_KMH`, `RIDER_MULT`, `LOAD_MULT`. Then `surfaceCatAt`, `segTimeH`, `naismith`, `buildCumRiding`, `rebuildPace`, `cumRidingAt`, `getDaySplits`. **This is the heart of the planner — changes here affect every ETA in the app.** |
| 1207–1262 | `OPENING HOURS PARSER` | `parseOH(oh)` parses OSM-style opening-hours strings into rule objects; `isOpen(rules,dt)`, `fmtOHSummary`. |
| 1263–1535 | `TIME CALC` | `startDT`, `sleepHoursFor`, `totalSleepHours`, `totalMealHours`, and `etaAt(distKm, r)` — the main function that turns a distance into an ETA including stops, sleep, and meals. |
| 1536–1565 | Date/time formatters | `fmtT`, `fmtDT`, `fmtDTY`, `fmtHM`, `dayOff`. |
| 1567–1840 | `STOPS` + surface fetch | `addStop`, `delStop`, `shopSt`, `surfaceCategory`, `snapToWay`, and the Overpass surface-type fetcher (chunked, multi-mirror, `SURF_MIRRORS`). |
| 1841–2091 | Overpass queries | Town geocode via Nominatim; POI search along route via Overpass (`MIRRORS`); accommodation search via Geoapify Places (needs `UI.geoapifyKey`). `snapTo(r,lat,lon,lastIdx)` — snap a GPS point to the route. |
| 2092–2288 | `GPS` | `toggleGPS/startGPS/stopGPS`, GPS watch handler, idle-timeout auto-stop, adaptive-calibration hooks, ride-avg accumulators, persistence of `lastGpsState`. |
| 2289–2410 | `ADAPTIVE SPEED CALIBRATION` | `adaptiveTimings(r)`, `runAdaptiveCalibration()`, `updateGPSPill`. Tunables: `ADAPTIVE_GAP_MS`, `ADAPTIVE_MAX_DRIFT` (±30% cap). |
| 2411–2584 | `RIDE SIMULATOR` | Plays back a GPX at simulated speed. `simStart/simPause/simStop/_updateSimButtons`, `_simPts/_simIdx/_simTimer`. |
| 2585–2678 | Audio alerts | `getAudioCtx`, `playTone`, `playBeepSequence`, `playTurnBeep`, `scheduleTurnBeeps`. Uses WebAudio + `navigator.vibrate`. |
| 2680–2725 | Wake lock | `_wakeLock`, `releaseWakeLock` via `navigator.wakeLock`. |
| 2729–2970 | Proximity & off-route alerts | `checkAlerts`, `showOffRouteAlert`, `playOffRouteAudio`, `triggerStopAlert`, `clearStopAlert`, `pulseStripCard`, `playStopChime`, `scheduleStopChimes`. Constants `OFF_ROUTE_M=150`, `OFF_ROUTE_SECS=8`. |
| 2972–3056 | Turn-review overlay event handling | `_handleTrvEvent`. |
| 3057–4350 | `MAP ENGINE` | Canvas map rendering. Per-canvas state in `_ms`. Tile sources in `TILE_URLS` (off / OSM / ArcGIS sat / CyclOSM / OpenTopoMap); `_tileMode` cycles between them. `getTile`, `drawTiles`, `drawMap`, `cidx`, `zoomMap`, `zoomForKmWidth`, `panTo`, `peekLiveStop`, `redrawMap`, `attachMap` (touch/mouse gestures), `hitTest`, `mapCtrlHTML`, `zoomBtnsHTML`. Also the offline-tile prefetcher (zoom levels 10–14, batched, cached in `packtimes-tiles-v1`). |
| 4351–4393 | `ELEVATION CANVAS` | `drawElev(cvs, r)` — small inline elevation strip. |
| 4394–4475 | `MODAL` + date/time picker | `openModal/closeModal` (stop add/edit), `_dtFmt/_dtRefresh/openDTPicker/closeDTPicker/_dtBtn`. |
| 4476–4588 | `PACE SEGMENT MODAL` | User-defined pace overrides per distance range. |
| 4589–4886 | Edit modal + helpers | `updateModalFields`, `closeEditModal`. |
| 4887–4898 | `HIGHLIGHT STATE` | `_highlightStopId`, `_tempRevealTimer` for the Stops map. |
| 4899–5217 | `DESKTOP LAYOUT` | `IS_DESKTOP()` (breakpoint ≥900px), `initDesktop`, `renderDesktopMap`. Desktop shows a fixed sidebar + map pane; mobile is single-column. |
| 5218–5443 | `DROPBOX SYNC` | OAuth PKCE flow. Constants: `DBX_APP_KEY='5uh7f72xfyv171g'`, `DBX_REDIRECT='https://pmac44.github.io/PackTimes/'`, `DBX_FILE='/plan.json'`. `dbxAuthURL/dbxSetStatus/dbxScheduleSave/dbxSave/dbxLoad/dbxAutoLoad/dbxShowStaleBanner/_dbxAgoStr`. Debounced save (5s). Export/import plan JSON: `exportPlan/importPlan`. |
| 5573–5622 | `TABS` + scroll helpers | The six tabs defined in the `TABS` array: `routes`, `stops`, `food` (labelled "Supplies"), `plan` (labelled "Mission"), `live` (labelled "Ride"), `settings`. |
| 5623–6121 | Rendering helpers | `render()` (rAF-gated), icon constants (`STRIP_ICON_*`, `ICON_FOOD`, etc.), live-strip builders, grade colours, elevation-profile drawing (`drawElevProfile`). |
| 6122–6187 | `RENDER` | **`_render()` — the central dispatcher.** Reads `UI.tab` and calls the appropriate `t*` template function. This is the function to start from when debugging anything visual. |
| 6188–6405 | Route + Stops tab templates | `tRoutes` (at 6961), `tStopsShell(r)`, stops-scroll/stops-map helpers. |
| 6406–6562 | Live shell + turn review | Power zones (`powerZone`, `hrZone` — Wahoo 7-zone model). `enterTurnReview/exitTurnReview/allReviewTurns/goToTurnReviewIdx/renderTurnReview`. |
| 6563–6959 | Live tab | `tLiveShell(r)` (live-map section + stats + next-stop strip + elevation), `LIVE_STATS` config, `STAT_ORDER`, `PILL_CYCLE`, `initLiveMap`. |
| 6961–7267 | `tRoutes` | Routes list + route detail combined. Route management, turn-detection settings per route. |
| 7268–7474 | `tSettings` | Settings tab: Dropbox, alerts, FTP/MaxHR, zoom/weather spacing, OSM defaults, offline tile download, simulator, Geoapify key, danger zone. |
| 7475–7596 | Plan tab helpers + stops | `clusteredStopRows`, `stopRow`, `clusterStops` (clusters stops within `CLUSTER_KM=3.0`), `makeCluster`, `typeIcons`, `stopChip`. |
| 7597–7951 | Weather | `RADAR_URLS` per country, `geoCountry`, `wmoIcon/windArrow`, `isSignificantWeatherChange`, `_weatherCache`, `ensureWeatherCache` (fetches from Open-Meteo — free, no key), `weatherAtEta`, `weatherPillHTML`, `weatherBarHTML`, `drawWeatherDot`. |
| 7952–8091 | Sunrise/sunset | `ensureSunCache`, `_sunApprox` (local calculation, no API), `bgIsLight`, `dayNightBg`, `dayNightLabel`. |
| 8092–8514 | `tPlan` | Mission tab template — the main planner view. |
| 8515–8637 | Gear | `DEFAULT_GEAR`, `getGearChecklist`, `_updateGearSummary`. |
| 8559–8795 | `tGear`, `tFood` | Gear and Supplies tab templates. |
| 8797–8855 | `printMission` | Opens a print-friendly window. |
| 8856–8935 | Speed-factor patching | `patchSpeedFactor`, `factorDesc` — live adjustment of the global `timeFactor` multiplier. |
| 8936–9232 | `TARGETED LIVE UPDATE` | `updateLive()` — surgical DOM updates on the Live tab to avoid full re-render during ride (prevents flashing). |
| 9233–9241 | `patchGPSInfo` | Updates Settings GPS panel without full re-render. |
| 9242+ | `EVENT DELEGATION` | Big `document.getElementById('tabs').addEventListener` and document-level click delegator. Most user interaction routes through here. |
| 10925–10937 | `INIT` | `loadAll().finally(() => { reset sim/GPS state; initDesktop(); render(); if(UI.dbxToken) dbxAutoLoad(); })`. |
| 10940+ | Service worker | Registered from a Blob. Cache name is bumped per release — current: `packtimes-v133` at line 10948. **Bumping this cache name is what forces a PWA update for existing users.** Tile cache: `packtimes-tiles-v1`. |

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

### Storage

- **IndexedDB `packtimes` v3**
  - `routes` store, keyed by route id
  - `kv` store for: `cur` (current route id), `dbxToken`, `dbxRefreshToken`, `dbxSavedAt`, `uiPrefs` (big blob of UI settings), `lastGpsState`, `sunCache`, `weatherCache`.
- **Cache API**
  - `packtimes-v{N}` — app shell (bumped per release; currently v133).
  - `packtimes-tiles-v1` — prefetched map tiles.

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
- **Service worker cache name must be bumped** when shipping a change you want to force onto existing users. See line ~10948: `CACHE_NAME='packtimes-v133'`. The SW skip-waits and activates immediately, so users get the new version on next load.
- **Copyright notice** at the top of `index.html` must stay intact.

---

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
