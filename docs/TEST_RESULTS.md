# Test results

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
