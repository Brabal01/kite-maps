# Kite Maps iPhone custom build — development progress

Updated: 2026-11-21

## v31 navigation, traffic lights and transit (branch `iphone-custom-v31-navigation-transit`)

Base: `804822f` on `iphone-custom-v29-redesign`, which already contains the v30
PR #8. The v30 planning, navigation, lane, alert, map and HUD work is preserved.

### P0 — Roundabout exit accuracy

- **`RoundaboutExitResolver`** (`VelaCore/Sources/VelaCore/RoundaboutExitResolver.swift`)
  is a pure, testable component. It rebuilds the circle from OSM ways, counts
  only legally usable exits in the direction of travel, merges dual
  carriageways, rejects private/access-restricted arms, and finds the route's
  actual way off the circle.
- Evidence order: complete OSM topology + route geometry → router + OSM agree →
  OSM alone → router alone → Google alone → unresolved conflict (no number).
- One authoritative maneuver: `exit`, `instruction`, `roundabout`,
  `routerExit`, `alternativeExit`, `exitSource`, `exitConfidence` and
  `exitAmbiguous` are written together. Banner, diagram, voice and Live
  Activity all read the same `Maneuver`.
- `Navigator.loadRoundabouts` freezes a maneuver that has already been spoken
  (`spokenStage >= 2`), so late map evidence cannot contradict the driver.
- Reroute identity guards (`route.id == r.id`) are unchanged; an old OSM answer
  cannot touch a new route.
- Mini-roundabouts keep their own count; the ring query no longer erases it.
- Diagnostics: per-roundabout source/confidence/eligible/rejected lines are
  available in Settings → Diagnostics and in the explicitly shared ZIP.
- 13 new resolver tests plus the existing `RoundaboutTests`.

### P0 — Directional traffic lights

- **`DirectionalRoadControlMatcher`**
  (`VelaCore/Sources/VelaCore/DirectionalRoadControlMatcher.swift`) asks whether
  the route actually follows the OSM way the control is on, in a legal
  direction, with a matching bearing. Proximity alone no longer qualifies.
- `RouteControl` now keeps OSM id, way id, direction tag, route distance,
  offset, confidence, source, `directionCertain`, `relevance` and a stop-line
  key.
- The 30 m merge is replaced by a 12 m/stop-line rule: two heads on one line
  merge; two junctions 20 m apart do not.
- `ControlDisplayPolicy` reads the control's own evidence; ambiguous controls
  are browsing-only and hidden in active driving guidance.
- The map layer uses route distance from `Navigator.allUpcomingControls`, not
  straight-line distance, and drops passed controls.
- `RouteEventCoverage` uses the matcher's `alongMeters` instead of re-projecting
  each point at section boundaries.
- 19 new matcher tests plus the existing policy, routing and walking tests.

### P1 — Transit Design 3.0

- **`TransitLineIdentity`** keeps provider/feed/agency/route ids, short/long
  name, headsign, mode, route type, official colour/text colour, operator,
  colour source and freshness.
- `TransitMode` separates walk, bus, trolleybus, coach, tram, light rail, metro,
  subway, suburban/regional/long-distance/high-speed rail, ferry, funicular,
  cable car, aerial lift, monorail, bike and unknown. It maps Transitous strings
  and GTFS route types; a line name never decides the mode.
- Official `routeColor` wins; otherwise a mode-specific fallback is used and
  clearly marked as non-official. `routeTextColor` is kept when its contrast is
  at least 3:1, otherwise black/white is chosen.
- `LineChip` 3.0: mode icon + line name + official colour + readable text.
- `TripRow` 3.0: card with times, duration, wrapped line chips, changes/walk
  summary, direction, delay, freshness and tight transfer.
- `TransitSteps` is a vertical timeline with coloured ride rails, dotted walk
  rails and a transfer node.
- Map: one feature per line on a shared track, with pixel offsets and
  mode-dependent widths; live vehicles use the mode icon.
