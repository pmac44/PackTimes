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

## Current status (17 July 2026, v263) — THE OUT-AND-BACK BUG IS FIXED. v261 pushed, v262/263 not.

**Peter's 17 July ride test found the biggest bug in months, and the direction detector was
innocent.** He rode a 30 km out-and-back he does regularly: *"it thought I was at the end when I
was actually starting… the distance started off as if I'd done the whole 30 km, and then it just
went in reverse."* Every turn cue was wrong for the same reason.

### THE ROOT CAUSE WAS A STALE INDEX, NOT THE DIRECTION DETECTOR

- `UI._lastSnapIdx` is **persisted to `lastGps` (~3752) and restored on app load (~1206)** — that
  restore is legitimate, it's there so a mid-ride reload doesn't lose your place.
- **`startGPS` reset `_snapDir` but never reset `_lastSnapIdx`.** So a NEW ride inherited the route
  position of the LAST one. On a loop he rides regularly and FINISHES, that index is the finish —
  so the first fix of the next ride went straight down the window path anchored at the end of the
  route. **No coin toss was involved: it was simply told where it had been last time.**
- **The direction detector then made it permanent, exactly as the v257 note warns.** The votes saw
  him leaving the finish, latched `_snapDir=-1`, and a backward-biased window is self-reinforcing.
  He thought the detector was broken. It was being fed a lie. **Don't "fix" the detector.**
- **Fix 1:** `startGPS` clears `UI._lastSnapIdx` unless we're resuming a recording that already has
  history (`_rec.points.length>1`) — that IS the crash-recovery case the restore exists for; a
  fresh `startRecording` has `points:[]`. `simStart` had the same hole and now clears it too.

### FIX 2 — PETER'S RULE FOR WHICH END YOU'RE AT

- Clearing the index isn't enough: the first fix then does a full search, which takes **the nearest
  VERTEX by raw distance**, and where start and finish sit metres apart that's a coin toss decided
  by GPS noise. **Truth-tabled: fix 1 alone still picks the finish.**
- **IT CANNOT BE SETTLED FROM GEOMETRY, and that's the load-bearing part.** Peter: *"this GPS route
  is a hard one to tell just from the GPS because it's a bike path… literally a 2- or 3-metre-wide
  path in both directions, which is identical."* There is no signal in the shape to find, and no
  amount of bearing cleverness invents one.
- **His rule, which needs no map data at all: "if you're just starting out, you're probably at the
  start rather than the finish."** Right essentially always, and the alternative is a ride that
  opens at 30 km and counts down. Implemented as: ends within `SNAP_ENDS_MEET_KM` (250 m) **and**
  you're at them **and** the search chose the far half → force idx 0.
- **Gated on a new `liveFix` argument + `lastIdx==null`** = the rider's own FIRST fix of a session.
  This matters: the POI/stop searches (~3179/3333/3423) and the gap-fill snaps (~4347) also omit
  `lastIdx` and are emphatically NOT starting a ride — forcing a café at a loop's start/finish to
  dist 0 would silently move a stop. Only the GPS callback and the two sim paths pass `true`.
- **At the FINISH the rule can't misfire**: by then `lastIdx` has tracked you the whole way round,
  so the window path answers and the fallback never runs. Truth-tabled.
- **Verified: whole-file `node --check` + 11/11 truth-table** on a faithful model (asymmetric
  `_snapDir`-biased window + full-search fallback; return leg offset 2 m, as a real bike path is).
  **It reproduces Peter's ride first** — stale index → reads 30.0 km at the trailhead, 29.0 km at
  1 km out — then proves the fix: 0.0 km at the start, **zero reversals across the whole 30 km**,
  finish still reads 30, POI snaps unchanged, A-to-B routes never engage the rule.
  ⚠ **My first harness was wrong** (symmetric window, both legs the identical line). A degenerate
  out-and-back is ambiguous everywhere and proves nothing — model the 2 m offset.

### v264 — "FOLLOWING THIS ROUTE?" IS BUILT. The app stops guessing.

**Peter's argument killed the v260 design, and it's decisive. Keep it verbatim:** *"I set a lot of
routes. And a lot of them start from my house, and a lot of them I ride regularly. I don't follow a
route on a GPS or a phone, so I just know them in my head… I don't think there's enough information
that an app can make that decision for you."*
- **v260's trigger was PLACE-only** — fire the prompt when you're NOT near the route. It rested on
  the assumption that standing at the start means you intend to ride it. **Peter's ride disproved
  that**: same route, same start, same time of day, opposite intent. **The two cases are physically
  identical. There is no signal. Don't build a cleverer trigger — build the question.**
- **So it ALWAYS asks**, whenever a route is loaded and you press record. Never when one isn't.
- **THE CLOCK QUESTION IS GONE.** v257's "Riding this now?" is replaced. v260 had already ruled that
  pressing record on a route always means NOW, so `_rideNowAuto` just sets it. ⚠ **DISPLAY only —
  `planStartInFuture` still gates CAPTURE, so a future-dated plan is still never stamped (v189).
  Truth-tabled explicitly; do not "simplify" that guard away.**
- **THE TIMEOUT (8 s) CHANGES NOTHING** — it closes the sheet and leaves the state alone. So the
  effective default is "follow" (what a fresh ride already is) without the sheet being able to
  **overwrite a choice already made**: a destructive default would undo a freestyle set from the
  bar seconds earlier. Truth-tabled as its own case.
- **"Just ride" reuses `_offRouteMode='abandoned'` — no new state.** It's v245's flag: already
  per-ride, already survives the ride, already resets at `stopGPS`, and **v263's distance bar
  already reads it**, so the chevrons and "to go" vanish and the odometer takes the slot for free.
- **TAP THE DISTANCE BAR TO CHANGE YOUR MIND — and it isn't a nicety, it closes a real hole.**
  Peter: *"how would you get out of that?"* Today you couldn't. The only exit was the v245
  off-route alert's "Stop following this route", **which only fires when you're actually off the
  route** — and freestyling out of his house along a road he has a route for, he never is. So the
  alert never appears and there is no exit at all.
  · The bar is the right switch: it IS the object that means "following a route", it's the thing
    visibly lying to you when you aren't, and it's already big and always there — no new furniture.
  · **It opens the SAME sheet rather than toggling.** A stray tap on something that size must cost
    a glance, not your turn cues. One sheet, two doorways; symmetric both ways.
  · Peter on this: *"I'm not sure about tapping the distance bar to toggle it, but happy to try."*
    **So it's on probation — if it doesn't land, the sheet still needs some permanent doorway.**
- **Rejected: a "no route" entry in the Route tab dropdown** (Peter's own alternative, and he
  rejected it himself — *"that sounds like more steps"*). Note v260's list still carries the same
  idea; the popup supersedes it as the primary path.
- **Verified: whole-file `node --check` + 17/17 truth-table** — record never waits on the question
  (v257's law); "Just ride" flips v263's bar to the odometer; the timeout can't undo a pre-set
  freestyle; the bar round-trips both ways; a future-dated plan runs on today's clock while
  `planStartInFuture` stays true so CAPTURE is still blocked; a today-dated plan is unaffected;
  no route or a zero-length route raises nothing. Zero orphan refs to the v257 sheet.

### STILL TO DO from the 17 July ride (Peter's list, in his words)

1. ~~No "follow the route / just ride" prompt at ride start.~~ **BUILT — v264 above.**
2. **The weather pill flashes constantly** — a warning always on; possibly tonight's temperature
   drop.
3. **The weather pill's temperature is in the wrong font** — *"reads like Courier"*, which is what
   `monospace` falls back to when DM Mono isn't applied. Everything else numeric renders fine, so
   suspect that pill's own font stack, not a font-loading failure.
4. **Notification layering is inverted** — a base-speed drift warning was masked by the info pills.
   **Notifications must be the top layer**, above everything.
5. **L/R balance reads 0/100 when coasting.** BLE reports ONE pedal's percentage; the meter sends 0
   with no power, so we render maximum-right. It's measuring nothing and displaying it. Peter:
   *"when you stop pedaling, it goes 100% right… I wonder if when I coast, that actually affects
   it."* Kill the reading when there's no power.
6. **The pills should be SET SLOTS in a solid band, not floating over the map** (Peter). *"You just
   can't really see much of the map, and it's actually eating some pixels."* The argument: you pay
   for that map twice — it's unreadable behind them anyway, and the pills must be opaque to sit on
   it. The pixels come from the gaps and margins, not the map; it helps small screens most; and the
   distance bar is the precedent — *"that distance bar with no gap works, so we shouldn't put too
   much thought into map padding."* Also dissolves the fit-button masking.
7. **Start ride → bottom-left; Resume/Stop → a popup** (see v262 below).

### Answered, not built (17 July)

- **CRANK LENGTH: no input needed, and don't add one.** Peter asked where to enter it. Pedal-based
  meters compute watts INSIDE the pedal (force × crank length) and crank length is a setting in the
  pedal's own app (Favero/Assioma, Garmin Connect). What arrives over BLE is finished watts, which
  is all `_parsePowerMeasurement` reads. If it's wrong it's wrong in the pedal's app and every head
  unit inherits it — Garmin and Strava included. Nothing for us to calculate.
- **L/R balance stays NEAR-INSTANTANEOUS — Peter talked himself out of his own complaint.** He
  expected a ride average, then: *"I actually found that was good because I have trouble balancing
  my leg power left to right, and that near-instantaneous reading actually gave me great feedback
  for changing my pedal stroke."* It's also consistent with cadence being instantaneous. **Leave
  it.**
- **The stoppage pill widening past 9h59** — he re-noticed it; it's v259's recorded, accepted
  behaviour (`fmtDurPill` + `min-width:4ch`, grows at 10 h, not 100 h). Not a surprise, not a bug.

### The distance bar is DONE (Peter, after the ride)

*"Distance bar, I think, is basically excellent… it's there. It's good. It works."* And the ridden
figure I argued against is validated twice over: it was **the only honest number on the screen**
while everything route-scoped was lying, and his second case is the one to remember — *"with 10 km
along the route, I just happen to have ridden 30 km because I rode 20 km from home"*, which is the
same shape as joining a group ride partway.

## Current status (17 July 2026, v262) — the Stops map's white hint DELETED. v261 IS PUSHED.

**v261 is pushed and Peter is ride-testing it.** On the phone: *"the chevrons look very good along
the top. Such a big improvement."* **His screenshot answers the one open worry from the whole
build — the 2.51px chevron gaps ARE legible on his OLED**, so `DIST_CHEV_N` stays at 24 and the
"drop to 22" fallback is not needed. That was the only number in v261 that came from my estimate
rather than a measurement.

### v262 — three small fixes off Peter's phone. NOT pushed at time of writing.

**(1) THE SHARING BUTTON STOPPED TRACKING THE WEATHER PILL — a real bug, and the 4th occurrence
of this file's most persistent shape.** Peter: *"the weather pill jumps up when the elevation
graph is shown, but the location share one does not… the sharing button has lost its ability to
jump up."*
- The share/pack button is not positioned by CSS — `_shareBtnSync` **measures the weather bar's
  top** with rect maths and sits 6px above it. So the moment `_adjustWeatherForElev` moves the
  weather bar, that measurement is stale.
- **Of its five callers, only `initLiveMap` re-synced the button.** The two elevation-toggle
  handlers and `updateLive`'s own call did not.
- **Why it hid for so long:** on a LIVE ride `updateLive` calls `_shareBtnSync` every tick, so it
  self-corrected within a frame. On an **idle** Ride tab `updateLive` never runs — so it stayed
  wrong. Peter's case exactly: parked, tapping the elevation strip open.
- **Fixed at the CAUSE, not the call sites:** `_adjustWeatherForElev` now ends by calling
  `_shareBtnSync()` + `_packBtnSync()`. Patching the three callers would have left the same trap
  for the fourth. **The thing that MOVES an anchor is the thing that must re-anchor whatever
  hangs off it** — same lesson as v252's rotation, v257's peek anchor, v260's `afterKm`.
  Verified non-recursive (neither sync calls back into it) and both are hoisted declarations.

**(2) Map-control padding 12 → 6** (Peter, on the fit button being masked). **Worth recording what
this is NOT:** there was no big unmeasured gap to reclaim. `h` is the strip's REAL measured
height and the padding on it was already 12px — the weather bar beside it has none at all. So it
buys **six pixels**, and only helps because the overlap Peter is seeing is "a pixel or two". It is
not a fix for a crowded column.

**(3) `.mhint` deleted** — see below.

### THE RIGHT COLUMN IS OVER-SUBSCRIBED — the real problem behind (2). Not fixed.

- **This PREDATES v261.** Modelled at v260's `top:48` the pre-ride column was already overlapping;
  v261's 16px took it past the point where you can see it. **v261 exposed it, it didn't cause it.**
- ⚠ **DON'T TRUST MY GEOMETRY MODELS HERE.** I modelled this off Peter's screenshot three times
  and got the section height wrong every time (last model said 40px of clearance; his crop showed
  them touching). Measure in the DOM or ask him — do not compute it from constants.
- **Peter's plan, agreed, NOT yet built:** (a) move **"Start ride" to the bottom-left** — a wide
  left-to-right button belongs on the left, and it belongs beside the sharing button because
  sharing only happens while recording, which is a coupling v257 said the UI must EXPLAIN and
  currently doesn't; (b) **Resume/Stop become a popup** — they're a transient state you're actively
  resolving, so sizing the permanent layout around them is backwards. **The popup already exists**
  (`rec-stop-confirm`, the v245 panel — and its "Back to ride" already means resume), so this is
  cheaper than it sounds. It also removes the 3-button paused case, which is what breaks first.
- **Deferred deliberately:** moving the record button means pulling it out of `mapCtrlHTML`,
  chaining a new bottom-left sync off the sharing button's rect maths, and rewiring its rebuild in
  `updateLive` — a refactor of the recording control, which this file calls sacred and which I
  cannot press from here. Not worth doing the evening before a ride test.
- **Nothing saves a small screen or a taller Next strip** — two pills need ~280px from the top.
  Peter's answer is right for a rider (*"that is the beauty of the pills — you don't have to show
  them all"*) but it isn't an answer for the app, which currently fails by silently overlapping.
  That's the standing RIDE-SCREEN CONSOLIDATION item.

### OPEN BUG — the map paints BLACK until you touch it (Peter, desktop small map AND mobile)

*"I've always got to sort of touch it and maybe trigger a slight pan for it to draw… as soon as
you touch or move anything, it just appears."* **Not diagnosed — hypothesis only, do not "fix"
this blind.**
- What's ruled out: the tile→redraw plumbing is intact (`drawMap` passes `cvs.id` → `drawTiles` →
  `getTile(z,x,y,cvsId)` → `img.onload` → `redrawMap(cvsId)`), and `redrawMap` handles every id.
- **The suspect, and it's this file's favourite shape:** `drawMap` line 1 is
  `W=cvs.offsetWidth, H=cvs._forcedH||cvs.offsetHeight||220`. **H has a fallback; W has none, and
  there is no zero-guard.** If the first draw runs before layout, `W=0` → `kx`/`scale` go to 0 or
  NaN → the tile loop's bounds are NaN → **the loop never runs, so no tile is ever REQUESTED** →
  no `onload` → no redraw. Nothing schedules another draw, so it stays black until a gesture
  redraws it with a real width. That the `||220` exists on H at all suggests someone already hit
  this class of bug on the height and patched only that side.
- **To confirm before building anything:** when the map is black on the desktop, RESIZE the window
  without touching the map. If it paints, it's layout/width. If not, look elsewhere.
- Likely fix if confirmed: bail out and retry on rAF (capped, so a hidden tab can't spin) rather
  than drawing into an unlaid-out canvas.

### v262 — `.mhint` deleted (one CSS rule + one usage, Stops map only)

Peter: *"the white text at the bottom of the map is largely unreadable, but also of questionable
need."* Both true, and the second is the reason it's deleted rather than restyled.
- It was `rgba(255,255,255,.35)` — **35% white laid over a map whose colour we don't control**
  (pale grey and green). It never had a chance. **Standing shape, 4th occurrence** (cf. v260's
  grey pill labels, which Peter killed for the same reason): translucent text over content you
  don't control is not a subtle label, it's an invisible one.
- **It DUPLICATED the list six pixels below it.** The stops list already opens with "Tap on the
  map to add a stop" in full contrast on the panel's own dark background — and that copy
  *scrolls away* once read, which is what a first-run hint should do. The v260 note about the
  peek title said exactly this: "that new title just scrolls away when you scroll the list up
  anyway."
- "drag to pan" is the universal map gesture and needs no caption.
- Verified: whole-file `node --check` (19,746 lines, ends `</html>`, both blocks clean); zero
  orphan `mhint` references; the `map-wrap` still closes correctly around canvas + controls.

## v261 — THE DISTANCE BAR IS A CHEVRON RULER (pushed 17 July, ride test in progress) It closes the v260 label mess: v260 had been pushed several times with
different code under one label, so a phone reporting "v260" could be any of several builds. That
is now behind us — **one step = one version bump = one push, and never re-push a version.**

**Round 7 of the distance bar, and it's Peter's design. The six rounds before it all argued about
TEXT PLACEMENT; none of them touched the thing he kept complaining about.** *"I'm still not happy…
It's lacking an impression of movement, of dynamics. It's just this bland bar."*

- **THE BAR IS NOW 24 CHEVRONS, EDGE TO EDGE** — ghosted ahead of you, accent behind. Full width,
  no radius, no map showing around it, numbers in their own row underneath.
- **THE MOVE THAT UNSTUCK IT, and it was Peter's: the chevrons are the RULER as well as the fill.**
  He asked for ruler marks at 10–20% intervals *and* a chevron fill, then spotted himself that the
  second might negate the first. It does — each chevron IS 1/24th of the ride. Fractions, not
  10 km: absolute marks degrade exactly where the bar matters most (~100 ticks on a 1000 km event),
  and absolute distance is already the elevation strip's job.
- **THE SIX-PIXEL FINDING — the one nobody checked in six rounds.** Moving the numbers OUT of the
  bar kills the whole straddle/flip/creep/reserved-ends problem class outright, and it costs
  **34px → 40px. Six pixels.** Every earlier round (the rail, the travelling pill, reserved ends,
  migrate) assumed taking the text out was expensive and designed around that assumption. It was
  only ever expensive while the bar was an inset pill floating on the map; once Peter gave it its
  own full-width band, the row below was nearly free. **Standing lesson: when four designs in a row
  are all working around the same constraint, price the constraint before you design round it again.**
  Floating pills stay at `top:48px` and do not move.
- **NO PARTIAL FILL — A WHOLE CHEVRON TURNS GREEN OR IT DOESN'T (Peter's rule).** *"My idea is that
  there is no vertical colour line. The progress is when another grey chevron turns green."* The
  vertical cut in the first mockups was **my** decision, not a mockup limitation — I clipped the
  fill to a rect assuming he'd want continuous motion. His is better: **the chevron is the unit of
  progress, the numbers below are the precise truth. The bar is the gauge, the numbers are the
  reading.** A leading chevron that fills as you ride it was mocked (`quantised.png`, bottom row):
  it is indistinguishable from the plain version at every real state. **Don't rebuild it.**
- **WAHOO — Peter caught this and he was right: *"chevrons are a large part of the Wahoo identity,
  so they should be visually different to avoid seeming to mimic."*** What is theirs is the **weight
  and packing** — fat, tightly-stacked symmetric V's with gaps as wide as the mark, stacked ACROSS
  the direction of travel on hardware (his reference images: KICKR flywheel decals). A horizontal
  row in a progress bar is road-sign/escalator idiom, not theirs. Ours is a **fine scale, not a
  slab**: same shape, opposite character. If this is ever restyled, weight and packing carry the
  association — not the chevron as such.
- **WHY 24, AND THE TRADE THAT DECIDES IT — the two forces pull AGAINST each other.** Quantised
  ticks want MANY chevrons; every gap must survive a phone. The gap is **diagonal**, so what you see
  is `gap·cos(40°) ≈ 0.77` of the horizontal gap, and below ~2.5 CSS px it mushes into the solid
  slab this version exists to kill (v258's lesson: a 3px tick vanished on Peter's phone). On a 393px
  bar:

  | gap (% of mark) | max chevrons | km per tick, 300 km route |
  |---|---|---|
  | 10% | 11 | 27.8 |
  | 15% | 16 | 19.4 |
  | 25% | 24 | 12.6 |

  **Counterintuitive and load-bearing: a WIDER gap ratio buys MORE chevrons**, because a fat mark
  spends its width getting to a gap you can see. So Peter's "gap no more than 10–25% of the chevron
  width" and his need for many chevrons meet at the TOP of his band. **Don't raise `DIST_CHEV_N`
  without widening the gap, and don't narrow the gap to fit more in — that's the intuition the
  table refutes.**
- **⚠ THE ONE THING TO WATCH ON THE PHONE: the gap has almost no margin.** 24 chevrons gives a
  perpendicular gap of **2.51 CSS px against a 2.5 floor** — and that floor is *my estimate*, not a
  measurement. At DPR 2.75 that's ~6.9 device px, so resolution isn't the risk; diagonal
  anti-aliasing is. **If the chevrons mush together on Peter's OLED, drop `DIST_CHEV_N` to 22**
  (gap 2.74px, ticks every 13.7 km) — one constant, no other change.
- **The tick rate scales with the ride ON PURPOSE**: a chevron is always ~4% of the day — 1.7 km on
  a 40 km ride, 12.5 km on Grenfell, **42 km (≈2 h) on a 1000 km ultra**. Peter accepted the ultra
  case with that number in front of him. It IS the opposite of "impression of movement" in the short
  term, which was his original complaint — the argument that carried it is that the km figures below
  do the second-by-second work. **Watch this on a long ride; it's the one decision made on reasoning
  rather than on a phone.**
- **`floor`, not `round`**: a chevron lights once its slice has been RIDDEN. Rounding would light
  the last one before the finish — the one moment the bar must not lie. Consequence accepted: the
  bar is all-grey for the first 1/24th.
- **DELETED with the flip they served**: `_distBarGeom`, `_distTextW`, `_distMeasCvs`, `DIST_PAD`,
  `.live-dist-fill`, the `on-fill` reversal, and v258's whole-pixel box SNAP (the bar is edge to
  edge now and has no side hairlines for it to fix). `legToGoKm` STAYS — it is the "to go" figure and
  the v257 leg-scoping rule still applies. Grep confirms zero orphan references.
### v261b — Peter's three notes off the first build ("a clear advancement")

- **BOTH ENDS ARE NOW DELIBERATE, AND ONE EXPRESSION DOES IT.** `left = (i+1)·pitch − th`
  (was `(i+1)·pitch − (pitch−th)/2 − depth`) puts the LAST chevron's front outer corners exactly
  on the bar's right edge, so **only its point is cropped** — it had been losing 11.5px of a
  21.5px body ("at the moment it is cropped too much"). That same expression is a pure 3.06px
  **translation** of the whole row, so it fixes the left end too and **cannot** disturb the ruler:
  a translation can't change a gap. Truth-tabled all 23 inter-chevron gaps identical after it.
- **THE FIRST CHEVRON HAS A FLAT BACK AT x=0** — Peter: *"the first chevron can be filled right
  to the left edge, which means there is no small black triangle left over."* The leftover was the
  rear notch, half off-screen. Chevron 0 is now a pentagon (flat back, same tip, same front face,
  longer tail). **He predicted the consequence before seeing it — "that is a big chevron. That's
  ok" — and it is: 24.77px against the others' 21.50.** The **gap to chevron 1 is unchanged**,
  because the gap is set by the FRONT face and only the tail grew. That's why this is safe.
- **THE FIGURES WERE TOO SMALL, and that one was mine.** Peter: *"the distance km numbers are
  still very small relative to the speed and other data pills. Distance is an important
  measurement."* Correct — 15px was me sizing the row to be **cheap** (to protect the "six pixels"
  headline) rather than sizing it to be **read**. Now **24px** (unit 13px), numbers row 20→30px,
  band **40→50px**, and **the floating pills moved `top:48px` → `56px`** — the first time this
  band has cost anything beyond the six pixels, and the pills are the only thing in the app keyed
  to it. **24, not the pills' 34px hero:** a pill's figure IS its pill's whole point, whereas here
  the chevrons carry the glance-read and the figures are the precise backup — so they rank below a
  hero and well above a caption. Options if he wants to trade: **20px keeps the pills at 48** (band
  47, nothing else moves); **28px** needs pills at 62. Two constants.
- **Wahoo, settled:** *"I think it is different enough that it does not look like the wahoo ones."*
- **Verified: honest WHOLE-FILE `node --check` — the mount finally caught up mid-session** (19,588
  lines, ends `</html>`, 2 script blocks, both clean; the `</html>` assert ran first, per the
  standing rule) **+ 16/16 truth-table** (first chevron flat at 0 with its tip on the same ruler
  and its gap identical to a normal one; last chevron's front corners exactly on the right edge
  with only the 8.4px point cropped; visible body 10.0px → 13.1px; the 3.06px shift is uniform;
  all 23 gaps equal; perpendicular gap still 2.51px; both clip-paths well-formed; "300.6 km" at
  24px fits both ends of a 393px bar with 189px of middle to spare).
- **STILL NOT PHONE-TESTED.** Open `index.html` in a browser once before `push.bat`.

### v261c — the ends, settled: SAME SIZE, SAME TREATMENT, NOTHING CROPPED

**Peter caught the inconsistency in v261b immediately and there was no principle in it:**
*"the first chevron has its tail FILLED (as I requested) but the last chevron has its point
CROPPED. I think both need to be treated the same — either fill the tail on the first and fill
the point on the last, or crop the tail on the first and crop the point on the last."* One end
was being completed, the other truncated. Built his **option 1 (fill both)**.

