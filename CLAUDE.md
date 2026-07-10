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

## Current status (10 July 2026, v236)

**v236 (10 Jul 2026) — turn cues made audible again (v235 was too gentle).** Peter
tested v235 in the sim: could hear the old 3-tone but NOT the new cue. Diagnosis (his
own clue confirmed it): the on-map turn markers appear then disappear as you pass each
turn, so the detection pipeline IS firing — the problem was pure audibility. v235 used a
soft SINE at vol 0.22 (single short heads-up beep); sine carries far less punch than the
old square triple-beep, so it fired but was easy to miss. Fix keeps the good part
(minimal, non-repeating, two-stage, direction on-screen) but makes it clearly heard:
`playCueTone` now uses a **triangle** wave (cuts through better than sine, softer than
square); `playTurnCue` reworked into two distinct, louder signals — heads-up = two quick
680 Hz beeps (vol 0.42) "turn coming"; 'now' = one longer higher 900 Hz beep (vol 0.5)
"turn now". Still no repeating, still far less than the old melody. Logic unchanged from
v235 (same `_turnCuesFired` two-stage loop). Not yet ride-tested.

## Current status (10 July 2026, v235)

**v235 (10 Jul 2026) — turn cues made minimal + two-stage (Garmin/Wahoo model).**
Peter: the old 3-tone descending/ascending "melody" (to encode L/R without the screen)
was too loud and beeped far too constantly — the real culprit was `scheduleTurnBeeps`
RE-firing the pattern every 0.5–2.5s the whole way in. We checked the proven devices:
Garmin cycling default is a fixed ~0.1 mile (~160 m) heads-up + a "turn now" at the
corner (speed-scaling only kicks in in *car* mode); RWGPS warns ~0.5 km out then again
at the turn. So distance-based (not time) and TWO cues is the norm — our 150 m heads-up
was already right; we were just missing the confirm and drowning it in repeats. Rewrote:
removed `playBeepSequence`/`playTurnBeep`/`scheduleTurnBeeps` (+ the repeating
`_turnBeepTimer` loop and `_lastTurnBeepDist`); new `playCueTone` (sine, vol 0.22 vs old
0.45) + `playTurnCue(stage)` — heads-up = ONE soft 660 Hz beep + short vibrate; 'now' =
a 760 Hz double-beep at ≤25 m + double vibrate. Live loop (`updateLive`) now fires each
stage once per turn via a `_turnCuesFired` Set (keyed `dist:h`/`dist:n`, cleared at the
same 4 GPS reset points), gated on distance only. Deliberate call with Peter: direction
is NO LONGER in the sound (accepted limit) — it shows on the on-screen turn popup; a PWA
can't fire the screen or beep reliably in the background anyway. When we go native the
same cue list (already parsed into `r.turns` from FIT/TCX) can trigger with the screen
off + add spoken L/R cues — nothing about this logic changes. Settings test-beep now
plays the heads-up cue. Node-verified (one heads-up + one confirm per turn, once each,
consecutive turns independent). `_turnBeepTimer` decl + its no-op clears left in place
(harmless). Not yet ride-tested.

## Current status (10 July 2026, v234)