- 13 new identity tests plus the existing transit parser tests.

### Tooling and CI

- `custom-iphone.yml` builds `Kite-v31-Full.ipa` and
  `Kite-v31-SideStore.ipa` from the same commit and uploads
  `Kite-v31-Test-Results`.
- `simulator-smoke.yml` captures `roundabout`, `roundaboutuncertain`, `signals`
  and `transitcolors` in light mode, dark mode and large Dynamic Type, and
  uploads `Kite-v31-Simulator-Screenshots`.
- Linux test portability: `WazeCameras`, the `vela-probe` HTTP imports and the
  zlib fixture are guarded, so the same 333-test suite runs on Linux and macOS.

### Not shipped in v31

- A new in-app GPS replay UI. The existing `vela-probe` drive replay remains the
  developer tool.
- Offline journey persistence, transit map filters, and user-adjustable control
  density. These stay on the roadmap.


## v30 advanced navigation (branch `iphone-custom-v30-advanced-navigation`, base `bb0cdfe`)

The P0 planning fix from v29 is preserved. v30 adds:

- **NavigationSession 3.0** — one UUID session and an explicit lifecycle
  (`NavigationState.swift`), integrated into `Navigator`; impossible state
  combinations are rejected. Guidance now always starts from a
  navigation-grade fix or enters `waitingForGPS`.
- **Reroute Engine 3.0** — explicit rerouting/recovered/unavailable states,
  request cancellation, original route kept while offline, remaining stops and
  exclusions preserved, arrival/departure evidence unchanged.
- **AlertCoordinator** — tested direction filtering, de-duplication, priority,
  hysteresis, cooldown and urgent-maneuver suppression; the HUD no longer sorts
  alerts inline.
- **Lane Guidance 3.0** — recommended/suitable/unsuitable/unknown lanes for
  turns, exits, splits, merges, straight approaches and roundabouts; never
  invents lanes.
- **Motorway Junction View** — vector Canvas diagram from real exit signs,
  lanes and road references; insufficient data shows the ordinary banner.
- **Road-control policy** — car guidance shows only nearby, direction-plausible
  lights/stops/crossings; walking and browsing get different sets.
- **Map Engine 3.0** — seven coherent presets (Classic, Navigation, Minimal,
  Explore, Transit, Outdoors, Satellite), adaptive labels/POI/buildings, and
  Navigation mode during driving. MapKit applies the POI/building subset.
- **HUD 3.0** — Simple, Advanced, Highway and Custom profiles with a live
  preview.
- **Saved Journeys** — full trip persistence (origin, destination, stops, mode,
  notes, preferences), reverse/delete/open, plus bounded GPX import and GPX
  export of a planned route.
- **Settings additions** — Public transport page, Diagnostics entry, map
  presets, HUD, haptics.
- **Haptics** — optional maneuver/alert cues, respecting Reduce Motion.

Verification for this branch is recorded in `docs/TEST_RESULTS.md` once the v30
CI run completes. Physical-device items remain in
`docs/V30_DEVICE_TEST_CHECKLIST.md`.

## v29 redesign (branch `iphone-custom-v29-redesign`, base v28 `462b575`)

Two things were done in parallel and are deliberately documented separately:
the packaging fix that decides whether the IPA installs, and the visual/product
redesign.

### Packaging and SideStore (P0)

- **Root cause found for a class of install failures:** the app target was built
  for iOS 16.0 while `NavigationWidget` required 16.2. iOS rejects a package
  whose extension needs a newer system. Both now use 16.2, the real Live
  Activities floor (`ActivityContent`).
- **Second cause:** `Build iPhone app` signed frameworks and the app but never
  the widget, then verified `--deep --strict`. It therefore failed on v28 while
  the custom workflow passed. Both workflows now call `.github/scripts/sign-app.sh`.
