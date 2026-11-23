# Kite v36 test results

These are the results **as far as they can be verified in the environment this
build was produced in** (a Linux container running `swift:6.0` for the VelaCore
suite, and GitHub Actions for the iOS build + simulator). Physical-device checks
are enumerated separately in `V36_DEVICE_TEST_CHECKLIST.md`.

Unless a number is marked *CI pending*, it is a real, reproducible run.

## VelaCore unit tests (in-container, `swift:6.0`)

Full suite:

```
Executed 440 tests, with 6 tests skipped and 0 failures
```

Breakdown (all pass):

- `RoundaboutExitResolverTests` — 16
- `RoundaboutTests` — 10
- `OlomoucRoundaboutTests` (new golden fixture) — 5
- `TrafficOverlayStateTests` (new) — 8
- All pre-existing suites (routing, diagnostics, GPS replay, transit, offline,
  jurisdiction, search, …) — unchanged, 0 failures.

### New: roundabout exit accuracy (the Olomouc bug)

| Test | Asserts |
| --- | --- |
| `testVejdovskoeRouteThroughTakesSecondNotFirst` | Router says 1, map counts 2; the through drive resolves to **2**, source `.osmTopology`, certain |
| `testVejdovskoeFirstArmIsStillFirst` | The first (service) arm still resolves to 1 |
| `testOsmOverridesWrongRouterWhenTopologyConfirmed` | Full pipeline: number=2, words="2nd exit", way-off carries 2 |
| `testUnconfirmedRouterNumberIsNotCertain` | A lone router number is never `isCertain` (confidence 0.55) |
| `testUnconfirmedNumberShowsDirectionNotAGuess` | §3.7: unconfirmed → `exit` nil, direction kept, routerExit still evidence |

### New: live traffic state

`TrafficOverlayStateTests` (8) cover off / on / loading / unavailable / no-coverage,
the three-kind separation, and the no-Google MapLibre provider case.

## CI (GitHub Actions, on PR #14 toward v35)

| Workflow | Item | Result |
| --- | --- | --- |
| build | Check search code (VelaCore `swift test`) | *pending* |
| build | Build iPhone app | *pending* |
| custom-ipsa | Build Kite.ipa (Core + both IPAs) | *pending* |
| simulator | Launch Kite in the simulator (v31/v33/v34/v35 UI + launch smoke) | *pending* |

Filled in after the runs finish.

## Notes

- The failing v35 simulator assertion (`V35UITests` line 39) is addressed by making
  the deterministic rail-demo fixture independent of map zoom, so the rail layer
  reappears after navigation ends — see `V35_MAP_TRAFFIC_TRANSIT.md` and the fix
  commit in this PR.
- Benchmark executable (`vela-bench`) and performance artifact are produced by CI;
  no synthetic speed-ups are claimed.