- **THE FIX WAS TO STOP ASSUMING THE PITCH.** Every version until now took `pitch = barW/N` as
  given and then paid for it at the ends (v261's over-cropped last chevron; v261b's 24.77px first
  against a 21.50px normal). **Solve for the ends instead** — let the 24 tips be evenly spaced by
  `p`, the first tip at `B`, the last tip exactly at `barW`:
  `B + (N−1)·p = barW`, `B = depth + th`, `p = (1+GAP)·th` ⇒ **`th = (barW − depth) / (1 + (N−1)(1+GAP))`**.
  Everything falls out: **all 24 chevrons are exactly 21.33px**, the first's flat back sits on
  x=0, the last's **point lands on 393.000 of 393** — whole, not cropped, not blunted — and
  nothing overhangs either edge. Truth-tabled at 320/393/780/1200px: ends flush at every width.
- **The first chevron now differs from the others by ONE VERTEX** — the rear notch is dropped so
  the back runs straight down. Same width, same tip, same front face, same `T`, so **all 23 gaps
  stay identical** and the gap is still exactly 25% of the mark. Cost: gap 3.28 → 3.23 CSS px
  (perpendicular 2.51 → 2.47). Immaterial — both sit on the same *estimated* floor.
- **CROP-BOTH was the other coherent option and was mocked (`ends-symmetry.png`, row C).** It is
  genuinely symmetric, but it brings back the left-edge black triangle Peter objected to — the
  chevron's own rear notch, biting into the edge. Rejected for that.
- **~~BLUNTING the last chevron's point is wrong: it kills the point at the finish, the one
  moment the arrow should land hardest.~~ WRONG — REVERSED IN v261g. See below.**
- **THE CHEQUERED LAST CHEVRON: tried, and it's a no** (`ends-symmetry.png` row D,
  `zoom-right.png` at 3×). Peter floated it himself — *"Nice idea, but could be terrible"* — and
  it's terrible. The chevron body is **13.1px wide, which buys about two and a half squares**: it
  doesn't read as a chequer, it reads as damage, and it eats the chevron's shape exactly where
  the shape matters most. **This is the SECOND time this file has found it** — v258 recorded that
  "the 8-rect flag dithers to mush at 14px". A chequered flag needs a slot far bigger than one
  chevron; if the finish ever wants marking, that's where to look.
- **Verified: whole-file `node --check` (19,592 lines, ends `</html>`, both blocks clean) +
  15/15 truth-table** (all 24 the same size; first at x=0; last tip exactly on the edge; nothing
  overhangs either end; all 23 gaps identical and still 25% of the mark; clip-paths well-formed;
  ends flush at four bar widths; the quantised ticks unchanged).

### v261d — the chequer, the figure size, and no-route. Peter on the desktop build: *"it looks pretty good… a really big advance."*

- **THE LAST CHEVRON IS CHEQUERED — and v261c's "don't rebuild it" was MY error, now reversed.**
  I judged the chequer at **3× zoom**, where it reads as damage, and called it terrible. Peter
  judged it at true size: *"I actually like the chequer… It's subtle but a nice little touch."*
  **Nobody rides at 3×.** Subtlety is a true-size property and I destroyed the very thing being
  judged by magnifying it. **STANDING LESSON, and this file already had it: JUDGE AT TRUE SIZE.**
  · v258's opposite finding (*"the 8-rect flag dithers to mush at 14px"*) is still true and is not
    a contradiction: **that flag had to be READ, this one only has to be FELT.** A mark that must
    be decoded needs resolution; a mark that only has to register a mood doesn't.
  · Built as `.live-dist-chev.fin` — styling only. Same shape, size, clip-path and tick rule, so
    it ghosts and lights exactly like its neighbours and the point stays a point. `currentColor`
    + a `conic-gradient` lets one rule serve both the ghost and the done state.
    **`background-color`, never the `background` shorthand — the shorthand would wipe
    the chequer's background-image.** (Checked by the verifier; keep checking it.)
  · **v261f — THE GRAIN, and it is NOT a CSS constant. Peter: *"the finish chequer needs another
    square or two filled in."* A chequer is always 50% ink, so this was never about coverage —
    it was GRAIN.** At the shipped 5px cell, one square was **39% of the mark's 12.93px body**, so
    a single transparent cell ATE THE POINT and the chevron read broken. **Rule: the cell must be
    small relative to the feature it textures.**
  · **And it must scale with the chevron, because the chevron isn't a fixed size.** `pitch =
    barW/24`, so the mark is ~26px on desktop against ~13px on a phone — a fixed cell would be a
    *different mark on each screen*. So the tile is set INLINE by `_distBarSync` as `th/2` →
    **exactly four cells across the mark at every width** (verified at 320/393/780/1200px). Phone
    cell 3.23px, desktop 6.48px, same mark. Floor of a 5px tile so a freakish width can't dither
    it to mush (v258). The `6px` in the CSS is only a first-paint fallback.

### v261g — THE LAST CHEVRON IS SQUARE-ENDED. My v261c ruling reversed, and Peter diagnosed why.

**Peter: *"the end chequer needs a square end. It needs to butt up fully on the right side. It
doesn't have to fit into a chevron shape… that gives us more chequer. I think my original point
was actually probably correct. But it was caused by the chequer not filling in the arrow head."***
He's right on both counts, and his diagnosis is the better one — the grain fix (v261f) treated a
symptom.

- **`clipN` = the exact mirror of `clip0`:** rear notch kept, front SQUARED against the bar's
  right edge. `polygon(0 0, D% 50%, 0 100%, 100% 100%, 100% 0)`.
- **MY v261c OBJECTION WAS WRONG.** I ruled that blunting "kills the point at the finish, the one
  moment the arrow should land hardest." **The finish is a DESTINATION, not a "keep going"
  signal.** The arrow points AT it; the flag doesn't need to point. I'd reasoned about the mark in
  isolation instead of about what it means.
- **AND THE POINT IS WHAT BROKE THE CHEQUER — a chequered flag is a rectangle.** A point and a
  chequer were never going to share a 13px mark; v261f's finer grain made that survivable, but
  Peter's fix removes the cause. Both changes stay: the grain rule is right independently.
- **Truth-tabled 10/10, and the symmetry is now exact rather than approximate: the first and last
  chevrons have IDENTICAL area (342.6px² each).** The first fills in its rear notch, the last
  fills in its point — the same 84px² at each end, off the same 258.6px² normal chevron. All 24
  still occupy the same 21.33px box, and **all 23 gaps are untouched** because a gap is set by the
  FRONT face of the chevron behind it, and only the last chevron's front changed.
- **+32% area is what makes the chequer legible**: 6.6 cells across the flag, against 4 across the
  old pointed mark, with one cell still only 25% of the mark.
- **THE FIGURES ARE 34px = THE SPEED PILL'S, and it took Peter saying it twice.** My 15px then
  24px were both me protecting map real estate and dressing it up as hierarchy. **My reasoning was
  upside down:** I argued distance ranks below a pill's hero because the chevrons carry the
  glance-read — but the chevrons are a GAUGE and carry no number at all, so that row is the ONLY
  place distance is ever stated. That makes it a **peer of speed, not its subordinate.** Band
  20+38 = **58px**; pills `top:48 → 64`. **Watch: that is 24px of map gone versus v258's bar.**
- **PETER'S "NUMBERS ON THE CHEVRONS" GUT FEEL — mocked (`pills-on-ruler.png`) and it is
  ARITHMETICALLY reserved ends.** He wondered whether the figures should sit on/над the chevrons as
  a pill in a fixed location, killing the blank centre. The idea is coherent — a **cased pill
  can't straddle, it occludes** (v258 said as much) — but the numbers eat the ruler:

  | figure size | pill width | ruler still visible |
  |---|---|---|
  | 34px (what he asked for) | 151px | **23%** |
  | 24px | 113px | 43% |
  | 15px (the size he rejected) | 78px | **61%** |

  **61% IS the 62% he twice rejected as "fudging".** So the two asks are in direct conflict: **the
  numbers being BELOW is what makes the big numbers possible.** The current layout isn't a
  compromise en route to the gut feel — it's what the gut feel would have to collapse into.
  **Don't rebuild this.**
- **THE BLANK CENTRE: still open, but it must NOT be a distance.** Mocked ridden-km in the centre
  (`centre-and-noroute.png`, row B) and it fails on **Peter's own v258 ruling** — route-done 150.3
  beside ridden 152.9 are near-identical on 95% of rides, and *"two distance bars would be
  stupid"* applies just as hard side by side as stacked. It invites a comparison that means
  nothing. Blank is more honest than that. Any future tenant needs to be a NON-distance field.
- **NO-ROUTE: the chevrons and "to go" now hide.** Peter: *"these chevrons are only relevant when
  you're following a route. Otherwise they need to be hidden."* Sharper than it sounds — on his
  16 July ride a route WAS loaded and he rode a training loop 1.8 km away, so `snapTo` faithfully
  reported a fiction and the bar sat frozen all ride.
  · **THE RULE: one number, one meaning — route distance while following, RIDDEN distance when
    not. Never both** (same v258 ruling as above).
  · `_distFollowing(r)` = route exists && `totalDist>0` && `_offRouteMode!=='abandoned'`.
    **Trigger is Peter's call: only signals that already exist.** No second prompt invented —
    no-route mode's designed record-start place-check will feed this same gate when it lands.
    **Deliberately NOT gated on `_snapOffKm`**: it's live, so it would flicker on a detour where
    you ARE still following. `'detour'` and `'ack'` both still count as following, per v245.
  · Band collapses 58 → 38, chevrons + to-go hide, the left figure becomes `UI.gpsTravelledKm`.
    **The pills' `top` is a CSS var (`--fpill-top`, 64/44) precisely so one line can move them** —
    an inline literal couldn't. The 6px clearance is identical in both states.
  · Verified **14/14** incl. the 16 July case (reads 23.4 km ridden, not the frozen 1.8 km snap).
- **Verified: whole-file `node --check` (19,657 lines, ends `</html>`, both blocks clean)**, plus
  the `--fpill-top` wiring checked in all three places it must agree, and the `background-color`
  shorthand check.

### v261e — the blank centre is filled: RIDDEN distance. And I had to retract twice.

**Peter, on the mockup: *"You've shown a 3rd distance… is that the actual distance, as against
the route distance? If so, that is a good place to put it."* He's right and my v261d objection was
wrong.** I invoked his own v258 ruling ("two distance bars would be stupid") against him and
**misread it**: that killed a second BAR, and the 4-second rotation where you'd never see both at
once. The same note ends *"if the route-vs-ridden distinction needs saying, it belongs on the pill
showing RIDDEN distance ('actual'), **where both numbers are visible at once and the difference
means something**"* — which is precisely this. **Standing lesson: before wielding a note against
Peter, read the whole note.** (Second occurrence — v260 recorded the same shape with the crosshair
buttons.)
- **My "near-identical, so meaningless" argument was also backwards.** When 150.3 and 152.9 agree
  that IS information (you're on route, nothing odd); when they diverge — his 12 July scout, where
  he rode part of the route and turned back — it's telling you something no other figure can.
  Cheap, usually boring, occasionally the only number that matters.
- **IT MUST BE LABELLED, and the evidence is that PETER had to ask what it was.** He designed the
  bar and still couldn't tell. So it ships as a stacked `20px figure` over an `11px "km ridden"`.
- **STACKED, while the two ends are inline — deliberate, and measured.** The stack is **60px**
  wide; an inline "152.9 ridden" is **98px**. Swept across the whole ride at 137/300/600/1024 km,
  the worst-case centre gap is **109px**, so the stack has margin everywhere and the inline gets
  tight. It also matches the pills' own unit-below language.
- **Centred by `translateX(-50%)`, NOT as a third flex item.** The two end figures are different
  widths (100.1 vs 200.5 at the worst point), so `space-between` would push the centre off-centre
  and it would drift all ride.
- **Hidden when there's no route** — it's a comparison, and there's nothing to compare against;
  the left figure has already become the odometer, so it would just be the same number twice.
  **Same value, two homes: centre when there's a route, left when there isn't.**
- **⚠ THE DECIMAL RULE: I claimed it, retracted it, and PETER supplied the case that reinstates
  it. `fmtDistKm` — ≥1000 km loses the decimal.** The sequence is worth keeping because the error
  is instructive. I first claimed the figures collide on a 1000 km ultra; the table was wrong
  (it assumed both ends could read 1024.7 at once — they can't, done + to go = total). I then
  retracted the rule entirely, having swept only up to ~1000 km and concluded "three figures fit
  everywhere". **They don't. Peter: *"I've done a 4,000 km ride… Tour Divide is 4,500 km long.
  Anything over 2,000 km, you can have four digits either side."*** Both ends CAN be four digits —
  on a **≥2000 km** route, which he has ridden and I had written off as unreal. Measured: 4000 km
  worst case leaves **68px for a 72px centre stack — a 3.7px collision.** Dropping the decimal
  at ≥1000 km restores 129px. **Lesson: I bounded the problem by my own imagination of the routes
  rather than by his.**
  · Same reasoning as v260's `fmtStopPct`: precision where it carries information, dropped where
    it's noise. 100 m on a 4,500 km ride is noise. Grenfell keeps its decimal.
  · **It gets NARROWER at 1000** ("999.9" → "1000"), so no figure can grow mid-ride and shove a
    neighbour — the property Peter required of `fmtStopPct`.
  · **THE TRUTH-TABLE CAUGHT THE SAME BUG v260 HAD, THIRD OCCURRENCE:** `v>=1000 ? … :
    v.toFixed(1)` emits **"1000.0" (6 glyphs)** at v=999.96 — under 1000 raw, but toFixed rounds
    it up. **When a format switches on a threshold, test the threshold against the FORMATTED
    output, not the raw value:** `+v.toFixed(1) >= 1000`. Verified every 10 m from 0 to 4600 km:
    nothing ever exceeds 6 glyphs and nothing ever widens across the boundary. 8/8.
- **Verified: whole-file `node --check` (19,693 lines, ends `</html>`, both blocks clean)** + the
  third figure checked in all five places it must agree (template, CSS, no-route hide, sync paint,
  odometer source), the transform-centring, and the no-grey caption rule.

- **OPEN — Peter: "when there is no route to follow that black strip has space for some other
  things. What could we put in there?"** Answered, not built. The strip's job on a route ride is
  ORIENTATION — how far through am I. Without a route the equivalent question is "how far can I go
  before I have to be back?", so the recommendation is **time to sunset** (or the sunset clock
  time): PackTimes already computes sun times (`sunCache`), nothing else on the ride screen says
  it, and it passes Peter's own *"what would you do about it?"* test hardest of any candidate —
  you turn around. Second candidate: **the clock**, which the ride screen simply doesn't have.
  **Rejected: total ascent** (interesting, not actionable) and **anything distance-shaped** (the
  v258 rule). **Don't let this become a dumping ground** — the five pill slots already carry the
  sensor and ride data; the strip should only hold what the ROUTE would otherwise have told you.
  · **RETURN ETA / "double back time" — Peter raised it, then killed it himself. Don't build it.**
    The idea: if you turned round now and rode back at the same pace, when would you get home?
    My objection was weak (it's ~`now + elapsed`, and the stoppage pill already shows elapsed).
    **His is decisive: elevation breaks the assumption.** *"If you've just been climbing a big
    hill for an hour, it's not going to take you an hour to get back. If you've gone down into a
    valley for an hour, it might take you many hours to get back."* And the failure is
    **asymmetric in the dangerous direction** — the valley case UNDER-estimates the return and
    tells you you're fine when you're hours from home in the dark. Same asymmetry as v245's faff
    uplift (15% not 10%, because erring slow is the safe way to be wrong). A metric that is
    confidently wrong in the direction that hurts you is worse than no metric.
  · So the strip states a FACT (sunset is at 17:42) and lets the rider do the arithmetic. Peter:
    *"You can do your own math if you need to, and this is not a planned ride, so you're probably
    not that fatigued."*
- **VERIFIED THAT THE THREE FIGURES FIT PETER'S REAL ROUTES**, sweeping every 0.05% of the ride
  with the shipped `fmtDistKm`: worst-case centre gap vs the 60px stack is **+49px on Grenfell,
  +70px on a 4000 km ride, +70px on Tour Divide (4500)**. Tour Divide at halfway reads
  `2250 km | 2295 km ridden | 2250 km`. **Counterintuitive and worth keeping: the ULTRA is the
  roomiest case, not the tightest** — the ≥1000 km decimal rule makes those figures narrower than
  a 300 km route's, so the rule that exists for the long rides is what makes them the easy ones.
- **Verified: fragment `node --check` clean + 19/19 truth-table** (gap is exactly 25% of the mark;
  perpendicular gap clears the floor; 25 chevrons provably would NOT, so 24 is the real ceiling;
  whole-chevron ticks at 0/12.0/12.6/150.3/299.1/300.6 km; clamped past the finish and below zero;
  per-tick distances match the numbers quoted to Peter; resize changes the pitch and the rebuild
  guard is stable; clip-path percentages well-formed).
- **NO whole-file check — the bash mount was truncated AGAIN** (19,439 lines, ends mid-statement in
  the SW's font block, no `</html>`), so a whole-file parse would have been a FALSE PASS. It *had*
  picked up the edits (v261 at line 932), so the regions were extracted from it and checked as
  fragments, and every edited region was read back via the Read tool. **Open `index.html` in a
  browser once before `push.bat`.**
- Mockups (true size, 2.748×, on Peter's real screenshot): `_planning/distance-bar-chevron/` —
  `var-A/B/C/D.png` (layout), `marks.png` + `marks-thin.png` + `marks-tight.png` (the Wahoo
  question), `quantised.png` (the chosen build). Generated with Pillow + the repo's real DM
  Sans/DM Mono; the sandbox still can't render HTML.

### Rejected on the way (don't rebuild these)

- **Reserved ends** (`var-A.png`) — Peter's own earlier idea, revisited and rejected again, and the
  chevrons are what killed it: with a visible ruler it becomes *obvious* the scale doesn't span the
  bar. His v258 word for it was "fudging", and the marks make the fudge legible.
- **RAKE / MTN / PENNANT / DART** (`marks.png`, `marks-thin.png`) — non-chevron marks tried to dodge
  Wahoo. RAKE (leaning stripes) was my recommendation until the tight-packing render; it gives up
  the point, and a lean *implies* direction where a point *states* it. PENNANT's point doesn't
  survive at true size (reads as a parallelogram). MTN is noise. DART still reads as a chevron.
- **THIN-10 / THIN-20** (thin marks, wide gaps) — a scale with no mass; you can't read proportion at
  a glance, which is the bar's whole job.
- **TICK** (plain vertical marks, same pitch) — built as the CONTROL and it earned its place: same
  ruler, no chevron, and it reads **inert**. That is the direct evidence that the chevron is
  carrying information rather than decorating, and it's today's bar with lines on it.

## Current status (17 July 2026, v260 — PUSHED and phone-tested by Peter)

A UI session, driven almost entirely by Peter putting builds on his phone. **Three of the four
real bugs found this session were invisible from the desktop**, and one of them would have been
*hidden rather than fixed* if I'd done as asked without looking. Recorded because the pattern is
the lesson: this file's remaining bugs live where the geometry meets a real device.

### THE FLOATING PILL FAMILY — the empty states are now first-class

- **EMPTY PILLS ARE FULL SIZE (Peter's rule).** *"The power, heart rate, and now this cadence pill
  should be their full size at all times, not only after they have paired. It makes it easier to
  press when moving, and you are not going to leave an unpaired pill there if you don't want it.
  You either pair it or cycle through to the small plus."* He'd **already made this call once**
  (v259, the stoppage pill's short empty state) — an empty pill is still a pill. Two things fall
  out beyond the tap target: **pairing no longer moves the furniture** (the old prompt was ~50px
  vs ~105px paired, so connecting a sensor shoved the column below it down mid-ride), and the
  empty pill becomes a preview of the paired one.
- **THE IDENTIFIER RULE: use the symbol the sport already owns; NEVER invent one to fill the slot.**
  The hero slot holds ⚡ / ❤️ / the word "Cadence", unit below, `hold to pair` in the reversed half
  at a readable 13px. I argued for words everywhere ("a set where two get symbols and one gets a
  word isn't a set"); **Peter overruled it having seen all three**: *"the words for power and heart
  rate are clear, but the symbols were also clear and looked better… for Cadence, I think 'rpm' is
  probably about as clear as it can get."* He's right on the fact I had wrong — ⚡ and ❤️ aren't
  icons anyone decodes, they're what every bike computer uses. 🔄 never was in that class, which is
  exactly why he read it as a **sync button** (*"what is that symbol for? I think it is separate to
  heart rate or power meter"*) — it also ships with its own blue rounded-square background. **The
  problem was always that CADENCE HAS NO GLYPH, not that glyphs were wrong.**
  · My v260d mistake, for the record: I filled the hero slot with a DASH and let the 11px unit do
    the naming, defending the dash as a "preview". A dash teaches you nothing — it was a preview of
    nothing, and it's why the only readable text had to be small.
- **THE FIGURE'S LINE BOX IS 34px; THE FONT SIZE VARIES INSIDE IT.** Peter: *"why does the cadence
  pill shrink? I know the font sizes in the bottom half are a little smaller, but why not just make
  the pill a little larger so it aligns with everything else?"* Exactly — v260c's 28px was a
  **width** fix (five glyphs of "49/51" burst the pill) and I let it cost 6px of **height** without
  asking why the two should be linked. They aren't. Pinning the box fixed the family alignment AND
  killed the "shrinks when it pairs" wart in one change. Every pill — speed, stoppage, power,
  cadence, HR — is now the same height, paired or empty.
- **THE HAIRLINE BETWEEN THE HALVES (power + HR only).** Found the instant all five pills were on
  screen together with real numbers: 136 and 145 bpm in the SAME zone flood both halves the same
  yellow, and the pill reads as **one solid slab**. The power pill escaped it in that screenshot
  only because 203 W and 251 W happened to differ. **On a steady ride current and average agree
  most of the time, so this is the normal case, not an edge one.** Cause is structural: the
  REVERSED half is what separates the two numbers, and zone colour overwrites it. Fix is 1px of the
  pill's own dark showing through — the family's existing language (the outer ring works the same
  way), and the detail Peter himself spotted on the speed pill. Padding drops 3px→2px to pay for
  the border so the height still matches.
- **THE STOPPAGE PILL SHOWS `0h00` / `0.0%` WHEN NOT RECORDING — no dashes, no instruction.** I
  offered it the sensor pills' "name yourself + tell me what to do" treatment; Peter dissolved the
  question instead: *"What is the pill showing really? It is time or duration, and then a percentage
  of that as stoppage… Why not just show 0h0m? There is no pairing going on here, and also show 0%
  for the stoppage."* **THE DISTINCTION, and it's the keeper: for a SENSOR zero would be a lie (no
  heart rate is not 0 bpm) — for a CLOCK zero is simply true.** A sensor pill is missing hardware
  and has something to tell you; this pill is missing nothing, so "record to measure" was an
  instruction with no mechanism behind it, which is why he read it as vague (*"it could mean
  anything"*). `fmtDurPill` now formats 0 rather than dashing it; the bottom label is a constant
  `stoppage`. **NO STOPWATCH ICON — the stopwatch is PackTimes' own logo mark** (v257: PackView has
  the eye, PackRide the dots); a brand mark used as a UI hint says "PackTimes" where it needs to say
  "press this". The app already owns the right symbol (the red record dot) — and honest zeros need
  no symbol at all.
  · **Known 60-second wobble, deliberately not "fixed":** idle reads `0.0%`, then goes to `—` for
    the first minute of recording (Peter's own v259 rule: 100% at the lights is true and useless),
    then to a real number. Flagged to him rather than silently overturning his rule.
- Copy: `stopped` → `stoppage`; `W · 3 s` → `W · 3 sec` (**two copies** — paired and empty);
  `L/R` → `Left / Right %`.

### COLOUR ON THE PILLS IS SPOKEN FOR — SETTLED, DON'T RE-OPEN

Peter asked for a subtle colour on the stoppage and cadence pills; the argument below persuaded him
(*"ok that's a good point, let's leave them as they are"*). Recorded in the code beside `pillBg` too.
- Colour already means exactly two things here, both load-bearing: **which ZONE** (power/HR — only
  because the colour IS the data, his own v260 ruling) and **which PRODUCT** (green PackTimes /
  yellow PackRide, one token — the distance-bar rule: colour = product, SIZE and REVERSAL = which
  number matters).
- So the monochrome pills aren't an oversight: power and HR wear colour because they HAVE zones. A
  decorative colour elsewhere would read as a zone that isn't there, with a real zone pill beside it.
- **Cadence cannot have an honest colour**: it needs a good/bad to encode and there is no agreed good
  cadence. Inventing bands = the app passing judgement with nothing behind it. Same trap as a made-up
  stoppage threshold (30% is fine on a tour, terrible on a non-stop ultra).
- **THE ONE ROUTE THAT WOULD BE HONEST, if it ever comes back:** colour stoppage against **the PLAN'S
  OWN stoppage %**. The plan has every stop and duration, so the benchmark is computable and it's the
  rider's own, not invented. That's a feature, not a styling pass, and it says nothing on a no-route ride.

### THE STOPS TAB — three buttons and a drag handle

- **Crosshair + GPS toggle DELETED from the Stops map.** Peter: *"we should only need FIT ROUTE, MAP
  TYPE, SURFACE TYPE."*
  · **HISTORY CORRECTION — I got this wrong and he was right.** I told him v245 added them "at your
    request". It didn't: he asked for the **position dot** after his ride test; *I* bolted the two
    buttons on alongside. And v245's note "**both stay** on the Stops/desktop maps" was written in the
    same version that had just put them there — "stay" implied a history they never had. He said
    *"the note suggests both STAY on the stops screen but they weren't there?"* and his memory beat my
    note. **Don't wield a note against Peter's recollection without re-reading what it actually says.**
  · Consequence he accepted with eyes open: **there is now no plain GPS toggle anywhere in the app** —
    the Ride tab's button starts GPS *and* a recording (v245). GPS belongs to the ride. If "show me
    where I am without recording" is ever wanted again, **Settings**, not a planning map. (The
    delegator still has an unreachable `UI.tab!=='live'` branch for `#btn-gpstoggle`; inert, left.)