- One packaging script and one verifier (`pack-ipa.sh`, `verify-ipa.sh`) produce
  and check two variants from one build:
  - **Kite Full** — app + NavigationWidget + Live Activities;
  - **Kite SideStore** — same source and navigation core, no extension, Live
    Activities not advertised.
- The verifier fails on: wrong bundle id, missing arm64, emulator slice,
  unsigned extension/framework, extension/app version, build or minimum-OS
  mismatch, foreign provisioning profile, a SideStore build that still contains
  an extension, or a Full build without `NSSupportsLiveActivities`.
- Build numbers use `1000 + git commit count` in both workflows (full history
  fetched), so they grow and do not reset per workflow.
- See `docs/KITE_2_PACKAGING.md`.

### Design and product (P1)

- **Kite Design System 2.0** (`App/Sources/KiteDesignSystem.swift`): adaptive
  light/dark palette, type ramp, spacing, radius, elevation, motion, cards,
  buttons, chips, empty states. Legacy `Vela` colours resolve to the new tokens,
  so old and new screens share one identity.
- **Map home:** new 58 pt search surface with voice action; contextual quick
  actions (Home, Work, Parking, Transit, Fuel, Food, Recent, Just drive) edited
  in Settings; duplicate Just drive and parking map FABs removed.
- **Camera start:** last browsed area → current fix → neutral world view. No
  London flash. A restored area is kept when the first fix is nearby.
- **Dock:** Map / Routes / Saved / Settings, one floating surface, soft teal
  selection. New **Routes** page: plan, resume a remembered trip, favourites,
  recent destinations, empty state.
- **Navigation HUD 2.0:** one banner hierarchy (maneuver tile, distance,
  instruction, signed exit panel with exit number and destinations, recommended
  lanes, then-row). A close follow-up turn is highlighted amber. Trip bar now
  carries arrival, remaining time/distance, destination, add stop, steps and end.
- **Place sheet:** one action row (Save, Share, Reviews, Photos) and a clear
  Directions / Go pair.
- **Route planning:** tokenised mode tabs, cards and Go; near-identical route
  alternatives are collapsed by a pure `RouteAlternatives` filter (6 new tests).
- **Accessibility:** combined banner sentence + repeat action, labelled lanes,
  dock selection traits, Reduce Motion respected by new transitions.

### v29 verification (build 1088)

