# V33 architecture and change log

Branch: `iphone-custom-v33-reliability-ux` (from v32 `c812777`). Target PR: v33 → v32.
Nothing is merged automatically into `main`; no history is rewritten.

## Guiding decision

V33 does **not** split `AppModel.swift` or `MapView.swift` wholesale. Both are large but centralised,
and a mechanical split would move bugs around without making them testable. Instead, each new concern
is a small compiled unit with its own tests, and the large files only call into it:

| Concern | Owner | Why it is separate |
| --- | --- | --- |
| Overpass circuit state | `VelaCore/EndpointHealth` | Thread-safe, synchronous, pure enough to test every HTTP status; shared by all mirror callers. |
| Road-section work | `VelaCore/RouteSectionScheduler` | Pure value type: request order, retry budget, breaker and progress are deterministic. |
| Road-event answers | `App/RouteEventCoverage` + `VelaCore/RouteControlCache` | The App-owned worker slides the window; the cache is bounded and walking-aware. |
| Diagnostics | `VelaCore/DiagnosticsLog` + `App/DataDiagnostics` | Three export levels and an in-app preview, so a user never shares more than they understood. |
| Camera law | `VelaCore/CameraJurisdiction` + `App/JurisdictionService` | A pure policy plus a geocoder; the device region is never used as proof of location. |
| Voice | `VelaCore/VoiceLevel` | One authoritative level instead of three booleans. |
| GPS replay | `VelaCore/GPSReplay` + `App/ReplaySession` | Fixture engine and clock are separate from the app position path; replay fixes cannot be stored. |
| Offline journey | `VelaCore/OfflineJourney` | An archived copy of a route, never a parallel live route model. |
| Transit filters | `VelaCore/TransitMapFilter` | Category mapping and sanitising are testable without SwiftUI. |
| Boarding | `VelaCore/BoardingDetector` | Conservative, deterministic evidence rules; the manual button remains. |

`DirectionsState` + `PlanningSession` remain the single source of truth for the live route,
selection, ETA and remaining distance. The offline snapshot is only read when the phone is offline
at restart and is labelled as a saved copy.

## P0 changes

1. **Validation before success.** `Overpass.fetch` used to clear the circuit on HTTP 200. Now
   `Overpass.accept` is the single acceptance point: an error `remark`, truncated JSON or a body the
   caller rejects counts as `.invalidResponse`; only a validated answer clears the state.
   `429`, `503` with `Retry-After`, timeouts and 5xx are classified centrally; cancellation is not a
   server failure. `EndpointHealth.status` exposes read-only state for diagnostics.
2. **Progress guard.** `RouteSectionScheduler.updateProgress` keeps monotonic progress but ignores a
   jump larger than 300 m when the map-match confidence is below 0.6 (the first fix has no earlier
   reference and is accepted). `RouteEventCoverage` cancels its sleeping worker when the window
   actually changes, so progress wakes it without a shorter poll, and evicts events more than 5 km
   behind the vehicle.
3. **Partial answers are not cached.** `RouteControls.lookupDetailed` reports whether both providers
   answered; `RouteEventCoverage` stores a cache entry only when the answer is complete and the
   mirrors are healthy.
4. **Diagnostics levels.** `.technical` (no movement), `.pseudonymized` (500 m/15 s snapped) and
   `.replay` (full relative offsets, explicit consent). The user previews the exported JSON before
   sharing and can delete the in-memory log. Relative traces are documented as *potentially
   identifying*, never as anonymous.
5. **Jurisdiction.** Country comes from reverse geocoding the route origin, cached for the session.
   Unknown means warnings are suppressed; the old device-region fallback now requires an explicit
   "I check local law myself" acknowledgement. The navigator reads one computed gate
   (`effectiveCameraWarnings`).
6. **Warnings.** `HighwayHeat.minZoom/maxZoom` are `nonisolated` constants; clipboard link detection
   uses the async `UIPasteboard` API (iOS 15+); `Locale.current.region.identifier` replaced
   deprecated `regionCode`. The build's known warnings were removed rather than suppressed.

## P1 changes

* `ReplaySession` owns a simulated drive's clock: fault profiles (clean, GPS noise, tunnel,
  late fix, wrong turn), pause/resume, 0.5–4× speed, skip to the next manoeuvre and simulated
  offline. It calls back with simulated fixes only; `AppModel.locationChanged(_:simulated:)` ignores
  real fixes while it runs and skips trip memory and Live Activity for replayed ones. The orange
  banner and a Stop control remain visible.
* Golden navigation fixtures are self-contained JSON (`VelaCore/Tests/Fixtures`): a four-exit
  roundabout, a tunnel with a real gap, and a wrong-turn jump. Tests decode them, drive the real
  tracker and assert progress, gap and off-route behaviour.
* `RoutePreviewSheet` is a planning-time walk through manoeuvres: step picker, camera focus, lanes,
  roundabout exit, mapped events near the step and an animated walk-through. It explicitly never
  creates a GPS source and never starts navigation, so it is distinct from diagnostic replay.
* Settings search indexes the existing pages by title, description and keywords and opens the same
  page; quick actions can be reordered, removed, re-added and reset to defaults.
* `vela-bench` is a deterministic microbenchmark executable; CI uploads real numbers rather than
  estimated improvements.

## What was deliberately not done

* No wholesale AppModel/MapView split, no new route model, no CarPlay, no offline map tiles or
  offline routing. Saved geometry is a read-only archived copy, not a router.
* No "reroute simulation" button: triggering a real reroute from a replayed fix would need a live
  router and would mix a developer tool with production navigation. The wrong-turn fixture exercises
  the tracker instead.
* No claim that camera-law coverage is exhaustive; the code labels the list as the app's current
  conservative set, not legal advice.
* Physical-device features (battery, locked-screen Live Activity, SideStore installation, map FPS)
  are listed as unverified in `docs/V33_DEVICE_TEST_CHECKLIST.md`.