**v234 (10 Jul 2026) — Ride strip now ends on a FINISH anchor row.** Peter: while
approaching the end, a bare destination town (Harden = the finish) didn't show on the
strip, and the old empty state was a bland "🏁 All stops passed" with no distance/time.
Agreed rule (kept deliberately simple): show the finish ONLY when the strip would
otherwise have no rows — i.e. all marked stops passed. It never fires while real stops
are ahead (they take the rows), so it can't clutter a multi-day route far from the end;
the distance-gating falls out for free. Replaced the empty-state early-return in
`buildLiveStrip` with a proper row: 🏁 + destination name + distance-to-go + ETA, plus
amenity icons CONFIRMED at a town sitting on the finish (💧/🍴/😴/🚻, same explicit-only
rule as the other rows). Destination name = the nearest stop within `CLUSTER_KM` of
`r.totalDist`, else "Finish". Node-verified both cases (finish-on-a-watered-town →
"🏁 Harden 💧"; bare finish 30 km past last stop → "🏁 Finish 30.0km/…"). Note: the top
ride bar already carries the finish ETA, so this is a tail-filler, not a duplicate — an
earlier stop/town on the strip still takes priority (Peter's "earlier town knocks off
the finish"). Not yet ride-tested.

## Current status (10 July 2026, v233)

**v233 (10 Jul 2026) — Ride strip is now EXPLICIT-only (safety) + amenity icons.**
Peter's safety point: assuming a place has water is dangerous — unmanned servos
(e.g. Jugiong) may have no food/water; on a remote leg a missing water stop can be
life-critical. So the strip must NOT imply food/water from type. Changed
`buildLiveStrip` `hasFood=s=>!!(s.meals&&s.meals.length)` (planned meals only) and
`hasWater=s=>s.type==='water'||s.waterHere===true` (real water stop or a "water here"
mark) — a starred servo shows NOTHING unless you confirmed it. Added per-row amenity
icons for what's CONFIRMED at the place (row stop + co-located): 💧 water, 🍴 meal,
😴 sleep, 🚻 toilet — each skipped when it's already the row's primary badge. All
three assignments already auto-star (sleep 13106, food 13153, water 13271), so
marking water/food/sleep on a servo stars it AND shows its icon. Node-verified.
NOTE: the mission-node/tile/filter still use `stopHasWater` (implied) for the water
FILTER + node buttons via `waterAssigned` — strip is the safety-critical view. Next
up (Peter's request): a one-tap mechanism to pull a nearer stop onto the plan mid-ride.

## Current status (10 July 2026, v232)

**v232 (10 Jul 2026) — water now mirrors FOOD exactly (manual on tiles, implied on
strip).** Peter: food outlets showed a blue water droplet on their stop tiles even
though he hadn't assigned water — "obviously food outlets, but you wouldn't auto-mark
food at every venue." Right model = water works like food: the TILE/NODE icon lights
only for a MANUAL assignment (`waterAssigned(s)=s.waterHere===true`), just as the food
icon lights only for an assigned meal; but the RIDE STRIP + water filter still treat
a café/servo as a water source (`stopHasWater(s)=stopWaterImplied(s)||waterHere`),
just as the strip treats a café as food. Two helpers now: `waterAssigned` (tiles,
nodes, auto-star) vs `stopHasWater` (strip, filter). Tapping the droplet assigns/
un-assigns (`waterHere` true/delete — dropped the tri-state false override); assigning
auto-stars the stop like assigning food does (removed the old `!stopWaterImplied`
guard — any manual assign stars, even a café). Node water buttons + handler switched
to `waterAssigned`. Node-verified: café/servo tile empty but strip=water; tap → blue
+ star; un-assign clears.

## Current status (10 July 2026, v231)

**v231 (10 Jul 2026) — manually adding water auto-stars the stop (like food).**
Peter's insight: the star discriminator is HOW the water droplet got there —
auto-implied (servo/café) = just info, don't star (you pass 100 of them); manually
MARKED (a tap at a bare spot you plan to refill at) = a deliberate "stop here"
decision = star it, same as assigning food auto-stars. Implemented in the
`.water-at-stop` handler: after the toggle, `if(!node && s.waterHere===true &&
!stopWaterImplied(s) && s.starred===false){ s.starred=true; ... }` and updates the
sibling `.star-stop` button in place (no re-render → no scroll jump). So an implied
servo NEVER auto-stars (even toggled off then on), but ticking water on a bare
manual stop / spring stars it. Node-verified truth-table.

## Current status (10 July 2026, v230)

**v230 (10 Jul 2026) — water unified into one rule + a real on/off override.**
Peter on v229: the Caltex water icon was blue but he couldn't DESELECT it (water
implied by fuel+ohRaw always overrode the flag), and it wasn't consistent on the
mission tab. Root cause: ~6 places each re-decided "has water" with `implied ||
!!waterHere`, so an explicit "no" was impossible and they could disagree. Fix:
new shared `stopWaterImplied(s)` + `stopHasWater(s)` (implied by type UNLESS
`s.waterHere` is set: true=yes, false=no, undefined=default). Replaced every inline
copy — buildLiveStrip `hasWater`, the stop-tile button, the mission-node buttons
(sleep + non-sleep), `isWaterSrc` (filter), the leg water icon, the handler's
in-place `hasW` — with `stopHasWater`. The toggle now sets an EXPLICIT override
(`s.waterHere=!stopHasWater(s)`), so you can turn a servo's water OFF (dry/closed)
or a bare spot's ON, and every view agrees. Food-picker checkbox writes explicit
true/false too. Node-verified: servo/café/toilet/manual all toggle both ways;
`waterHere=false` beats an implied source. `s.waterHere` is now tri-state (was
bool) — no migration needed (undefined = default).

## Current status (10 July 2026, v229)

**v229 (10 Jul 2026) — stop-tile water icon now always shows (consistency with the
mission node).** Peter: a Caltex servo (fuel + OSM hours = water implied) had NO
water icon on its stop tile, while toilets did — inconsistent, and you want to SEE
that the servo has water. v222 hid the tile's water button whenever water was
implied; that clashed with the mission-node button (always shown, blue when
watered). Fixed: the stop-tile `.water-at-stop` button now shows on every stop
EXCEPT a dedicated water stop (which already has the WATER badge), blue `#60a5fa`
when water is available (food/shop/pub, town/servo with ohRaw, or `waterHere`),
outline when uncertain; tapping still toggles `waterHere` (a no-op on implied
stops — the fill stays, honest). Handler's in-place recolour switched from
`!!s.waterHere` to the full `hasW(s)`. Now the stop tile and mission node behave
the same. Node-verified (servo=blue, toilet=outline until ticked, water stop=none).

## Current status (10 July 2026, v228)

**v228 (10 Jul 2026) — Ride strip merges co-located stops (amenities model).**
Peter's edge case: a manual "Touts Lookout" stop + an OSM toilet a few metres apart;
on the Ride strip the toilet (a hair closer) stole slot 1 and the lookout vanished.
Fix in `buildLiveStrip`: slot 1 now takes the most NOTABLE stop within a tight
`MERGE_KM` (0.15 km) of the next stop, via a `rank()` (sleep/meal 6 > food/town/
accom/fuel 5 > manual stop 4 > camp/hut/peak 3 > water 2 > wc 1). Co-located minor
stops are marked `seen` (no duplicate row) and surface as amenity add-on icons on
the row: a 💧 where you can refill (co-location-aware now) and a 🚻 toilet marker.
Peter's framing: a toilet (like water) is an amenity OF a place — shown as an add-on
unless standalone. Verified via node: toilet+lookout → "Touts Lookout 🚻"; a
standalone toilet still shows as its own WC. Sits on top of v227 (built in a parallel
session; my edits matched the current code cleanly). NOTE: v226/v227 changelog entries
are from other sessions — QR retirement (v226) etc.

## Current status (10 July 2026, v226)

**v226 (10 Jul 2026) — retired the QR "Transfer plan to phone" path; Offline Storage
copy rewritten.** Peter never used QR, and his real plans exceed a QR's capacity (a
300 km / 194-stop plan is 8 KB compressed vs the ~2.3 KB byte-mode ceiling — and the
old `>7000` guard in `showQRModal` was set well above what a QR can actually hold, so
mid-size plans would pass the guard then silently fail to draw). Removed the
`#btn-qr-export` button from `offlineBody` and its click handler in the delegator.
Rewrote the panel into two clear jobs: "get your plan onto your phone" → Dropbox
(export/import file as the fallback), and "send a whole ride to someone else" → the
route-tile share button. **Left dormant (not ripped out, to keep the change low-risk):**
the `qr-modal` HTML block, `showQRModal`/`loadQRLib`, and the qr-modal listeners — all
now unreachable from the UI but harmless; `decodePlanStr` is KEPT (shared with the
ride-import path). Strip the dead QR code later if wanted. Bigger picture: Peter wants
proper file hosting eventually to replace flaky Dropbox sync (regular reconnects,
unclear which end is newer) — parked, not today's job.

