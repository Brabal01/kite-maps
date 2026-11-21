# AlertCoordinator

Status: implemented in VelaCore and integrated into the driving HUD.

## Input

`AlertCandidate` is renderer-neutral and contains:

- stable ID, kind, source, severity;
- title, distance and optional position along the route;
- event bearing and route bearing;
- accuracy and provider confidence;
- report time and optional expiry;
- speed limit and current speed;
- a reply flag.

A candidate with an opposite bearing (more than 65° difference), an expired
timestamp, a non-finite distance or confidence below 0.2 is rejected.

## Priority

The score combines severity, proximity, freshness, confidence and kind.
Safety-critical cases get explicit boosts:

- a speed camera while over the limit;
- closures and major crashes;
- any event whose speed is above a known limit.

Aircraft and average-speed checks are intentionally lower than a nearby road
hazard.

## Hysteresis and cooldown

- The current primary card is kept unless a challenger scores at least 18%
  higher (configurable).
- A camera while over the limit always takes the card.
- Dismissing a report suppresses it for 20 seconds (configurable).
- Two sources describing the same event are de-duplicated by kind and
  distance bucket, keeping the stronger/fresher record.

## Urgent maneuver

When the next maneuver is under 90 m, ordinary warnings are suppressed. Only a
critical event or an over-limit camera may still take the card, so the turn
instruction is never covered by a stale hazard.

## Integration

`NavAlertStore` maps Navigator's camera, Waze, average-speed, aircraft and
road-control values into candidates and refreshes only when a coarse alert key
changes. It then maps the coordinator's primary and queued IDs back to
`NavAlert`. No second alert implementation remains in the view.

## Tests

`AlertCoordinatorTests` covers de-duplication, opposite direction, camera over
limit, hysteresis, cooldown, urgent maneuvers and expired/low-confidence/reply
events. All are deterministic and network-free.
