# Kite 2.0 architecture

## Reality first

Kite is one iOS app target plus a WidgetKit extension, with the pure logic in a
local Swift package (`VelaCore`). v29 does **not** introduce eight new framework
targets. Splitting 16k lines into modules for their own sake would add build
complexity and risk exactly the launch failures v28 fought, without making any
behaviour testable that is not testable now.

What exists and where:

```
App/Sources/                 SwiftUI + UIKit app target
  KiteDesignSystem.swift     tokens and shared components (new in v29)
  ContentView.swift          app shell, map screen, search, quick actions, demos
  KitePages.swift            dock, Routes page, Saved page
  MapView.swift              MapLibre renderer, layers, camera, gestures
  AppleMapView.swift         MapKit renderer behind the same MapSurface
  MapSurface.swift           renderer-neutral camera protocol
  NavigationViews.swift      navigation HUD, alerts, trip bar, lane strip
  Navigator.swift            live trip state, voice, reroute, progress
  AppModel.swift             app-wide state and coordination
  PlaceViews.swift           place sheet, photos, reviews, departure board
  DirectionsViews.swift      planning, alternatives, transit bodies
  SettingsViews.swift        settings and diagnostics
Shared/TripActivity.swift    ActivityKit attributes shared with the widget
NavigationWidget/            Live Activity + Dynamic Island UI
VelaCore/Sources/VelaCore/  pure, Linux-testable core
VelaCore/Tests/             unit tests
```

## Layering

1. **VelaCore (pure)** — geometry, route and maneuver models, GPS matching,
   reroute policy, lane approach, roundabout shape, route alternatives, search
   parsing, OSRM/Valhalla/Photon/Google clients, transit planning and
   GTFS-Realtime. No UIKit, no map objects. This is where logic is unit tested.
2. **Services (app target)** — `LocationService`, `LiveCamStore`,
   `WazeHistory`, `Connectivity`, `VoiceSearch`, `JourneyActivity`. Thin
   wrappers around system frameworks with lifecycle handled explicitly.
3. **Coordination (app target)** — `AppModel` owns the state machine: search,
   selection, route planning, navigation, transit, just-drive, parking.
4. **Presentation** — SwiftUI screens and the map renderers. The renderers only
   draw and report gestures; they never own a trip.

The v29 additions follow this split: `RouteAlternatives` is pure and tested in
VelaCore; `QuickActionKind` and the camera memory are plain persisted state;
`KiteDesignSystem` is presentation-only.

## Map rendering

- `KiteMapSurface` is the camera contract both MapLibre and MapKit implement, so
  navigation code is renderer-agnostic.
- Layers are created once (`vela-*` sources/layers) and updated by identity:
  routes, cameras, Waze, transit, puck, places. v29 did not add a second copy of
  any layer.
- The browse camera is now persisted (throttled: at most every 6 s and only
  after 250 m of movement) and restored at creation. Launch order is:
  last area → current fix → neutral world view. No hard-coded London.
- A restored view is kept on the first fix if the user is within 60 km of it;
  otherwise the camera moves to the user. This avoids yanking the map away from
  the area the user left.

## Navigation state

`Navigator` remains the only navigation implementation. v29 changed its
presentation, not its state machine:

- maneuver data → banner, spoken text, and VoiceOver all come from the same
  `Maneuver`/`SpokenText` path;
- lane guidance uses `LaneApproach` (when to show) + `LaneGuide` (which lanes),
  unchanged;
- the "then" maneuver is shown in a dedicated row and highlighted in amber when
  it is under 180 m away, with one combined accessibility sentence;
- alert prioritisation is still `NavigationOverlay.alertsUp` (most urgent
  first, one big card, the rest in a pill). A separate `AlertCoordinator` type
  was **not** introduced: duplicating that ordering would risk two sources of
  truth. Extracting it is a listed next step.

## Persistence and migration

All user data stays in the existing keys and the same bundle identifier
`app.vela.ios`. v29 adds only additive keys:

- `quickActions` (array of raw strings; unknown values are dropped)
- `lastMapCenter`, `lastMapZoom` (browse camera convenience)

Nothing is deleted on upgrade. `TripActivity` remains optional: the SideStore
variant removes the widget extension and turns `NSSupportsLiveActivities` off;
the app's activity code is already guarded by `areActivitiesEnabled` and
availability checks.

## Build and distribution

One build produces both packages; see `docs/KITE_2_PACKAGING.md`.
`VelaCore` tests run on the macOS runner; the app builds for device and for the
simulator in separate workflows.

## Known architectural debt

1. `ContentView.swift`, `MapView.swift`, `NavigationViews.swift` and
   `Navigator.swift` are still large. v29 split presentation into small views
   and moved two pure decisions into VelaCore, but the files remain the main
   maintenance risk.
2. `AppModel` is still the single coordinator; a `NavigationSession` extraction
   is the next safe split (state only, no UI).
3. Alert ordering should become a tested pure function before more alert types
   are added.
4. Map style presets (Classic / Navigation / Minimal) are not a separate
   setting yet; the existing satellite/terrain/Apple/Mapbox choices remain.
