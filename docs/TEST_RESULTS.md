# Test results

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