- Final IPA workflow run
  [44836383104](https://github.com/Brabal01/kite-maps/actions/runs/44836383104):
  **success** on commit `77adc49`. Both variants passed the structure checks.
- VelaCore: **222 tests, 0 failures**, including six `RouteAlternativesTests`
  and two regression tests for the transit entrance query.
- Artifacts (from the same source commit):
  - `Kite-v29-Full.ipa` — arm64 app and MapLibre, `app.vela.ios` 0.8.0 (1088),
    iOS ≥ 16.2, Live Activities on, `app.vela.ios.navigation` extension 0.8.0
    (1088), signed.
  - `Kite-v29-SideStore.ipa` — the same app with no PlugIns and Live Activities
    switched off.
  - Both unpack cleanly, contain no provisioning profile, and have matching
    app/extension versions and minimum OS.
- Simulator smoke with screenshots: run
  [`44838972349`](https://github.com/Brabal01/kite-maps/actions/runs/44838972349)
  on the same commit. It launches the app three times, once without location,
  once in safe mode, then opens home, routes, place, navigation and settings,
  plus home/navigation in dark mode, and uploads
  `Kite-v29-Simulator-Screenshots`. Curated frames are in
  `docs/screenshots/v29/`.
- The earlier build 1078/1081 runs verified the same packaging path while the
  final UI changes were still landing.

Physical SideStore installation remains unverified; that needs the phone.

## v28 stability

## v28 stability (in progress)

Branch: `iphone-custom-v28-stability`, based on verified v27.

- **No physical crash log was available**, so the v27 launch crash is not claimed as fixed.
- Added a real safe mode (launch argument, persisted switch and automatic entry when the previous launch
  did not reach its first healthy screen (10 s). It avoids AppModel, MapLibre/MapKit, location, network, transit and
  Live Activities, and never deletes user data.
- Added privacy-safe launch breadcrumbs and a MetricKit crash-diagnostic collector shown in safe
  mode.
- Hardened `LocationService`: background location updates are only enabled when the generated
  Info.plist has the `location` background mode, and never from the background. Modes remain
  browse / Just drive / drive / walk-bike / transit.
- Removed a possible `TransitCatalog` trap on duplicate/renamed CSV columns.
- Added `.github/workflows/simulator-smoke.yml`: simulator build, install, three launches and a
  safe-mode launch, with logs and screenshot artifacts.
- See `docs/CRASH_RECOVERY.md` for the audit, suspects and exact phone steps.

### v28 verification (build 1051)

- Custom IPA run `44794880719` succeeded in 5m02s on commit `462b575`.
- Artifact `Kite-custom-ipa` checked: clean `unzip -t`, arm64 app and widget, bundle IDs
  `app.vela.ios` / `app.vela.ios.navigation`, `CFBundleVersion` 1051, `_CodeSignature` on both.
- iOS simulator smoke run `44794890053` succeeded in 13m22s. It launched the normal app three
  times, once with location denied, and once in safe mode. MapLibre initialised in the four normal
  launches and not in safe mode; no crash/fatal/exception lines were found in the collected logs.
- The smoke test is a simulator launch check, not a physical-device crash reproduction. The v27
  physical crash remains unconfirmed without the phone's `.ips`/MetricKit diagnostic.

## v27 (verified build 1043)

Base: `iphone-custom-v26` (verified build 1036/1037).

### Route abandonment and GPS reliability

- `RouteTracker` now keeps counting outside-corridor fixes past 3, so a weak-but-usable 40–60 m
  accuracy can actually reach the confirmation needed by the reroute policy.
- Departure evidence is separate from map-match confidence. A fix 100 m off the road can have
  confidence 0 and still prove a departure; a poor fix close to a parallel road cannot.
- `ReroutePolicy` uses that evidence, requires 3 confirmations up to 45 m accuracy and 4 above it,
  and keeps the cooldown/destination/car-park guards.
- Estimated positions (dead reckoning or a GPS gap) can no longer trigger arrival. The UI shows
  the GPS state instead of ending the trip on a guessed point.
- `LocationService` has explicit GPS modes: browse (10 m accuracy, 15 m filter, no background),
  Just drive (best, 5 m), driving navigation (best-for-navigation, no filter), walking/cycling
  (best, 2 m) and transit. Browse stops location/compass in the background; navigation keeps going.

### Live transit

- GTFS-Realtime matching now uses provider feed, trip id, route id, direction id, start date and
  start time. Ambiguous updates are skipped instead of being attached to a random trip.
- Overnight trips are matched against the previous service day (24:xx start times).
- Live freshness is explicit: `live`, `recent`, `stale`, `scheduled`, `unavailable`, with the age
  in seconds. A feed older than five minutes is not applied; a vehicle older than two minutes is
  not shown as a current position.
- The public Mobility Database CSV catalog (`files.mobilitydatabase.org/feeds_v2.csv`) is used to
  discover keyless, active GTFS-Realtime feeds covering the journey area. Feeds needing an API key,
  inactive feeds and development-only feeds are skipped. The manual URL remains the override.
- The trip sheet shows Live / recent age / stale / scheduled, the live feed host, platform
  changes, skipped stops, service alerts and a "Tight transfer" warning when a delay consumes the
  walking transfer.
- The timetable is shown immediately; a slow live feed updates it afterwards without blanking the
  screen.

### Verification

- GitHub Actions run `44768158140` built commit `44f6fa0` successfully in 3m27s.
- VelaCore on CI: **214 tests, 0 failures** (208 local Linux + the Darwin-only fixture).
- Artifact `Kite-custom-ipa` downloaded and checked: clean `unzip -t`, arm64 app and widget,
  bundle IDs `app.vela.ios` / `app.vela.ios.navigation`, `CFBundleVersion` 1043, `_CodeSignature`
  on both.
- Physical iPhone checks for locked screen, background GPS, compass and battery still need a device.

### Not done in this stage

- SIRI XML, offline maps/routing, CarPlay and a shared HTTP/cache layer for every provider remain
  roadmap work.
- Physical iPhone checks for locked screen, background GPS, compass, Live Activity and battery
  still require a device.

## v26 (verified build 1036)

Base: `iphone-custom-v25` (verified build 1035).

### Navigation core

- **Map matching v2** in `RouteTracker`: candidates are scored by distance, GPS accuracy,
  vehicle heading against the segment bearing, the distance the vehicle could have travelled
  since the last fix, and continuity with the previous match. This keeps the arrow on the correct
  carriageway/flyover instead of jumping to a parallel road.
- **Dead reckoning** covers short signal gaps and fixes beside bridges, tunnels or car parks:
  the tracker keeps advancing along the last good match and reports low confidence instead of
  teleporting. `Progress.isPrecise` is false for poor-accuracy fixes, so the UI cannot present
  them as measured.
- **Guarded rerouting**: `ReroutePolicy` requires a confirmed departure, a usable accuracy, a
  cooldown and confidence; a noisy single fix cannot start a reroute loop. Precise fixes still
  trigger promptly. Stops, toll/highway avoidance and exclusions remain unchanged.
- **ETA from mapped segments**: `Route.remainingSeconds(from:)` sums remaining stretches using
  mapped traffic spans, instead of always taking a flat share of the whole trip. Without traffic
  spans it falls back to the previous proportional estimate.
- **Stale traffic request cancellation**: a new traffic refresh cancels the previous one; older
  answers cannot overwrite a newer route. Transit requests are cancelled the same way.
- **Rendering**: `NavGlide` skips identical puck/camera frames, so a parked car does not redraw
  the map at 60 Hz.

### Verification

- GitHub Actions run `44758806622` built commit `48178b7` successfully in 5m39s.
- VelaCore on the CI runner: **200 tests, 0 failures**.
- Artifact `Kite-custom-ipa` downloaded and checked: `Kite.ipa` opens cleanly, `Payload/Kite.app`
  and `Payload/Kite.app/PlugIns/NavigationWidget.appex` contain arm64 Mach-O binaries,
  `CFBundleVersion` is 1036, bundle identifiers are `app.vela.ios` and
  `app.vela.ios.navigation`, and both app and widget carry `_CodeSignature`.
- Physical iPhone checks for locked-screen, background GPS and compass still need a device.

### Not in this stage

- A shared provider abstraction/cache for every external service is still roadmap work; existing
  providers keep their own timeouts and fallbacks.
- SIRI, offline maps/routing, CarPlay and new transit discovery remain roadmap items.
- Physical iPhone checks for locked-screen, background GPS and compass are not possible here.

## v25 (verified build 1034)

Base: `iphone-custom-v24` (verified build 1033).

### Map location and orientation

- The browse map now hides MapLibre/MapKit's default blue dot and draws Kite's teal heading
  arrow at the current position, the same visual used for Just drive and navigation.
- The compass is read from `CLHeading` (`trueHeading` when valid, magnetic otherwise), filtered
  for bad accuracy, and stopped while Kite is in the background.
- GPS course is used while moving; the phone compass is used when stopped or when course is
  unavailable. `HeadingFilter` smooths the shortest angle so north does not jump 359°→0°.
- The first location fix turns the browse map to the phone's heading unless the user chose
  north-up. Manual pan, rotate, pinch/zoom and the north button still work as before.

### Police-risk chip

- The bottom-left chip is hidden unless Waze, police alerts and police risk are all on.
- A failed live Waze ask can no longer leave a stale high score on screen: the area risk is
  cleared when its inputs are unavailable.
- Historical reports can still raise the risk to *medium*, but only a live answer can produce
  *high*. This prevents a false "High" when live data is missing.

### Live transit

- Transitous remains the planner and already carries real-time delays, skipped stops and alerts.
- A new dependency-free GTFS-Realtime reader (`TransitRealtime`) reads `TripUpdate`,
  `VehiclePosition` and `Alert` protobufs from any public feed URL configured in
  *Map & display → Live transit*. It has no country, agency or city assumptions.
- The feed is joined by trip id and route id. It adds delays, skipped stops, service alerts and
  vehicle positions, and does not double-apply a delay Transitous already provided.
- Trip rows show *Live* or *Scheduled*; vehicle positions are drawn on the transit map when the
  feed provides them. If there is no feed, a failed feed or no live data, the timetable remains.

### Traffic-sign destinations

- OSRM `destinations`, `destination:ref` (inside `destinations`), `exits` and `ref` are used
  before street names. A turn now says "Turn right toward Prostějov" rather than only the road.
- The same instruction string feeds the banner and the spoken voice; the map's next-road pill
  prefers the signed destination too. Missing sign data keeps the normal street instruction.

### Verification

- VelaCore tests pass locally on Linux: 186 tests, 0 failures, 1 skipped.
- GitHub Actions run
  [44751600117](https://github.com/Brabal01/kite-maps/actions/runs/44751600117) — success,
  4m41s, on commit `134c1ab7810c3b77288c8e6829da3ac31e9eb37f`.
- Artifact `Kite-custom-ipa` was downloaded and inspected: `Payload/Kite.app/Kite` and
  `NavigationWidget.appex/NavigationWidget` are arm64; app identifier `app.vela.ios`, widget
  `app.vela.ios.navigation`; `CFBundleVersion` 1034; `unzip -t` clean; ad-hoc `_CodeSignature`
  present; MapLibre framework arm64. The new GTFS-Realtime strings are in the binary.
- No physical iPhone is available for locked-screen, background-GPS, compass or Dynamic Island
  checks.
- SIRI XML feeds are not implemented; GTFS-Realtime is the supported extra live format. A SIRI
  endpoint is region-specific and no public keyless default is assumed.

## Branch and base (v24)

- Working branch: `iphone-custom-v24`
- Base: `iphone-custom-v23` at `ed88cb5abc726b6ba64937ef564b24f3b8c9397c`
- Base commit name: `Open Google Maps reviews, photos and transit inside Kite`
- The last verified v23 build is GitHub Actions run
  [44728196650](https://github.com/Brabal01/kite-maps/actions/runs/44728196650) (success, 5m14s).

## What changed in v24

### 1. The nine historical patches are now ordinary source

The v23 workflow applied these files, in this order, on every build:

1. `Kite-0.7.16-custom.patch`
2. `Kite-v16-changes.patch`
3. `Kite-v17-changes.patch`
4. `Kite-v18-changes.patch`
5. `Kite-v19-changes.patch`
6. `Kite-v20-changes.patch`
7. `Kite-v21-changes.patch`
8. `Kite-v22-changes.patch`
9. `Kite-v23-changes.patch`

The patched tree is now checked in (commit "Materialize v23 customizations as versioned sources").
The patch files stay in `.github/workflows/` as history, but the workflow must not apply them
again: the source already contains every change, and a second application would duplicate it.

This removes the main long-term hazard: a change could previously exist in a patch but not in a
reviewable source file, and a newly added source edit could be silently overwritten by the next
patch in the chain.

### 2. Workflow

`.github/workflows/custom-iphone.yml` now:

- no longer applies the historical patches;
- verifies that the versioned customization files are present;
- runs `swift test` in `VelaCore`;
- builds with Xcode 27.1 / iOS 27.1 SDK on the `xcode-27` runner;
- stamps `CFBundleVersion`, ad-hoc signs the app, the widget and the frameworks;
- packages `Payload/Kite.app` into `Kite.ipa`;
- uploads the `Kite-custom-ipa` artifact;
- runs on `workflow_dispatch` and on pushes to `iphone-custom-v23` or `iphone-custom-v24`.

The app and widget identifiers are unchanged (`app.vela.ios`, `app.vela.ios.navigation`), so
SideStore can still install and re-sign the package.

### 3. Native place details

- Native reviews are shown first. The Google web page is now an explicit fallback at the bottom,
  labelled as the Google Maps website, not as native content.
- Reviews are deduplicated by Google's review resource name, then by author and text.
- The sheet shows the rating and rating count when available.
- A stale async answer can no longer replace the reviews of a place opened later.
- Photos remain native (`PhotoStrip` thumbnails, full-screen `PhotoViewer`), with the Google web
  page offered only for the complete Google gallery.
- The UI states that Google provides only a sample without a Places API key. No scraping,
  CAPTCHA bypass, consent bypass, account or paid key is required for the native path.

### 4. Place identity

`Place.matchesNearby` now treats two different non-empty Google place IDs as different places,
even when the names are identical and they are within 150 m. This prevents two branches of a
chain, or two units in a shopping centre, from being merged into one saved place or detail card.

### 5. Faster-route offer

The faster-route card no longer takes the new route by itself after 30 seconds. If it is left
alone it expires and the current route stays; switching is always an explicit "Take it" tap.
Rerouting after leaving the route is unchanged.

### 6. VelaCore testability

`VelaCore` now imports `FoundationNetworking` conditionally, and `GoogleJSON.isBool` has a
swift-corelibs-foundation path. This lets the pure navigation/search/transit tests run on Linux.

## Verification

- VelaCore unit tests on Linux (Swift 6.0, scratch copy without the two Darwin-only zlib tests and
  the `vela-probe` executable): **177 tests, 0 failures, 1 skipped**.
- New regression test: `PlaceMatchingTests.testSameNameButDifferentGooglePlacesStayApart`.
- First v24 GitHub Actions run:
  [44746989805](https://github.com/Brabal01/kite-maps/actions/runs/44746989805) — **success, 4m24s**
  on commit `4b8c28b98f4a2613e227ffbf7e7173b6a7d8d1e0`.
  - Artifact `Kite-custom-ipa` (ZIP containing `Kite.ipa`) was downloaded and inspected.
  - `Payload/Kite.app/Kite` and `Payload/Kite.app/PlugIns/NavigationWidget.appex/NavigationWidget`
    are both `Mach-O 64-bit arm64`.
  - `CFBundleIdentifier` is still `app.vela.ios`; the widget is `app.vela.ios.navigation`.
  - `CFBundleVersion` is `1032`, one above the verified v23 build 1031.
  - The app and widget carry `_CodeSignature`; the workflow's `codesign --verify --deep --strict`
    step passed.
  - `MapLibre.framework` and the Czech `cs.lproj` resources are inside the IPA.
- Physical-device checks (locked screen, background voice, Live Activity, Dynamic Island, real GPS
  loss): **not performed here**.

## Known limitations / open work

- **Google reviews and photos without a key**: only the sample embedded in search results is
  available natively. The full list needs either the optional Places API key or the Google Maps
  web page. This is now stated in the UI.
- **Transit**: Transitous is the only structured transit source wired in. A second keyless source
  (GTFS/GTFS-RT or another planner) still needs to be added and tested; the current fallback only
  widens the access walk around Transitous.
- **Native photo swiping for API photos**: the existing strip and viewer work, but Places API
  photos are resolved one by one; collecting all links before opening the viewer would make
  swiping across the complete Google sample smoother.
- The historical patch files should eventually move to `docs/patches/` with a README, or be
  deleted once the history is considered fully captured by source control. They are kept for now
  to preserve provenance.
