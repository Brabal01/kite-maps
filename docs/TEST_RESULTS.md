# Test results

## v36 (branch `iphone-custom-v36-traffic-roundabout-accuracy`)

* VelaCore: **440 tests, 0 failures** (6 skips for live/opt-in checks), run in a
  `swift:6.0` container. New suites: `OlomoucRoundaboutTests` (5, real OSM golden
  fixture) and `TrafficOverlayStateTests` (8).
* Detailed results: `docs/V36_TEST_RESULTS.md`.
* iOS build, simulator UI and IPA results are on PR #14.
* Physical-device checks: `docs/V36_DEVICE_TEST_CHECKLIST.md`.

## v33 (branch `iphone-custom-v33-reliability-ux`)

* VelaCore: **420 tests, 0 failures** (6 skips without live checks, 3 Darwin-only skips with
  `KITE_VERIFY_TRANSITOUS=1`; all three live Transitous tests passed).
* New suites cover HTTP 200 with a bad Overpass body, retry/backoff, GPS jump guard, camera
  jurisdiction, golden roundabout/tunnel/wrong-turn fixtures, three-level diagnostics, replay
  and voice (from v32).
* Reproducible microbenchmarks: `VelaCore/Sources/vela-bench`, numbers and conditions in
  `docs/V33_TEST_RESULTS.md` and in the `Kite-v33-Performance-Results` artifact.
* iOS IPA, simulator and UI results are in `docs/V33_TEST_RESULTS.md` and on PR #11.
* Physical-device items are explicitly unverified — see `docs/V33_DEVICE_TEST_CHECKLIST.md`.

## v32 (branch `iphone-custom-v32-refinement`)

### VelaCore (Linux Swift 6.0.3, local)

* **400 tests, 0 failures, 6 skipped** (`swift test`). The skips are three Darwin-only compression
  tests and three opt-in live Transitous checks when `KITE_VERIFY_TRANSITOUS` is not set.
* New deterministic suites: `SavedJourneyTests` (8), `DiagnosticsTests` (5), `EndpointHealthTests` (9),
  `RouteSectionSchedulerTests` (12), `VoiceLevelTests` (3), `OfflineJourneyTests` (4),
  `GPSReplayTests` (6), `LaunchHealthTests` (5), `TransitMapFilterTests` (4),
  `BoardingDetectorTests` (7). All 336 v31 tests still pass.
* **Live integration** (`KITE_VERIFY_TRANSITOUS=1 swift test --filter TransitousLiveTests`):
  3 tests passed against api.transitous.org — plan between Prague stops, live metro route map,
  live departures at a central stop. They fail, rather than skip, when the service is unreachable.

### iOS CI (GitHub Actions, xcode-27)

* At commit `910cacce`: `Build custom iPhone IPA`, `iOS simulator smoke test` and
  `Transitous live integration` all succeeded. The simulator run includes `PlanningUITests` and
  `V31UITests`; the IPA workflow builds, ad-hoc signs, packages Full and SideStore from the same
  commit and verifies their structure and signatures.
* Later v32 commits (offline journey, replay, transit filters, safe mode, boarding detection) were
  pushed after that build; the final v32 verification run is the one linked from the PR.

### Not verified here

Physical iPhone, SideStore installation, Live Activity on a locked device, battery drain, map FPS.
## v31 navigation, traffic lights and transit (branch `iphone-custom-v31-navigation-transit`)

### Unit tests (VelaCore, Linux Swift 6.0.3)

- **336 tests, 0 failures, 3 skipped** on the local Linux harness.
  - The 3 skips are Darwin-only: the Waze zlib fixture (Compression is not in
    Linux Foundation) and two tests that call the compression helper. They run
    on macOS CI.
- New deterministic suites:
  - `RoundaboutExitResolverTests` (16) — topology correction, corroboration,
    entrance-only arms, dual carriageway, reverse traversal, left-hand traffic,
    provider conflict, router-only, no evidence, missing branch, close exits,
    route integration, diagnostics.
  - `DirectionalRoadControlMatcherTests` (19) — our road, opposite carriageway,
    crossing road, two junctions 20 m apart, two heads on one stop line,
    turn-lane head, overpass, under-bridge, one-way junction, missing direction,
    reversed travel, route change, passed light, parallel road, empty answer,
    Postpass node, duplicate nodes, browsing-only ambiguity.
  - `TransitLineIdentityTests` (13) — GTFS/Transitous modes, name-vs-mode,
    fallback colours, official colour source, invalid hex, contrast, agency
    identity, parser identity, shared track offsets, bus zoom, departure board,
    icons.
