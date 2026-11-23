# Kite Maps V35

V35 starts from `d38bd40`, the V34 head that passed both its custom IPA and simulator workflows. See [V34 IPA build](https://github.com/Brabal01/kite-maps/actions/runs/45064671677) and [V34 simulator checks](https://github.com/Brabal01/kite-maps/actions/runs/45064677633).

## Olomouc map rendering

The original iPhone frame shows Apple Maps attribution, a blue active route and thin off-route red, blue and cyan lines. V34 enabled the Transitous network for every active journey, including car navigation. The shared coordinator supplied that network to both MapLibre and MapKit. MapKit rendered each network line using its supplied color. Kite's alternative road routes were gray, traffic spans were red or amber on the active route, and Waze incidents were point features. The Apple basemap, Apple traffic and police heat raster are independent of Kite's colored network.

The public Transitous route-map response for 49.585/17.248 to 49.603/17.286 at zoom 14 contained a multi-point bus path with a straight edge of about 2.2 km and a three-point tram path with an edge of about 1.08 km. Those paths passed V34's check because it rejected long chords only in two-point non-metro paths. The V35 parser, run on the downloaded response, retained valid street segments. Its longest remaining bus and tram edges touching the box were 963 m and 682 m. The test fixture reproduces the shape defect with synthetic points. The original device's exact layer state and original fetched tiles were unavailable.

Kite now removes the transit network when ordinary road guidance starts, clears obsolete overlays on mode changes and invalidates the render cache when a new style loads. The network and colored itinerary remain available for transit planning and guidance. Camera and heading updates are shared between the two renderers.

Enable Map Layer Inspector under Diagnostics, return to the map and use the eye controls while parked. Export includes layer names, sources, feature counts and data times where supplied. MapKit does not expose feature counts or source timestamps for its own traffic tiles. Close the inspector to restore temporarily hidden layers.

## Live traffic

The traffic toggle gates native Apple traffic or the existing MapLibre tile overlay and the colored spans on a planned drive. A successful refresh on the same route can update the spans without replacing the route, resetting the tracker or changing the selected route. Pieces that project to a different road or in reverse order are discarded. A five-minute validity window keeps old colored spans from continuing to represent current conditions.

## Transit

Set **Public transport → Alternate MOTIS server** to the HTTPS base URL of a MOTIS installation that serves `/api/v2/plan` and has current regional GTFS. It is contacted after an error or an empty result from Transitous. The planner preserves the selected time and credits the source of the itinerary. The setting is empty by default. Kite provides external choices including Tallinja in Malta and Metro İstanbul for rail in Istanbul.

In spot checks on 23 November 2026, Transitous returned no itineraries for Valletta to Malta Airport and Taksim to Sultanahmet. The result applies to those requests and times. The three opt-in live checks in Prague passed.

## Verification

- Linux Swift 6.2.4: 435 Core tests discovered, 429 passed, six skipped. The three opt-in Transitous tests passed in a separate run.
- Simulator test: same drive in MapKit and MapLibre, transit layer isolation, start and end of road guidance, renderer switch and foreground return. The workflow exports screenshot attachments.
- On an iPhone, repeat the original drive near třída Kosmonautů with both renderers and traffic enabled, then switch to transit and back. Test an actual reroute, style change and lock-screen return. Compare the arrow while stationary and following a moving GPS course. Repeat after installing both IPA variants independently.
