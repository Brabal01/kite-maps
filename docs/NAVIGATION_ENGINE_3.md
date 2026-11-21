# Navigation Engine 3.0

Status: implemented in the v30 branch, verified by VelaCore tests and the
simulator UI test. Physical-device feel and battery use are **not** verified.

## One authoritative navigation state

`VelaCore/Sources/VelaCore/NavigationState.swift` owns the lifecycle:

`idle → preparing → waitingForGPS → navigating → gpsUncertain / gpsLost /
offRoute → rerouting → rerouteUnavailable / routeRecovered → arriving →
arrived → ended`

`Navigator` keeps the same speech, camera and alert behaviour, but also owns a
`NavigationSessionState` with a UUID session ID. Every real guidance path in
`AppModel.beginNavigation` now starts from a navigation-grade fix or explicitly
enters `waitingForGPS`; a stale search fix is never presented as a live
position. The pure state table rejects illogical combinations (for example
arrival while a reroute is still loading).

## Reroute Engine 3.0

The existing guarded `ReroutePolicy` is retained. v30 adds:

- an explicit reroute state (`rerouting`, `rerouteUnavailable`,
  `routeRecovered`) instead of a single boolean;
- request generation cancellation in `Navigator.reroute`;
- the original route and instructions remain in use while offline or while a
  request fails;
- `adopt()` keeps the remaining stops and exclusion preferences;
- route recovery is confirmed by the next on-route progress, not by a guessed
  new route;
- telemetry through the existing `trace` logger (no private coordinates are
  added to diagnostics beyond the existing route trace).

## AlertCoordinator

See `docs/ALERT_COORDINATOR.md`. The driving screen no longer sorts alerts
inline: `NavAlertStore` maps camera, Waze, average-speed, aircraft and
road-control data into `AlertCandidate`, then uses the tested
`AlertCoordinator` for priority, direction filtering, de-duplication,
hysteresis and cooldown.

## Lane Guidance 3.0

`LaneGuidanceEngine` (VelaCore) classifies every lane as recommended, suitable,
unsuitable or unknown. It covers turns, motorway exits, splits/merges, a
straight approach before a close next turn, and roundabouts with mapped entry
lanes. It never invents lane geometry; when the router and OSM provide no
usable lane list, the ordinary banner is shown.

`LaneApproach.showsStrip` gained a HUD lead multiplier so Highway mode can show
lanes earlier without changing the Advanced profile.

## Motorway Junction View

`JunctionGuideBuilder` builds a diagram only for a ramp/fork/keep split with at
least one real source: an exit sign, two mapped lanes or a road reference. The
SwiftUI `JunctionDiagram` is a vector Canvas; the card carries the exit number,
road shields, signed destinations, lane count, recommended lane numbers and the
follow-up maneuver. Insufficient data returns `nil`, so no fork is invented.

## Road controls

`ControlDisplayPolicy` separates browsing, free driving, car, walking and
cycling. During car guidance it shows lights/stops/railway crossings only when
they are close and direction is plausible; pedestrian crossings and one-way
markers are browsing/walking information, not driving cards. Unknown direction
is treated as unknown rather than as our green light.

## HUD 3.0

`HUDCatalog` defines Simple, Advanced, Highway and Custom profiles. Settings
store the mode and the three custom toggles. The banner uses the profile for
lane lead, lane visibility, the follow-up turn and junction diagrams. A live
preview is in Settings → Map & display.

## Still not done

- Lane-level map geometry (painted lane polygons) is not drawn on the map.
- Reroute feel and GPS behaviour in tunnels must be checked on a physical
  iPhone; simulator results are not a substitute.
- Alert density is a simple count; there is no per-driver learning.
