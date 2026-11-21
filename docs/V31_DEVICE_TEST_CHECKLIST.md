# Kite Maps v31 — device test checklist

Branch: `iphone-custom-v31-navigation-transit`
Base: `iphone-custom-v29-redesign` at `804822f` (contains v30 PR #8)

Mark each item on a real iPhone. Items marked **CI** can also be checked in the
simulator workflow; a physical SideStore install must not be inferred from CI.

## Packaging

- [ ] Full IPA installs over the v30 build without deleting saved places.
- [ ] SideStore IPA installs and launches; no widget appears in the app library.
- [ ] Full IPA shows the Navigation Live Activity.
- [ ] App and widget build numbers are identical.
- [ ] Bundle id is `app.vela.ios`; minimum iOS is 16.2.
- [ ] MapLibre renders the map on first launch (no blank map).

## Roundabouts

- [ ] A four-arm roundabout entered from the south, third exit east: banner,
      diagram, voice and Live Activity all say the 3rd exit.
- [ ] A router number that disagrees with the map is corrected by the map
      (compare the banner with the road signs).
- [ ] A roundabout with a service road: the service arm is not counted unless it
      is a legal exit.
- [ ] A dual carriageway roundabout: the in/out arms count as one road.
- [ ] Two roundabouts close together: each gets its own number and picture.
- [ ] A mini-roundabout keeps its number after the OSM ring query returns.
- [ ] When the sources conflict and the map cannot settle it, no ordinal is
      shown; the banner says "take the exit onto …" or "check signs".
- [ ] A prompt already spoken is not contradicted by a late OSM answer.
- [ ] A reroute recalculates the roundabout; an old answer cannot change the new
      route's exit.

## Directional traffic lights

- [ ] A light on our approach appears in navigation.
- [ ] A light on the opposite carriageway does not appear as ours.
- [ ] A light on the crossing road does not appear as ours.
- [ ] Two signalised junctions 20 m apart both appear.
- [ ] Two heads on one stop line appear once.
- [ ] A turn-lane light appears only when the route takes that lane.
- [ ] A light on an overpass is not shown for the road below.
- [ ] A light under a bridge on our road is shown.
- [ ] A passed light does not come back into the upcoming strip.
- [ ] Walking shows pedestrian crossings and hides car-only furniture.
- [ ] Browsing shows context lights without claiming they are ours.
- [ ] With the detailed lookup unavailable, the fallback is clearly a
      proximity hint, not a confirmed instruction.

## Transit

- [ ] A metro line uses its official colour and a metro icon.
- [ ] A tram uses a tram icon, not a bus icon.
- [ ] A bus with no official colour uses the mode fallback and is not labelled
      official.
- [ ] A regional/suburban train is not shown as a metro because its line is
      called `S1`.
- [ ] A trolleybus/coach is distinguishable from a bus.
- [ ] A ferry uses the ferry icon.
- [ ] Line chips are readable in light and dark mode.
- [ ] A long line name truncates without breaking the card.
- [ ] The journey timeline colours each ride and dots each walk.
- [ ] A transfer has its own node.
- [ ] A shared track on the map shows more than one line.
- [ ] The same line has the same colour in the card, timeline, departure board
      and map.
- [ ] Delay/freshness is shown separately from colour.
- [ ] Large Dynamic Type does not clip the chips or the timeline.

## Regression (must stay working)

- [ ] PlanningSession and the GPS planning lifecycle.
- [ ] Manual start without GPS.
- [ ] Drive / walk / bike / transit switching.
- [ ] NavigationSession 3.0 and reroute lifecycle.
- [ ] Lane Guidance 3.0 and Motorway Junction View.
- [ ] AlertCoordinator, HUD profiles, map presets, 3D buildings.
- [ ] Saved journeys, GPX import/export.
- [ ] Transit realtime, Safe Mode, CrashDiagnostics.
- [ ] SideStore install and launch.

## Evidence to attach

- device model and iOS version;
- build number from Settings;
- screenshot of the roundabout banner and diagram;
- screenshot of a signalised junction;
- screenshot of a transit card in light and dark mode;
- Console excerpt for any mismatch (Settings → Diagnostics → Share).