- **THE CROSSHAIR BUG — Peter found it on the phone, and it's the valuable half.** Recording a
  training loop hundreds of km from the loaded route: *"the crosshair button just zooms to the route
  start… so that button doesn't even work in this scenario."* It **never looked at the GPS**: it read
  `UI.gpsDistKm` (your distance ALONG THE ROUTE) and centred on `r.points[cidx(r,gpsDistKm)]` — the
  ROUTE's point at that distance. Far from the route that's null, so it fell into a branch commented
  *"No GPS"* and flew to the start; his GPS was working perfectly, the condition really meant "not near
  THIS route". Even when it did fire it centred on the ROUTE, not on him (1.8 km off route → lands on
  the route). Now uses `UI.gpsPos` (the actual fix, `{lat,lon,acc,speed,ts}`, owing nothing to any
  route). **THE DESKTOP MAP'S CROSSHAIR SHARED THE HANDLER AND THE BUG** — deleting the Stops buttons
  would have hidden it, not fixed it. Also a preview of no-route mode: *a control that only works when
  a route happens to be under you is the wrong shape for "I'm just going for a ride."*
- **The expand/collapse button is gone, replaced by a DRAG HANDLE** (`.stops-drag` / `_stopsDragInit`,
  mobile only — desktop pins the map at 250px and never had the button). Peter: *"a better approach
  would be to do what we do on the ride tab — have the stops list drag down so a single small strip is
  visible at the bottom, and you drag that strip up… a more direct control, which is intuitive, and
  gets rid of another button."* Verdict after riding the phone build: *"efficient and intuitive, and
  only 3 buttons."*
  · The button had a deeper problem than being a button: **its expanded state hid the list outright**
    (`display:none`), so the only way back was the button itself. Leave a strip and the control and the
    thing it controls are the same object.
  · **THE RIDE TAB'S "DRAG THE LIST UP" IS NOT A GESTURE — IT'S NATIVE SCROLLING** (`.live-outer` is
    the scroller, so the map scrolls up out of view). **Nothing to reuse**, and the cheap move of making
    Stops scroll the same way does NOT work: scrolling *translates* the map, it doesn't *resize* it —
    you'd be looking at the bottom half of a full-height map with fit-route fitting the route into a box
    half off screen. (Dead stubs `scrollMapUp` / `resetMapScroll` / `handleStopsScroll` are the remains
    of a scroll-driven resize that was built and taken out. It's been tried.)
  · Two snap positions via `_stopsApplySnap`; **nearest-end snapping, not direction** (predictable, and
    can't strand you mid-way); 5px dead zone so a tap doesn't nudge the map; one redraw per frame via
    rAF (attachMap's pan already redraws at gesture rate, so it's proven). `UI.stopsMapExpanded` keeps
    its old name and meaning so nothing else changed.
- **THE PHANTOM 48px HEADER — a real bug, and the best find of the session.** Peter, with the list
  dragged fully down: *"it still leaves all of those lines showing, which is bad."* He was getting
  ~140px of list where the code asked for 92. Cause:
  `const headerH = document.querySelector('.header')?.offsetHeight || 48;` — and **`.header{display:none}`**
  on mobile, so `offsetHeight` is **0** and `0||48` is **48**. It subtracted a header that is not on the
  screen; 92 + 48 = 140, exactly his screenshot. **The honest number was already in the same function's
  OTHER branch** — the full-screen case measures `panel.getBoundingClientRect().top`, which absorbs the
  status bar, any header and the tabs without knowing what they are. Now `_stopsAvailPx()` is the one
  authority and both branches use it. Map went 665 → **763px (92% of the tab)**; the resting half also
  gained 24px, having been quietly short by the same phantom all along.
  · **STANDING SHAPE, now at least four occurrences: MEASURE WITH RECT MATHS. A fallback constant
    standing in for a real measurement is a bug with a long fuse.** (cf. v258's `clientWidth` rounding,
    v255's pill positioning, v258's bar-box snapping.) `||48` looked like a safe default and was a guess
    that was always wrong on the only device that matters.
- **The strip is ONE LINE (42px) + a peek title**, not 92px. My 92 answered the wrong question: I sized
  the strip to be **grabbable**, but the grab target is the handle, which is always there. The strip only
  needs to be big enough to **say what's under it**. `#stops-peek-title` reads `Stops (n)` and sits where
  Peter put it — *"a single line of text perhaps ABOVE the current first 'Tap on the map…'. That new title
  just scrolls away when you scroll the list up anyway."* That last clause is why it's ordinary list
  content and not a sticky header: it has a job in exactly one state and gets out of the way by itself.

### Answered, not built

- **Electronic drivetrains (Di2 / AXS): parked, and I'd advise against it.** Recording gear is the easy
  half — FIT already has it (`front_gear_change` / `rear_gear_change`, four 8-bit values packed into the
  event message's 32-bit data field). **Getting** the data is where it dies: shifting has no public BLE
  service (unlike HR 0x180D / power 0x1818); Shimano broadcasts over **private ANT** (D-Fly) and phones
  have **no ANT radio** — that's why Garmin/Wahoo can and a PWA can't; SRAM's own AXS Web doesn't read
  the bike, it pulls the FIT out of Garmin Connect. Three brittle reverse-engineered integrations, per
  brand, breakable by any firmware update. **And it fails Peter's own test — "what would you do about
  it?"** You can see your chain and feel your gear; gear stats are post-ride analysis, which Strava
  already has. The one genuinely actionable bit for an ultra is **Di2 battery on day 3**, behind the
  same locked door.

### Verification notes for this session

- One **honest** whole-file `node --check` got through mid-session (both script blocks clean, 18,473
  lines, file ended `</html>`). The mount then went stale/truncated and stayed there, so the crosshair
  fix and the strip fix are verified by **reading the regions back**, not by parsing. Truth-tables:
  32/32 on the drag gesture, 15/15 on the geometry (**the 140px bug was reproduced in the model first,
  so the fix was proven against a known-bad baseline**).
- **The mount lies by going SHORT, and a whole-file parse of a truncated file is a FALSE PASS** (it
  finds 0 script blocks and "passes"). Always assert `</html>` before trusting a check. Open
  `index.html` in a browser once before `push.bat`.

## Current status (15 July 2026, v257) — SLICE 1 BUILT: the sharing button + sheets (solo)

First build slice of the ride-screen consolidation (design below). **NOT ride-tested, NOT
sim-tested — desktop fragment checks + a 14-case node truth-table only.** What's in:

- **The SHARING BUTTON** (`_shareBtnSync`, LOCATION SHARING section, after the retry
  triggers): 54px, bottom-left above the weather pill (same getBoundingClientRect maths as
  the pack pill), built from updateLive + initLiveMap (NOT the template — the pack-pill
  lesson). Four states via `_shareBtnState()`: notset/armed/live(pulses via `shbPulse`
  keyframes, added next to recpulse)/off(slash). Hidden when `eventActive()` — in a
  PackRide the slot belongs to the pack pill until slice 2 merges them. One-time armed
  bubble "Shares when you start riding" (`UI.shareBubbleSeen`, persisted in shareAuth).
  **The old share pill is GONE** (template block + handler + `_packPillSync`'s shp0 lines).
- **Setup sheet + sharing sheet** (`_shareSheetShow/_shareSheetRender`, fixed overlay
  z-9999, ids `share-sheet-*`, handlers in the delegator where the share-pill handler
  was). Setup = name → shareSetup right there. Main sheet = universal rule line, per-ride
  switch, Copy permanent / Copy PackView / Copy PackRide invite (invite row only when in
  an event; creation itself is slice 3). Copy rows reuse an existing live link before
  minting a new one.
- **Per-ride off** (`UI.shareOffThisRide`, in shareAuth as `offThisRide`): now part of
  `shareIsOn()`, so it gates every transmit path structurally. Set/cleared by the sheet
  switch; **auto-reverts at finaliseRecording AND _recStopDelete** (ride over = safety
  default back). Sheet switch ON also clears the Settings master (`shareEnabled=true`) —
  the rider flicking it on means it. Settings master stays sticky, copy updated to say so.
- **Pre-ride PackView links** (the flagged build question — resolved with no schema
  change): `UI.shareNextRideId` (in shareAuth) is minted on first pre-ride copy;
  `startRecording` uses it as the ride id and clears it. Ride ids were always
  client-generated and `ride_start` upserts, so the pinned link simply shows nothing
  until the ride starts. 48 h expiry from link creation (same as the Settings path).
- **'Family' → 'Permanent'**: `shareSetup`'s auto-created first link renamed.
- Verified: fragments `node --check` clean; truth-table (notset/armed/live/paused/
  off-this-ride/master-off × recording states, pre-mint lifecycle, revert-on-finalise,
  revert-on-delete, master untouched by ride end) — all pass. **APP_VERSION v256 → v257.**
- **Fix from Peter's first desktop test (same session): the sheet was DEAF.** The main
  click delegator is bound to `#content-wrap`, but the sheet overlay hangs off
  `document.body` — so no click inside it (scrim, toggle, copy rows) ever reached the
  handlers. Moved all sheet handling to `_shareSheetOnClick`, bound directly on the
  overlay (the showSurfHelp pattern), and added an explicit **Done** button. **STANDING
  GOTCHA: anything appended to document.body cannot use the content-wrap delegator —
  bind directly, like every other body-level modal in the file.** Also from that test:
  a STALE PackRide event squats on the ride screen forever (events never end) — leave/
  delete in Settings → Group Rides is the only exit; auto-expiry + a visible "Leave this
  ride" are now explicitly slice 2 scope, and "Start a group ride" as a sheet row (second
  doorway to slice 3's Route-tab creation) is noted for slice 3. In-event there is NO
  ride-screen path to the per-ride switch until slice 2's pack overlay lands (Settings
  master is the workaround). Second test fix: **_recToast was z-1001, under the sheet's
  z-9999** — "link copied" fired invisibly behind the scrim. Toast is now z-10001;
  toasts are feedback and must outrank every overlay. Third fix (unrelated to sharing,
  found in the same test): **the GPS arrow on north-up maps (desktop big map / stops
  map) anticipated turns by ~½ km** — the arrow block in drawMap had its OWN copy of
  the v243 look-ahead bug (snap vertex → vertex+15), which survived when v252 fixed the
  map rotation. It now uses `_rideHeadingDeg(pts)` — the same ±30 m chord authority the
  live map rotates by (extra calls safe: easing is time-based). On the rotated live map
  nothing changes (arrow cancels frame rotation there). Fourth fix from the same test:
  **the speed pill changed width with the digits** — both numbers were on var(--sans)
  (DM Sans digits are proportional; the v244 rule is numbers = DM Mono, no exceptions).
  Now DM Mono weight 500 (Mono ships 400/500 only), pill min-width 100px sized for
  "88.8", and the AVERAGE half is REVERSED (light bg #eef3ee, dark figures) — Peter's
  idea: on a long ride average matters more than the wobbling current speed. He
  SAW it and likes it (avg now same 34px size as current — his call). Fifth fix:
  **the rotated live map anticipated hairpins** — `_rideHeadingDeg`'s ±30 m symmetric
  chord had its forward arm around the apex while the rider was still approaching
  (node-measured 24° of rotation before even entering a 15 m hairpin; mid-corner it
  read as riding backwards). Arms are now ASYMMETRIC (25 m behind / 10 m ahead —
  node-verified: 3.5° pre-corner, continuous 3.8°/m sweep through it, exact after).
  Principle: heading = where you ARE going ≈ where you've just been; the map turns AS
  you turn, never before. Also gated the arrow's _rideHeadingDeg call to north-up maps
  only (rotated map's arrow just cancels the frame). Sixth fix: **tapping anything
  while the sim was PAUSED knocked ~0.5 km/h off the displayed average per tap** — the
  ride-average session time used `UI.simRunning?_simElapsedMs:wall-clock`, so a paused
  sim fell back to real elapsed time (a bigger, growing denominator). All three sites
  now use `(UI.simRunning||UI.simPaused)?_simElapsedMs:…`. **Seventh (the big one — the
  map-rides-backwards flip + the premature rotation, SOLVED with Peter's real FIT).**
  Three synthetic reproductions failed; Peter dropped the real 200 km Kyrgyzstan FIT in
  and the harness (Garmin SDK via `_planning/fit-spike/`, exact snapTo+_rideHeadingDeg,
  sim-tween emulation) reproduced BOTH complaints exactly: 206 reversed frames, first at
  12.7 km — the very spot in his screenshot. TWO root causes, both in snapTo:
  (1) **checkAlerts' off-route check calls snapTo WITHOUT lastIdx every tick**, which
  re-ran the "first fix" direction guess each time — ±20-point bearing arms = ±1.6 km on
  this 80 m-spaced route, straddling the whole switchback cluster = coin flip, written
  straight to `_snapDir` with no latch. Now gated on `_snapDir===0` (startGPS resets it,
  so the genuine first fix still works). (2) **The old |delta|>2 vote rule made forward
  riding voiceless** (normal progress advances 1–2 points/fix), so a wrong -3 lock never
  recovered — and its backward-biased window self-reinforces. Votes now come from
  gpsHeading vs the route's LOCAL bearing (±1 vertex) with the same ±3 latch; node-tested
  on the real route: forced wrong direction recovers in ~550 m (old: never). Plus
  (3) **`_snapRefine`**: snapTo returned the nearest VERTEX's dist, so gpsDistKm jumped
  up to half a segment ahead crossing each midpoint (real route: up to 49 m ahead, 19 m
  mean error) — THAT was the "rotating prematurely" Peter kept seeing (it was never the
  chord length); it also made the turn countdown and orange highlight run early. Now
  projects onto the two segments adjacent to the winning vertex → interpolated dist +
  true perpendicular off. Verified on the real route, 60 km incl. both trouble spots:
  reversed frames 213 → 0, position error 49 m max → ~0. Harness scripts left in
  `_planning/fit-spike/_tmp_realroute.mjs/_tmp_recovery.mjs/_tmp_full.mjs/_tmp_lead.mjs`
  (bash can't delete on this mount — Peter can bin them). Peter's FIT is in the session
  uploads, not the repo. **Follow-up measurement (same session): chord forward arm HF is
  OPTIMAL at 10 m** — shortening it makes lead WORSE (mean 3.0° at 10 m → 4.4° at 0 m;
  shorter chord = noisier target = more time mid-transition). Residual "looking ahead"
  Peter sees at 5× sim is a playback-speed artefact: 5× ≈ 90 km/h through switchbacks,
  map perpetually mid-swing, leftover rotation from one bend reads as anticipation of the
  alternating next. At 1× the same route measures ~2° mean error. Verdict: judge rotation
  at 1× / on a real ride before touching the v252 easing constants. Also: speed-pill
  numbers now right-justified in a fixed 4ch box (decimal point never moves).

**PackView batch (same session, Peter's requests from watching a shared sim link):**
(1) **The EYE is live** — PackView's logo and browser-tab favicon are now the eye
(`_MARK_EYE` / `_packFaviconEye`), not the recoloured stopwatch; `_packLogo` refactored
to `_packLogoMark(colour, word, mark)` and PackRide's logo now wears its three-dot pack
mark (`_MARK_PACK`) per the settled marks design — slice 4 is effectively done for
PackView/PackRide (PackTimes keeps the stopwatch). (2) **Layer toggles moved to their
own row** (`#view-layers`, below `#view-tiles`): km markers + the new "Trail line".
(3) **Trail = DOTS at each real fix by default** (screen-space thinned at ~9 px for
drawing only — tap hit-test sees every point; newest fix always drawn); the yellow
connecting LINE is now a toggleable layer (`_viewLines`, `packview_lines` in
localStorage, off by default — Peter: less clutter with many riders, and the line
visibly jumped ahead of the interpolated dot). (4) Small permanent caption bottom-left
(`#view-lagnote`): "The moving dot runs a little behind the newest fix · tap a trail
dot for its time" — the moving dot is deliberately not tappable (it's the render-buffer
playhead, ~35 s behind; the dots are the truth).

**SLICE 2 BUILT (same session): the pack button + the two-stage pack peek.** NOT
sim-tested. What's in (all in the PACKRIDE section, replacing `_packPillSync`):

- **The PACK BUTTON** (`_packBtnSync`): 54px, same slot/rect-maths as the sharing
  button, PackRide yellow, pack mark + placing ("2/5"), **pulses (`pkbPulse`) while
  `shareIsLive()`** — the button IS the sharing indicator in an event. Replaces the
  pack pill AND the placing pill. The old `zoomToPack` is gone (refactored into
  `_packFit(pts, bandFrac)`).
- **Stale events stop owning the slot** (`_eventStale`/`_eventLive`): started >48 h ago
  AND nobody heard from in 24 h → pack button hides, sharing button returns; membership
  stays in Settings. `UI.events` lazily fetched once per boot (`UI._eventsFetched`) so
  staleness is judgeable cold. Both buttons gate on `_eventLive()` now.
- **Tap → ¾ rider list + top ¼ map strip** (`_packListShow`, overlay z-9998 with its
  own click listener — the content-wrap delegator can't hear body-level overlays):
  rows sorted by along-route distance (newest trail point's dist_km), you highlighted
  with placing ("2nd of 5"), others show ±gap (m under 950 m, km above, ±10 m
  rounding), stale riders dimmed with "last seen". Map fits you + nearest ahead +
  nearest behind into the top band (`_packPeekAnchor` — redrawMap's live anchor reads
  it while the peek is on); outliers become edge chips (behind left, ahead right).
  Floating pills/dist bar/map-ctrl/weather/turn cue hide via `.pack-peeking` CSS.
- **Strip tap → full-screen pack map** (`_packFullShow`): whole pack, whole canvas
  (the v253 fit), transparent tap-catcher, tap anywhere = out.
- **BOTH views on one ~8 s countdown** (`_packCdReset/_packCdTick`, yellow bar): any
  list touch resets it; the sharing sheet on top pauses it; expiry or tap →
  `_packOvClose` → `_packPeekEnd` restores the EXACT previous zoom, following you.
- **Footer rows:** "Sharing & invites ›" → closes the peek, opens the sharing sheet
  (finally a ride-screen path to the per-ride switch in-event); "Leave this ride" →
  confirm → `eventLeave` (leave ≠ delete — the organiser-side delete stays in
  Settings).
- **Rider colours** (`PACK_COLS`/`_packColFor`, reset in `packReset`): stable per
  rider per event, used by the list rows AND `drawPack`'s dots + trails (was all-blue)
  — the list IS the legend. Name tags hidden only while the LIST view is open (the
  list is the legend there); they SHOW on the full pack map, where there's no legend
  and there's room (Peter's sim-test question, refined from "hidden during any peek").
- Verified: fragment `node --check` clean + 10-case truth-table (gap formatting,
  sort/placing, nearest-focus, colour stability, stale×3) all pass. Still v257 (one
  push = one version; v257 is unpushed).
- **Sim-test fixes (same session):** (a) desktop peek overlay now confined to the
  ride column via `_packOvRegion()` (was fixed inset:0 over the whole window incl.
  the big planning map); tab clicks close the peek (the tab bar stays reachable on
  desktop). (b) **Strip-view jitter** — updateLive's RAF peek draw used anchor:0.5
  while redrawMap's peek branch framed at `_packPeekAnchor` (~0.15); two framings
  alternating per tick = vertical hopping; now both read `_packPeekAnchor` (the v252
  one-authority lesson, third occurrence). Both peek draws are north-up by design —
  a pack overview has no "up". (c) name tags show on the FULL pack map (no legend
  there), hidden only in the list view. (d) strip view now centres on YOU (Peter's
  rule: the frame itself says ahead-is-up-there/behind-is-down-there), zoomed so the
  nearest ahead + behind both fit (`_packFit` grew an optional `centre` arg); the
  full view keeps the whole-pack bbox fit.

**Sim-test checklist for slice 2 (two browser windows, the v251 recipe):** pack button
appears with placing once riders are known · pulses only while recording+sharing ·
tap → list + strip (gaps sane, you mid-list) · strip tap → full map → tap → back at
your exact zoom · countdown auto-closes both views · "Sharing & invites" opens the
sheet in-event · "Leave this ride" exits and the SHARING button returns · yesterday's
stale event no longer claims the slot on boot.

**SLICE 3 BUILT (same session): PackRide creation where the route is.** NOT tested.
- **PackRide button on the SELECTED route's tile** (`.packride-route`, logo + words —
  "PackRide · start a group ride", or "· invite" when already in an event). Excluded
  from the tile's select-tap like the other tile buttons.
- **The creation sheet** (`_evSheetShow/_evSheetRender/_evSheetOnClick`, ids
  `ev-sheet-*`, body-level overlay with its own listener): three states — not-set-up
  (→ opens the sharing setup sheet), already-in-an-event (event name + Copy invite
  row + where to leave), and the form (ride name, update frequency slider 10 s–5 min
  default 30 s, "Create & copy the invite link"). Uses cur() route + its start time
  (asking twice for the same fact is how forms get long — same rule as the Settings
  creator, which stays). After create it re-renders into the invite state.
- **"Start a group ride" row in the sharing sheet** when NOT in an event (the invite
  row's slot — they're mutually exclusive); in an event the invite-copy row shows as
  before. Second doorway, same sheet.
- Verified: fragment `node --check` + smoke run clean. STILL OPEN (unchanged): a
  `?join=` link boots the full app, not the PackRide preset (architecture §3.6/§3.7).

ALL FOUR SLICES of the ride-screen consolidation are now BUILT (v257, unpushed):
1 sharing button + sheets · 2 pack button + peek · 3 creation doorways · 4 the marks.
None of it has met a phone or a two-window sim yet.

**POWER PILL restyled to match the speed pill (same session, Peter's request):** DM Mono
figures right-justified in a fixed 4ch box; top half = 3 s power ("W · 3 s" — that IS the
existing POWER_SMOOTH_MS window) with the zone colour tinting the TOP HALF + border only;
bottom half REVERSED light with **weighted power** (the existing 30 s-rolling NP maths)
plus a cadence · L/R balance line in dark mono. Also fixed on the way: the BLE patch and
updateLive set textContent on `live-power-cad`/`live-power-bal` whose unit labels were
NESTED inside — first live update wiped "rpm"/"L/R"; units now sit outside the patched
spans. The BLE zone-patch no longer repaints the np/label colours (they live on the light
half now). HR pill deliberately untouched — same treatment can follow once Peter approves
the power pill's look.

**TWIN RAILS deleted (same session, Peter's verdict): the v243 turn-indicator evaluation
is over — single bold orange line wins.** Removed: the rails branch in drawMap's
turn-highlight block, `_tcRailsPts` (the mitre maths), the Settings "Indicator style"
radio, the `turn-ind-opt` change listener, and `UI.turnIndicator` (STATE + uiPrefs
save/load — a stale `turnIndicator` key in old saved prefs is simply ignored, no
migration needed).

## Current status (16 July 2026, v259) — THE LEG CLOCK + STOPPAGE PILL. NOT ride-tested.

**v258 is pushed and being ride-tested. v259 is unpushed.**

**The design conversation is the valuable part — read this before touching any time/average code.**
- Peter: *"stoppage is a big issue in bikepacking… % stoppage is a real number that you monitor and try
  to keep low. I think it is actually quite important."* And: *"on a non stop ultra you can have a great
  moving average, but your stops might be too long, so your overall speed is not great. That's why an
  overall average is a better truth. On a multi day with planned sleeps and defined wake ups, you
  actually aren't riding against the clock as such, because the clock effectively stops each day."*
- **THE APP HAS THREE DIFFERENT TIME CLOCKS, and the live average runs on one nobody chose:**
  · `_rideAvgMsAccum` — moving **+ up to 5 min of every stop** (`GPS_IDLE_STOP_MS`). Drives the speed
    pill's "avg". That 5 minutes is a battery constant that accidentally became a definition.
  · `_recMovingH` — moving **+ stops under 15 min** (`REC_CALIB_BREAK_MS`, the v179 faff rule). Drives
    CALIBRATION, i.e. the plan's pace.
  · `endTS-startTS` — true elapsed.
  **So the plan is calibrated on clock 2 and the live average is computed on clock 1: they are not
  comparable, and the live avg reads optimistically fast against its own plan.** Unfixed — see below.
- **THE TRAP, and the reason stoppage is measured from the RECORDING:** the obvious source is the avg
  clock, and it would LIE. It forgives 5 minutes per stop, so **twenty 4-minute stops = 80 minutes gone,
  reported as 0% stoppage** — exactly backwards for bikepacking, where the damage is death by a thousand
  stops. The recording detects a stop in **5 SECONDS** (`REC_STOP_DETECT_MS_DEFAULT`) and marks it. Sixty
  times finer. Truth-tabled: that exact scenario now reads 17%.
- **PETER'S RULE (`legHasFixedWake`) — do NOT merge this with legEnd's predicate.** They look alike and
  aren't: a sleep with a **fixed wake (`departTime`)** absorbs variance (arrive 2 h late, still leave at
  07:00) so the clock stops and each day stands alone → leg-scoped. A sleep with only a **duration
  (`sleepH`)** carries variance forward (arrive late, leave late, the plan slides) → you ARE racing the
  clock → one leg, and the long stop must hurt. `legEnd` keys off ANY sleep because "what time do I get
  in tonight" is fair at either kind.
- **THE SPLIT (same one that made "Riding this now?" work): the PLAN decides the meaning, the RECORDING
  supplies the measurement.** Peter wondered *"maybe the line in the sand is if you are recording or
  not.. Hmm, not sure"* — **it isn't. Recording is the CLOCK, not the RULE.** It's the only thing with an
  honest start, end and pause. Whether you pressed record cannot decide what an average means.
- **REJECTED (built, then reasoned away — don't rebuild it):** a pill showing time ridden + ETA. Peter:
  *"mixing duration with clock time, a poor mix."* Right, and **the tell was in my own code** — I'd
  formatted it "5h23" instead of "5:23" specifically so it wouldn't be mistaken for a clock. **If two
  numbers need a format hack to stay apart, they don't belong in one pill.** The speed pill works because
  both halves are km/h. Also rejected: elapsed as the top half — it fails Peter's *"what are you going to
  do about it?"* test (only answer: maybe sleep, which the plan already models).
- **REJECTED: three values in one pill** (moving/stopped/%) — stop% is derived from the other two, so it
  would spend a third of the pill on a number carrying no new information.

**What's built (v259):**
- `LEG_SLEEP_MS` (2 h), `_legStopT`, `_legReset`, `_legVals` in RECORDING (a measurement);
  `legHasFixedWake` + `fmtDurPill` in TIME CALC (a plan question). Hooks: `startRecording` starts the
  leg; the `_stop` marker records `_recStop.t` — **the stop's TRUE start, not the marker's own time,
  which is written `stopDetectMs` later and would discount 5 s from every stop**; the `_resume` marker
  either ends the leg (long stop + fixed-wake plan) or banks the stoppage — never both.
- `UI.legStartTS/legStartKm/legStoppedMs` persisted in uiPrefs beside `recId`, so a crash recovery
  doesn't restart the leg and report 0% on a ride that already lost an hour. `_legStopT` is deliberately
  not persisted (a reload mid-stop loses that one stop's start — same as `_recStop`).
- **The STOPPAGE pill** (`type==='stop'`, cycle is now `speed → stop → power → hr → off`): **elapsed**
  over **stop % in the REVERSED half**. Peter: *"I think we need an elapsed time with a stoppage % on
  it."* He's right and my first cut (stopped duration + %) was weaker: the % is a ratio OF the number
  above it, so stopped duration falls out and doesn't need a slot. Elapsed alone fails his "what would
  you do about it?" test — paired with the %, it's the denominator that makes the % mean anything.
  Top label says **"leg elapsed"** on a fixed-wake plan, because the clock restarts each morning and
  "elapsed" would be a lie on day 2. Dashes + "record to measure" when not recording; the % waits 60 s
  (3 s into a ride at the lights, "100%" is true and useless).
- **Geometry is the speed pill's, verified property-by-property** (34px figures, 4ch box, both paddings,
  both label sizes, min-width 100, #eef3ee) — Peter spotted the pill was short; the cause was my 30px/5ch,
  not the empty state.
- **`fmtDurPill` keeps the minutes at any length and lets the pill GROW** (`min-width:4ch`, not `width`).
  Peter: *"It's okay if it did get wider because it doesn't fluctuate like speed… duration is just very
  gradual."* The 4ch box exists to stop a WOBBLING figure shifting its decimal; a number that ticks once
  a minute doesn't need it. **NOTE: "10h00" is FIVE characters** — the pill grows at **10 h**, not 100 h
  as first assumed, i.e. on most ultras. It grows again at 100 h ("120h34"). Height is unaffected.
- **THE SIM SLIDER TELEPORTS — `_simClockAt` (Peter: "66.8 km. It's only taken 41 minutes. That's not
  really possible for a bicycle").** He diagnosed it himself: *"it is the scrubbing that is doing it."*
  A scrub moves you 60 km down the road and adds NO time, so every time-based figure disagrees with every
  distance-based one. `simStart` made it worse: it starts `_simIdx` from the slider position but zeroed
  `_simElapsedMs`, so play-from-a-scrub reported only the part it watched. **The plan is the authority on
  how long a distance takes, so scrubbing now asks it:** `_simClockAt(dist,r)` = `cumRidingAt × timeFactor`
  — the same expression `etaAt` uses (after rebuildPace `estDuration === crTot`, so its scale reduces to
  timeFactor). Wired into `simStart` and BOTH slider handlers (there are two — they must agree).
  Verified: Peter's exact frame goes from an implied **98 km/h → 20.0 km/h**, and a scrub to any distance
  now implies the plan's own speed. **Pause/resume was never at fault** (`if(!resuming)` guards the reset)
  — Peter confirmed that independently.
  · Note this also improves the speed pill, whose sim average was built on `_rideAvgMsAccum` + a zeroed
    sim clock. That accumulator still accrues REAL time on each `stopGPS` and can be restored from a
    previous session (`lastGps.rideAvgMs`), so in a sim it mixes real minutes with sim minutes. Not
    touched here — it's part of the v260 average job.
- **THE SIM CLOCK — 4th occurrence of the same lesson.** `_legVals` read `Date.now()`, so the sim showed
  real seconds against simulated kilometres ("12 minutes elapsed but I've done 50 km" — Peter). The sim
  has its OWN clock: `_simElapsedMs` accrues the ride-world time each step would really have taken, so
  it's independent of 1×/2×/5× playback, and the speed pill already guards this exact way. **ANY
  ride-time measurement must ask the sim for the time** (v257 rotation → peek anchor → paused-sim average
  → this).
- **Verified:** fragment `node --check` + **26/26 truth-table** — the 20×4-min trap reads 17% not 0%;
  fixed-wake sleep starts a new leg and is not stoppage; duration-only sleep does NOT split and reads
  90%; non-stop 4 h bivvy = stoppage, overall avg 45 where a moving avg would have flattered at 75;
  live stop counts as it happens; stopped can never exceed elapsed; formats never burst the 5ch box.

## Current status (16 July 2026, v260) — three of the ride-test findings BUILT. NOT ride-tested.

v259 is pushed. v260 clears the ride-test items that were already DECIDED; the ones still needing Peter
(no-route mode, the distance bar's arrow, the average's wording) are untouched and listed below.

- **DROPBOX'S CONSTANT RE-LOGIN WAS A BUG, NOT A DROPBOX PROBLEM — and it was a one-word answer to a
  much bigger question.** Peter asked whether Supabase (now that sharing has a backend) could replace
  Dropbox for plan sync, *"because Dropbox is a bit of a pain… you have to regularly log in."* The
  honest answer was to check the re-login first, and it was self-inflicted: `dbxAuthURL` correctly asks
  for `token_access_type:'offline'`, `dbxHandleRedirect` correctly **stored** `data.refresh_token`, and
  `saveAll`/`loadAll` faithfully persisted it across sessions — **and nothing ever spent it.** All three
  API call sites treated a 401 as `UI.dbxToken=null` + "reconnect". Dropbox access tokens last ~4 h, so
  he re-authorised roughly every session while holding the key that would have renewed it silently.
  **Strava, in the same file, does it correctly (`stravaFreshToken`) — Dropbox was simply never
  finished.** Standing lesson: when a third-party integration "is a pain", check whether we implemented
  the boring half of its auth before proposing to replace it.
- **Built (mirrors the Strava shape):** `dbxRefreshNow` (force refresh) → `dbxFreshToken` (proactive,
  5-min skew window) → `dbxFetch` (adds the Authorization header + **one** 401 retry). The three call
  sites — `dbxSave`, `dbxLoad`, `dbxCheckOnFocus` — just swapped `fetch` for `dbxFetch` and dropped their
  hand-built auth headers; their existing `401` branches now only fire **after** a refresh has already
  been tried, so nulling the token there is finally honest. New `UI.dbxExpiresAt` persisted beside the
  other dbx keys.
- **NO CLIENT SECRET, and there must never be one.** Dropbox uses PKCE, so refresh takes `client_id`
  only — unlike Strava, which is stuck embedding a secret. Truth-tabled to prove the body stays clean.
- **The traps, all caught by the truth-table rather than by luck:**
  · **Offline must not log you out.** A failed refresh keeps the tokens; only an explicit `invalid_grant`
    (a genuinely revoked grant) drops the refresh token. A dead network throws to the caller's existing
    `catch` and changes no state.
  · **Disconnect has to stay disconnected.** `dbxFreshToken` is gated on `if(!UI.dbxToken)return null` —
    without that gate a lingering refresh token would have *silently revived* a session the user ended.
    The gate also means every existing `if(!UI.dbxToken)return;` guard keeps working untouched.
  · **The disconnect handler was leaving the refresh token on disk** (it only cleared `dbxToken`/
    `dbxSavedAt`) — a live credential surviving "Disconnect". Now clears refresh + expiry, like
    `stravaDisconnect`.
  · **Concurrent refreshes.** `dbxSave`'s 5 s debounce and `dbxCheckOnFocus` can fire together, so two
    callers would each mint a token and the second would invalidate the first. `_dbxRefreshInflight`
    de-dupes: three simultaneous callers → one refresh.
  · **Existing installs have a refresh token but no stored expiry.** A strict expiry check would have
    ignored it; a null expiry deliberately falls through to one refresh, which then learns the real
    value. **Peter should NOT have to reconnect once** to pick this up — his stored refresh token is
    almost certainly still good.
- **Verified: fragment `node --check` + 25/25 truth-table** (silent recovery, upgrade case, no needless
  refresh on a valid token, the 5-min window, surprise-401 retry, dead grant gives up without looping,
  offline keeps the session, disconnect stays dead, 3-way race = 1 refresh, no secret in the body).
  **The whole-file check was skipped on purpose: bash's mount was truncated again** (ends mid-statement,
  no `</html>`, 18,042 lines) so a whole-file parse would have been a FALSE PASS — the documented
  gotcha, now at least the third occurrence. **Open `index.html` in a browser once before `push.bat`.**
- **THE SUPABASE QUESTION IS PARKED, NOT ANSWERED — and it should stay parked until this ride-tests.**
  The transport is genuinely half-built (`route_ensure` already carries route + ele + stops + pace), but
  sync ≠ share, and Supabase fixes neither hard part: (1) **identity** — a share link IS the identity,
  whereas sync needs your phone to know it's *you* on the desktop, and `shareAuth` is one anonymous
  token per device; you'd need a pairing code or real accounts, the thing Peter has deliberately avoided.
  (2) **"which end is newer"** — his other Dropbox complaint — is a sync-design problem that would follow
  us across unchanged (`dbxLoad` already compares timestamps). (3) It makes Peter **custodian of
  everyone's plans**, and per the freemium sketch server-side sync is the *paid* side of the line. So
  it's a business decision wearing a bug's clothing. **Ride with the refresh fix first; if Dropbox stops
  nagging, the question dissolves.**

- **ORANGE TRAIL IS SYMMETRIC** — `afterKm = alertM/1000`, replacing the hard-coded 60 m in `_activeTurn`.
  **The trap I nearly walked into: there were TWO copies of the exit length.** `_activeTurn` decides when
  the turn hands over; `drawMap` (~9496) had its own hard-coded `0.06` for the line it actually DRAWS.
  Changing one would have left the drawn orange vanishing at 60 m while the hand-over rule thought it was
  still lit. `afterKm` is now returned by `_activeTurn` and drawMap uses it — one authority. (Nth
  occurrence of this file's standing trap.)
  · Verified 9/9: lit exactly alertM before and after at 20/50/150/250 m; **the v243 demote guard still
    protects the next turn** — with turns 100 m apart and a 250 m alert it hands over cleanly and turn 1
    is already lit, so there's no gap in guidance; at 50 m it correctly stays on turn 0 until its exit is
    spent (turn 1 is 80 m away, not due).
- **CADENCE + L/R SPLIT OUT INTO THEIR OWN PILL** (`type==='cad'`, cycle now
  `speed → stop → power → cad → hr → off`). This one change answers all three of Peter's power
  complaints: **measured, the power pill goes 134px → 100px** — the cad/bal line ("85 rpm · 49/51 L/R",
  13px, nowrap) was 118px and was the widest thing in the pill, which is exactly why it cropped its
  neighbours. Splitting it also un-squeezes the figures (13px → 34px, his "very hard to read") and gives
  the option he wanted ("if they want to see their power, they don't want to see their RPM"). The cad
  pill is ~118px because "49/51" is 5ch — it has its own slot now, so that's harmless.
- **ZONE COLOUR ON THE WEIGHTED-POWER HALF.** Peter overruled v257's rule that a reversed half must stay
  light: *"the weighted power section should be the zone colour… that tells you what zone you're
  averaging in, because the colour means something."* He's right — when the colour IS the information,
  style can't outrank it. **The two halves now carry DIFFERENT zones on purpose:** the top is the 3 s
  zone (flickers as you surge), the bottom the WEIGHTED zone (where you actually live). Patched in BOTH
  places that repaint the pill — `updateLive` and the BLE `characteristicvaluechanged` handler (~18593,
  which is where the v257 note's "zone-patch" lives) — and only written when the zone changes, since the
  BLE one fires ~1/s.
- Also swept: pill labels off `var(--font)` → `var(--sans)` (v244 rule) and off grey → full contrast,
  matching the v260 speed/stop change.
- **STRAVA 404 ON RENAME IS NOW AN ANSWER, NOT A RETRY** (Peter's screenshot: *"Strava rename failed —
  Strava can't find that activity (404) — was it deleted there?"* on a ride still showing "On Strava ✓ —
  view activity"). The v205 message was doing its job — it named the cause — but the state behind it was
  a lie in two directions: `stravaNamePending` stayed set so the queue retried on **every** trigger
  forever, and the detail modal kept offering a dead link. A 404 is permanent. `stravaSyncName` now
  intercepts it BEFORE the generic `!res.ok` throw and clears `stravaActivityUrl` / `stravaUploadedAt` /
  `stravaUploadStatus` / `stravaNamePending`, so the ride honestly reads as not-uploaded and can be sent
  again by hand. **It deliberately does NOT re-upload** — deleting it on Strava was a deliberate act, and
  silently resurrecting it would be the app overruling the rider. Re-renders the detail modal if it's the
  one on screen, or it keeps showing the stale ✓ until closed and reopened.
- **FIVE PILL SLOTS, IN THREE COLUMNS** (Peter: *"we now have more pills than spots, can we add some
  spots below the current ones, on left and right, perhaps not centre as it blocks the route line"*).
  `0` top-left · `1` top-centre · `2` top-right · `3` below-left · `4` below-right. **He's right about
  the centre** — the live map is heading-up, so the route runs straight up the middle column and a second
  pill there would sit on the line. Now there are exactly as many slots as data pills (speed · stop ·
  power · cad · hr), so all five can be on at once.
  · **The columns are FLEX, not computed tops.** Pill heights vary from 28px ("off") to ~105px (two
    halves), so any fixed `top` for row 2 would break the moment a slot changed. `_renderFloatingPill`
    no longer positions anything — the column does (`FPILL_COLS`). `align-items` per column keeps each
    pill hugging its own edge, so a wide one grows inward rather than off screen.
  · **THE MIGRATION TRAP, caught by the truth-table:** the old load guard was
    `prefs.livePills.length===3`, and every saved layout in existence holds 3 — so a strict check would
    have **silently discarded Peter's pill choices** the first time v260 opened. It now pads instead:
    old three kept exactly, two new slots start empty. Verified 11/11.
- **THE HR PILL JOINS THE FAMILY — it was the last one still in its pre-v257 clothes**, and every
  difference Peter spotted came from that one fact. It had: units INLINE ("137 bpm") where every other
  pill puts them below · figures at 32/26px where the family is 34 · **DM Sans weight 800, i.e.
  PROPORTIONAL digits that jiggle on every beat** (the v244 rule is figures = DM Mono) · the whole pill
  flooded with one zone colour instead of two halves · a 2px zone border · and an **average hardcoded to
  "—" in the template** even though the BLE handler computes it (`UI._hrSum/_hrCount`). Now mirrors the
  power pill exactly: top = current bpm in the CURRENT zone, bottom = average bpm in the AVERAGE's zone,
  34px DM Mono centred, unit below. Verified 6/6.
- **THE STALE-ZONE BUG (Peter found it: "the colours are wrong for the zones").** `live-power-top`'s
  background was painted ONLY by the template and the BLE handler — `updateLive` never touched it. So
  anything driving power through updateLive (the new fake sensors) left the top's colour frozen at the
  last render while the bottom updated live. The tell was arithmetic, not taste: **362 W showed a LOWER
  zone than 290 W, which no single FTP can produce.** Both halves of both pills are now patched in
  updateLive AND the BLE handler. **Standing shape: if a pill can change mid-ride, every path that
  changes it must repaint it — the template is not one of those paths on desktop (v238).**
- **NO ZONE-COLOURED BORDER on power or HR** (Peter: *"the border around the bottom half in the same
  colour as the top half is weird"* — it was). It used the TOP half's zone and wrapped the whole pill, so
  the bottom half sat inside a ring belonging to neither zone. The halves carry the zone; the border is
  just the pill's border. **But the border itself STAYS** — Peter asked whether the power pill needs one
  at all: yes, and it's the same mechanism he admired on the speed pill. The pill's dark bg shows through
  the 1px `rgba(255,255,255,0.15)` ring, which is the only thing stopping a saturated zone colour
  touching the map — and Z4 green sits on a green map.
- **Power/cadence figures CENTRED, not right-justified** (Peter). The 4ch right-aligned box exists to stop
  a DECIMAL POINT moving (speed 9.2 → 18.0); watts and rpm have no decimal, so there was nothing to hold
  still. **Rule: right-align when there's a decimal to anchor, centre when there isn't.**
- **The "dirty green" is probably the DISPLAY, not the palette.** Peter: *"that green doesn't look like
  the green on my phone… it looks a dirty green"*, then *"I could have sworn it was much brighter and
  more saturated on my phone."* Measured: the zone palette is Material Design — Z4 is Green 600
  (`#43A047`, brightness 63%) next to the app's mint `--accent` (`#4ade80`, brightness 87%). On a desktop
  LCD it reads muddy; his phone is OLED and renders it far more vividly. **Judge the zone palette on the
  PHONE — that's where it's ridden.** If it still looks wrong there, the honest fix is a palette pass
  (the zone colours belong to Material, not to this app), not nudging one swatch. Also measured, for
  whoever does that pass: white text FAILS on Z1 grey (1.88) and Z5 yellow (1.40), so an all-white
  palette is not available while yellow is a zone — the mixed black/white treatment is forced.
- **FAKE SENSORS IN THE DESKTOP SIM** (`_simSensorsSet`/`_simSensorTick`, `#desktop-sim-sensors`).
  Peter: *"Can there be a small dial or something in the simulator near the slider so I can cycle the
  power and heart rate pills? I can learn a lot on the desktop without riding."* The power/HR pills need
  a paired BLE sensor, so on a desk they only ever said "hold to pair" and could not be judged at all.
  A checkbox + a watts slider now drive `UI.powerWatts/powerCadence/powerBalance/hrBpm` **and the same NP
  accumulator the BLE handler feeds** — that last part matters: without it the weighted half sits on "—"
  and the zone colour (the thing v260 changed) never appears. Verified 8/8, including the case that IS
  the v260 point: settle at 150 W then surge to 320 W → **top half Z7, bottom half Z2**. Sim-only, never
  persisted; a real meter still wins because `connectPowerMeter` owns `powerConnected` and the off-switch
  only releases what it faked (`if(!_powerChar)`).
- **THE AVERAGE'S LABELS ARE SETTLED** (build in v261): **both**, switching on the rule —
  `leg incl. stops` when `legHasFixedWake(r)`, else `avg incl. stops`. Peter asked whether it was one or
  both; it's both, so the label can never lie about its own scope, and "leg" only ever appears when the
  leg is genuinely scoped. Measured: both fit the 84px label slot, so the explicit wording costs nothing
  over the jargon ("overall", 31px) — and "incl. stops" needs no domain knowledge, which matters because
  the rider who defaults to moving average *because it flatters* is exactly the one who won't decode
  "overall".
- **NO-ROUTE MODE — options written up and revised with Peter: `_planning/no-route-mode.md`.**
  · **THE RULE THAT OUTRANKS EVERYTHING:** *"When you press that record button, you want the recording to
    start… You might have cold hands, brain fog… The other things from that can be secondary."* Already
    law (`startRecording` → `render` → `_rideNowMaybeShow`, v257) — **never regress it.** Ignoring any
    prompt must always leave you with a recording ride.
  · **MY ERROR, Peter corrected it: *"you still absolutely need distance for a no route ride."*** I'd
    written distance off entirely. What dies is distance-as-a-PROPORTION (the bar's fill); the
    **odometer** needs no route and is the number every rider expects. `UI.gpsTravelledKm` already has
    it — it just has nowhere to live, because the bar is the only place distance is shown and the bar is
    route-scoped. Leaning: the bar's slot becomes a plain "23.4 km" readout when there's no route (no
    discovery needed, space already there); a `dist` pill type is the better answer for ROUTE rides that
    want the odometer too (his 12 Jul scout is the case where route km ≠ ridden km).
  · **THE TRIGGER — two signals, both already in the app:** wrong TIME (`planStartInFuture`) or wrong
    PLACE (`snapTo` → `UI._snapOffKm`). So the sheet fires only when **the plan and reality disagree**,
    not on every record start — which answers the objection to widening it. On Peter's ride the PLACE
    check would have fired instantly (1.8 km off) and the time check would not have (his plan wasn't
    future-dated) — which is exactly why the v257 sheet stayed silent.
  · **The doorway that already exists:** v245's off-route alert already offers *"Stop following this
    route"* (`_offRouteMode='abandoned'`) — rider-declared, per-ride, already survives the ride, already
    resets at `stopGPS`. It just doesn't act on it beyond silencing the alarm. Catches the case the
    record-start check misses: you meant to ride it, then changed your mind 40 km in.
  · **"No route" belongs on the RIDE tab, pinned at the TOP of the list** (Peter) — today it's
    Ride → Route → dropdown → pick → Ride. Top of the list = the one entry whose position never changes
    as routes come and go.
  · **DECIDED — THE v257 "RIDING THIS NOW?" PROMPT COLLAPSES TO ONE QUESTION.** Peter: *"If you ride a
    planned route outside of your planned start time, I can't see a need to have the planned clock time.
    That makes no sense. You do want the times to adjust to right now: how far/long is the next stop
    etc."* So **pressing record on a route always means NOW** — the clock question answers itself, and
    "Keep planned times" turns out to be a button nobody would ever press with a recording running.
    The prompt becomes:
        **You're not near this route.**   `[ Follow the route ]  [ No route — just ride ]`
    with "Follow the route" quietly meaning *and use today's times*.
    · **THE TRIGGER THEREFORE BECOMES PLACE-ONLY.** If record-on-a-route always means now, a TIME
      mismatch needs no question at all (you're at the start of your Grenfell route, three weeks early,
      recording — nothing is ambiguous). So the sheet fires on `_snapOffKm` only. One prompt, one
      trigger, one question — and it's exactly Peter's ride and nothing else.
    · **KEEP THE MACHINERY, DELETE ONLY THE QUESTION.** `planShowsPlanned()` still splits CAPTURE from
      DISPLAY — even riding the 8 Aug plan today, real times are never written onto it (v189's promise).
      What goes is the prompt's second button; the answer just becomes automatic. **Do not "simplify" the
      guard away with it.**
  · **PRESETS ARE OUT OF SCOPE** (Peter: *"that's different about storage and stuff and user profile"*).
  · Second finding: **the stop pill and the speed pill ARE the no-route ride screen and both already
    work** — so the cheapest test is to ride it as-is and see whether map + speed + stop is enough.
- **MOUNT WARNING FOR NEXT SESSION:** bash saw only 18,166 of ~18,700 lines all session — the POWER METER
  section was invisible, so `grep` "proved" `UI.powerWatts` was never assigned. **A grep that finds
  nothing may mean the mount is short, not that the code is absent.** Use the Read/Grep tools (they read
  the real file) whenever a result seems too surprising to be true.

## RIDE TEST — 16 July 2026, v259 on a real ride. Peter's findings, ALL still to do.

**THE BIG ONE — RIDING WITHOUT A ROUTE. PackTimes cannot do it, and that's a product hole, not a bug.**
Peter rode a training loop he does regularly and has no route for. A route was loaded (a different one),
so: *"the distance bar didn't work. It never changed. It sat on 1.8 km, which is probably the nearest
point to the route I was on."* Exactly — `snapTo` found the nearest point on a route he wasn't riding and
he never moved along it, so every downstream figure was faithfully reporting a fiction. **Nothing is
broken; the app has no concept of "I'm just going for a ride."**
- Irrelevant without a route: distance bar, elevation graph, turn directions, next-stops strip, ETAs.
- **Peter: *"There needs to be the option of just doing a ride without a route, and that fits in with our
  scenario of this being usable for someone on an everyday basis, just as a go-to riding tool."***
- **His proposed doorway: the record-start prompt.** *"Maybe in the same window as when you start
  recording… 'Hey, this is not the time you've set in this route. Do you want to follow that route, or do
  you want to just do your own thing without a route?'"* — i.e. **extend the v257 "Riding this now?"
  sheet**, which already fires at exactly that moment and already asks a question of the same shape
  (which plan does this ride belong to?). Do NOT build a second prompt.
- *"If it's without a route, then obviously a lot of things should hide. Somewhere there needs to be a
  preset."* This is the same preset idea as §3.6/§3.7 and the two-markets point below — the doorway sets
  what you see.
- **Connects to the two markets (Peter, same day):** *"PackTimes is for ultra and long-distance riders,
  but PackRide could just be for someone doing one social ride on a weekend for one hour… they ride hard,
  they might stop for a coffee halfway, and they're ended. There are two different markets there."* The
  no-route ride and the social ride are the same customer. This is the strongest argument yet that the
  preset — not a settings toggle — is what should decide the ride screen's contents AND the average's
  definition (moving for the social rider, overall for the ultra).

**WHAT WORKED — the stoppage pill.** *"The percentage of stoppage was excellent… it's actually a number
you can drive. If you want to change your average speed, you can change it a bit by going harder or
softer, that's true, but the stoppage is really relevant in ultra. That's a really good measure, and I'm
really happy with that."* Elapsed worked too. The leg clock is proven on a real ride.

**SMALL FIXES PETER ASKED FOR (clear enough to just do):**
- **"4m" READS AS METRES.** It's minutes, but `m` is the SI symbol for metre (min is minutes). His fix:
  always lead with the hours — **"0h04"** — so the `h` disambiguates and the shape never changes. Also
  keeps 4ch.
- **The grey labels are unreadable.** *"We actually can't read that grey km/h in the current speed pill.
  It should be white, with full contrast. I think for all those pills, I'd just use black and white. I
  wouldn't use the grey. I don't think it really works."* → kill `rgba(255,255,255,0.5)` / `#4a5a4a` on
  every pill label.
- **Stop % — ADAPTIVE precision (`fmtStopPct`), which is better than either option on the table.** Peter
  asked for one decimal (*"1.1, 1.2… it would just give you a better idea of what the number's up to, and
  you've got plenty of space"*), then spotted the cost himself — *"it will get worse when it is 10 or
  above"* — and offered to drop the decimal entirely. **His own example is the rule**: he said "1.1, 1.2",
  i.e. LOW numbers, which is exactly where a decimal carries information. At 15% the `.3` is noise.
  · `<10%` → `1.2%` (4ch) · `≥10%` → `12%` (3–4ch). Never over 4ch, so the pill holds the family's
    100px (was 118) AND the figure stays at the family's 34px — the hero never shrinks, which is why the
    cad pill's 28px fix was wrong here (the % IS the hero).
  · **It gets NARROWER at 10, never wider** — so the pill can't grow mid-ride.
  · **Bug the truth-table caught in my own rule:** `p<10 ? p.toFixed(1) : …` emits **"10.0%" (5ch)** at
    p=9.96 — under 10 raw, but toFixed rounds it up. Test the ROUNDED value (`+p.toFixed(1) < 10`), not
    the raw one. 17/17.
- **The cad pill's balance figure is 28px, not 34** — "49/51" is 5 glyphs and 5 glyphs at 34px is 102px,
  forcing the pill to 118 and cropping its neighbour. 28px is the LARGEST size that returns it to exactly
  100px, so it's the smallest reduction that works; the cadence figure above stays at 34 ("88" is 41px).
  Peter: *"I don't see a way of reducing that except for reducing the font size for the left right. The
  RPM font can stay the same size."* Correct — there is no other lever.
- **Unit placement is inconsistent**: the speed pill puts its unit UNDERNEATH the figure; the time pill
  has it inline ("8h04"). Peter: *"we need to be trying to be consistent."* Not yet resolved which wins.

**THE POWER PILL (Peter's list):**
- **Too wide — it crops the other pills.** Must not.
- **RPM and L/R balance are very hard to read** (too small). *"Should the RPM and the left and right
  pedal balance have its own pill? Think about Wahoo and Garmin. They're all separate data fields… It
  also gives someone the option, if they want to see their power, they don't want to see their RPM."*
  → likely a separate `cadence` pill type in the cycle.
- **The weighted-power half should carry the ZONE COLOUR.** *"It really should be because that tells you
  what zone you're averaging in, because the colour means something."* Currently the v257 BLE zone-patch
  deliberately does NOT repaint the np/label colours (they live on the light half). Peter is overruling
  that: the zone colour is information, and the averaged number is where it means most.

**THE DISTANCE BAR — STILL NOT RIGHT. Peter: *"I'm still not happy… It's lacking an impression of
movement, of dynamics. It's just this bland bar."*** Round 6, and the diagnosis is new: every previous
round argued about TEXT PLACEMENT. This one says the graphic itself is inert — it shows a proportion but
not a direction. His sketch:
- **Full width, NO radius, edge to edge** — not an inset pill floating on the map.
- **A small dividing line between it and the tab bar** above (route/stops/supplies/mission…).
- **Back to a RESERVED section** (his earlier idea, which we rejected as "fudging" — he's revisiting):
  the white done-zone at the left is always big enough to hold "0.0 km".
- **THE MISSING THING IS AN ARROW.** *"It's got an arrow. It's just simply 45° lines going into the
  black."* — i.e. the fill's leading edge becomes a **chevron/arrowhead pointing forward** instead of a
  flat divide. That is what supplies the direction and the movement the flat edge can't.
- At the finish end, *"maybe it has a receiving arrow"* — a notch that the advancing arrow eventually
  mates with. Peter: *"I don't quite understand the second part, but something needs to change."*
- **Worth noting the arrow may also solve the old problem for free**: an arrowhead is a much more legible
  divide than a straight edge, so the done/to-go boundary reads at a glance even in peripheral vision.

**PARKED — the orange turn highlight should trail LONGER (Peter, from real riding, 16 Jul):** *"the orange
turn marker should extend PAST the turn as much as it started BEFORE the turn. I am finding the orange
marker excellent for confidence after a turn, but the ~40 or ~60 m quickly passes, and then you have a
sense of uncertainty again and might go to zoom the map to make sure."*
- **The finding is the valuable part: the orange's job after the corner is CONFIDENCE, not guidance.** It
  answers "did I take the right road?", which is a different question from "a turn is coming" — and the
  evidence is that when it ends too early he reaches for the zoom. That's a job the route line alone
  can't do: *"the route colour matching sky is very good, but at times it can have minimal contrast."*
  So the approach length and the exit length serve different purposes and needn't be equal.
- **DECIDED: symmetric. `after = UI.turnAlertM`, replacing the hard-coded `afterKm=0.06`.** I flagged
  that on the default (alert 50 m) symmetry gives a 50 m trail — SHORTER than today's 60 m, the opposite
  of the ask. **Peter's answer resolves it and is better than my worry:** *"the same exit length as entry
  might actually still be good, because if you're happy with a short entry warning, it probably means
  you're in a city or riding slowly. It's really probably okay. Both match."* The alert distance already
  encodes speed and context — a rider who wants 50 m of warning is moving slowly enough that 50 m of
  reassurance lasts the same time. **One setting drives both ends; no second slider, no max() fudge.**
- Related, already known: the v243 demote guard means a long exit can't strand the next turn — if the
  next turn's window opens while the orange is still lit, it hands straight over.

**PARKED — distance bar tick marks (Peter's idea, 16 Jul):** *"some minor lines in the opposing colour in
the distance bar — indicating every 10 km, or maybe half, quarter, 1/8 distance. They would have to stay
clear of the text of course."*
- **The "opposing colour" is the good part**: a tick drawn dark on the fill and light on the to-go side
  flips at the divide and stays visible on both — the same trick the migrating figures use.
- **Fractions, not 10 km.** Absolute marks degrade exactly where the bar matters most: 13 ticks on a
  137 km route, 30 on a 300, ~100 on a 1000 km event. Quarters (3) or eighths (7) are scale-free and match
  what the bar is FOR — proportion. Absolute distance is already the elevation strip's job.
- Dodging the figures is cheap: `_distBarGeom` already knows both figures' boxes, so a tick just skips
  when it would land under one.
- Not built. Judge it at true size before committing — the v258 lesson was that a 3px tick vanished on a
  phone and only looked right at 2×.

**STILL TO DO (v260) — the speed pill's average:**
- Peter's decision: *"I'd opt for the average to show the current leg only, if there is a sleep with a
  fixed wake up."* The leg clock now computes exactly that (`_legVals().distKm / elapsedMs`), so the
  switch is small. **Deliberately NOT done in v259:** the average currently works without recording, the
  leg clock does not, and the clock is the risky new measurement. Prove it on a ride first, then rewire
  something that already works — one step, one version.
- Open with it: what the average does when NOT recording (fall back to today's clock, or show dashes),
  and that the speed pill's "avg" label should say WHICH average it is.

## Current status (16 July 2026, v258) — THE DISTANCE BAR IS BUILT (migrate). NOT ride-tested.

The design agreed below (round 5) is now code. **v258, unpushed at time of writing.**

- **The bar is now: casing · fill · done left · to-go right. No centre text.** Dropping the centre
  slot is what makes the migrating figures possible — the centre is exactly where the divide lives.
- **CSS** (`.live-dist-bar` and friends, ~line 168): radius 6 → **8px** (the speed pill's, now the app's
  style reference); fill inset by a **1px hairline** and `border-radius:7px 0 0 7px` — **left corners
  rounded, right edge SQUARE** because that edge is the done/to-go divide (radius = outside edge, square =
  "this divides"); fill is `var(--accent)` not `--accent3` (a PackRide theme overrides the token — that's
  the whole theming mechanism, don't hard-code yellow); units are **DM Sans 12px muted** (`--font` → mono
  was a live v244 violation); `.on-fill` reverses a figure to dark.
- **`_distBarGeom(r,liveDist,barW)`** (TIME CALC, after `legToGoKm`) is the ONE authority for where the
  figures sit. `_distBarSync()` paints it. **The template renders the bar EMPTY on purpose** — the flip
  depends on the bar's measured width, which a template string cannot know. Same reason the sharing/pack
  buttons are built from updateLive (v257 lesson, now three occurrences).
  · Call sites, mirroring `_shareBtnSync` exactly: `updateLive` (every tick), end of `sizeLiveMap`
    (resize changes the flip points), after `sizeLiveMap()` in initLiveMap, and the 200 ms settle timeout.
  · Text is measured on a **canvas**, not the DOM — no layout flush per tick, and the width is known
    before the element exists. **The canvas fonts must track the CSS**; if the CSS sizes change, change
    `_distTextW` too.
  · `barW` unknown (first paint) → safe flush-left fallback, positioned properly on the next tick. Never
    guess a width: a wrong flip is worse than a plain one.
- **DELETED**: the 4-second centre rotation (`Math.floor(Date.now()/4000)%3`), `.live-dist-finish`, and
  updateLive's old patch block which computed the fill + both figures itself.
- **`legEndTxt` + `LEG_FLAG_SVG` + `LEG_MOON_SVG` are now UNREFERENCED but deliberately kept** — the time
  pill (next job) shows "time to the leg or total finish", which is that exact rule incl. flag-vs-moon.
  If the time pill is abandoned, delete all three. `legEnd`/`legToGoKm` stay regardless (`legToGoKm` is
  the bar's "to go").
**Two fixes from Peter's first desktop look at v258 (same version, still unpushed):**
- **THE CORNER NOTCH (a real bug, mine).** I applied only half my own rule. The fill's right edge is a
  DIVIDE while there's road left, but at the finish it becomes the bar's **own outside edge** — I left it
  square always, so the last ~7px showed a square green edge inside a rounded black corner. The right
  corners now round progressively over the final 7px (`rr = clamp(7-(inner-fillW),0,7)`, set in
  `_distBarSync`). At Peter's exact screenshot state (99.85%) the radius is 6.45px and the notch is gone.
- **The fill's width is now PX, not %.** A `%` width resolves against the whole bar, so with the fill
  inset `left:1px` it overshot the right edge and the 1px hairline existed on the left only. Now
  `width = (barW-2)*pct` px → symmetric hairline both ends.
- **THE SIM SLIDER COULD NEVER REACH THE FINISH — the actual cause of the "not quite right" end fill,
  and a real bug in its own right (Peter's instinct: "there's probably some rounding going on"). He was
  right.** `renderDesktopMap` set `sl.max = r.totalDist.toFixed(0)`, rounding a DISTANCE as if it were a
  display string. Wrong in BOTH directions: a 137.2 km route → max 137, so the last 200 m were
  unreachable and the sim could never ride to the finish; a 300.6 km route → max 301, letting you scrub
  **400 m past the finish**. Compounded by `step="0.5"` on the input — a range input can only take
  `min+step*n`, so even with the max fixed it would have stopped at 137.0. **Fixed both:** `sl.max =
  r.totalDist` (no rounding) and `step="any"`. Verified across 137.2/300.6/137.6/166.4/99.9/42.5/1.9 km —
  every one now lands exactly on the finish.
  · **The distance bar was never at fault here.** On a real ride `gpsDistKm` comes from `snapTo`, which
    reaches `totalDist` fine. This only ever bit the simulator — but it meant the last 200 m of any route
    (finish arrival, final turn, the `0.0 km` state) could not be sim-tested at all.
- **Sub-pixel snap (2nd look — "the end green fill is not quite right").** At Peter's 137.0/137.2 km the
  remainder is **0.55px**. The progressive radius was geometrically right there (6.45px, concentric with
  the casing) but a half-pixel of dark doesn't read as "road left" — it anti-aliases to a grey smudge on
  the corner. Now: `if(inner-fw<1.5)fw=inner` → snaps to full over the last **~410 m of a 137 km route**.
  Below a pixel there is nothing honest to draw, and the figures still read the truth.
- **THE HAIRLINE'S SUB-PIXEL ASYMMETRY (4th look) — the bar's BOX is now snapped to whole pixels.**
  Peter: *"the green on the left is bleeding over the black border… on the right the black is slightly
  thicker… the length of the green and the length of the black are correct. The green is offset too much
  to the left, probably a little bit of a pixel."* Exactly right, and the maths was never wrong — the
  hairline is 1 CSS px on all four sides by construction. What was wrong is where it LANDS: the bar is
  `left:6/right:6` inside the map section; on desktop the section's left comes from the sidebar (an
  integer) so the bar's LEFT edge sits on a whole pixel and renders crisp, but the section's WIDTH is
  viewport-derived and fractional, so the bar's RIGHT edge sits mid-pixel and the identical 1px hairline
  is anti-aliased across two device pixels — reading as thicker. `_distBarSync` now pins the bar's box to
  integers (`Math.round(sec.left+6)` / `Math.round(sec.right-6)`, written only when the width actually
  changes, so no per-tick layout thrash). Modelled across real geometries: before = crisp/smeared on every
  case; after = 1.00px both sides. **Desktop-only symptom** — at DPR 2–3 the smear is half a device pixel.
  Cost: the bar's outer margin can be 6.0 vs 6.33 — invisible, unlike a fuzzy hairline.
- **THE RIGHT HAIRLINE WAS FAT — `clientWidth` ROUNDS (3rd look).** Peter: *"the final black border on the
  right seems slightly too big compared to the black borders on the top, bottom, and left side."* Correct.
  `clientWidth` returns an **integer**, and this bar is `left:6/right:6` off a viewport-derived map
  section, so its real width is nearly always fractional. Rounding it left the fill short and dumped the
  remainder onto the right edge — measured up to **1.4px against the 1px hairline** on the other three
  sides. **The left/top/bottom are CSS `1px` insets the browser places exactly; only the right edge is
  COMPUTED, so only the right edge inherits the error.** Now `bar.getBoundingClientRect().width` (and the
  fill's width at 2dp, since 1dp would re-introduce 0.05px of the same error). Verified: 1.00px on all
  four sides at every fractional bar width tried. **Same lesson as v255's pill positioning — measure with
  rect maths, never with rounded box metrics.** Now three occurrences; treat rounded box metrics as a
  smell anywhere pixel alignment matters.
- **The unit is baseline-aligned to the figure** ("can the km be bottom justified to match the text?").
  The row is `display:flex;align-items:center`, so the figure and its unit were two flex items centred
  SEPARATELY and their baselines missed. New `.live-dist-fig{display:inline-flex;align-items:baseline}`
  wrapper sits them on one baseline while the row still centres the pair — this is exactly what the old
  bar's inline `display:inline-flex;align-items:baseline` span did, and I dropped it in the rewrite.
- **'km/route' → 'km'** (`DIST_DONE_UNIT`, one string to revert). **NOTE: I did not add '/route' — it was
  in the bar all along.** Peter asked whether to drop it or let it flip separately from the figure.
  Measured: keeping it flips the done figure at 30.3% with a 107px jump; dropping it → 20.8% / 71px (a
  third smaller). **His "flip the unit later" idea gives the best flip (17.7% / 59px) but was rejected:**
  the unit is 48px wide, so the divide takes **12.7% of the ride** to cross it — "km/route" would sit
  two-tone for that whole span, which is the exact straddle this version exists to remove (and the reason
  he rejected INVERT). Dropped instead because the bar no longer shows GPS distance (removed this same
  version), so every figure on it is route-scoped and there is nothing to disambiguate from. **If the
  route-vs-ridden distinction needs saying, it belongs on the pill showing RIDDEN distance ("actual"),
  where both numbers are visible at once.** Peter's counter-argument on the record: *"route km is not the
  same as km ridden"* — true, and his 12 Jul scout ride is the case where it bites.
- **Verified**: new fragment `node --check` clean + **21/21 truth-table** — the invariant (**zero straddles
  across 1,000 samples of the whole ride**), colour always matches the side, **each figure flips exactly
  ONCE** (done 18.4%, to-go 81.7% on a 300.6 km route at 381 CSS px), ends read `0.0/300.6` → `300.6/0.0`,
  figures never overlap, never escape the casing, no NaN on a zero/absurd width, the v257 leg-scoped
  "to go" still honoured (fill stays whole-route), and the fill's right corner is square mid-ride but
  rounded at the finish.
- **NOT VERIFIED: no whole-file `node --check` this session.** The bash mount was stuck on a stale,
  truncated replica (the documented Dropbox gotcha) and never caught up, so a whole-file parse would have
  been vacuous — it reported "0 script blocks" and passed, which is a FALSE PASS worth remembering. Every
  edited region was instead read back via the Read tool and confirmed balanced. **Open index.html in a
  browser once before `push.bat`.**
- **STILL TO DO:** the **TIME PILL** (v259) — Peter's design: a two-half pill like the speed pill showing
  **time ridden + estimated time to the leg or total finish**, optional, in one of the three floating slots.

## Design session — 16 July 2026 — the distance bar, mocked (v257 IS NOW PUSHED; schema v9 IS RUN)

**Peter has run `schema-v9.sql` and pushed v257. So v257 is live and the next code change is v258.**
Everything in the 16 July build session below is now on a phone but still **not ride-tested**.

Mockups: **`_planning/distance-bar-mockups.html`** + `_planning/distance-bar/*.png`, and a reusable
clean plate at `_planning/GPS Screens/ride-clean-plate.png` (the real screenshot with the baked-in bar
painted out, so lighter designs can be judged — map texture borrowed from lower down; ignore the seam).
Scope was Peter's: **graphics only** — content, the 4 s centre rotation and the whole-route fill untouched.

- **Measured, don't guess:** the bar is `x 16–1064, y 360–456` in the 1080×2424 screenshot = CSS 34px at
  **2.748×**. Mockups were rendered with **Pillow using the repo's real DM Sans/DM Mono** (woff2 → ttf via
  fontTools) at true size, because **the sandbox cannot render HTML** — no sudo, so Playwright's chromium
  has no deps. Lesson: render mockups as PNGs and LOOK at them; don't hand Peter a CSS page never seen.
- **THE FINDING — the bar is worst exactly when it matters most.** `--accent3` is `#16a34a` (bright, not the
  dark green I assumed). At 89% the whole bar is a **green slab with white text on it** — on the last 30 km
  of a long day. Early on it's a 6px nub that reads as an artefact; mid-ride the left figure sits on green.
  This isn't styling to tolerate: it's why the bar feels wrong, and it degrades as the ride goes on.
- **Four problems named:** (1) text layers sit ON TOP of the sweeping fill — **structural, no restyle fixes
  it**; (2) the 0.6% nub; (3) **units inherit DM Mono** (the bar sets `font-family:var(--font)`), which is a
  live **v244 rule violation** — mono is for figures, DM Sans for words; (4) no hierarchy + the 8-rect flag
  dithers to mush at 14px.
- **ROUND 1 (rail) — REJECTED by Peter, and he was right.** I proposed shrinking the fill to an 8px rail so
  text could sit on solid dark. His objection: *"the rail is too small. The whole idea of a distance bar is
  that it is a full bar so there is something of a clear size to look at… We are complicating it by trying to
  show text in there."* I had fixed the symptom by damaging the thing that matters — the graphic. **Standing
  lesson: when a component has two jobs that fight, take one job OUT; don't shrink the important one.**

**ROUND 2 — THE AGREED DESIGN (Peter's concept, mocked, NOT BUILT):** bar + travelling pill.
- **The bar is ONLY a graphic** — full width, **HALF height (CSS 34 → 17px, Peter's call to save real
  estate)**, no text in it at all.
- **The pill is the playhead**: sits at your position, split side-to-side (done left / to-go right), black &
  white like the speed pill — it reads as a magnified slice of the bar at the point you're at.
- **The caret keeps it honest**: near the ends the pill clamps to the screen, so the caret slides WITHIN the
  pill to keep pointing at the true position on the bar. The pill may be approximate about its x; the caret
  may not.
- **The rotating info flips to whichever side the pill isn't.**
- **PETER'S BORDER NOTE IS THE KEY DETAIL** — *"a subtle thing about the speed pill is the black border on
  the white part of the fill."* So the fill lives INSIDE a black casing and never touches the map. That is
  precisely what stops a full-width fill glaring at night, and it's the flaw today's wash has. It's why a
  full bar is now viable when I'd assumed it wasn't.
- **COLOUR — the rule that fell out of Peter's theming point** (*"green for PackTimes, yellow for
  PackRide"*): **the graphic carries the product colour; the numbers stay black and white.** Bar = accent
  (green / PackRide yellow, one token); pill = monochrome, matching the speed pill. Colour means WHICH
  PRODUCT; size and reversal mean WHICH NUMBER MATTERS. Don't overload colour with importance.
- **THE ONE REAL FLAW, found by rendering it:** mid-bar, "flip to unoccupied space" has nowhere to flip —
  at 48% both side gaps are too narrow for "Grenfell 21:00" and the ETA silently VANISHED. Fix: the ETA pill
  is **adaptive** — full name when it fits, `21:00` when it doesn't. Measured across the whole ride, **only
  the ~40–55% band needs the short form**, and it degrades to the more useful half (the strip below already
  names the place).
- **COST: ~+16 CSS px of map.** Bar halves (−17) but the pill row adds ~30, so the zone goes `6–40` → `6–58`
  and the floating pills must move `top:48` → `~64` (mocked with the speed pill redrawn there, and it fits).
  **Offered alternative if that's too much: the pill STRADDLES the bar** (≈cost-neutral — the pill's split
  point already IS the fill edge). Not yet mocked.
- **ROUND 3 — Peter's corrections, all applied and mocked:**
  · **The speed pill's "black border" is ~1px and is NOT DRAWN.** Ground truth from the code:
    `border:1px solid rgba(255,255,255,0.15)` + `overflow:hidden`, and the white `#eef3ee` child stops at the
    padding box — so the pill's own dark bg shows through that 1px ring. That's why it's visible only against
    the white and invisible on the dark half. My round-2 mock drew a ~2px black band: far too thick.
  · **Radius 8px (the speed pill's) on both bar and pill** — not stadium/half-height.
  · **The white fill is rounded LEFT ONLY**; its right edge is the done/to-go dividing line, so square.
    General rule: radius = outside edge; square = "this divides".
  · **The pointer is a STRAIGHT LINE, not an arrowhead.** Cased (white line, thin dark outline) so it
    survives light terrain — bare white vanishes on pale map at 89%.
- **THE ROTATING CONTENT FITS — measured, not guessed** (Peter's worry). The rotating pill's space is worst
  when the travelling pill is dead centre: **112 CSS px at 50%**. Long forms: `5h 23m mov.` fits ALWAYS;
  `Grenfell 21:00` and `145.2 km actual` don't. Short forms all fit (`21:00`, `5h 23m`, `145.2 km`). So each
  rotating item needs a short form, used only in the ~40–55% band, each degrading to its more useful half.
- **THE FALLBACK Peter raised: distance as a 4th pill TYPE in the existing speed/power/HR slots**, deleting
  the bar. Parked, not chosen — **his own earlier argument is the counter**: a bar is understood without
  reading; two numbers must be read and compared. Deleting the graphic solves the layout by removing the
  feature. Cheap to reach later (the pill is already speed-pill-shaped). If it ever happens, his 4th-slot
  idea is right: below an existing slot, LEFT or RIGHT, never centre — the route line runs up the centre
  column on a heading-up map.
- Peter's wider point, recorded: *"PackTimes has evolved rapidly and the graphics have been neglected. I think
  the speed pill is a big improvement and could be a good reference for the overall style of the app."*
  **The style reference, now that the speed pill has been pulled apart:** figures DM Mono / words DM Sans
  small+muted; white panels sit inside black via a 1px hairline (never a band) so they never touch the map;
  radius 8px everywhere; a boundary between two values is square, an outside edge is rounded; one hero number
  per component; colour = product, not importance.
**ROUND 4 — THE TRAVELLING PILL IS OFF. Peter: the pill mockup "just doesn't strike me as 'great'."**
Back to first principles at his direction: **full-height bar, numbers stay INSIDE it**, done left / to-go
right, always far apart. Rotating ETA/ride-time/GPS-distance deliberately parked ("one step at a time").
- **THE REFRAME THAT CRACKED IT (Peter's):** the problem was never *text in the bar* — it was **text
  STRADDLING the divide**. So don't remove the text; just never let a number sit on both colours at once.
  Everything since had been solving the wrong problem (my rail shrank the graphic; the travelling pill
  evicted the text).
- **RECOMMENDED — "RESERVED ENDS", and it is Peter's OWN earlier idea** (*"reserve a space on the left for the
  smallest number (0.0km) that is always the done colour… the bar doesn't start far left… same for the
  finish"*). Neither of us spotted at the time that it solves the straddle, not just the nub. **Left zone is
  ALWAYS the done colour, right zone ALWAYS the to-go colour, the variable fill lives only in the MIDDLE** →
  nothing moves, nothing jumps, no glyph is ever cut, both figures sit permanently on solid colour at full
  size. **And it costs ZERO extra height** (unlike the travelling pill's +16px) — the floating pills don't move.
  · Honest cost: zones are 200px each → **the variable middle is 62% of the bar**; at 0% it already shows ~19%
    done-colour, at 100% ~19% to-go. Peter accepted that trade when he proposed it. Smaller figures shrink it.
- **REJECTED "MIGRATE"** (his other idea, mocked): numbers hop to whichever side has room. Full-width graphic
  and no straddle, but the done figure **creeps right with the fill then jumps ~200px left at ~21%** — motion
  in a number whose whole point is being read without effort.
- **REJECTED "INVERT"** (my alternative, mocked): numbers never move; drawn twice and clipped at the divide so
  glyphs flip colour exactly at the boundary. Elegant, and it *realises Peter's hunch* about the digits going
  in first while "km" stays behind — that falls out naturally and reads fine. **But it loses on the to-go
  number:** right-aligned, so the divide crosses it for the **last ~24% of the ride** — `33|.1 km`, cut
  mid-digit, as a sustained phase not a moment. (The done number's crossing is short and lands on the small
  muted "km".)
- **STILL OPEN:** the rotating ETA/ride-time/GPS-distance has nowhere to live under reserved-ends — the middle
  is the fill. Likely answers: a chip with its own dark casing sitting on the fill (a cased chip may straddle;
  a bare label may not), or the row below. Peter parked it deliberately.
**ROUND 5 — DECIDED. Peter picked MIGRATE. The bar is now settled; NOT BUILT (next job = v258).**
- **RESERVED ENDS rejected** despite being close: *"I like a lot of the RESERVED concept, except that
  graphically it is fudging."* Correct — its 62% dynamic range means the bar lies about its own scale.
- **INVERT rejected** — *"a lesser choice"* (the to-go figure stays cut mid-digit for the last ~24%).
- **MIGRATE chosen, and the CREEP is accepted with eyes open.** I flagged that the done figure doesn't just
  flip once — it rides just ahead of the fill, then jumps. Peter's ruling: *"it is happening so slowly that I
  don't really think it is a big problem. Undesirable, but probably the lesser of all evils… it is not like a
  speed number, constantly changing."* (~1px/min on a 300 km ride.) **Don't re-litigate this; a fixed
  two-position variant was offered and declined.**
- **THE BAR IS NOW JUST: full-height casing · fill (accent = product colour) · done left · to-go right.**
  No centre text — which is what finally makes migrate work, since the centre is where the divide lives.
- **GPS distance: DROPPED from the bar.** Peter: *"a fringe measurement… often near identical to distance
  along the route… Two distance bars would be stupid."*
- **Leg ETA: not needed in the bar** — *"partly visible in the Next Strip, and the extended stops list which
  can be dragged up."*
- **NEW — the TIME PILL (Peter's idea, not yet mocked properly):** a pill *"like the speed pill"* showing
  **time ridden + estimated time to the leg or total finish**, i.e. the same two-half shape (dark over
  reversed light). **Optional, in one of the existing floating pill slots** — *"less important than distance,
  and somewhat optional."* This is the home for the rotating content the bar gives up.
- **THE ELEVATION-STRIP QUESTION, answered from the code** (Peter mused: *"should the distance bar be a
  corollary of the elevation strip and profile, but on top?"*). **No — they are different SCOPES and must not
  be merged.** `drawElev` uses `elevZoomKm` = `min(totalDist*0.2, 30)` by default, with the rider pinned at
  `gpsFrac=0.15` from the left and `distMin=liveDist-0.15*visSpan` — i.e. a **moving ~30 km window**,
  swipe-zoomable 2 km→full. It answers "what's the next hill like?"; the distance bar answers "how far
  through the whole ride am I?" on a fixed whole-route axis. Squeeze 300 km of profile into 393 px and the
  next climb is invisible; keep the window and it isn't a distance bar. **The distance bar is the only
  whole-route view on the ride screen** — an argument for keeping it separate, and at the top.

## Session — 16 July 2026 (built as v257, now PUSHED) — leg ETAs · "Riding this now?" · PackRide carries the plan

Three builds off Peter's questions. **None ride-tested; desktop reasoning + node truth-tables
only (18/18, 25/25, 22/22). Still v257 — it has never been pushed, so a v258 label would name
a version no phone ever ran.**

**First, the answers to what he asked (all read out of the code, not guessed):**
- **PackRide links already carry stops AND the start time.** `route_ensure` sends `p_stops`;
  `event_create` sends `p_start_at` from the route's `startDT()`; `eventRouteToRoute` rebuilds
  both. What was NOT travelling was the *plan* — see below.
- **Sharing starts when RECORDING starts. Full stop.** `shareIsLive() = shareIsOn() && _rec &&
  status==='active'`. There is no 15-min-before, and no "ride" to activate — the event exists
  from creation; your dot appears when you record. The planned start time does **nothing** for
  sharing; it is used only for display, staleness (`_eventStale`, >48 h), and the joiner's route
  start date. So copying a PackRide link at any time is safe. Peter was not overthinking — two
  of his four worries were phantoms, two were real.

**(1) THE DISTANCE BAR'S ETA IS NOW THE END OF TODAY, not the finish** (`legEnd`/`legEndTxt`/
`legToGoKm`, TIME CALC, after `etaAt`). **Peter's argument, and it's stronger than it first
sounds:** with a planned sleep + a wake time, the sleep ABSORBS all variance — arrive at the
motel two hours late, you still wake at 07:00, so the finish doesn't move. A finish ETA on day
1 of 3 therefore *looks* live while being structurally insensitive to how today is going: the
worst kind of number, because it invites trust. His framing: a planned sleep implies planned
rest, so it isn't a non-stop race — **finishing each day is the goal**.
- **ONE rule, no toggle, no setting:** the next sleep stop ahead; if none ahead, the finish.
  Self-solves at both ends — on the last day there IS no sleep ahead, so it becomes the finish
  exactly when the finish starts to matter; a non-stop/race plan has no sleep stops, so it
  always reads the finish, which is correct there.
- Returns **arrival** at the sleep stop (`etaAt` is arrival, before that stop's own sleep/meals)
  = "what time do I get in tonight".
- **Chequered flag = finish, crescent moon = tonight's bed.** Two destinations must never wear
  one icon. No weekday on a leg end (the next sleep IS tonight); the finish keeps its weekday.
- **"To go" is leg-scoped too** (`legToGoKm`) — otherwise the bar named two destinations at once
  ("247.3 km" beside "Grenfell 21:00"). The FILL stays whole-route on purpose: left figure +
  fill = where you are in the whole ride; centre + right = tonight's target. Two honest scopes.
  Identical to the old number on a plan with no sleeps. **Flagged for Peter to veto — trivial revert.**
- **ONE authority** (`legEndTxt`) called by both the template and `updateLive`'s patch. Two
  copies of one rule is how this file has drifted three times (v252 rotation, v257 peek anchor).
- Deliberately untouched: the `finish` stat PILL still says "Finish" and still means it.

**(2) "RIDING THIS NOW?" — a future-dated plan can run on today's clock** (`rideNowOn`/
`rideNowClear`/`rideNowRestore` in TIME CALC; `_rideNowMaybeShow` in RECORDING). **The bug Peter
half-noticed without naming:** he rode his 8 Aug plan on 12 Jul to scout some legs. v189 correctly
refused to let that ride pollute the plan — which also meant every ETA, daylight and weather
reading on his ride screen was anchored to 8 August. The ride screen was useless for the ride he
was actually doing. His only workaround was to change the start date (wiping the plan's stamps)
and change it back.
- **Naming: Peter rejected "scout"** — most people never scout, they just ride a route on a
  different day. Chose **"Riding this now?"** (over "Riding it today?"/"Use today's times?") —
  "now" also covers an 11 pm start that runs into tomorrow. Buttons: **Ride now** / **Keep
  planned times**.
- **THE KEY MOVE — this does NOT re-break v189.** The two jobs `planStartInFuture` used to serve
  are now split and **must not be re-merged**:
  · **CAPTURE** ("may we write real times onto this plan?") still uses `planStartInFuture` RAW.
    A future-dated plan is *never* stamped, even while ridden today. v189's promise, intact.
  · **DISPLAY** ("what clock does the screen run on?") uses new `planShowsPlanned(r)` =
    `planStartInFuture(r) && !rideNowOn(r)`.
  The transient "actual start" lives on the **recording** (`_rec.startTS`) — where actuals
  belong — so `startDT` returns today's real start without writing a thing to the plan.
  `startDT` checks ride-now FIRST: it outranks even a stale actual stamp, because it's the most
  specific statement of intent the rider can make.
- **Also closes the standing open item** "route colour + weather don't re-time to NOW when a ride
  starts" — same root cause (`etaAt`'s GPS re-anchor gated by `planStartInFuture`).
- **Trigger: record start only** (Peter's call). GPS-on would prompt on any stray fix near the
  route while planning — the exact nuisance v189 exists to stop. **Non-blocking**: the ride starts
  the instant the button is pressed and the prompt appears over it. Pressing record must never
  wait on a question; ignoring the prompt just gives today's behaviour.
- **Per-ride, like the v257 sharing flag**: cleared at `finaliseRecording` AND `_recStopDelete`,
  and **restored by `_recStopUndo`** — un-stopping within the 5 s window must not silently drop
  the screen back onto 8 August with no way to re-ask (the prompt only fires at record start).
  Persisted in `uiPrefs` (`rideNowId`/`rideNowTs`) so crash recovery keeps today's clock.
- Note `_recStopUndo` does NOT restore `shareOffThisRide` — pre-existing v257 gap, same shape.

**(3) PACKRIDE NOW CARRIES THE PLAN, NOT JUST THE PINS** (`_shareStopsPayload`). A joined rider
got "Grenfell Motel" as a bare sleep pin — no duration, no wake time, no meals — so their ETAs
disagreed with the organiser's for reasons neither could see, and the sleep (which shapes the
whole multi-day plan) was simply missing. Now sends `sleepH`, `departTime` (the wake time — the
most load-bearing number on a multi-day plan), `meals[]`, and `waterHere`.
- The stop-level fields need **no schema change** — `p_stops` is `jsonb`, stored and returned
  wholesale. The PACE fields below **do** (see `supabase/schema-v9.sql`).
- **Every field optional → pre-v257 events still work** (verified): missing fields fall back to
  the old defaults (`sleepHoursFor`'s ||10, no meals). No migration. `waterHere` stays tri-state —
  never write `false`, that's an explicit "no water here" the organiser never said.
- Killed the two verbatim-duplicated `p_stops` blocks (`_shareQueueRide` + `eventCreate`) — one
  authority now.

**(3b) THE ORGANISER'S PACE TRAVELS TOO — `supabase/schema-v9.sql`, RUN IT BEFORE PUSHING**
(`_sharePacePayload`). **I got this wrong first and Peter caught it.** He'd said sharing a plan
"implicitly includes your speed… that's a rabbit warren"; I read that as *don't send speed*. He
meant the opposite: the plan carries the organiser's speed and that's FINE — the rabbit warren is
trying to *reconcile* different riders' speeds automatically. His actual model: **the organiser
decides the group's pace** (that IS the plan); a race has differing speeds by definition; the
receiver can adjust it, or GPS + adaptive speed fix it on the day.
- **He was right, and the code proves it twice over.** (i) `newRoute()` gives a joiner
  `timeFactor 1.0 / riderPreset 'regular' / loadPreset 'moderate' / no paceSegs` — so a joiner's
  ETAs were neither the organiser's NOR their own: a stranger's. On a social-pace + heavy-load
  plan the toy model measured a **5.6 h gap on a 300 km leg**. (ii) The existing **"share whole
  ride" file has ALWAYS sent** timeFactor/baseTimeFactor/riderPreset/loadPreset/adaptiveSpeed/
  paceSegs (SHARE WHOLE RIDE, ~11840). PackRide was the odd one out — two ways of sharing one
  plan that disagreed.
- **Sends:** `timeFactor`, `riderPreset`, `loadPreset`, `paceSegs` (deliberate per-section
  overrides are plan decisions like a sleep or a meal).
- **THE ELEGANT BIT — the "don't copy someone else's speed" worry is already handled by the
  architecture, for free.** `buildCumRiding` (~1739) is
  `rm = (UI.estModeAdv ? calibRiderMult() : null) || RIDER_MULT[riderSimplePreset(r)]` — so a
  joiner running **Advanced calibration keeps their OWN rider ability**, the organiser's
  riderPreset is simply ignored, and nothing double-counts. Meanwhile `lm` is always the ROUTE's
  loadPreset, so the organiser's load still applies (correct — the load is a fact about the ride,
  not the rider). Verified both ways.
- **NOT sent:** `baseTimeFactor` (the adaptive ±30% drift baseline — `unpackRoute` already derives
  it from timeFactor, and the joiner set it from the plan's factor on decode, so adaptive drifts
  from the organiser's pace rather than fighting a 1.0 the plan never used); `adaptiveSpeed`
  (whether YOUR ETAs self-correct is your setting).
- **ORDER MATTERS, same trap as v256:** the new client sends `p_pace`, which the v8 function does
  not accept. **Run `supabase/schema-v9.sql` BEFORE deploying.** Old clients are fine against the
  new function (p_pace defaults null); a pre-v9 route has `pace = null` → joiner keeps its own
  defaults = today's behaviour exactly. Existing events keep their old route row — re-create the
  event (or just ride it again; `route_ensure` upserts) to republish with pace attached.
- Standing lesson recorded: **when Peter says something is "a rabbit warren", check WHICH part he
  means before deleting a feature.** I removed the wrong half and told him it was his call.

**STILL OPEN from today:**
- **RUN `supabase/schema-v9.sql` BEFORE THE NEXT PUSH** — the client now sends `p_pace`.
- **Nothing here has met a phone or a sim.** The leg ETA wants a multi-day plan with a real sleep;
  ride-now wants a future-dated plan + record; the pace payload wants a two-window PackRide sim
  (organiser on social/heavy, joiner should read the SAME ETAs).
- **The distance bar VISUAL is the next job — and it is ONLY graphics.** Peter's verdict, explicit:
  *"I think graphics is the main problem with the distance bar, not the concept or content"* — and
  he already knew about the 4-second centre rotation (`Math.floor(Date.now()/4000)%3`), it doesn't
  bother him. So **do not redesign the content, the rotation, or the fill scoping**; make the thing
  look good. The one structural note worth carrying in: three text layers sit ON TOP of a sweeping
  fill, so a label rides over dark bg, then fill, then half-and-half — a contrast problem no amount
  of styling fixes, so the fix probably has to separate text from fill rather than restyle it.
  Mockups on Peter's real screenshot, the turn-cue process.
- Leg-end naming uses the SLEEP PIN's name ("Grenfell Motel"), truncated at 12 chars — v215 says
  the TOWN is the cluster's title ("Grenfell"). Cheap to switch via `clusterStops` if Peter prefers.

## Design session — 15 July 2026 (ride-screen consolidation designed & agreed; slice 1 built as v257 above)

The "ride-screen consolidation" open item is now a settled design, mocked in
`_planning/ride-screen-sharing-mockups.html` (9 frames on Peter's real Ride screenshot) +
`_planning/packview-eye.svg`. Decisions, all Peter-approved:

- **ONE button, bottom-left above the weather pill, replaces THREE things**: the share pill,
  the pack pill, and the 1/2 placing pill. Solo ride = the SHARING button; in a PackRide the
  same slot = the PACK button (sharing is implied by being in the ride).
- **Solo states:** not-set-up (grey) / armed (green outline + one-time bubble "Shares when you
  start riding" — this is how the recording↔sharing coupling finally gets EXPLAINED) / live
  (solid green, slow pulse) / off-for-this-ride (dimmed + slash). Tap not-set-up → setup sheet
  IN PLACE (name → mints token + permanent link, ready to copy — no Settings dead end). Tap
  when set up → sharing sheet.
- **Sharing sheet:** universal rule stated ONCE at top ("Links only ever see you while you're
  recording a ride — whichever kind they are"), then: per-ride switch ("Off = ride privately ·
  recording still works"), Copy your permanent link ("Every ride you record · family &
  friends"), Copy a PackView link ("Watch this ride only · expires after it"), Invite a rider —
  PackRide ("Join this ride only · expires after it"). The two temporary kinds deliberately
  share the same sub-text shape so permanent-vs-temporary is unmissable.
- **Naming: "Permanent", not "Family"** (Peter: "Family" annoys people without/not wanting
  family). Change `shareSetup`'s auto-created link label 'Family' → 'Permanent' when building.
- **Per-ride off must REVERT next ride** — a new transient this-ride flag, reset at
  `startRecording`. Today's sticky `UI.shareEnabled` stays as the master switch in Settings.
  (Peter's point: the current sticky-off is WORSE for the safety default.)
- **Pack button tap → ¾ rider list + top ¼ live map strip** zoomed to you + nearest ahead +
  nearest behind. NO name labels on the map — dot colours match the list rows (the list IS the
  legend); outliers become edge chips ("Dave 4.2 km ›"). You highlighted mid-list showing
  placing ("2nd of 5"); gaps are along-route distance only (time gaps lie). The whole strip is
  one giant button → full-screen pack map. BOTH views on countdowns (~8 s, list touches reset
  it): expiry or any tap → map snaps back to the EXACT previous zoom, following you, via the
  v253 peek save/restore. One tap in, ZERO taps required out (the glove rule). NO zoom-scope
  setting yet — nearest-riders fit is the only behaviour until it annoys someone.
- **PackRide creation moves to the Route tab** (logo + words, not logo alone) → popup: ride
  name, join link to copy, update frequency (frequency here, not Settings). NOT mocked yet —
  simple enough to design in code.
- **PackView finally gets its own mark: the EYE** (`_planning/packview-eye.svg` — squarish
  64×52 in a 100 viewBox, stroke-7 like the stopwatch, solid pupil, NO lashes — tried, rejected:
  fuzz at 16 px, off-family, reads cosmetic). Colour locked: **PACKVIEW_CYAN**, and the route
  line STAYS cyan (blue is water's colour in-app; blue route would sink into OSM water + blue
  cycle-route dashes). Until now all three products shared the recoloured stopwatch in
  `_packLogo` — PackRide keeps the three dots, PackTimes the stopwatch.
- **Temporary links keep expiring** (Peter probed "should PackView links live forever for
  replay?" — answer: no; link leakage accumulates, and "where you've been" leaks
  home/route/absence patterns). "Expires after ride" copy is fine; the 48 h grace lives in fine
  print. **Replay of past epics = a possible future deliberate share-a-past-ride feature**
  (mint a fresh link to a finished ride from the Rides card), parked — not a side effect of
  immortal links.

**Build questions flagged, unresolved:** (1) Copying a PackView link BEFORE recording starts —
the ride id doesn't exist yet; likely mint it armed for "your next ride" and attach at
`startRecording`. (2) Frame 8's map strip: the floating pills (speed box etc.) must HIDE while
the peek is open. (3) The sim recipe (one storage per rider) is the test path before any real
ride.

## Session summary — 11 July 2026 (v243 + v244, NOT yet pushed, NOT yet ride-tested)

Everything below in one place, so neither of us has to re-read the long entries. Detail is in the
v243 / v244 sections that follow.

**The big one — turn cues rebuilt (v243).** Peter's insight: the route line already shows the exact
shape of the turn, so an always-on arrow just covers the map. So we now **highlight the route
itself in orange** (`--turn:#f2740c`) through the turn, plus a compact box (glyph + distance +
street) above the elevation strip. Two styles to ride and choose between (Settings → single bold
line vs twin rails); the loser gets deleted. Width-blinks at car-indicator rate in the last 50 m,
stops at the corner, lingers 60 m past.

**Safety model (the part that matters).** RWGPS turn markers sit a *variable* distance BEFORE the
real corner (an export setting, 5–100 m). So everything — distance shown, the ✓, the blink, the
"turn now" beep — keys off the **real corner**, not the marker. `detectMarkerOffset` works this out
per route on import (confirmed correct on real 30 m and 100 m exports); the manual slider only
appears when it can't tell. The ✓ is now *earned*: it only shows once you're clearly past the
corner AND still on route — because at the turn you can still take the wrong road.

**Method rule Peter established (now a standing convention):** route-anchored graphics are drawn ON
the map canvas inside `drawMap`, in the already-rotated frame. Don't hand-compute the rotation in an
overlay — two attempts did and both misplaced the line.

**Fixes from the first real ride test:** map no longer *anticipates* turns (heading window was
looking 300–700 m ahead; now a short window centred on the rider, damped); orange exit leg 40 → 60 m;
power L/R balance maths corrected (a real 49 % was reading as 98); speed pill relaid out with the
unit below the number.

**Smaller things:** simulator gained 1×/2×/5× and now tweens smoothly between sparse points; ride-end
strip gained a **Delete** button; recording deletes are a plain yes/no (was type-"delete"); spacebar
toggles a turn in the Turn Review editor; weather popup now sits in FRONT of the turn box.

**Fonts (v244).** IBM Plex reverted to DM Sans + DM Mono, as real files rather than base64. 19 MB of
Plex source removed from the repo, 132 KB of dead base64 stripped from `index.html`.

**Still open:** stop-peek zoom hides the peeked stop under the +/speed button; the top distance bar
is hard to read (Peter dislikes it); roundabouts are treated as a single corner; generated turns
(geometry-only) need OSM junction context; off-route alert needs a dismiss; and the route colour +
weather should re-time to NOW when a ride starts (diagnosed, not built — `etaAt`'s GPS re-anchor is
gated by `planStartInFuture`, so a future-dated plan stays on its planned clock).

---

## Current status (14 July 2026, v251–v256) — PackRide sim-test fixes + THE ROTATION FIGHT

Fixes from Peter's first two-browser PackRide simulation (desktop, two windows + a
PackView window). **NOT ride-tested.** Note: v248–v250 (PackRide itself — events, join
links, the pack on the live map, the 1/2 placing pill) were built in another session and
are not written up here; grep the `PACKRIDE` banner (~5625) for the model.

**(v252) THE MAP-ROTATION JITTER — three controls genuinely fighting (Peter called it).**
After v251's flip fix the map was still jittery at every bend, at 1× and on the phone.
Peter's diagnosis — "competing controls for aligning with the route and pointing north,
maybe using the phone's heading" — was right on all three counts:
1. **The MAIN per-GPS-tick draw in `updateLive` used `rotate:true` = RAW GPS heading**,
   while every `redrawMap` path used the eased route heading — the map was told two
   different orientations many times a second. Now all live draws go through
   `forceHeading:_rideHeadingDeg(...)` (one authority).
2. **A second old copy of the live-draw branch in `sizeLiveMap`** also rotated by raw
   heading (or north-up) on every resize — address-bar/strip reflows on the phone.
   Replaced with a plain `redrawMap('live-map')`.
3. **`_rideHeadingDeg`'s ±30 m window walked route VERTICES** — points spaced wider
   than 30 m found nothing → silent fallback to raw GPS heading → target flickered
   route-bearing ↔ phone-heading at bends. Now an interpolated chord (binary search,
   ~30 m behind → ~30 m ahead of `gpsDistKm`): never degenerate on-route, and the
   bearing sweeps CONTINUOUSLY through corners.
Also: easing is now TIME-based (close ~2×error/s), not per-call — redraws come from
several timers at once (tween 110 ms / pack 120 ms / blink 130 ms) and per-call steps
beat against each other. Node-verified on a twisty sparse route: dead steady on
straights, smooth 0→90° sweep through a corner, max 14°/s, sparse points no longer null.
**Rider name tags counter-rotate** in `drawPack` (translate → rotate(+`cvs._heading`))
so they stay horizontal on the heading-up map — they read upside down half the time.

**(1) Pack + sharing pills were drawn ON TOP of the distance bar.** Both were hard-coded
`top:8px`, but the ride distance bar owns 6–40px and the floating pills own `top:48px`.
Now `_packPillSync` measures the slot-0 floating pill each pass and sits BOTH pills just
below it on the left edge (falls back to below the bar if no pill row). The share pill is
repositioned there too — its template `top:8px` had the same overlap on solo shared rides.

**(2) Map rotated violently to-and-fro in the start/finish overlap zone.** At ~324 km the
route runs beside its own outbound 25 km leg; the snap flipped between legs, the target
heading flipped ~180° each time, and the 0.18 easing swung the whole map around and back.
Two additions to `_rideHeadingDeg`: **flip rejection** (a >120° jump is held for 2.5 s
before being believed — a ridden switchback never trips it because its bearing sweeps
through intermediate angles rather than jumping) and a **rate cap** (map may not rotate
faster than 60°/s of wall-clock time, so 20× sim or snap jitter can't whip it). Node truth-
tabled: flip-flop = zero swing; real U-turn comes around after the hold; 90° corner and
±15° jitter unchanged.

**Sim-testing PackRide (the recipe, for next time):** one browser window per rider — each
needs its own storage (incognito = one extra rider; Chrome profiles or other browsers for
more). Organiser creates the event; rider 2 opens the `?join=CODE` link. **A rider is only
visible while RECORDING** (sharing transmits only then), so each window must press record
AND run the sim. The "1/2" pill = your placing of the riders the server knows. PackView
`?view=` links are single-rider by design — there is no whole-event spectator page yet.
Sim artefacts, not bugs: watcher speed reads ~20× real (positions arrive 20× fast); the
trail's yellow line jumps ahead of the interpolated dot on each fresh position.

**(v253) Pack pill works + wears the colours.** Tapping the pill did nothing: `zoomToPack`
set the map centre and a `_packFollow` flag that NOTHING read, so the next GPS tick's
follow-draw yanked the map straight back. Now it's a proper PEEK: `_packPeekOn()` gates
the follow branches in `redrawMap` AND `updateLive`'s RAF draw; zoom is saved/restored;
snaps back after 12 s or on a second tap ("Following you"). Pill icon is now three
yellow dots on a diagonal (a paceline — Peter's request; hex #fde047 hard-coded in
`PACK_PILL_ICON` because `PACKRIDE_YELLOW` is declared later in the file), text +
border yellow to match.

**(v254–v255) Pill polish + moved to Peter's spot.** Pack pill icon is now EXACTLY the
mockup mark from `_planning/packride-mockups.html` (three dots in formation, leader +
two behind, viewBox 20). Pill moved to bottom-left, just above the weather pill.
v254 composed inline `bottom` values and landed BELOW the weather pill on the elevation
strip — the weather bar and the pill live in DIFFERENT containers. v255 measures with
`getBoundingClientRect` (container-agnostic, rides up when the bar expands). Share pill
still sits below the speed pill. **Gotcha for anything positioned against another live
overlay: the live-map-section spans more than the map canvas, and overlays are anchored
in different sub-containers — always use rect maths, never compose `top`/`bottom` px.**

**STILL OPEN (Peter's direction, next session):**
- **RIDE-SCREEN CONSOLIDATION (design piece, do it with mockups like the turn-cue
  process).** Peter: "There is a lot going on... it needs to be super simple." Sharing
  pill + pack pill + record button all compete. His ideas so far: the PackRide button
  could BLINK/PULSE to show location sharing is live (one object, two jobs); tap →
  popup listing every rider and their position/gap (big, glove-friendly). Also:
  "recording must be on to share" is fundamentally right (Peter agrees) but currently
  incomprehensible to a user — the UI must EXPLAIN the coupling, e.g. a sharing pill
  that shows "sharing starts with your ride" when armed-but-not-recording.
- ~~Joined riders get a FLAT route~~ **DONE (v256 + schema-v8.sql, Peter's diagnosis was
  exact).** Routes now carry `ele` — whole metres, delta-encoded with the same varint
  scheme as the poly (`_encodeEles`/`_decodeEles`, ~1 B/pt, node-verified exact
  round-trip on 6,000 points). Both `route_ensure` payloads send it; `event_info`
  returns it; `eventRouteToRoute` decodes it (pre-v8 routes have null ele → falls back
  to 0 as before). **ORDER: run `supabase/schema-v8.sql` BEFORE using the v256 client**
  — the new client sends `p_ele`, which the v7 function doesn't accept (old clients
  against the new function are fine; p_ele defaults null). Existing events keep their
  flat route row — create a NEW event (route_ensure upserts) to get elevation across.
  `share_view`/PackView deliberately untouched (no elevation graph there).
- **Joining via a PackRide link should open the PackRide PRESET, not full PackTimes.**
  Peter's sim: the `?join=` link showed the join page, but after joining it boots the
  FULL app ("all features enabled"). The architecture-plan §3.6/§3.7 model is doorways
  set the preset — a rider arriving via a PackRide link should land in the pared-down
  group-ride experience. `event_create` already stores `p_preset`; nothing applies it
  client-side yet.
- **Event PackView (Peter wants this)**: a spectator page for a whole event — one link,
  ALL riders, for a follower at home. **Scoped, needs NO backend change:** `event_pack`
  already accepts a null write token (granted to anon; isYou simply false) and
  `event_info(code)` returns the route poly + stops. So: a `?watch=EVENTCODE` boot mode
  reusing the PackView shell + `drawPack`, polling `event_pack`, plus a "Copy spectator
  link" button in the PackRide settings section.
- **PackView: trail lines OFF by default, as a toggleable LAYER** (like the km-marker
  toggle) — the yellow line drawn between fixes (which also visibly jumps ahead of the
  interpolated dot on each fresh position) shouldn't show unless turned on.
- **PackView: hover on a rider dot → name + some info** (speed / distance / last seen).
  It's a kitchen-table page, so hover is fair game; complements the existing
  tap-a-breadcrumb timestamp/speed.
- Organiser window UX: nothing tells you the other riders can't see you until you record.

## Current status (13 July 2026, v247) — POWER + HEART RATE ARE NOW ACTUALLY RECORDED

**A real hole, found by Peter asking a question: power and HR were never recorded, so they
were never uploaded to Strava.** The sensors were read over Bluetooth, shown live on the Ride
tab pills, and then *thrown away* when the fix was stored. A rider with a power meter got a
bare GPS track on Strava — the one number they care about, missing. Silently, for months.

**Root cause, and the reason it stayed hidden:** four separate places in `_appendPoint`
built a recorded point with their own object literal (first fix / moved-enough / stop marker
/ resume marker). Nobody thought to add sensors to all four, so nobody added them to any.
Fixed structurally: **all four now go through one `_recPt()` builder.** If a field needs to
ride along with a fix, there is exactly one place to add it. Keep it that way.

- **Point shape** gains `hr`, `pw`, `cad`, `bal` — *omitted, not null*, when there's no
  sensor, so a sensorless rider's recordings are byte-identical to before. No migration.
- **FIT** record message gains the standard fields: `heart_rate` (3), `cadence` (4),
  `power` (7). Points with no reading are written as FIT "invalid" (0xFF / 0xFFFF), which is
  the spec's way of saying "no data" — decoders and Strava skip them. Session `sport` was
  already `cycling`, so Strava derives avg/max/normalised power and HR zones straight from
  the per-record values; nothing else needed computing.
- **GPX** gains the standard Garmin extensions — `gpxtpx:TrackPointExtension` (hr, cad) and
  `gpxpx:PowerInWatts`. Same ones Strava/Garmin Connect/every analysis tool already read.
- **VERIFIED against the real Garmin SDK decoder** (`_planning/fit-spike/`, which exists for
  exactly this): integrity true, CRC valid, zero decode errors, sensors present on precisely
  the records that had them and absent on the ones that didn't, sport = cycling.

**Not yet ride-tested with a real power meter / HR strap.** The maths is verified; the
Bluetooth capture path is the untested half.

## Current status (13 July 2026, v246) — LOCATION SHARING + PACKVIEW (Phase 2 begins)

**The one-way door is open: PackTimes now has a backend.** Supabase (free tier, Sydney
region, project `iwlgfkedrkajesgorysz`). Schema is version-controlled in
`supabase/schema-v2.sql` — that file is the source of truth; `schema-v1.sql` and
`schema-v2-patch.sql` are superseded and can be deleted. **NOT ride-tested.**

**The model (Peter drove this, and it's right).**
- **One SHARE = one rider.** A secret `write_token`, minted once by `share_init`, lives
  on the phone in its OWN KV row (`shareAuth`) — deliberately NOT in `uiPrefs`, so it
  never rides along to Dropbox with the rest of the prefs. The phone pushes its position
  **once** per interval, no matter how many people are watching.
- **Many VIEW LINKS hang off it.** Each is an 8-char public code, separately named,
  separately expiring, separately revokable.
  - *Permanent* (`ride_id` null) → follows every ride. Give it to family once, forever.
  - *Pinned* (`ride_id` set + 48 h expiry) → welded to ONE ride. Hand it to a group-ride
    organiser and they can never see any other ride, ever, even by accident.
  - Revoking one link leaves the others alone.
- **Why this shape:** my first cut tied the write token and the view code together 1:1,
  which meant a NEW LINK EVERY RIDE — useless, your wife would need a fresh URL each
  time. Peter caught it. Splitting rider-identity from watch-window is what makes both
  the permanent-family case and the one-off-organiser case fall out for free.

**PRIVACY — the rules, and why (do not quietly erode these).** Full contract in
`architecture-plan.md §7`, which was rewritten today.
- Nothing is EVER sent until the rider deliberately sets sharing up. No token = no code
  path that can transmit. Structural, not a flag.
- Sharing runs **only while recording** (Peter's call — kept the original rule). Pause
  the recording, sharing pauses. Stop it, sharing stops.
- Then it **defaults ON every ride**, with a visible indicator and one tap to kill it.
  The asymmetry is deliberate: thinking you were shared when you weren't could cost you;
  forgetting to turn it off costs you some privacy with someone you already trust.
  **Key argument that resolves the default-on vs off-by-default tension:** for a rider
  who has never made a link, default-on carries the full privacy cost and *zero* safety
  benefit — nobody is watching. Safety only exists once someone holds a link. So
  "off until set up, on by default after" is the same rule applied honestly, not a fudge.
- **Not an emergency beacon, and the UI must never imply it is.** Needs reception, which
  is exactly what you don't have where an accident is worst. Not a PLB substitute.

**SECURITY.** The publishable key is in `index.html`, which is public on GitHub — so
assume everyone has it. Both tables have **RLS on with ZERO policies**, so the key cannot
touch them directly at all. Everything goes through narrow `security definer` SQL
functions (`share_init`, `share_set_label`, `link_create`, `link_list`, `link_revoke`,
`share_push`, `share_view`). Holding a view link lets you WATCH and nothing else — there
is no path that returns a write token. Guessing a view code is 32^8 ≈ 1.1 trillion tries.
Accepted limit: anyone with the key can call `share_init` and make junk shares; costs us
rows and nothing else. **Gotcha:** pgcrypto lives in the `extensions` schema on Supabase,
so every function needs `set search_path = public, extensions` or `gen_random_bytes` is
not found.

**PACKVIEW is the same file, not a second app** (Peter's reasoning, and it's the strongest
argument in the room): two codebases = two map engines = every map fix has to be remembered
twice, and that's what rots side projects. So `index.html?view=ABC123` boots into
`renderViewer()`, which replaces the WHOLE `#app` shell — no tabs, no settings, nothing to
install — and reuses the real `drawMap`. Checked the load cost first because Peter made it
a condition: 875 KB raw but ~180 KB gzipped over the wire, once, then cached. Less than a
phone photo. `_render()` bails early when `_viewCode` is set (there's no content-wrap to
render into). `redrawMap('view-map')` is special-cased like `rec-detail-map`.

**Code map:** new `LOCATION SHARING` + `PACKVIEW` banner sections sit between STRAVA and
RIDE SIMULATOR (~5206). Hooks: `_shareMaybePush` fires from the top of `_appendPoint`
("one capture, two destinations" — a failed push never affects the local recording);
`startRecording`/`finaliseRecording` reset `_shareLastPos`; Settings gets a
`📍 Location Sharing` section; the Ride tab gets a `#share-pill` indicator (only rendered
while genuinely transmitting, tap to stop).

**Offline behaviour:** `_shareFlush` drains the queue oldest-first, strictly sequentially,
and stops dead at the first failure. No reception = points WAIT (persisted in the
`shareAuth` KV row, so a crash doesn't lose them). Nothing is ever dropped because a push
failed — ride back into signal and the whole backlog lands, filling the trail in behind
you. Retry triggers are the same set Strava's queue uses (`online`, `visibilitychange`).

**Interval:** default 60 s (Peter wants it fast for testing). Most dot-watching sites use
5–10 min; slower is kinder to the battery and no watcher needs better. Slider is 15 s–5 min.
High-frequency mode is a Phase 4 / PackRide concern.

**STILL OPEN:**
- **Nothing in v246 is tested on a real ride.** Desktop/SQL only. Two things a ride must
  prove: positions actually land at 60 s intervals with the screen off, and the queue
  drains correctly after a reception blackout.
- ~~PackView shows the breadcrumb trail only~~ **DONE (schema v3).** PackView now draws the
  **planned route + stops** underneath the yellow breadcrumb trail — same `drawMap` the Ride
  tab uses. The route is uploaded once per route (`route_ensure` upserts on `route_key`, so
  re-riding is free and editing republishes), as an encoded **Google polyline** — a
  6,000-point / 300 km route is **24 KB**, vs 118 KB as raw JSON. `rides` links a ride to its
  route, which is what lets a *pinned* link show the right route for its one ride while a
  *permanent* link follows the rider onto the next. Queued through the SAME retry machinery
  as positions, so a ride started in a dead spot gets its route up when signal returns.
  **Peter's argument for defaulting route-sharing ON, and it's the right one:** in an
  emergency the PLAN can matter more than the position — a plan is searchable when a
  position is stale or was never sent. Family should have it; a group ride already has the
  route; a public event publishes it anyway. If a "position only" link is ever wanted, add a
  `show_route` flag to `view_links` — the plumbing is already isolated for it.
- PackView extras built alongside: map-style switcher (Map/Satellite/Cycle/Topo — just sets
  the existing `_tileMode` global), km-marker toggle (new `opts.noKm` in `drawMap`), tap a
  breadcrumb for its timestamp/speed (its OWN hit test — the map engine's `tapCb` path runs
  `hitTest`, which calls `cur()`, and PackView has no current route), follow-the-dot with a
  Recentre button when the watcher pans away, and its own yellow (`PACKVIEW_YELLOW` #fde047
  — NOT `--amber`, which is the warning colour and reads orange).
- **ETAs / next stop are still not shown** in PackView. The stops are on the server now, so
  this is mostly a rendering job.
- No **data retention/expiry job** yet (privacy promise 8 says delete after ~7 days).
  Supabase free tier has `pg_cron`; wire it up before anyone but Peter uses this.
- Supabase free projects **pause after 7 days of database inactivity** (~30 s wake on the
  next request; the phone's queue retries straight through it, so nobody sees it). The
  real tail risk is a *very* long layoff — a twice-weekly keep-warm ping kills it. Not
  built yet.
- Accounts, paid tiers, and using the same backend to replace flaky Dropbox sync: all
  deliberately parked. Get the technical pipe solid first (Peter).

## Current status (13 July 2026, v245) — ride-test fixes

**v245 (13 Jul 2026) — four fixes from Peter's 12 Jul ride test. NOT yet ride-tested.**

**(1) Slow startup with no reception — ROOT CAUSE FOUND.** The SW served the page
**network-first with no timeout**. With no signal the radio does NOT fail fast — `fetch`
sits there 30–60 s before rejecting, and `respondWith` blocks the paint the whole time.
Peter hit this at a ride start and thought the app had hung. Fixed with a **2-second
leash**: `navigator.onLine` false → straight to cache; otherwise race the network against
a 2 s timer, and if the timer wins, serve the cached app NOW and let the fetch finish in
the background (`e.waitUntil`) to refresh the cache for the next open. Accepted trade-off:
on a slow-but-working link a new push can land one open later than before; on a good link
the fetch beats 2 s and nothing changes. Everything ELSE at startup was already local —
IndexedDB, `font-display:swap` + SW-cached woff2, and `dbxAutoLoad` fires *after* `render()`.
So this was the only network dependence in the boot path.

**(2) Off-route alert — three real exits (Peter's design).** The old "Got it" felt like it
only delayed the alarm. It did dismiss the episode, but the **escalation rule re-fires the
full alarm every 50 m further from the route** — and on a detour you're continuously getting
further away, so it re-fired almost immediately. New `_offRouteMode` (null | 'ack' | 'detour'
| 'abandoned') drives three buttons:
- **Got it — turning around** (`ack`) → alarm stops but STILL escalates if you keep straying.
  (Peter wanted to keep this; it's the safety net.)
- **Taking a detour** (`detour`) → fully silent however far you go; **auto-re-arms the moment
  you rejoin the route**, so a later unintended departure alarms again.
- **Stop following this route** (`abandoned`) → silent for the rest of the ride. Deliberately
  does NOT re-arm on rejoining (brushing past the line shouldn't restart the alarms); cleared
  only when GPS/recording stops, via `_offRouteReset(true)` in `stopGPS`.
`_offRouteReset(clearMode)` is the single reset. **Idle auto-pause deliberately does NOT clear
the mode** (parking for a coffee mid-detour must not re-arm the alarm); only `stopGPS` and a
fresh sim start do. Buttons are full-width and tall — this gets tapped with numb hands in gloves.
Verified via an 8-scenario node truth-table (ignore/ack/ack-and-keep-straying/detour/detour-
rejoin-stray-again/abandon/never-off/brief-excursion) — all correct.

**(3) Stops-tab map now shows your position.** It drew with `showGPS:false`, so there was no
dot. Now `showGPS:true` for `stops-map` + `desktop-map`, and **never `followGPS`** — these maps
pan and zoom freely and must stay where you left them (the point is working out a detour
mid-ride). **No battery cost**: drawing the dot is free and we never switch the GPS on
ourselves. Also surfaced the **GPS toggle + crosshair buttons** on `stops-map` — both were
already built in `mapCtrlHTML` but only ever *inserted* for `live-map`
(`${mapId==='live-map'?gpsBtn:''}`, and `recenterBtn` gated on `showGPS` which was passed
`false`). That's why the desktop crosshair appeared to do nothing: it re-centred on a GPS
position that was never drawn. The delegator already routed `#btn-gpstoggle` to a plain GPS
toggle when `UI.tab!=='live'`, so no handler change was needed.

**(4) Record button.** The green play triangle read as "play a video", not "record a ride".
Now camera-app language: **idle = white button, red record dot + "REC"**; **recording = SOLID
red, white pause bars**; **paused = SOLID amber**. The washed-out recording red Peter
complained about was `@keyframes recpulse` animating the background between two *translucent*
reds (`rgba(...,.10)` → `.22`), which **overrode the button's inline fill** — now it breathes
between two solid reds (`#f87171` ↔ `#dc2626`).

**Deliberately NOT changed: ride-map pan.** Peter reconsidered — zoom-only is genuinely good
on a vibrating bar, pan gets confused with zoom and you can shove the map off-screen with numb
hands. (For the record, the *reason* pan appeared broken: it works, but the next GPS fix yanks
it back because `redrawMap` passes `followGPS:true` on `live-map` whenever GPS is on. If we ever
revisit, the fix is a pan-hold flag reusing the existing `_liveFitReturnTimer` snap-back pattern.)

**Known limit, not fixable in a PWA: GPS re-acquire after screen-off.** No signal → no
assisted-GPS → the chip does a cold fix, several seconds. That's hardware. The real answer is
the Phase 1b Capacitor wrap. Possible sop: show the last known position greyed with
"acquiring…" instead of looking frozen.

**(5) Ride-stop / save windows reworked.** Peter's screenshots. (a) FONT: "Stop ride", "Stop
ride?", "Recording saved" and the ride-name input were all on `var(--font)` = **DM Mono** —
that's the NUMBERS font, so words rendered as typewriter text. DM Mono is for figures only;
everything prose is `var(--sans)`. (b) The stop-confirm popup is now a centred panel with the
three actions stacked FULL-WIDTH in a column (was a cramped row of three small buttons):
**Stop & save** (green, primary) / **Back to ride** (neutral) / **Delete ride** (SOLID red).
"Cancel" → "Back to ride" because you can only reach this panel from a PAUSED ride, so it
returns you to paused — "Continue recording" would be a lie. (c) The **ride save modal** was
doing three unrelated jobs with equal weight; now three visually separate boxes in the order
they happen: ✓ Ride saved (a statement — the ride is already on disk AND already queued to
Strava by then, nothing here can undo it) → Name → Optional "use as a speed sample" (dashed
card). The old **"Dismiss" button silently THREW AWAY the name you'd just typed** — removed
entirely; one "Done" button, and the checkbox is the only real choice.

**(6) Button/colour system.** New tokens `--red2:#dc2626` / `--red3:#991b1b`: `--red` (#f87171)
is a light salmon — fine as text or a thin outline on dark, but as a FILL it reads PINK (that's
what Peter saw on the recording button). New `.btn-d` = solid destructive red (`.btn-r`'s faint
outline was so subtle he never registered Delete as dangerous). **`.btn` now defaults to
`justify-content:center`** — it was left-aligned, invisible on shrink-to-fit buttons but wrong on
any button forced wider than its label (the Delete/Cancel confirm rows, Duration/Wake-at,
+Meal/+Snack). **Colour discipline, keep it:** red is RESERVED for *recording* (live) and
*delete* (destroys). "Stop ride" is deliberately neutral — stopping isn't irreversible, it just
opens the save panel. Resume is GREEN (a button's colour describes its ACTION, not the state;
amber means caution and there's nothing cautionary about carrying on).

**(7) Recording control — text where you can afford it, icon where you can't (Peter's rule).**
The state model wasn't legible. Now: **Idle** → wide dark button, red dot + "Start ride".
**Recording** → small 52px solid-red square, pause bars, blinking (you're RIDING; the map
matters — this is the only state that can't afford words). **Paused** → green "Resume ride" +
neutral "Stop ride". The blink is now a DISCRETE `steps(1,end)` flip between two true reds: the
old smooth ease-in-out crossfade passed through a pink midpoint and a gradual pulse is hard to
perceive at all. Map controls now sit on the RIGHT on desktop too (mobile always did; desktop
just fell through to `.map-ctrl`'s `left:8px` default — an unset value, not a decision).

**(8) Fit-route (⛶) + crosshair REMOVED from the ride map while a ride is live.** They're
coupled: the ride map follows GPS continuously, so the crosshair has nothing to recentre; the
only way to get off-centre is fit-route, which zooms out to the whole route on a screen where
panning is deliberately disabled. Kept when GPS is OFF — the map is then a plain pannable map
and with no fit button you could strand yourself. Both stay on the Stops/desktop maps. Also
squared the tile button on the ride map (its `width:auto` made it narrower than the 52px
record button beside it).

**(9) Sample rides — eviction is now redundancy-based, not oldest-first (REAL BUG).** Peter asked
whether near-identical rides should be blocked. They shouldn't, and the maths says so: each
sample reduces to `factor = actual ÷ predicted` where the prediction already accounts for that
ride's surface/elev/load — so the factor is a pure rider-ability number, and `calibFactor` is a
distance-weighted mean of them. Ten identical rides therefore give the SAME answer as one (no
distortion), and while there's room they're actively useful — repeated measurements cancel out a
one-off headwind or bad day. The real bug was eviction: with the list full, `_recCalibAdd` retired
the **oldest recorded ride**, so riding the same loop weekly would silently flush out your one big
gravel epic — the most informative sample you own. Now `_calibDiff` / `_calibRedundancy` score how
much a sample says that another sample doesn't (surface mismatch = fully different evidence; plus
relative distance, climb rate, and the resulting factor), and the most REDUNDANT recorded ride is
evicted instead. Verified: full list of 9 commutes + 1 gravel epic + a new commute → old code
deleted the epic, new code drops a middle commute. Manual samples still never auto-evicted; the
toast names what was displaced so an eviction is never silent.

**(10) Sample rides — limit 10 → 20, and the Advanced Estimation screen reorganised.** Storage is
nothing (a sample is ~8 numbers), and with redundancy eviction a longer list keeps MORE variety,
not more clutter. Screen was upside-down: a wall of instructions first, the one number it exists
to produce buried at the bottom. Now **headline factor card at the top** (big `0.64 ×` + "You ride
about 36% faster than an average rider" + sample count), a two-sentence plain-English "what a
sample ride IS", the long how-to-choose guidance folded into a `<details>`, and the sample list
**hidden behind an "Edit sample rides (N)" toggle** (auto-opens if there are no valid samples yet,
or one is half-finished). **AGE IS DISPLAY-ONLY AND MUST STAY THAT WAY (Peter's rule).** Samples now
carry `ts` and the list shows "2 yrs ago" etc., but the factor maths ignores it and nothing evicts
or decays by age — because *the rides that matter most are the rare ones*: a 400 km ultra happens
once every year or two, so it is inherently the OLDEST sample AND the most informative one for
planning another ultra. Age-decay would delete precisely the evidence you need. Redundancy eviction
already protects them (a one-off ultra has no near neighbour → never the victim). Verified: list of
20 (2 old ultras + 18 recent road rides) + a new road ride → old code evicted the 2-year-old Hunt
1000; new code drops a middle road ride.

**(11) Faff uplift — the "non-stop segment" trap (REAL accuracy bug).** PackTimes does NOT model
short stops as stops; it bakes them into the rider factor (the v179 "faff rule": stops under
15 min count as ride time, longer breaks excluded). So a sample taken from a **Strava segment or
any non-stop effort contains NO faff** — no bottles, layers, gates, snacks — and produces an
artificially fast factor that makes **every plan optimistic**, by 10–15% (hours, on a 400 km
ultra). The help text told people to add 10–15% by hand; nobody would. Now a per-sample checkbox
**"Add 15% faff — this was a short non-stop effort (e.g. a Strava segment)"** (`s.nonstop`, new
field, undefined/false = old behaviour, so existing samples are untouched) multiplies the sample's
hours by `CALIB_FAFF_UPLIFT` (1.15) inside `calibRideFactor`. Collapsed rows show `· +15% faff` so
an uplifted sample never hides it. **Why 15% not 10% (Peter):** the figure is a generalised guess,
not a measurement — so take the top of the range, because the failure modes aren't equal. Too much
faff → pessimistic plan → you arrive early with daylight in hand. Too little → optimistic plan →
you're short of the next stop as the light goes. Erring slow is the safe direction to be wrong in.

**(12) Advanced-estimation copy.** Sample list was rendered in BOTH the Speed Estimation modal and
the Edit Sample Rides popup — so "Edit sample rides" looked like it re-opened the same thing. The
summary screen now shows only the factor + "Based on N sample rides you've done"; the list lives
only on the screen whose job is to edit it (no show/hide toggle there — that popup IS the list;
header + Save footer fixed, one scroll container, no nested scrollbars). Opening line now covers
both routes in: *"a ride you've actually done — whether you recorded it in PackTimes or entered it
by hand"*. The wall of guidance is broken into five headed sections. Note the surface guidance is
deliberately soft — *"Keep rides to a single surface as much as possible"* — because a pure
single-surface ride is rare and the old wording implied a standard nobody can meet.

**(13) Eviction refined — of two SIMILAR rides, the OLDER one goes (Peter's rule).** Redundancy
alone could evict any member of a cluster. Now `_recCalibAdd` takes everything within a tight band
(`CLOSE = 0.10`) of the most-redundant score and drops the **oldest** of them: two similar rides say
the same thing about your ability, so keep the one that says it about your CURRENT ability. Samples
with no `ts` (pre-v245) count as oldest and retire first. **Simulated 370 rides over 3 years** (70%
commutes): final list = 10 commutes, 5 weekend road, 2 gravel days, 2 big bikepacking, 1 ultra —
i.e. it converges on a diverse spread, and rare rides are massively over-represented vs how often
they're ridden. **Honest caveat Peter accepted:** an old ultra IS eventually replaced — but only by
a NEWER ultra, never by a commute. The list is a slow rolling window, not a permanent archive.

**(14) Sample rides got NAMES, an Edit affordance, and a per-sample Save.** Three separate
"the app knew but never said" bugs Peter found by using it:
- **Name** (`s.name`, optional, first field): recorded rides always carried one; hand-entered ones
  were an anonymous row of numbers you couldn't identify — or audit — six months later. A sample
  silently scales EVERY estimate, so being unable to recognise one is a real reason not to trust it.
  Rows now lead with the name; renaming a recorded sample keeps its `recId`/`src`/`ts` intact.
- **Edit button** on each collapsed row. The row was always tappable but showed only a ✕, so the
  list read as view-and-delete — there was no way to discover the editor existed.
- **"Save this ride"** inside each sample box. The popup edits a DRAFT and only wrote on the footer
  button, which also closed the window — so there was no way to bank one ride and add another.
  `_calibCommit()` is now shared by both paths, so neither can half-save. Incomplete samples refuse
  to save ("Add a distance and a ride time first") rather than vanishing.
- `_calibScrollTo(i)` brings the open card into view: reveal the BOTTOM (so Save is visible) but
  never push the card's TOP off (you can't fill in a form you can't see). Card taller than the
  scroll area → top wins.

**(15) Copy: less of it.** Peter's verdict on my first explainer: *"good for the tech head, but the
average person won't read or understand it"* — and he was right; it explained the implementation
(distance-weighted mean, per-sample factors) rather than what a rider needs. The whole "How your
rider factor is worked out" section was DELETED. Sample Rides now opens with the headline number
and two sentences: what a sample is (recorded or hand-entered → faster/slower than an average
rider), and that it keeps up to 20 covering different distances/surfaces/loads, dropping older
similar ones as new rides come in. The long practical guidance stays, collapsed, behind "How to
choose a good sample ride". **Standing lesson: the reasoning belongs in CLAUDE.md and code
comments; the app only says what a rider must act on.**

**(16) Popup renamed "Advanced Estimation" → "Sample Rides".** "Advanced Estimation" is the name of
a MODE (the Basic/Advanced toggle). Reusing it for the popup that edits the rides the mode feeds on
was a genuine collision. The mode keeps its name; everything pointing at the popup now says Sample
Rides. Also: the desktop map's controls are **hand-written static HTML** (`desktop-map-ctrl`), NOT
built by `mapCtrlHTML` — which is why it never had a crosshair despite my saying it would keep one.
Added `data-recenter="desktop-map"` there. Deliberately NO GPS toggle on it: the id would collide
with the Ride tab's recording button (both `#btn-gpstoggle`).

**STILL OPEN / NEXT SESSION:**
- **Nothing in v245 is ride-tested.** Pushed 13 Jul 2026 after a desktop smoke test only.
- Two things only a real ride can prove: (a) the **SW 2-second leash** — the startup hang only
  reproduces with no reception; if the app ever feels SLOWER to open on good signal, that's the
  leash misbehaving. (b) the **off-route 'detour' mode** — it must stay silent however far you
  stray, then auto-re-arm the moment you rejoin the route.
- Carried over from v243/v244: roundabouts treated as a single corner; generated turns (geometry
  only) need OSM junction context; stop-peek zoom hides the peeked stop under the +/speed button;
  the top distance bar is hard to read; route colour + weather don't re-time to NOW when a ride
  starts (`etaAt`'s GPS re-anchor is gated by `planStartInFuture`).
- Phase 1b (Capacitor wrap) still gated on a couple of clean soak-test rides. Don't push it.

## Current status (11 July 2026, v244)

**v244 (11 Jul 2026) — IBM Plex reverted → DM Sans + DM Mono, shipped as REAL FILES (v242
undone).** Peter never liked the Plex figures and asked for a reason to keep it; there wasn't
one, so we reverted. Two decisions worth remembering. (1) **Not embedded.** v242's rationale for
base64 (`@font-face` inline = offline-safe with no SW work) doesn't actually buy anything: the
SW already caches the shell + tiles, so it can cache six woff2 files just as reliably, and the
worst failure is a system-font fallback rather than a break. Peter's call: *"unless there is a
clear advantage… not having to embed fonts is the winner."* So the fonts now live in `fonts/`
(`dm-sans-latin-{400,500,600,700}`, `dm-mono-latin-{400,500}`, all from `@fontsource`, ~85 KB
total) and the SW **precaches them on install** (`FONTS` list built from `BASE`, `addAll` wrapped
in a `.catch` so a missing font can never fail the install) and serves any same-origin `.woff2`
**cache-first**. Note the SW is a template literal — do NOT put a `\.` regex escape in it (the
backslash gets eaten before the SW sees it); the font test uses `endsWith('.woff2')` on purpose.
(2) **DM Mono is still needed for numbers.** I initially told Peter DM Sans had tabular figures —
**that was wrong**: DM Sans has no `tnum` feature and its digits are genuinely proportional (a "1"
is 312 units vs a "0" at 684), so live numbers would jiggle and columns wouldn't line up. So we're
back on the original style-guide system — `--sans:'DM Sans'` for UI/prose, `--font:'DM Mono'` for
numbers/metrics — no exceptions. The turn-cue distance (`.tc-dist`) was on `var(--sans)` in v243
because Peter disliked the PLEX mono figures at that size; DM Mono is a different font and the
countdown (250→240→230 m) is exactly the wobble case, so it's now on `var(--font)` weight 500
(DM Mono only ships 400/500 — don't ask it for 600). Flip back to `var(--sans)` if he dislikes it.
DM Mono's zero is also slashed. The canvas code
(`drawMap`/elevation, ~6315/6347/6379/9438/11401) already asked for `'DM Mono'` by name, so those
resolve properly again. **Cleanup DONE:** the five dead IBM Plex base64 `@font-face` lines were too
large to hand-edit and the bash sandbox sees a truncated copy of `index.html`, so Peter ran a
throwaway `strip-plex-fonts.ps1` on his machine (980 KB → 848 KB; backup at
`backup/index-v244-pre-plex-strip.html`). The script and its `.bat` wrapper have since been deleted.
The 19 MB of Plex source (`IBM_Plex_Sans/`, `IBM_Plex_Mono/`, `ibm-plex-mono.zip`,
`fonts/ibm-plex-*.woff2`) is gone too. **Gotcha if you ever write another `.ps1` for Peter:** keep it
PURE ASCII and hand him a `.bat` wrapper (`powershell -ExecutionPolicy Bypass -File …`). PowerShell 5
reads `.ps1` as Windows-1252 without a BOM, so a UTF-8 em-dash decodes to a smart quote — which it
treats as a string delimiter, giving a baffling "string is missing the terminator" parse error. And
`.ps1` files don't run on double-click by default. Both bit us. Not yet ride-tested.

## Current status (11 July 2026, v243)

**v243 (11 Jul 2026) — turn cue reworked: HIGHLIGHT THE ROUTE, don't cover it (long design
thread with Peter, all mocked as composites on his real Ride screenshot in `_planning/GPS
Screens/`).** Peter's insight: PackTimes always shows the map + route line, so the exact turn
shape is already on screen — a big always-on arrow just blocks it. New model, agreed after
iterating mockups: retire the grow-on-approach glyph overlay; instead **highlight the route
itself** through the turn in ORANGE (`--turn:#f2740c`, new token). Two styles, switchable in
Settings (evaluation toggle `UI.turnIndicator` = `'single'` bold line | `'rails'` two lines
either side that keep the underlying route colour visible between them — Peter wants to ride
both and pick; delete the loser later). The orange segment spans from the alert distance,
through the turn, to ~30 m past. Steady until the final ≤50 m, then a **car-indicator-rate
width-BLINK** (~0.35 s each, thin↔thick, never fully off — so you can't miss it in an "off"
phase; via the `.blink` CSS class + `@keyframes tcLine/tcCase`). Blink stops at the corner; the
orange then **stays lit until you've ridden past the END of the drawn segment** (`marker + after`,
along-route in `_activeTurn` via `showOrange`), THEN advances to the next turn — UNLESS the next
turn's window has already opened while you're still on this one, in which case it hands straight
over (the demote guard). **The distance+direction BOX is ALWAYS visible** for the next turn
(counts down from any distance; `showOrange` only gates the on-map orange, not the box). SIM: at
low speed / sparse points the desktop sim jumped every few seconds — `simStart` now **tweens**
(`_simTweenTo`) the marker + map across gaps >180 ms so motion is smooth; per-point logic (alerts,
recording) still runs on arrival. Historical note: the older model cleared the cue via the
straight-line alert distance (turned off ≈ at the corner) — UNLESS the next turn's window had
already opened, in which case it jumped
straight there (guards the common quick-one-after-another case). A compact box (manoeuvre
glyph + distance + street) sits **above the elevation strip**, low enough that the rider dot
stays visible above it. Number uses **Plex Sans** (`var(--sans)`, proportional) not Plex Mono
— Peter disliked the mono figures at small size; DM Sans was his ideal but isn't embedded, so
Plex Sans is the zero-cost middle ground (embed DM Sans later if he still wants it).
Implementation (all `index.html`). **The highlight is drawn ON THE MAP CANVAS, inside
`drawMap`'s already-rotated frame** (the turn-highlight block just before the GPS-arrow block),
using the SAME `px`/`py` as the route line — so it rides the route exactly and the map's own
heading-up rotation (v207) carries it, with NO separate rotation maths. (Two earlier attempts
drew a separate SVG overlay and re-computed the rotation by hand — both misplaced the line; the
lesson, per Peter: draw it on the map and let the existing rotation do the work.) `_activeTurn(r,
liveDist)` (shared by the map draw + the box) picks the turn; `_turnSegPts` builds the highlight
from real route points spanning `nt.dist` (reliable/monotonic; NOT lat/lon which mis-snaps) — from
backKm before to fwdKm past, interpolated endpoints (`_ptAtDist` is binary-search). KEY (Peter,
confirmed by exporting the same route at 30 m vs 100 m turns): the imported RWGPS turn point is a
HEADS-UP trigger placed a VARIABLE distance (RWGPS setting, **5–100 m**) BEFORE the corner, never on
it. So there's no fixed forward distance that both stays tidy and always reaches the corner — a
short forward misses far corners, a long one over-runs near ones. **SAFETY MODEL (Peter, corner-relative — the important bit):** using the marker for distance/‌"done"
fired the ✓ ~30 m BEFORE the rider had actually turned (dangerous at night/fatigued — you could
still take the wrong road) and the countdown lied about the real corner. Fixed via **Option A**: a
`turnMarkerOffsetM` setting (default 30 m, matches the RWGPS export; slider `turn-off-sl`). The real
corner = `marker.dist + offset` along the route (ground truth — RWGPS places the marker exactly that
far before the maneuver, same for every turn in an export). `_activeTurn` computes `cornerOf(t)` and
keys EVERYTHING off it: distance-to-turn (straight-line to the corner), the past/✓ state
(`liveDist>corner`), blink (stops at the corner), linger (until `corner+after`). The orange's APPROACH side = the alert
distance (`turnAlertM`, where it appears); its EXIT side = a FIXED 40 m past the corner (linger +
exit leg). (`turnHlBeforeM` and `turnHlAfterM` were both removed as sliders — scope-creep cleanup —
merged into the alert distance / hard-coded 40 m respectively.) The marker-offset slider is now
**hidden when auto-detect succeeds** (shows just the detected value; slider only appears as a
fallback). Audio toggle moved to a sub-option under Alert distance. The Alerts settings section was
reorganised into **Turns / Stops / Off-route / Screen** groups; `turnAlertM` = the turn "wake-up"
distance (beep + orange appears + approach start + future screen-wake). Twin-rails now use a proper MITRE (`_tcRailsPts`, offset
g/cos(half-angle)) so the outer rail no longer cuts the corner. Chose A (deterministic ground truth) as the base over B (geometry scan) because the cue is
safety-critical and geometry can mis-fire. **Option B now built on top (Peter's design):**
`detectMarkerOffset(r)` scans a spread of up to 8 turns, measures each marker→sharpest-bend distance
(`_tcHdg`/`_tcAngDiff`, ~25°+ bend within 150 m fwd), and if they CORRELATE (≥60% within ±15 m of
the median) returns the rounded median — else null. `_markerOffKm(r)` caches it on `r._moffM`
(undefined=not scanned, null=no reliable result, number=m) and is used by `_activeTurn` + the audio;
falls back to the manual `turnMarkerOffsetM` slider when detection can't tell. Settings shows the
auto-detected value per route. Edge case: two turns closer than the offset — RWGPS clamps the marker,
so a fixed offset slightly over-shoots the corner (still far better than marker-based). `_ptAtDist`
is binary-search. `_tcRailsPts` offsets the twin rails. Width blinks
via a `Date.now()` phase in `drawMap`; `renderTurnCue` now only manages the **box** (glyph +
distance + street, HTML, above the elevation strip) and drives the blink by calling
`redrawMap('live-map')` on a ~130 ms timer while in the blink window (cleared when the turn
passes). **Settings:** turn-alert range widened 50–500 → **20–250 m, default 50**
(RWGPS exports default ~30 m, so 30 m + city-tight values must be options; 500 m retired);
new "Turn indicator style" radio (single/rails). Persisted in `uiPrefs` (`turnIndicator`);
`UI.turnAlertM` default 50, `turnIndicator:'single'`. Audio cues (checkAlerts two-stage
heads-up + "now") were later made CORNER-relative too (add `offKm`), so the "turn now" beep sounds
at the real corner not ~30 m early at the marker. Node-verified all
three edited fragments (renderTurnCue+helpers, the alertsBody template, the change-listener).
NOT yet ride-tested. Auto-detect (`detectMarkerOffset`) CONFIRMED working on clean RWGPS exports
(30 m and 100 m both detect correctly); the visible "Scan:" diagnostic was pulled once confirmed
(the internal `r._moffDiag` string is still built but unread — harmless, excluded from packRoute).
Method that worked: strongest bend from marker up to the NEXT marker (cap), ±12 m heading arms,
densest-cluster (mode) of ~20 sampled turns, ≥50% cluster to accept else fall back to the manual
slider. Genuinely inconsistent/legacy routes correctly decline → manual 30 m + the on-route ✓ gate.
**First real RIDE TEST done (Peter) — fixes made:** (a) map was rotating to *anticipate* turns —
`_rideHeadingDeg` looked 15 route-points ahead (300–700 m); now a short ~±20 m window centred on the
rider so it shows current direction, rotates only *as* you turn; (b) orange exit leg 40 → **60 m**
past the corner (clearer past the turn); (c) **power L/R balance maths** was wrong (`_parsePowerMeasurement`
masked bit 7 + skipped the ÷2 → a real 49 % showed as 98) — now `Math.round(byte/2)`; (d) **speed pill**
relaid out — big number centred with the unit *below* it (was "km/h" off to the right). STILL OPEN from
that ride: **stop-peek zoom** puts the peeked stop at the top, hidden under the +/speed button and the
ride-info pill (and the heading rotation swings it out) — reposition + maybe hold rotation during a
peek; and the **top distance bar** graphic is hard to read (Peter dislikes it) — redesign, secondary.
OPEN / next: (1) **ROUNDABOUTS** — the cue treats a roundabout as a single corner + 40 m, but a
roundabout is a sequence (enter → arc → exit N, often 50–150 m), so the orange barely reaches the
exit. Proper fix = detect roundabout cues (FIT/TCX carry "Exit N"/roundabout info) and highlight the
whole entry-to-exit arc; parked as its own task. (2) **Generated turns need ROAD CONTEXT** (Peter):
`autoDetectTurns` (used for track-only GPX like Komoot exports) works from geometry alone, so it
can't tell a road curve from a junction-turn — a real reliability step-down from authored FIT/TCX
cues. Proper fix = cross-check each geometric bend against OSM road **junctions** (same Overpass pipe
we already use for POIs/surface): bend + junction = real turn; bend + no junction = just the road
curving, drop it. Big step up from pure geometry (not perfect — rural OSM gaps). Parked as its own
task; for now steer riders to RWGPS FIT. (3) off-route alert needs a proper dismiss (till next turn /
entirely) — annoying, parked. May want to tune blink rate, segment length, rail gap, exact orange
after a real ride.

## Current status (10 July 2026, v242)

**v242 (10 Jul 2026) — IBM Plex fonts embedded (Claude design pass, folded in by me).**
Peter had "Claude design" do the font pass and handed back `PackTimes.html`. I verified it
was built on v241 (kept `TURN_GLYPHS` + `renderTurnCue` intact), switched the tokens to
`--sans:'IBM Plex Sans'` (UI/prose) + `--font:'IBM Plex Mono'` (numbers/metrics), and —
crucially for the offline PWA — **embedded all 5 woff2 as base64 `@font-face`** (Plex Sans
400/500/600 + Plex Mono 400/500), zero external font refs, so no service-worker font
caching needed and it works offline self-contained. Checked: file ends clean, both inline
`<script>` blocks pass `node --check`, fonts present. Backed up the old file to
`backup/index-v241-pre-plex.html`, renamed `PackTimes.html` → `index.html`, bumped
`APP_VERSION` v241 → v242. NOTE: the standalone `fonts/` woff2 folder I created earlier is
now redundant (fonts are inlined) — left in place, Peter can delete. STILL OPEN: the turn
cue's number/road label are still the **system-sans placeholder** (set inline in
`renderTurnCue`, so the CSS font pass didn't touch them) — point them at Plex Mono/Sans
when Peter's ready. Not yet ride-tested.

## Current status (10 July 2026, v241)

**v241 (10 Jul 2026) — turn cue now uses professionally-drawn glyphs (Peter's "vector
graphics" push).** After a long visual iteration (all previewed as composites on Peter's
real Ride screenshot + an arrow-set HTML, in `_planning/`), replaced the procedurally-bent
arrow (which looked "bitmap clunky" / heads didn't align) with a set of eight **designed
manoeuvre glyphs**: straight, slight/normal/sharp × left+right, u-turn. Key method change
Peter steered: each glyph is a SINGLE outline shape (shaft + arrowhead + the rider dot all
**unioned** into one polygon, computed offline with shapely) that is then just **filled
white + one dark stroke** — like drawing a shape and adding a border in a graphics program.
No more separate shaft-stroke + separate triangle (that join was the misalignment); white
is inherently continuous, border only on the outside, dot merged in (no interrupting line),
dot sized down to match a thinner body. Baked into `index.html` as the `TURN_GLYPHS` const
(130×150 space, dot at 65,132 — DO NOT hand-edit; regenerate via the shapely script in
`_planning/`). `turnGlyphKey(type,notes)` picks the glyph; `renderTurnCue` scales it (dot
pinned to the rider, on-screen height = H·(0.16+0.20·p), grows as you approach) instead of
bending. Kept from v240: only the imminent turn shown (gated on `turnAlertM`, sim ×20),
smooth straight-line countdown, distance + road below. Node-verified glyph selection +
scale math. **Font is deliberately still the placeholder** (system sans) — Peter is
reviewing how the bike computers handle type; proper type pass + the style-guide DM Mono
question come next. Also (Peter's request) reaffirmed: **read `PackTimes-style-guide.md`
before every UI change** (noted in memory). Not yet ride-tested.

## Current status (10 July 2026, v240)

**v240 (10 Jul 2026) — turn-cue rework after Peter's first WALK test of v239 (v239 was
bad).** Peter walked a loop with v239 and it failed on four counts, all real: (1) the
arrow was far too big + thick and looked "bitmap clunky" — cause: fat strokes (11–26 px)
+ a separate mismatched polygon arrowhead that didn't join the shaft; (2) the distance
jumped in ~50 m steps — cause: it used the along-route position (`nt.dist-liveDist`), and
`snapTo` snaps to route points spaced ~50 m; (3) it ignored the turn-alert-distance
setting (he set 50 m, it still showed at 250–300 m) — cause: v239 was deliberately
"always visible"; (4) it kept jumping to the turn-AFTER-next and so pointed the wrong way
(left turn ahead, arrow already showing the right after it) — cause: always-on + a far
look-ahead on a tight self-crossing loop. Rework (all `renderTurnCue`/`turnCueGeom` in
`index.html`): now **gated on `turnAlertM`** (sim ×20) so ONLY the imminent turn shows —
respects the setting, kills the jump-ahead; distance is now **straight-line from
`UI.gpsPos` to the turn's lat/lon** (`hav`), so it counts down smoothly (10 m steps via
`fmtTurnDist`) instead of 50 m snaps, and a far/mis-snapped wrong turn falls outside the
window and is simply hidden (better than pointing wrong); geometry is **much smaller +
crisp** — reach 42→110 px, line 4→7 px (was up to 250/26), drawn as a thin white line
with a thin dark border and an **open chevron arrowhead** (two strokes, joins the shaft
cleanly — no more polygon blob); proximity `p` now ramps across the alert window (small +
straight on appearance → grows/bends to the turn); font switched to system sans, smaller.
Node-verified across 50 m/150 m/sim windows + slight/sharp/u-turn. STILL residual + known:
self-crossing-loop mis-snap can still pick a wrong "next" turn (now hidden not wrong); the
bend is screen-left/right on the heading-up map (not true bearing yet); dot still sits over
the canvas blue triangle; colour held (white/black only), proper colour+font pass later.
Not yet re-tested on foot.

## Current status (10 July 2026, v239)

**v239 (10 Jul 2026) — turn POP-UP BANNER replaced by a bending-arrow overlay (new turn
UI, first testable cut).** Long design thread with Peter (competitor review of Garmin/
Wahoo/Karoo/Coros + mockups composited onto his real Ride screenshot, all in
`_planning/`). Agreed model: retire the top pop-up banner; draw ONE arrow on the map that
emanates from a black "you" dot (replacing the reliance on the blue position triangle),
**small and straight-ahead when the next turn is far, growing + bending toward the turn as
you approach**, with distance + road name below it, sitting above the elevation strip.
Always visible while a turn is ahead (screen-on / bike-computer-alternative case); on a
future native build it stays hidden with the screen off and appears at full size when the
screen wakes. Colour held for now (white + black outline; the size change carries "turn
coming" — Peter didn't want it garish); fonts/colours to be a later pass. Implementation
(all `index.html`): removed `.turn-popup`/`.turn-arrow`/`.turn-*` CSS → one `.turn-cue`
(absolute, `pointer-events:none` so map gestures pass through); removed the pop-up builder
from `tLiveShell` and the build/patch block in `updateLive`; new `fmtTurnDist`,
`turnCueGeom(remM,type,notes,simMult)` (pure — proximity `p` ramps 500 m→60 m, sets bend
angle by type/notes incl. slight/sharp/u-turn, reach R and stroke width), and
`renderTurnCue(r,liveDist)` which builds/updates an SVG `#turn-cue` inside
`#live-map-section` anchored at the rider (W/2, H·0.66). `updateLive` now just calls
`renderTurnCue`. Sim-aware (×20 thresholds) so it grows/bends visibly in the desktop sim.
Audio cues (`checkAlerts` two-stage) untouched. Node-verified the geometry across
far/near/slight/sharp/straight/u-turn/sim. Dead `#turn-popup` tap handler left in place
(harmless, never matches). NOT yet done: removing the canvas blue triangle (dot currently
sits over it), angling the bend to the true route bearing (currently screen-left/right on
the heading-up map), elevation-hidden drop, colour/font pass. Not yet ride-tested.

## Current status (10 July 2026, v238)

**v238 (10 Jul 2026) — turn popup now really shows on the desktop sim + tone re-fires
after a slider scrub.** Two bugs from Peter's desktop-sim test of v237. (1) No turn
graphic: v237's "widen the window" fix was pointless on desktop because the popup was
only ever created by rebuilding the live shell via `render()` — and on desktop during a
sim/GPS, `render()` deliberately short-circuits to `updateLive()` and returns WITHOUT
rebuilding (anti-flash guard at the top of `_render`), so the popup was never built. Fix:
`updateLive` now BUILDS the `#turn-popup` element directly (createElement + appendChild
into `#live-map-section`, which is `position:relative`) instead of calling `render()`;
still sim-aware window, still one popup (patched in place after, removed when passed).
Works on mobile too (updateLive runs there as well; no duplicate — it only builds when
`getElementById('turn-popup')` is null). (2) Tone fired only once: `_turnCuesFired` keys
persist, and the sim slider handlers (`#sim-sl`, both the map-overlay one ~7705 and the
delegated one ~13931) set `UI.gpsDistKm` + `updateLive()` but never cleared the fired
set, so replaying through the same turn stayed silent. Fix: both slider handlers now
`_turnCuesFired.clear()` on scrub, so upcoming turns re-fire fresh. Node-verified the
popup HTML builder. Not yet ride-tested.

## Current status (10 July 2026, v237)

**v237 (10 Jul 2026) — turn popup now shows during a sim (window bug).** Peter tested
v236 on the desktop sim: heard the (now quiet-but-OK) beep, but the on-screen turn popup
never appeared. Root cause in `updateLive`: the popup is CREATED by an `else if` that
calls `render()` only when a turn is within `alertDistKm2` — and that gate used the plain
150 m window WITHOUT the sim ×20 multiplier that the popup's own template and the audio
loop both use. At 20× the rider skips past the 150 m zone between ticks, so `render()`
never fired and the popup was never built (audio was fine — it lives in `checkAlerts`,
which does use ×20). Fix: `alertDistKm2` now applies the same `UI.simRunning?…*20` widen.
Popup appears once per turn (render fires once to build it, then updateLive patches the
distance and removes it when passed). Also confirmed: the **simulator is desktop-only** —
its Play/Pause/Stop live in `desktop-sim-ctrl` on the big-map overlay (rendered inside
`renderDesktopMap`, which early-returns on mobile), so there is no way to launch the sim
on the phone. Real-device audio can still be checked via the Settings turn-audio toggle
(plays the heads-up cue). Not yet ride-tested.

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
