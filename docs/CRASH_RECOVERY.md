# Crash recovery — v28 stability

## What is known

- The v27 IPA was built successfully (build 1045, artifact verified arm64/widget/signature).
- It reportedly crashes on a physical iPhone.
- **No `.ips`, `.crash` or Console backtrace from the phone was available in this workspace.**
  The root cause is therefore not confirmed. The v28 work is a diagnostic and hardening build,
  not a claim that the v27 crash is definitively fixed.

## Suspects inspected

The v26→v27 diff was reviewed with particular attention to startup:

1. `LocationService` now changes `desiredAccuracy`, `distanceFilter`, `activityType`,
   `pausesLocationUpdatesAutomatically`, `allowsBackgroundLocationUpdates` and
   `showsBackgroundLocationIndicator` in several modes. iOS raises an Objective-C exception when
   background updates are enabled without the `location` background mode, or in some background
   transitions.
   - v28 only enables them when the generated Info.plist actually contains `UIBackgroundModes`
     `location`, and never while the app is already in the background.
2. `VelaApp` previously constructed `AppSettings` before the scene. Safe mode now avoids
   `ContentView`, which also avoids `AppModel`, MapLibre/MapKit, location startup, network
   discovery and Live Activities.
3. `TransitCatalog` is only touched when a transit journey is planned, not at launch. Its CSV
   header map no longer uses `Dictionary(uniqueKeysWithValues:)`, so a duplicate/renamed column
   cannot trap. Responses remain size-limited by the catalog and a 25 s timeout.
4. `TransitRealtime` is only used after a transit plan. Its parsers use bounded readers and do not
   index the payload without checks.
5. No `fatalError`, `try!`, `as!` or forced collection indexing was found in the new v27 path.
   The remaining force unwraps are constant `TimeZone(secondsFromGMT: 0)!` and existing legacy
   code.

## Safe mode

- Launch argument: `--safe-mode`.
- Persisted switch: *Settings → About → Start in safe mode next time*.
- Automatic: if the previous launch did not reach its first healthy screen (10 seconds), the next
  launch enters safe mode. The marker is stored in `UserDefaults`; no user data is removed.
- Safe mode shows version/build, bundle id, the last MetricKit crash diagnostic, and a short
  launch trace. It does not start location, maps, network requests or Live Activities.
- *Leave safe mode* turns the switch off; Kite must be closed and opened again for the normal path.

## Simulator verification (build 1051)

- Run `44794890053` launched the app three times normally, once with location denied and once in
  safe mode. All five processes stayed alive for the test window.
- MapLibre initialised in the four normal launches and not in safe mode, so the safe-mode branch is
  actually bypassing the map stack.
- No crash, fatal or uncaught-exception lines appeared in the collected logs.
- This proves the simulator launch path and safe-mode split; it does not prove the physical iPhone
  crash is fixed. The v27 crash log is still required for that claim.

## Diagnostics added

- `LaunchTrace`: up to 40 timestamped, privacy-safe milestones (`app init`, `AppModel init`,
  `LocationService init/start`, map creation, first location).
- `CrashDiagnostics`: MetricKit `MXCrashDiagnostic` subscriber. iOS delivers exception type,
  signal, termination reason and the call-stack tree on a later launch. The app stores only these
  technical fields, never coordinates or queries.
- `simulator-smoke.yml`: builds for an iPhone simulator, installs the app, launches it three times,
  then launches `--safe-mode`; fails if the process is not alive, and uploads logs/screenshot.

## What still must be done with the phone

1. Install the v28 IPA.
2. If it crashes, relaunch; the next launch should enter safe mode automatically.
3. On the safe-mode screen, read/share the last MetricKit crash (if delivered) and the launch
   trace.
4. If safe mode also crashes, the fault is before the normal UI (startup, signing, framework or a
   stored setting); send the safe-mode trace and the IPA/device/iOS version.