- Existing suites (288 tests) still pass unchanged, including `RoundaboutTests`,
  `ControlDisplayPolicyTests`, `RoutingTests`, `WalkEventsTests`, `TransitTests`,
  `TransitRealtimeTests`, `NavigationStateTests`, `AlertCoordinatorTests`,
  `LaneGuidanceTests`, `JunctionGuideTests`, `PlanningSessionTests`.

### App / simulator

- `simulator-smoke.yml` captures:
  - `roundabout` (confirmed exit, source and confidence),
  - `roundaboutuncertain` (conflicting sources, no ordinal),
  - `signals` (two close signalised junctions),
  - `transitcolors` (metro/tram/bus/train colours and modes),
  - the same roundabout and transit screens in dark mode,
  - a transit card at accessibility-extra-large Dynamic Type.
- The workflow still runs `PlanningUITests` and the launch/safe-mode checks.
- **v31 CI run 44928133681 passed every step.**
  - `PlanningUITests`: 1/1 passed.
  - `V31UITests`: **3/3 passed** — roundabout banner (24.8 s), directional
    lights (18.5 s), official line chips (23.4 s).
  - Screenshots captured: `demo-roundabout.png`,
    `demo-roundaboutuncertain.png`, `demo-signals.png`,
    `demo-transitcolors.png`, `demo-dark-roundabout.png`,
    `demo-dark-transitcolors.png`, `demo-transit-large-type.png`.
  - Screenshot artifact:
    [Kite-v31-Simulator-Screenshots](https://github.com/Brabal01/kite-maps/actions/runs/44928133681/artifacts/14716919377).

### v31 IPA build

- **CI run 44928133658 passed.**
- Build number **1118**.
- Full: `Kite-v31-Full.ipa` (8.4 MB) — app `app.vela.ios 0.8.0 (1118)`,
  iOS ≥ 16.2, arm64, MapLibre arm64 signed, embedded
  `app.vela.ios.navigation 0.8.0 (1118)` signed.
- SideStore: `Kite-v31-SideStore.ipa` (8.3 MB) — same app, no extension.
- Both variants passed the structure checks. Both come from commit
  `605793f`.
- Artifacts:
  [Full IPA](https://github.com/Brabal01/kite-maps/actions/runs/44928133658/artifacts/14716234595),
  [SideStore IPA](https://github.com/Brabal01/kite-maps/actions/runs/44928133658/artifacts/14716900527),
  [test results](https://github.com/Brabal01/kite-maps/actions/runs/44928133658/artifacts/14716463885).
- The macOS VelaCore step also ran **336 tests, 0 failures** (no Linux skips).

### v30 reference

The last verified v30 build is
[run 44886980456](https://github.com/Brabal01/kite-maps/actions/runs/44886980456)
on `iphone-custom-v30-advanced-navigation`. v30 documented 288 VelaCore tests;
v31 adds 48 and keeps the same 3 Darwin-only skips on Linux.

### Not verified here

- Physical SideStore installation of the v31 SideStore IPA.
- A physical drive through the roundabout/signal fixtures.
- Live Transitous feeds for the eight sample cities; the transit tests use
  deterministic fixtures with real-looking official colours.

## v30 advanced navigation (branch `iphone-custom-v30-advanced-navigation`)

### Unit tests (VelaCore, Linux Swift 6.0)

- **282 tests, 0 failures, 1 Darwin-only skip** on the local Linux harness.
  The skipped test is the zlib Waze camera fixture, which requires Apple
  Compression and runs on macOS CI.
- New deterministic suites:
  - `NavigationStateTests` (7) — lifecycle, GPS loss/recovery, reroute
    lifecycle, terminal ended state, two independent sessions.
  - `AlertCoordinatorTests` (7) — dedupe, opposite direction, over-limit camera,
    hysteresis, cooldown, urgent maneuver, expired/weak/reply events.
  - `LaneGuidanceTests` (6) — exits, straight junction, split fallback, unknown
    lanes, left/right roundabout, off-route/lead limits.
  - `JunctionGuideTests` (6) — right-hand exit, left-hand fork, insufficient
    data, city/roundabout rejection, follow-up maneuver, road refs.
  - `ControlDisplayPolicyTests` (5) — car/walk/browse, unknown direction,
    ordered upcoming controls.
  - `MapPresetTests` (5), `HUDProfileTests` (4), `SavedJourneyTests` (2),
    `GPXTests` (3).
  - `PlanningSessionTests` gained navigation-grade strictness and invalid
    coordinate/future-clock tests (21 total).

### CI

The v30 IPA, VelaCore macOS tests and simulator UI test are recorded after the
branch is pushed. They must not be inferred from the v29 numbers below.

## v29 redesign (branch `iphone-custom-v29-redesign`)

### Unit tests (VelaCore, macOS CI)

- **220 tests, 0 failures** in run `44808484156`, plus two regression tests
  added afterwards (entrance-query ID interpolation): **222 tests**.
- New: `RouteAlternativesTests` (6) — fastest kept, near-identical alternatives
  dropped, clearly different roads kept even when slower, shorter route with a
  similar time kept, tolerance scales with trip length, empty/single input.
- All v28 navigation, reroute, roundabout, lane, sign, transit and GTFS-RT tests
  remain green.

### Release IPA (custom workflow)

- Run [`44836383104`](https://github.com/Brabal01/kite-maps/actions/runs/44836383104):
  **success**, build **1088**, commit `77adc49`.
- VelaCore: **222 tests, 0 failures**.
- Both variants passed `.github/scripts/verify-ipa.sh`:
  - Full: app + `app.vela.ios.navigation` extension, both 0.8.0 (1088),
    both iOS ≥ 16.2, MapLibre arm64, signatures valid, Live Activities on.
  - SideStore: no extension, Live Activities off, same app binary, arm64.
- An independent download of build 1078 (same packaging path) confirmed the
  arm64 Mach-O app (14 MB), arm64 MapLibre, clean zip, no provisioning profile
  and matching versions.

### Simulator and screenshots

- Final smoke run
  [`44838972349`](https://github.com/Brabal01/kite-maps/actions/runs/44838972349)
  on commit `77adc49`: three normal launches, one denied-location launch and
  one `--safe-mode` launch survived; it then opened home, routes, place,
  navigation and settings, plus home/navigation in dark mode.
- Artifact `Kite-v29-Simulator-Screenshots` contains the eight full-size PNGs.
  The workflow checks each expected frame exists, is not black and is not a
  uniform colour. Layout quality was reviewed from these images, not asserted
  by the script.
- Curated, downscaled frames are committed in `docs/screenshots/v29/` with a
  provenance note (including the one frame taken from the previous run because
  the simulator did not deliver a fix in time).
- An earlier smoke run on the same code base (`44836387766`, build 1088) also
  passed the launch and safe-mode checks.

## v28 stability

- Safe mode, launch trace and MetricKit crash collector compile in the iOS target.
- Custom IPA build 1051: GitHub Actions run `44794880719`, success; artifact verified arm64,
  widget, bundle IDs and `_CodeSignature`.
- Simulator smoke: run `44794890053`, success; 3 normal launches, 1 denied-location launch and
  1 safe-mode launch survived. MapLibre initialised in normal launches only; no crash lines in the
  collected logs.
- The v27 physical-device crash cannot be reproduced without the phone or an `.ips` report.

## v27 local (Linux, Swift 6.0)

- VelaCore: **208 tests, 0 failures, 1 skipped**.
- New v27 tests: departure evidence vs confidence, weak-accuracy confirmation, dead-reckoned
  arrival guard, GTFS-Realtime operating-day/overnight matching, stale feed/vehicle handling,
  direction mismatch, Mobility Database CSV parsing and quoted fields.
- The v26 tests remain green.

## v26 local (Linux, Swift 6.0)

- VelaCore: **194 tests, 0 failures, 1 skipped**.
- The skipped test is the Darwin-only zlib Waze camera fixture; it runs on macOS CI.
- New v26 tests:
  - `RouteTrackerV26Tests`: parallel carriageway/heading, noisy-fix dead reckoning,
    traffic-span ETA, poor-accuracy precision flag.
  - `ReroutePolicyTests`: confirmed departure, noisy fix guard, cooldown/destination guard,
    car-park departure.
  - Existing roundabout, lane, sign, heading, risk and transit tests remain green.

## iOS build

- Compiled, signed and packaged by `.github/workflows/custom-iphone.yml`.
- Verified build for v27: run `44768158140`, commit `44f6fa0`, artifact `Kite-custom-ipa`,
  `CFBundleVersion` 1043.
- VelaCore on the CI runner: **214 tests, 0 failures**.
- Verified build for v26: run `44758806622`, commit `48178b7`, `CFBundleVersion` 1036.
- Artifact checks: `Payload/Kite.app`, arm64, `NavigationWidget.appex`, bundle identifiers,
  `unzip -t`, `_CodeSignature` on app and widget.

## Not testable here

- Physical compass/GPS behaviour, locked screen, background voice, Live Activity/Dynamic Island.
- Long-drive memory/CPU profiling.
- Real provider outages in every region; unit tests use synthetic responses.
