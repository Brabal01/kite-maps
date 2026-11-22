# V33 test results

Branch: `iphone-custom-v33-reliability-ux`, PR #11 → `iphone-custom-v32-refinement`.

## Verified build

The code verified by CI is commit `13a78f4` (`v33: remove unused bundle info binding`),
app **0.8.0 (1150)**, bundle `app.vela.ios`, iOS 16.2+, ARM64. Any later commit on the branch is
documentation-only; the IPA artifacts come from `13a78f4`.

* IPA workflow: https://github.com/Brabal01/kite-maps/actions/runs/45006863802 — **success**,
  Full and SideStore packaged and verified from the same commit, **0 compiler warnings**.
* Simulator workflow: https://github.com/Brabal01/kite-maps/actions/runs/45006863863 — **success**:
  `PlanningUITests` 1/1, `V31UITests` 3/3, `V33UITests` 3/3, plus three launch/smoke cycles and
  the screenshot pass (light and dark).
* Live Transitous workflow on the same commit:
  https://github.com/Brabal01/kite-maps/actions/runs/45009296635 — **success**.
* Artifacts: `Kite-v33-Full-ipa` (14747933193), `Kite-v33-SideStore-ipa` (14747169678),
  `Kite-v33-Test-Results` (14748187305), `Kite-v33-Simulator-Screenshots` (14748494558),
  `Kite-v33-Performance-Results` (14747624858).

## VelaCore (Swift 6.0.3, local Linux)

* `swift test`: **420 tests, 0 failures, 6 skipped** when live checks are off.
* `KITE_VERIFY_TRANSITOUS=1 swift test`: **420 tests, 0 failures, 3 skipped** — the three skips are
  Darwin-only compression tests; all three real Transitous checks ran and passed.
* New deterministic suites added in v33:
  * `OverpassAcceptanceTests` (5) — HTTP 200 with an error remark, truncated JSON, caller-rejected
    body, validated answer clearing the circuit, non-200 never accepted, timeout classification,
    read-only status.
  * `RouteSectionProgressTests` (6) — low-confidence jump rejected, confirmed jump accepted, short
    jumps allowed, backwards correction ignored, non-finite values ignored, repeated bad fixes.
  * `CameraJurisdictionTests` (4) — known codes, unknown never allowed, device region only after
    acknowledgement, acknowledgement cannot override a known restriction.
  * `GoldenNavigationFixtureTests` (4) — self-contained roundabout, tunnel and wrong-turn fixtures,
    corrupt fixture rejection.
  * `DiagnosticsTests` extended (6) — three export levels, previewable JSON, 500 m/15 s snapping,
    potential-identification note, redaction, retention and capacity.
  * `EndpointHealthTests` extended (9) races, backoff, Retry-After, half-open probe.
  * Plus the 400 v32 tests, unchanged.

## Live Transitous integration

Separate workflow, opt-in with `KITE_VERIFY_TRANSITOUS=1`, fails rather than skips when the service
does not answer. Three tests pass: planning between two Prague stops, the live route map with metro
lines, and live departures near a central stop.

## iOS CI (GitHub Actions, xcode-27)

* Workflows on the v33 branch: `Build custom iPhone IPA` (Full + SideStore from one commit),
  `iOS simulator smoke test` (planning, v31 and v33 UI suites, launch loop), and
  `Transitous live integration`.
* Final results for the verified commit are recorded on PR #11 and in the workflow links listed in
  the final report. Only those runs are evidence of IPA and simulator success.

## Benchmarks

`VelaCore/Sources/vela-bench` produces `Kite-v33-Performance-Results` in CI. Local numbers on this
Linux runner (single process, no network, wall clock, pure algorithms — **not** iPhone FPS):

| Operation | Iterations | µs / iteration |
| --- | --- | --- |
| `Geo.project` on a 1,000-point line | 10,000 | 41.14 |
| `RouteTracker.update` (snap + progress) | 5,000 | 139.56 |
| `RouteSectionScheduler` next + succeed | 5,000 | 153.43 |
| `GPSReplayPlan.schedule` (300 fixes) | 500 | 371.42 |
| `DiagnosticRedactor.sanitize` | 20,000 | 6.43 |
| `OfflineRouteSnapshot` encode + restore | 2,000 | 1246.64 |
| `SavedJourney` decode | 10,000 | 24.11 |
| `RouteControlCache` store + load | 10,000 | 1.18 |

These are baseline measurements, not claims of improvement. No before/after percentage is asserted.

## Not verified here

Physical iPhone, SideStore installation, Live Activity on a locked screen, battery life, map FPS,
and real road behaviour of roundabout/signal resolution. See `docs/V33_DEVICE_TEST_CHECKLIST.md`.
