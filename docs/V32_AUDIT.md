# V32 — independent audit of v31 and the changes made

Date: 2026-11-21. Base reviewed: `00c3065` (`iphone-custom-v31-navigation-transit`), plus the v32 commits on `iphone-custom-v32-refinement`.
This is an audit of **code**, not a repetition of earlier reports. A class name, a green build or a
passing test is not treated as proof of a feature. Every claim below names the file and, where
available, the test that proves it.

## Method

* Whole source tree read: `App/Sources`, `VelaCore/Sources`, `VelaCore/Tests`, `AppUITests`,
  `NavigationWidget`, `Shared`, `project.yml`, `.github/workflows`, `.github/scripts`, docs.
* Linux Swift 6.0.3 toolchain installed for local verification (no Mac in this environment);
  `swift build` and `swift test` run before and after each change.
* Real network integration: live Transitous queries from the Linux runner (`KITE_VERIFY_TRANSITOUS=1`).
* iOS builds and simulator UI runs only through GitHub Actions on `xcode-27`.

## Findings in the v31 base

| # | Severity | File | Finding | Resolution in v32 |
| --- | --- | --- | --- | --- |
| 1 | High | `VelaCore/Sources/VelaCore/SavedJourney.swift` | `reversed()` executed `copy.destination = origin ?? destination`. A journey starting at "My location" became a trip whose start and end were the same place. No test covered the nil-origin case. | Model the trip as planner state: `origin` (nil = current location), `destination`, `stops`, and `isReturnTrip` for the case where one end is not a place. `reversed()` is involutive; automatic names follow travel order. 8 tests incl. the v31 JSON shape. |
| 2 | High | `App/Sources/Navigator.swift` (old lines 519, 1342, 1410) | Four `Logger` interpolations wrote exact `%.5f,%.5f` coordinates with `privacy: .public`. Spoken route instructions were public too. Anyone collecting a sysdiagnose could reconstruct visited places and destinations. | Public logs now carry route-relative distances, accuracy, speed and state only; spoken text and inferred place names are `.private`. A separate `DiagnosticsLog` holds events in memory only, max 3 h / 800 events; positions are never logged and are omitted from a share unless the user opts in explicitly, then exported as metres from an unknown origin. 5 tests. |
| 3 | High | `App/Sources/RouteEventCoverage.swift` | Every 4 km section was requested in one loop; failures retried after a fixed 60 s forever, sequential order, no back-off, no HTTP 429 handling, no cancellation of a superseded route's work, no cache. On a 400 km route that is ~100 sections × 4 OSM queries each, retried indefinitely. | Replaced the loop with `RouteSectionScheduler` (24 km sliding window, nearest first, one request at a time, 4 attempts max, exponential back-off, 3-failure circuit breaker, cancellation) + `RouteControlCache` (20 min, bounded, walking-aware key) + `EndpointHealth` shared by all Overpass callers (Retry-After, 429/503/timeout, half-open probe). Progress from the navigator slides the window. 21 tests. |
| 4 | Medium | `VelaCore/Sources/VelaCore/Cameras.swift` | `Overpass.fetch` was hard-coded to an upstream User-Agent and did not record any status except 200; `firstAnswer` raced all four public mirrors on every query, including when one was rate-limiting us. | One shared User-Agent, status classification and health recording in `fetch`; mirrors currently resting are skipped. A HTTP 200 whose body fails validation still counts as a failed answer (the validation itself is in `firstAnswer`; see the V33 audit item for the residual gap). |
| 5 | Medium | `App/Sources/AppSettings.swift`, `MapboxSettings.swift` | The Mapbox token was stored in `UserDefaults`, i.e. plaintext in unencrypted device backups. A Google Places key already used the Keychain — the two credentials were treated differently for no reason. | `SecretStore` + `MapboxCredential` migrate the token once, verify the Keychain write before deleting the old copy, and fall back to `UserDefaults` where Keychain is unavailable (sideloading). Mapbox `pk.` tokens are public client identifiers; no paid key became mandatory. |
| 6 | Medium | `App/Sources/Navigator.swift`, `AppSettings.swift` | Voice had three mutually overriding booleans; only "all / alerts only / off" existed. | `VoiceLevel` (all / turns only / alerts only / off) is one authoritative value; every spoken line declares `SpeechKind`, so "turns only" really suppresses warnings and "alerts only" really suppresses turns. 3 tests. Stored switches migrate forward. |
| 7 | Medium | `.github/workflows/*.yml`, `VelaCore/Tests` | No live integration test existed; the Transitous code was validated only with deterministic fixtures, so a dead service could still produce a green build. | `TransitousLiveTests` (plan between two Prague stops, live route map with metro, live departures) is opt-in (`KITE_VERIFY_TRANSITOUS=1`) and **fails** if the service does not answer; a separate workflow runs it. All three passed against the real service. |
| 8 | Medium | `App/Sources/SafeMode.swift` | Safe mode was entered after a single launch whose marker had not been cleared in 120 s. Opening the app and immediately swiping it away could look like a crash; the marker was re-armed after the switch was set, risking a persistent safe-mode loop. | `LaunchHealth` requires two unconfirmed launches within ten minutes; a clean background transition marks the launch healthy; entering safe mode resets the counter. 5 tests. |
| 9 | Medium | `App/Sources/AppModel.swift` | The saved "interrupted trip" kept only destination/stops/mode. After a restart offline there was no route geometry to continue with. | `OfflineJourney`/`OfflineRouteSnapshot` store geometry, manoeuvres and timing atomically in Application Support, max 2 h old, with schema version and sanitising on load. Resume uses the file only when offline; otherwise the planner recalculates. The UI says plainly that no offline rerouting exists. 4 tests. |
| 10 | Medium | `App/Sources/Navigator.swift`, `DirectionsViews.swift` | No way to replay a drive; roundabout, signal and reroute bugs needed a physical car to reproduce. | `GPSReplay` fixtures (east/north metres, no absolute positions, deterministic noise/late/tunnel/poor-fix options) and an in-app replay driven through the same `locationChanged` path. Real fixes are ignored while it runs, nothing replayed is saved, and an orange "Simulated GPS" banner with a Stop button stays visible. 6 engine tests. |
| 11 | Medium | `App/Sources/MapView.swift`, `SettingsViews.swift` | The Transit map layer was a single on/off switch; there was no way to see just trams or just metro. | `TransitMapFilter` maps all 20 `TransitMode`s to 8 categories, keeps official colours, republishes the layer from cached lines (no new network request when toggling), never hides a line used by an active journey. 4 tests. |
| 12 | Low | `App/Sources/AppModel.swift` | A moving tram beside a tram line could be mistaken for boarded because boarding used "speed ≥ 3 m/s and 30 m of progress", with no waiting evidence. | `BoardingDetector`: waiting at the stop near departure, four consecutive aligned fixes above walking speed, ≥120 m along the ride's own line, ≤40 m offset, optional live-vehicle proximity; a bad guess never skips the manual "I'm on board" button. 7 tests. |
| 13 | Low | `App/Sources/KitePages.swift`, `AppModel.swift` | "Reverse" in the saved-journey context menu overwrote the stored journey just by opening it; there was no favourite, rename, duplicate or import/export. | Reverse now opens the opposite direction without mutating the saved copy; saving it is a separate explicit user action. Added favourites, rename, duplicate, `lastUsedAt` ordering, archive import/export with fresh ids and a 5 MB bound. Tests cover v31 JSON decoding, future schema fields being optional and a corrupt archive. |
| 14 | Low | `App/Sources/DataDiagnostics.swift` | The shareable ZIP already warned about the map screenshot but had no preview of what was actually in it, and no separation between technical data and a movement trace. | Detailed diagnostics is now an explicit switch; the trace is omitted from the report unless the user confirms a dialog for that report; recorded positions are cleared when the switch is turned off; a delete button clears memory. The ZIP contains `navigation-events.json`; relative positions are described as **potentially identifying**, not as anonymous. |

