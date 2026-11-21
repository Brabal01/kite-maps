# Directional Road Controls 3.0

## The problem

A traffic light within 10 m of the blue line is not necessarily the driver's
light. On a wide junction the opposite carriageway, the crossing road and a
turn-lane head can all sit inside that radius. v30 filtered by distance, merged
same-kind controls less than 30 m apart, and then drew them with straight-line
distance. That produced three visible failures:

- missing lights, because two separate junctions 20–30 m apart were merged;
- lights for the opposite direction, because proximity was treated as proof;
- wrong countdowns, because the map used crow-flight distance instead of
  distance along the route.

v31 replaces the proximity filter with a matcher that reads the OSM way and the
route's direction on it.

## Data model

`RouteControl` now keeps the evidence, not only a kind and a point:

| Field | Meaning |
| --- | --- |
| `kind` | light, stop, railway, tram, crossing, give way, one-way |
| `location` | the original mapped point (never moved to the junction centre) |
| `osmID` | original OSM node id |
| `wayID` | the OSM way whose approach it governs |
| `directionTag` | `traffic_signals:direction` / `direction` |
| `alongMeters` | distance from the route start |
| `offsetMeters` | distance from the route line |
| `confidence` | 0…1 |
| `source` | `osm`, `postpass`, `proximity` |
| `directionCertain` | true only when the way topology says this is our approach |
| `relevance` | relevant, ambiguous, irrelevant |
| `stopLineKey` | one physical stop line, for de-duplication |

`ControlDisplayPolicy.shouldShow` now also reads the control's own
`directionCertain` and `relevance`. A caller cannot accidentally present an
ambiguous control as a certain one.

## Matching rules

`DirectionalRoadControlMatcher.match`:

1. Builds the node index and the road/rail membership from every returned way,
   including ways without geometry (Postpass often returns only the point).
2. For each control node, projects it onto the route and enforces a reach by
   kind: 12 m for lights, 10 m for stop/give way, 15 m for crossings.
3. For each way through the node, samples 20 m along the way in both directions.
   The way is ours only when:
   - the sample is within 4.5 m of the route line;
   - its route distance is 4–55 m ahead of the node;
   - the route bearing and the way bearing agree within 42°.
4. Applies `oneway`, `access`, `motor_vehicle` and `direction` tags.
5. Treats a head explicitly facing the other way on our own way as irrelevant,
   not ambiguous.
6. Keeps a control with no way geometry only when it sits on the line itself
   (≤4 m) and has no opposite direction tag.
7. Marks anything else near the line as **ambiguous**. Ambiguous controls are
   shown while browsing but hidden in active driving guidance.

Bridges and tunnels: a rail way with a non-zero `layer` is not a level crossing
for the road below; a road control on a bridge is not the road under it.

## De-duplication

The 30 m distance merge is gone. Two controls merge only when they are the same
kind, less than 12 m apart along the route, and either share the same OSM way or
both sit within 6 m of the line and within 8 m of each other.

Consequences:

- several heads on one stop line → one marker;
- two signalised junctions 20 m apart on the same road → two markers;
- a turn-lane head 6° from the through head → not merged; the chosen one depends
  on which way the route actually goes;
- duplicate Postpass and Overpass copies of the same node → one marker.

## Distance and time

Navigation uses `UpcomingRoadControl.meters`, which is route distance. The map's
signal layer now reads `Navigator.allUpcomingControls` and applies the policy to
`event.meters`. It no longer computes straight-line distance from the puck.
`refreshUpcomingControls` drops anything with `meters < along`, so a passed light
cannot re-enter the list.

`RouteEventCoverage` uses the matcher's `alongMeters` when present instead of
re-projecting the point in each 4 km section, which also removes a source of
jitter at section boundaries.

## Modes

| Mode | Behaviour |
| --- | --- |
| Browsing | context controls around the visible area; ambiguous allowed |
| Free drive | confirmed lights, stops and railway crossings within 350 m |
| Navigating (car) | confirmed controls only; lights/stops ≤450 m, railway ≤600 m |
| Navigating (walk) | crossings, lights and railway; car-only furniture hidden |
| Navigating (bike) | lights, crossings, railway; stop/give way ≤180 m |

Walking keeps its own legacy rules for one-way streets and pedestrian nodes; a
car's approach is not the relevant one there.

## Other controls

The same matcher handles stop signs, give-way signs, railway/tram crossings and
pedestrian crossings. Each kind keeps its own reach and display limits; the
system does not apply the car light rules to a tram crossing.

## Diagnostics

`RouteControl` carries the way id, direction tag, confidence, source and
relevance, so a developer panel can show why a light was accepted, rejected or
marked ambiguous. The matcher never guesses a traffic-light colour; it only
shows the mapped infrastructure.

## Tests

`DirectionalRoadControlMatcherTests.swift` covers:

1. light directly on the route, with route distance;
2. light on the opposite carriageway;
3. light on the crossing road;
4. two signalised junctions 20 m apart both kept;
5. two heads on one stop line merged;
6. turn-lane signal relevant only when the route takes the lane;
7. signal on an overpass not the road below;
8. signal under a bridge on our road kept;
9. one-way junction shows only our approach;
10. missing direction tags still show our road's light;
11. reversed travel on the same road;
12. fast route change drops old controls;
13. a signal behind the vehicle is not upcoming;
14. two parallel roads do not share a signal;
15. missing Overpass answer means no controls;
16. Postpass node without geometry still counts on the line;
17. duplicate nodes produce one control;
18. ambiguous control is browsing-only.

`ControlDisplayPolicyTests`, `RoutingTests` and `WalkEventsTests` continue to
cover the policy, Postpass parsing, tram/rail inference and walking rules.

## Known limits

- A junction mapped as one signal node for the whole intersection is treated as a
  controlled junction on our way; no separate head position is invented.
- A signal with no way geometry and a non-cardinal `direction` value is
  ambiguous, not certain.
- OSM can be missing a light entirely. Kite does not invent one.
- The proximity fallback (`Cameras.signalsOnRoute`) is used only when the
  directional lookup fails; it is marked ambiguous and is browsing context, not
  a confirmed instruction.
