# Kite v30 — physical device checklist

Everything here is **not verified** by CI. Simulator screenshots prove layout,
not real driving behaviour.

## Planning and GPS

- [ ] Plan from a stationary phone for 1, 5 and 10 minutes.
- [ ] Switch car → walk → bike → transit repeatedly while the fix is pending.
- [ ] Deny location, then grant it in Settings and return to the planner.
- [ ] Approximate location: route preview appears; starting navigation asks for
      a precise fix.
- [ ] Type both start and destination and plan with location off.
- [ ] Lock/unlock and background/foreground while waiting.

## Navigation

- [ ] Deliberate wrong turn on a motorway and a city street: reroute starts
      quickly, stale answer is ignored, remaining stops survive.
- [ ] Tunnel: estimated position is labelled, no false arrival.
- [ ] Parallel carriageway / bridge / underpass: arrow does not jump.
- [ ] Arrival at a stop, then continue to the next stop.
- [ ] Cancel navigation during a reroute.
- [ ] Start navigation twice from the same preview.

## Guidance UI

- [ ] Simple, Advanced, Highway and Custom HUD on a small and a large phone.
- [ ] Motorway exit with real signed destinations and lanes.
- [ ] Fork with insufficient data: no invented diagram.
- [ ] Roundabout left-hand and right-hand traffic.
- [ ] Traffic light on our road versus a cross street.
- [ ] Camera over the limit versus a nearer hazard; dismiss and confirm it does
      not return immediately.
- [ ] Reduce Motion and VoiceOver on the banner and lane strip.

## Map

- [ ] All seven presets, light and dark.
- [ ] 3D buildings before and during navigation.
- [ ] Satellite and Apple Maps alternatives.
- [ ] Rapid preset switching: no stale layer visibility.

## Saved journeys and GPX

- [ ] Save a journey with stops, reopen it, reverse it, delete it.
- [ ] Import a valid GPX, a malformed file and a >5 MB file.
- [ ] Export a planned route and open the file in another app.
- [ ] Confirm an imported GPX is labelled as a track, not turn-by-turn.

## Performance and privacy

- [ ] Launch time and memory with the new map profiles.
- [ ] Battery use on a 30-minute drive.
- [ ] Confirm diagnostics contain no coordinates, queries or keys.