## Current status (10 July 2026, v225)

**v225 (10 Jul 2026) — water button on sleep nodes + real scroll fix + water
filter honesty.** Three from Peter: (1) tapping a water button STILL scrolled the
list (v223's `renderKeepScroll` didn't hold on desktop) — rewrote the `.water-at-stop`
handler to update the tapped button IN PLACE (no re-render at all), recomputing the
town's water for node buttons via `clusterStops`. Node buttons now carry
`data-node="1"` so the handler knows to check the cluster vs the single stop. (2)
Sleep nodes (motel/bivi, e.g. Grenfell) had no water button — added it to BOTH
sleep-node variants in `tPlan` (before `cluster-edit-btn`), so a remote retreat gets
it too; consistency. (3) The Plan water filter did nothing because `isWaterSrc`
(node build ~11560) counted every town + any meal as water — aligned it to the
shared rule (water/food/shop/pub / town-or-fuel+ohRaw / waterHere), so the filter
now actually hides dry nodes. All fragments node-verified.

## Current status (10 July 2026, v224)

**v224 (10 Jul 2026) — water toggle button in the mission-plan node action row.**
v223 put a small 💧 indicator in the node's chip row, but Peter expected an actual
water BUTTON up in the action row next to sleep/food/edit (like the stop tile has).
Fixed: added a `.water-at-stop` droplet button to the non-sleep mission-node button
row in `tPlan` (~line 11764, before `cluster-edit-btn`), data-sid = the cluster's
town stop; filled blue `#60a5fa` when any stop in the town has water (same rule as
the strip's `hasWater`), outline when none. Reuses the existing `.water-at-stop`
handler (toggles `s.waterHere`, `renderKeepScroll`). Removed the redundant v223
chip-row droplet. Note: only on NON-sleep nodes so far — sleep nodes (e.g. a motel
bivi) don't have the water button yet; add if Peter wants. Node-verified.

**v223 (10 Jul 2026) — water-button scroll fix.** Tapping the v222 water button
scrolled the stop list to the top — the handler used `render()`; swapped to
`renderKeepScroll()` (matches the food picker). (The v223 chip-row droplet it also
added was superseded by the v224 action-row button.)

**v222 (10 Jul 2026) — per-stop water toggle button on the stop tile.** Peter: a
buried food-picker checkbox is inconsistent; make water a first-class one-tap
button in the tile action row alongside star/sleep/food/edit/delete. Added a
`.water-at-stop` droplet button in the main stop tile (`tRoutes`/stops list, the
button row ~line 10969), shown ONLY where water isn't already implied
(café/shop/pub/water/confirmed town) — so it's always a real yes/no, appearing on
plain towns and bring-your-own spots, not on cafés. Outline when off, filled blue
when on; toggles `s.waterHere`; handler in the delegator before the star toggle.
The v220 food-picker checkbox is KEPT for now as a harmless fallback (also covers
the cluster-edit sub-view path); consolidate later. Not yet added to the cluster
sub-view tile or desktop. Node-verified.

**v221 (10 Jul 2026) — dedicated water row only when it's the NEAREST water.**
Peter: on the Grenfell FIT plan the strip showed a WATER row for Monteagle Hall
228 km away on day 2, even though Foodary (next food, 32 km) already has water (💧).
Fixed the v220 over-reach in `buildLiveStrip`: the water candidate now shows only
if `nextWater.dist <= firstWaterDist` (nearest stop with any water). So a nearer
food-with-water suppresses a far dedicated water stop; a tap before food, or the
only water for a long stretch, still shows. Node-verified.

**v220 (10 Jul 2026) — always-visible next water + "water here?" for self-catered
eats.** Peter's point: a food outlet has water, EXCEPT a self-catered eat at a bare
spot (bring-your-own lunch) — food but maybe no water; default to safety. Built in
`buildLiveStrip`: new `hasWater(s)` = water stop / food outlet (food/shop/pub) /
confirmed town or servo (ohRaw) / `s.waterHere` — a planned MEAL alone does NOT
imply water. Next-water row now always shows the next dedicated water stop (removed
the "closer than food" gate); it keeps its own WATER badge. Every other row that
has water gets a small 💧 droplet after its badge (café reads "EAT 💧"; self-catered
eat reads "EAT" with no droplet) — keeps Peter's coloured badges, adds the water
info he wanted. New stop flag `s.waterHere` (bool, default off) set by a "💧 Water
available here" checkbox in the food picker, shown ONLY when water isn't already
implied (i.e. for manual/bare-town eat spots). Verified via node truth-table.

## Current status (10 July 2026, v219)

**v219 (10 Jul 2026) — planned meals outrank the stop's type on the Ride strip.**
Peter (from a sim): a town where he'd planned to eat showed "EAT" while it was the
food candidate, but flipped to "TOWN" the moment it became the next stop — the meal
vanished exactly on arrival. Fix in `liveStripIcons`: `effectiveType` now =
sleep (if a sleep stop) → else meal (if the stop has planned `meals`, or is surfaced
for the food reason, and isn't itself food/shop) → else the raw type. So a planned
meal reads EAT everywhere; sleep still wins for overnighters; cafés stay FOOD; a
bare town stays TOWN. Still open with Peter: always-visible next-water hierarchy,
and whether to split OSM place=village/hamlet from town (pop is already shown).

## Current status (10 July 2026, v218)

**v218 (10 Jul 2026) — route-format order standardised to FIT · TCX · GPX · KML.**
Peter's preferred natural mapping (best-to-worst for PackTimes): FIT (turns + smallest),
TCX (turns, big), GPX (no turns, universal standard), KML (no turns, Google Earth
fallback). Reordered everywhere user-facing: the upload button + empty-state ("Upload
FIT / TCX / GPX / KML"), the "all supported" help line, the Route help blurb, the file
`accept` attributes, and the "Best file for turn alerts" box — which now splits GPX (3)
and KML (4) onto their own lines so all four ranks are explicit and KML's role (a
fallback for Google Earth / My Maps exports; offers nothing over GPX here) is stated.
Copy-only, no logic change.

## Current status (10 July 2026, v217)

**v217 (10 Jul 2026) — food button = one place to manage the whole town's meals.**
Peter: the food button on the cluster tile only let you ADD meals, while the pencil
(edit) button was the only place you could edit/delete existing ones — so the same
job lived in two spots. Fix: the food picker (`.food-at-stop` handler) is now
cluster-aware. It flattens EVERY meal across all pins in the town cluster into one
list (`clusterList` via `clusterStops`; each row remembers its owning `{st,mi}`), so
you can edit/delete any of them and add more from the single food popup. Rows on a
different pin than the one tapped get a small "at <pin>" label. New meals attach to
the tapped pin; `closeAndSave` now tidies empty `meals` arrays + auto-stars across the
whole cluster. Since v216 makes timing label-driven, it doesn't matter which pin a
meal lives on. Verified via node (dinner-on-town + breakfast-on-cafe both show in one
picker with the owning-pin label). Not yet phone-tested by Peter.

## Current status (10 July 2026, v216)

**v216 (10 Jul 2026) — before/after-sleep is decided by the LABEL, not pin geometry.**
Follow-up to v215. Peter's Grenfell case has a food pin that sits just *before* the
motel on the route; v215's finish engine (`etaAt`) still inferred before/after from
distance order, so a breakfast marked "after" on that pin was wrongly cancelled into
the open-ended sleep instead of adding after wake. Fix: new `_clusterMealInfo(r)` +
`_mealSplit(s,hasSleep,info)` (by `sleepHoursFor`/`totalMealHours`). For a town cluster
with exactly ONE sleep, every meal in it is folded onto the sleep stop by its
before/after LABEL and the other pins are skipped (no double count); towns with no
sleep, or >1 sleep, keep per-stop behaviour. Wired into the **pure-planning branch**
of `etaAt` only (the branch every plan — incl. future-dated + the simulator — uses).
The three live-GPS/recorded branches are deliberately untouched: they anchor to real
arrival times mid-ride, and folding passed-but-not-yet-eaten meals onto a sleep there
would double-count. Verified via node: dinner-before + breakfast-after gives the same
finish whether the cafe pin is before OR after the motel (20.99h), matches all-on-one-
pin, and a no-sleep town just adds both meals (1.5h). Rule now holds: before-sleep meal
comes out of an open (wake-time) sleep = no change to finish; after-sleep meal adds
after wake = pushes the finish later. Not yet phone-tested by Peter.

## Current status (10 July 2026, v215)

**v215 (10 Jul 2026) — town is the cluster "bucket" + before/after-sleep food works
across the whole town.** Peter's overnighter case: dinner at the town, sleep at the
motel, breakfast at a cafe — three separate pins. Two problems fixed. (1) The mission
sleep tile was titled after the *sleep pin* ("Bivi at Grenfell Motel") with the town
as a mere chip; now a sleep cluster builds ONE node titled after the **town**, with
the motel + food inside it (`tPlan` node-building ~`clusters.forEach`: `townStop`,
`nodeName`, `clusterAll`, town dropped from chips, `node.dist`=cluster entry so arrival
isn't double-counted; pop badge reads `node.clusterAll`). (2) The food picker's
Before/After-sleep toggle was gated on the *same pin* having sleep, so breakfast at a
cafe couldn't be marked "after". New `clusterHasSleep(r,stop)` (+ shared `isSleepStop`)
makes the toggle appear for food on ANY pin in a town that contains a sleep. The sleep
tile's display + `departEta` now aggregate before/after meals across the whole cluster
(`node.clusterAll.stops.flatMap`), and the sleep-tile edit list shows every pin in town
with its own food button. Finish time is untouched (etaAt unchanged — every meal was
already counted once); only the intermediate wake/depart split and titling change.
Verified via node against the Grenfell numbers (arrive 16:16 → sleep 13.7h → wake 07:00
→ breakfast 60min → depart 08:00, dinner & breakfast on separate pins). Known minor
limit: two sleep pins in one town shows the first as primary, the rest as chips. Not
yet phone-tested by Peter.

**v214 (9 Jul 2026) — "next food" on the Ride strip fixed (bare towns no longer
masquerade as food).** Peter: on the sim, "next food" vanished — a town coming up
had knocked it out. Root cause in `buildLiveStrip`: (1) `hasFood()` counted EVERY
`type==='town'` as food, and (2) the food candidate was skipped entirely when the
next stop already "had food" — so a foodless town as the next stop suppressed the
food row. Fix (Peter chose "real food sources, not bare towns"): `hasFood` now =
planned meals OR food/shop/pub OR (town/fuel WITH `ohRaw` confirmed hours) — a bare
town no longer qualifies; and the food candidate is ALWAYS computed (no suppression
gate), finding the next real food (dedup drops it if it's already the next stop).
Also improves the water row (uses the same `hasFood`, so a bare town no longer
hides water either). `updateLive`'s `nextFood` was dead code (patchCard is a no-op;
strip rebuilds via `buildLiveStrip`), so the one fix covers live updates too.
Verified via node scenarios. Not the bigger turn-alert redesign (still parked).

## Current status (9 July 2026, v213)

**v213 (9 Jul 2026) — future-plan ETAs no longer pinned to "now" by the simulator
(v189 follow-up).** Peter ran the ride sim on the future-dated Grenfell plan (start
Sat 8 Aug) and every ETA collapsed to today's clock (~16:48). Root cause: `etaAt`'s
GPS-active branch (`if(UI.gpsActive&&UI.gpsDistKm!==null)`) anchors everything to
now + remaining distance and — unlike the no-GPS branch that v189 guarded — never
checked `planStartInFuture`. The sim sets `gpsActive` and leaves `gpsDistKm` at its
stop point (~250 km), so stops behind it showed "now" and the two ahead projected
forward. Fix: added `&&!planStartInFuture(r)` to that branch, so a future-dated plan
always computes from its planned start even while GPS/sim is active. Real rides
(start today/past) unchanged. Verified via node truth-table. (Note: `simStop` does
clean up via `stopGPS`, but `simPause` — and exporting mid-sim — leaves the state,
which is why it persisted; the guard fixes all cases.)

## Current status (9 July 2026, v212)

**v212 (9 Jul 2026) — format-preference hint at the upload point.** Added a small
ranked list in the route picker (`pickerBody`, under the upload button): 1. FIT
Course (smallest + turns), 2. TCX Course (turns, bigger), 3. GPX/KML (no turns,
estimate in Turn Review). Puts the recommendation at the moment of choosing an
export, not just buried in the help.

## Current status (9 July 2026, v211)

**v211 (9 Jul 2026) — FIT Course turn import (FIT is now the recommended format).**
`parseFIT` now reads `course_point` messages (global msg 32: fields 2=lat, 3=lon,
5=type enum, 6=name) alongside records (msg 20), maps FIT's turn-type enum to
PackTimes base types (6→Left, 7→Right, 8→Straight, 19/20→Left +slight/sharp note,
21/22→Right, 16/17→fork, 23→U turn; non-nav points like start/end skipped), snaps
each to the nearest route point for a route-aligned dist (as the TCX parser does).
Verified end-to-end against Peter's real RWGPS export (Grenfell 302 km): 124 turns,
correct L/R/slight/sharp breakdown, and the FIT is ~15× smaller than the TCX (103 KB
vs 1.5 MB) with even finer turn typing. All turn help copy (hello Route/Ride lines,
`_helloDetailHTML`, `showTurnHelp`) rewritten to lead with FIT Course as best
(smallest + full turns); TCX still fine, GPX/KML are the no-turns fallback.

## Current status (9 July 2026, v210)

**v210 (9 Jul 2026) — "Your route file" detailed help rewritten (Peter's format
knowledge).** Fixed the wrong "a plain GPX is ideal" claim (GPX is a fallback —
no turns). New `_helloDetailHTML` copy leads with "export a TCX Course", warns
about the Course-vs-History / route-vs-recorded-ride trap (RWGPS "TCX History" or
a GPX of a finished Strava activity = every logged GPS point = huge file), covers
relative file size (FIT most compact/binary; GPX/TCX/KML text; only balloons on a
recording), notes turns come only from TCX in PackTimes, and keeps the
ride-time-from-distance/elevation rationale. Peter-tunable copy.

## Current status (9 July 2026, v209)

**v209 (9 Jul 2026) — TCX benefit spelled out in the main "How PackTimes works"
help.** Rewrote the `_helloContentHTML` 'Route' line: TCX is best for turn alerts
(real cues from RideWithGPS/Komoot), GPX has none (estimate in Turn Review), and —
Peter's key point — "already loaded a GPX? You're not stuck, just re-import the
TCX version any time." Complements the v208 Turn Review "?" explainer.

## Current status (9 July 2026, v208)

**v208 (9 Jul 2026) — turns no longer auto-guessed on import; turn-data explainer.**
Peter's call: guessed turns shouldn't appear automatically (they look official but
aren't reliable). Removed the `autoDetectTurns` fallback from BOTH import paths
(main file import + apply-GPX-to-existing-route); now GPX/KML/FIT import with NO
turns, TCX still brings its real cues. Generating GPX turns is now a conscious act
in Turn Review: when a route has 0 turns the overlay shows a "Generate turns from
the track" prompt (`#trv-generate` → `autoDetectTurns` + re-open overlay). Added a
"?" in the Turn Review header (`#trv-help` → new `showTurnHelp()`, mirrors
showSurfHelp/showFatigueHelp) explaining TCX-vs-GPX turns + file size (~2–3× but
trivial) + how to export a TCX. Updated the Ride help blurb to match. Existing
saved routes keep their turns (change only affects new imports). NOT the bigger
turn-ALERT redesign (popup/sounds) — that's still parked pending Peter's TCX tests.

## Current status (9 July 2026, v207)

**v207 (9 Jul 2026) — ride compass/triangle reworked (field-test fix).** Peter:
the blue position triangle wandered, "not connected to anything". Root cause: the
live map was heading-up off the phone's GPS heading (unreliable on a bike at low
speed), AND the triangle's screen angle was `travelDeg − heading` — two jittery
numbers subtracted. Agreed design (Peter reasoned it out): triangle is FIXED
pointing up ("you, going forward"); the MAP orients to one reliable number. New
`_rideHeadingDeg(pts)` (before `redrawMap`): uses the ROUTE bearing at the snapped
position when on-route (`UI._snapOffKm < 60 m`, stored now at both snap sites),
falls back to GPS heading only when off-route/lost, eased 35%/frame along the
shortest angular path. The two rotating live `drawMap` calls now pass
`forceHeading:_rideHeadingDeg(r.points)` instead of `rotate:true`; the arrow block
uses `arrowDeg = heading!=null ? heading : travelDeg` so "you" points up on an
oriented map (net 0) and along-travel on a north-up map. Verified via node
(on-route→route bearing, off-route→GPS, 350→10 eases short way, triangle net 0).
Not yet ride-tested.

## Current status (9 July 2026, v206)

**v206 (9 Jul 2026) — fatigue skipped on short plans.** Peter's 1.9km test ride
showed a phantom ~6% slowdown when fatigue was toggled: it was the circadian dip
keyed off the route's *planned* start time (default 06:00), not the actual ride
time (13:25) — working as designed but confusing on a trivial ride. Fix in
`buildCumRiding`: refactored the fatigue forward-pass into an inner `accumulate(fp)`
and, if fatigue is on but the total ride is under `FATIGUE_MIN_RIDE_H` (2h),
recompute with fp=null. Recompute only ever hits short routes (cheap); long plans
are byte-identical to before. Verified: 1.9km ride on==off; 100km ride on≠off.
Circadian kept (it's real + well-evidenced even when rested — ~7–11% daily swing).

## Current status (9 July 2026, v205)

**v205 (9 Jul 2026) — Strava rename/upload reliability (field-test fixes).**
Peter's test ride: renaming gave no feedback so he re-uploaded to force it, which
then jammed on "queued". Root cause = everything was silent. Fixes (STRAVA
section): (1) `stravaSyncName(rec, announce)` + `stravaMarkRename` now toast the
outcome ("Name updated on Strava ✓" / "…will keep trying" / "will sync after the
upload") so a rename never needs a manual re-upload; (2) broadened the duplicate
matcher in `stravaProcessQueue` to `duplicate of (?:activity )?(\d+)` plus a bare
"duplicate" fallback, so a re-upload re-links + resyncs the pending name instead
of sticking forever; (3) the detail-modal status line now appends the last
attempt's error after "Queued for Strava upload" instead of hiding it. This also
unjams Peter's currently-stuck ride on next retry. Written + fragment-tested, not
yet re-ridden.

## Current status (9 July 2026, v204)

**v204 (9 Jul 2026) — fatigue popup wording pass (Peter's edits).** Honesty
fixes only, no logic change: dropped the "four hours clears the day's tiredness"
overclaim (now "rough minimum to keep going… you'll still be tired… varies, no
hard cut-off"); removed the overstated "nod-off danger flagged separately" (there
is no such feature — only the >20h amber note), catnap line now ends on Peter's
safety-signal point; reworded the awkward "gentler thing than a bad night feels
like".

**v203 (9 Jul 2026) — fatigue recovery set to the textbook curve (τ=4.2h) +
transparent popup.** Changed `FATIGUE_SLEEP_TAU_H` 2 → 4.2 (published two-process
sleep-decay constant, Daan/Beersma/Borbély 1984): 1h nap recovers ~21%, 4h ~61%,
8h ~85%. Peter's call after we worked through it — ~4h reads as the sustainable
nightly minimum (matches multi-day-rider lore) and catnaps stay modest for PACE
(their real job is fighting microsleep — safety, already covered by the >20h-awake
warning, not pace restoration). A full night still lands inside the fresh window
= effectively fresh, so well-slept plans are ~unchanged (verified: 8h sleep after
16–24h awake → back under the 8h window). Popup rewritten to explain the method
honestly (sleep-science curve, 4h floor, catnaps-for-safety, "guide not a
precise promise"). Grounded in `_planning/sleep-fatigue-research.md`.

**v202 (9 Jul 2026) — sleep recovery now scales with sleep length (diminishing
returns).** Replaced the binary `if(hasSleep)fSince=0` with
`fSince*=Math.exp(-sleepH/FATIGUE_SLEEP_TAU_H)` (τ=2h, new const by
`FATIGUE_MODES`). Front-loaded recovery: 1h nap clears ~39%, 4h sleep ~86%
(lands back inside the fresh window = effectively full, so realistic sleep plans
behave as before — only short catnaps change, and now read slower/more honest).
Grounded in the Borbély two-process homeostat. Popup copy updated to describe
diminishing returns (the v201 "counts the same" caveat is gone). Existing routes
pick it up automatically — `buildCumRiding` reruns on load.

**v201 (9 Jul 2026) — fatigue popup notes the binary sleep reset (superseded by
v202, which actually fixed it).** Documented a
real limitation: in `buildCumRiding`, `if(hasSleep)fSince=0` resets the
sleep-debt fully at ANY sleep stop regardless of length — a 15-min nap == a
4-hour sleep for fatigue recovery (sleep length still shifts the clock/circadian
timing, just not the debt reset). Added a line to `showFatigueHelp` warning that
catnap-heavy plans read optimistic. Not fixed in code (partial nap recovery was
in the research design but never built) — documented only, per Peter.

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
