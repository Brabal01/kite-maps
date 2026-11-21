# Roundabout Exit Resolver 3.0

## Why it exists

The blue route can be right while the spoken "take the 2nd exit" is wrong. The
router's `exit` number is a count of the branches **it** saw at the moment it
built the step. It can differ from the branches a driver legally passes because:

- the router numbered a service road, a private entrance or an entrance-only arm;
- a dual carriageway meets the circle twice (in and out) but is one road;
- two exits of the same road sit a few metres apart;
- the router step and Google's step are offset along the line;
- two roundabouts follow each other closely and a maneuver is assigned to the
  wrong one;
- the route geometry leaves the circle at an arm the router did not count.

v30 trusted the router number and only used OpenStreetMap to draw a picture. The
picture and the words could therefore disagree. v31 makes one component decide
the number, and makes every view read that one result.

## Data flow

```
OSRM / Google / Valhalla steps
        │  (router exit, Google's words)
        ▼
Roundabouts.apply(to:)
        │  Overpass: ring ways, every road touching them, access/oneway/layer
        ▼
RoundaboutExitResolver.resolve(evidence)
        │  entry arm, legal exits, travel order, route's way off the circle
        ▼
Maneuver.exit + Maneuver.instruction + Maneuver.roundabout
        │
        ├── banner text ("3rd exit")
        ├── RoundaboutDiagram (same taken index)
        ├── voice (spokenWords reads the same instruction)
        ├── Live Activity (same instruction string)
        └── developer diagnostics
```

`RoundaboutExitResolver` is a pure function of `RoundaboutExitEvidence`; it never
does network I/O, which is why it can be tested with fixture geometry.

## Evidence order

1. **Complete OSM topology + the route's own way off the circle.** The strongest
   answer. The resolver rebuilds the ring, counts only arms traffic may legally
   leave by, sorts them in the direction of travel, and finds the arm nearest the
   point where the route leaves the circle.
2. **Router and OSM agree.** `routerCorroborated`, confidence above 0.9.
3. **OSM topology alone.** `osmTopology`; this is the case that *corrects* a wrong
   router number.
4. **Router alone.** `router`, confidence 0.55, never marked certain.
5. **Google's words alone.** `google`, confidence 0.5.
6. **Conflict with no map evidence.** No number. The banner says "take the exit
   onto …", never a made-up ordinal.
7. **Weak map match conflicting with the router.** No number, `ambiguous = true`;
   the diagram shows the mapped shape without a number and the banner says
   "check signs".

The resolver never invents a number when the topology is incomplete. If the map
has a circle but not the way off it, the router number is kept only as a
best guess and is not `isCertain`.

## Counting rules

- The road the route entered by is **not** an exit ahead. A four-arm roundabout
  entered from the south has three exits ahead: west, north, east.
- An arm is an exit only when `oneway`/`motor_vehicle` allow traffic to leave by
  it. Entrance-only arms are drawn faint and not counted.
- `access=no` and `access=private` arms are rejected (and listed in the
  diagnostics).
- Dual carriageways are merged when one arm enters and the other leaves within
  40°, with the same way or the same name.
- Two arms of the same way are one road even when their names differ.
- Exits within 18° of each other, or two arms of the same way, make the result
  ambiguous rather than silently picking one.
- Left-hand traffic reverses the travel order; the same physical roundabout
  entered from the opposite arm gets the opposite count.
- Mini-roundabouts keep the count from their own mapped point; the ring query is
  skipped so it cannot erase it.
- A missing branch counts only what the map actually has; the resolver does not
  pad the circle.

## One authoritative maneuver

`Roundabouts.apply` writes `exit`, `instruction`, `routerExit`,
`alternativeExit`, `exitSource`, `exitConfidence`, `exitAmbiguous` and
`roundabout` together. The "exit roundabout" step copies the same values.

`Navigator.loadRoundabouts` applies those fields only when the maneuver has not
been spoken yet (`spokenStage < 2`). A late OSM answer cannot contradict a
prompt the driver has already heard. Because banner, diagram, voice and Live
Activity all read the same `Maneuver`, they cannot disagree with each other.

## Diagnostics

Each resolved roundabout contributes a compact block:

```
— A33 at 1820 m
final: 3
source: osm-topology
confidence: 0.91
router: 2
google: 3
eligible exits: 3
ambiguous: false
```

The block is shown in **Settings → Diagnostics** and included in the
diagnostics ZIP only when the user runs and shares it. It contains route
distances and road names, never coordinates or a stored history of drives.

## Tests

`VelaCore/Tests/VelaCoreTests/RoundaboutExitResolverTests.swift`:

- wrong router number corrected by topology;
- router + topology corroboration;
- entrance-only arm not counted;
- dual carriageway merged;
- reverse traversal;
- left-hand traffic;
- conflicting providers with no map do not invent a number;
- router alone is kept but not certain;
- no evidence means no number;
- missing branch counts only mapped exits;
- two exits 6° apart are flagged ambiguous;
- route integration keeps number, words and picture together;
- diagnostics name every source.

`RoundaboutTests.swift` continues to cover the router sketch, circle fit, lane
rules, mini-roundabouts and the legacy shape builder.

## Known limits

- OSM must have the ring and the approach roads. A roundabout mapped as a single
  node is handled as a mini-roundabout, not by this resolver.
- Turbo and spiral roundabouts are counted by legal arms, not by painted lane
  markings; lane advice remains separate (`RoundaboutShape.entryArrows`).
- A service road is counted when it is legally usable. It can be downgraded in a
  future release with an explicit `service` weighting rather than a silent rule.
- A physically wrong OSM topology produces a wrong count; the resolver reports
  low confidence and ambiguity instead of pretending otherwise.
