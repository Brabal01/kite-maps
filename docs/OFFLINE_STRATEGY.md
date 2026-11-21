# Offline strategy — v30 status

Three different promises must not be mixed.

## Offline Journey (not implemented yet)

A route can already survive a temporary network loss while navigation is
running: `Navigator` keeps the current route, geometry, maneuvers and stops, and
does not replace it with a guessed reroute. This is **not** a persisted offline
journey after an app restart.

Next safe step: encode a completed `Route` (polyline, maneuvers, distances,
preferences, stops) into a versioned file, validate it on load, and offer it in
Saved Journeys with a clear "offline preview" label.

## Offline Maps (not implemented)

No map tiles are downloaded in v30. OpenFreeMap/OSM tile terms, storage limits
and update policy need review before shipping. There is no UI claim that offline
maps exist.

## Offline Routing (not implemented)

No local OSRM/Valhalla graph is packaged. The app continues to use the online
routers and their existing fallbacks. GPX tracks are imported as geometry
between their ends; they are not an offline routing engine.

## GPX

`VelaCore/GPX.swift` provides bounded parsing (5 MB, 100,000 points), coordinate
validation, elevation/time reading, distance and climb calculation, and export
of a planned route. Imported GPX is marked `isGPXTrack` and the UI says it is a
track, not turn-by-turn guidance.
