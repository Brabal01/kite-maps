# Kite v29 QA checklist

Status legend: **A** = verified automatically in CI, **M** = verified manually
in this workspace (simulator/log), **U** = not verified (needs a device, a
service, or a human review).

## Build and packaging

| Check | Status | Evidence |
| --- | --- | --- |
| VelaCore unit tests | A | `swift test` in the IPA workflow |
| Release device build (arm64) | A | `xcodebuild … -sdk iphoneos` |
| Simulator build | A | `simulator-smoke.yml`, screenshot workflow |
| Widget signed before the app | A | `sign-app.sh` order + `codesign --verify --deep --strict` |
| App/extension build and version numbers match | A | `verify-ipa.sh` |
| App/extension minimum OS match | A | `verify-ipa.sh` |
| Full IPA contains NavigationWidget | A | `verify-ipa.sh full` |
| SideStore IPA contains no extension and no Live Activities claim | A | `verify-ipa.sh sidestore` |
| No emulator slice, no foreign provisioning profile | A | `verify-ipa.sh` |
| Physical SideStore install | U | requires the phone |

## First launch and stability

| Check | Status |
| --- | --- |
| Cold launch reaches the map | A (simulator) |
| Three repeated launches survive | A (simulator smoke) |
| Launch with location denied | A (simulator smoke) |
| Safe mode launch | A (simulator smoke) |
| Launch with v28 saved data | U (covered by additive keys + unchanged IDs, not executed) |
| Background → foreground | U (device) |
| Lock/unlock with navigation running | U (device) |

## Map

| Check | Status |
| --- | --- |
| No London flash before the first fix | M (code path: saved → fix → neutral) |
| Restored area kept when the fix is nearby | M (code path) |
| First fix centres when far from the restored area | M (code path) |
| MapLibre and MapKit both start from the same camera | M (both call `model.mapStart`) |
| Layer objects are not recreated per settings change | M (existing `vela-*` identity kept) |
| GPS heading arrow and compass | U (device) |
| 3D buildings while navigating | U (visual/performance on device) |
| Style switching (satellite/terrain/Apple/Mapbox) | U (visual) |

## Search and places

| Check | Status |
| --- | --- |
| Search bar focus, submit, clear, voice button | M (simulator screenshots) |
| Quick actions: Home/Work/Parking/Recent | M (simulator) |
| Hiding a shortcut and adding it back | M (settings binding) |
| Place sheet opens and closes repeatedly | M (demo steps) |
| Long place name does not overflow | A (screenshot captured; human review pending) |
| Photos/reviews sheets | U (network/provider dependent) |

## Route planning

| Check | Status |
| --- | --- |
| All four modes load | U (live routers) |
| Alternatives collapse near-identical answers | A (unit tests) |
| Selected alternative changes the map | U (visual) |
| Add stop / reorder / reverse | U (device) |
| Route options (tolls/highways/walking speed) | M (existing paths kept) |

## Navigation HUD

| Check | Status |
| --- | --- |
| Banner shows distance, instruction and road | M (light/dark navigation screenshots) |
| Exit number, signed destinations and lane row | M (code path + earlier roundabout demo; not in the final screenshot frame) |
| Lanes shown only when data exists and close enough | M (existing `LaneApproach` path) |
| Then-row appears for close maneuvers | M (code path) |
| Roundabout diagram uses real exit geometry | A (existing roundabout tests) + M (demo) |
| Trip bar: ETA, remaining, add stop, steps, end | M (demo) |
| Voice instruction matches on-screen text | M (same `SpokenText` source) |
| Left-hand traffic | A (existing `Geo.drivesOnLeft` tests) |
| Reroute in a simulated departure | U (needs GPS replay on device) |

## Transit

| Check | Status |
| --- | --- |
| Timetable shows without live feed | U (live Transitous) |
| Live delay/stale labelling | A (existing VelaCore tests) |
| Transfer warning | A (existing tests) |
| Vehicle position freshness | A (existing tests) |
| New card layout | M (demo `transit`) |

## Accessibility and layout

| Check | Status |
| --- | --- |
| Dark and light palette | M (screenshots in `docs/screenshots/v29/`) |
| Long names | M (Saved page truncation reviewed) |
| Large Dynamic Type | U (no captured frame in the final run) |
| Small phone (SE) fits banner + trip bar | U (device-type capture not available on the final runner) |
| Landscape | U (no automated orientation capture) |
| Reduce Motion respected by new transitions | M (code reads the environment) |
| VoiceOver labels for banner, lanes, dock, quick actions | M (code) |

## Honest limitations

- Screenshot automation proves a frame was drawn and is not blank. It does not
  prove a layout is good; review the uploaded images.
- No physical iPhone is available here: SideStore install, locked-screen GPS,
  battery, compass and CarPlay remain unverified.
- Live providers can be down; the app is expected to fall back, and unit tests
  use synthetic responses.