## Correctness claims that were checked and **not** changed

* `RoundaboutExitResolver` and `DirectionalRoadControlMatcher` logic is left intact as requested; their
  existing 35 tests still pass. A residual risk remains when OSM answers arrive after the instruction
  was spoken (the navigator freezes spoken manoeuvres) — see `docs/V33_DEVICE_TEST_CHECKLIST.md`.
* One authoritative route/selected-index/ETA state remains in `DirectionsState` +
  `PlanningSession`; no parallel route model was introduced. The offline snapshot is a separate
  *archived copy* and is never mixed with live state.
* App version, bundle id (`app.vela.ios`), iOS 16.2 floor, ARM64, MapLibre and both IPA variants are
  unchanged. No force push, history rewrite or merge was made.

## Problems found but **not** fixed in v32

* `EndpointHealth` records a success in `Overpass.fetch` as soon as HTTP 200 is seen. `firstAnswer`
  validates the body afterwards, so a server that returns HTTP 200 with an error `remark` can reset
  its own failure count. Fixing this needs the validation to flow back into the HTTP layer — v33 P0.
* `RouteSectionScheduler.updateProgress` keeps the maximum distance forever, so one wildly wrong
  map-match would permanently skip earlier sections. Guarding unverified jumps needs a cross-check
  with the tracker's confidence — v33 P0.
* `DiagnosticsLog.report` exports relative positions; with a known start point (home, work) a trace
  can still be re-identified. The UI now says so, but a stronger policy is needed — v33 P0.
* `AppSettings.camerasRestricted` uses the device region, not the place being driven through: a
  Czech phone driving in Germany gets the wrong camera-warning policy. — v33 P1.
* Swift 6 / actor-isolation warnings in `HighwayHeat.swift`, deprecated `Locale.regionCode` and old
  pattern-detection API in `ContentView.swift` were left to v33, where they can be fixed with tests
  instead of suppressing checks.
* The 2,300-line `AppModel.swift` and 1,500-line `MapView.swift` were **not** split in v32. The new
  replay, offline and filter code was deliberately put in separate files rather than making those
  files larger. A real decomposition is v33 work, one coordinator at a time.
* Physical iPhone, SideStore install, Live Activity on a locked phone, battery life and map FPS
  cannot be verified on Linux or in a simulator. None of these are claimed as verified.
