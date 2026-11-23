# Kite v36 live traffic

## Goal

Live traffic must work **while browsing a route-free map**, not only on a planned
or active route. The old design conflated three different things under one
`traffic` flag and, on MapLibre, required `noGoogle` to be off (the overlay there
is Google tiles), so a browsing user often saw nothing.

## The three traffic kinds (§4.3)

V36 keeps them apart so "there is traffic on the map" is not confused with
"the route is slow" or "there is an accident".

| Kind | What it is | Renderer source |
| --- | --- | --- |
| `map` | Live congestion across the visible roads, no route needed | MapKit `showsTraffic`; MapLibre Google tile layer |
| `route` | Congestion on the planned / active route | Polyline spans (`vela-route-traffic`) |
| `incident` | Accidents, closures, hazards (not a measured speed) | Waze reports |

## One shared state model (§4.6)

New `TrafficOverlayState` (`VelaCore/Sources/VelaCore/TrafficOverlayState.swift`)
is the single answer to "is live traffic on this map right now, and why". It
carries:

- kind (map / route / incident), provider (Apple / Google tiles / none),
- renderer, whether the user requested it, whether the renderer supports it,
- whether the data is actually **loaded** (so an on-but-empty layer says
  `loading`, not `on`),
- received-at and the provider's own stated age — a tile download time is explicitly
  *not* presented as the age of its data,
- a severity legend, a human reason, and the last error.

Status is derived: `off` (not requested), `loading` (requested, not loaded),
`unavailable` (renderer/error), `noCoverage` (provider is `none`, e.g. MapLibre in
no-Google mode), `on`. There are 8 unit tests
(`TrafficOverlayStateTests`), including the no-Google MapLibre no-coverage case.

## User control (§4.7)

The existing traffic toggle feeds the map overlay. The Map Layer Inspector now
shows a live **`PROVIDER: STATUS`** line (accessibility id
`layer-inspector-traffic`) so a browsing user (and a tester) can see whether traffic
is on, loading, off, or simply absent for this renderer, instead of a silent gap.

## Honest about no-Google mode

On MapLibre the only live congestion overlay is Google tiles. With `noGoogle` set
there is **no** traffic source, and V36 reports that (`noCoverage` / a reason) rather
than pretending a normal speed-limit or no overlay is "free-flowing traffic". We do
not bypass a provider's terms, API keys or technical protections, and we never draw
a fake heat-map and call it live traffic (§4.5).

## ETA (§4.10)

A visible traffic overlay is not treated as a traffic-aware routing signal. ETA is
only recomputed from a structured source that actually provides congestion data;
the map overlay alone is visual.

## Verified vs. not yet verified

- State model logic: **unit-verified** (8 tests, container/CI).
- Inspector status line and browse wiring: depends on the iOS build + simulator
  smoke results.
- Watching a real busy area and seeing Apple/Google tiles update live on a device:
  **not yet verified** on a physical iPhone — see `V36_DEVICE_TEST_CHECKLIST.md`.