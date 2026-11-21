# Kite Maps — improvement roadmap

This is a living backlog, not a claim that everything below exists. Items already shipped are
marked **done**; everything else needs code and tests.

## v31 status

- **Done (v31)**: `RoundaboutExitResolver` with evidence ordering, legal-exit
  counting, dual-carriageway merge, ambiguity handling, one authoritative
  maneuver, diagnostics.
- **Done (v31)**: `DirectionalRoadControlMatcher` with way/direction matching,
  stop-line de-duplication, route-distance display, browsing vs driving policy.
- **Done (v31)**: `TransitLineIdentity`, mode classification, official colours,
  contrast-safe text, LineChip 3.0, TripRow 3.0, journey timeline, shared-track
  map offsets, mode-specific vehicle icons.
- **Done (v31)**: 48 new VelaCore tests (336 total on Linux, 3 Darwin-only skips)
  and v31 screenshot steps.
- **Partial (v31)**: roundabout diagnostics are in Settings → Diagnostics and
  the shared ZIP; there is no standalone roundabout debug map overlay.
- **Partial (v31)**: simulator screenshots and IPA builds are wired into CI but
  physical SideStore installation is still unverified.
- Next (P1): in-app GPS replay UI with recorded/synthetic drives and golden
  fixtures for roundabout/signal/transit scenarios.
- Next (P1): physical-device verification of the v31 checklist.
- Next (P2): offline journey persistence with the saved route geometry and
  maneuvers; transit map filters; user-adjustable control density and transit
  icon size.
- Next (P2): transit Live Activity card with line colours.
- Next (P3): turbo/spiral roundabout lane modelling from painted arrows.


## v30 status

- **Done (v30)**: explicit `NavigationSessionState` and navigation-grade entry
  guard; reroute lifecycle and offline route preservation.
- **Done (v30)**: tested `AlertCoordinator`, `LaneGuidanceEngine`,
  `JunctionGuideBuilder`, `ControlDisplayPolicy`.
- **Done (v30)**: seven map presets, adaptive POI/label/building density,
  Navigation mode while driving, MapKit POI/building subset.
- **Done (v30)**: HUD Simple/Advanced/Highway/Custom with preview.
- **Done (v30)**: saved journeys, GPX import/export with bounded validation.
- **Partial (v30)**: settings regrouped and search is not yet implemented;
  offline journey/map/routing are documented but not shipped.
- Next (P1): physical-device reroute/GPS/performance verification.
- Next (P2): settings search, along-route detour ranking, richer Live Activity
  fields, offline journey persistence.
- Next (P3): offline map areas and local routing graph.

## v29 status

- **Done (v29)**: one packaging/signing/verification path, two IPA variants from
  the same build, matching app/extension minimum OS, monotonic build numbers.
- **Done (v29)**: Kite Design System 2.0 tokens; map home, search, quick actions,
  four-tab dock, Routes page, camera restoration, Navigation HUD 2.0, place
  header, planning surfaces, tested route-alternative filtering.
- **Done (v29)**: screenshot workflow for SE/standard/Max, light/dark, large
  text, long names, with a mechanical blank-frame check.
- Next (P2): extract alert prioritisation into a tested `AlertCoordinator`; no
  second implementation may exist during that change.
- Next (P2): dedicated motorway junction diagram from mapped exits/lanes.
- Next (P2): adaptive map style presets (Classic / Navigation / Minimal) as one
  setting rather than several independent toggles.
- Next (P2): extract `NavigationSession` state from `AppModel` without moving UI.
- Next (P3): saved journeys, shortcut reordering, MHD card polish, richer Live
  Activity states, offline areas.

## Navigation core

- **Done (v27)**: departure evidence separated from match confidence; weak-but-usable GPS can
  confirm a real departure; dead-reckoned positions cannot trigger arrival; GPS modes for browse,
  drive, walk/bike, transit and background.
- **Done (v26)**: accuracy/heading/history-aware map matching, parallel-road protection,
  confidence/precision reporting, dead reckoning for short GPS gaps.
- **Done (v26)**: guarded reroute policy and stale traffic-request cancellation.
- **Done (v26)**: remaining ETA from mapped traffic spans with proportional fallback.
- Next: map matching with elevation/bridge layer and lane-level road geometry where OSM supplies it.
- Next: predictive ETA using observed speed history per road class; label it as an estimate, never
  as live traffic unless the provider actually sends live traffic.
- Next: a dedicated reroute state machine with explicit timeout/cancel telemetry in diagnostics.

## Navigation guidance

- **Done**: roundabout layout/exit counts from the selected route, lane presentation, straight-on
  city lanes, two-step preview, sign destinations, voice/banner consistency.
- Next: `destination:lanes` and `turn:lanes` enrichment from OSM where the router omits them.
- Next: country-aware spoken units and junction naming for more languages.
- Next: motorway diagram mode using mapped gantries and exits.

## Camera and rendering

- **Done**: speed/turn-aware `NavZoom`; smooth `NavGlide`; 3D/follow/manual zoom; north-up.
- **Done (v26)**: skip identical frames while stationary.
- Next: profile map camera updates on a physical device; consider 30 Hz camera with 60 Hz puck.
- Next: adaptive label density and reduced building detail at speed.

## Worldwide providers

- **Done**: keyless Google web search, OSM/Photon fallback, OSRM/Valhalla fallback, Transitous.
- **Done (v27)**: GTFS-Realtime identity matching by feed/trip/route/direction/service date,
  overnight service days, freshness levels and stale vehicle filtering.
- **Done (v27)**: keyless Mobility Database discovery of public GTFS-Realtime feeds by coverage.
- **Done (v26)**: optional GTFS-Realtime feed for any region.
- Next: one shared HTTP client with per-provider timeout, cancellation, cache, freshness and
  circuit breaker; surface provider health in diagnostics.
- Next: automatic transit feed discovery by bounding box/agency, with explicit coverage limits.
- Next: regional toll/vignette/low-emission data with an "unknown" state, never guessed.
- Next: legal/technical review of CarPlay; do not ship it before entitlement and review.

## Places and maps

- Next: unify Google/OSM/Apple place records and keep stable provider identity.
- Next: native review pagination where the source supports it; otherwise mark the sample clearly.
- Next: offline map areas, offline search and offline routing (OSRM/Valhalla graph packaging).
- Next: cycling elevation/GPX import, round trips, hiking profiles.
- Next: more building entrances and accessible routes.

## iOS platform

- Next: richer Live Activity/Dynamic Island states and haptic maneuver cues.
- Next: widgets for saved places and next departure.
- Next: Shortcuts for home/work/stop and share-ETA actions.
- Next: verify background location/GPS behaviour on a physical iPhone after 30 s, 2 min and 10 min.

## UI and accessibility

- Next: configurable banner layout and simple/advanced modes.
- Next: landscape-specific layout and larger Dynamic Type coverage.
- Next: accessibility audit of map controls, banners, live activities and transit rows.
