# Transit Design 3.0

## Goals

A transit result must answer five questions at a glance:

1. which line,
2. which kind of vehicle,
3. which official colour,
4. which direction,
5. whether the data is live.

v30 showed every mode with the same blue chip when a feed omitted `routeColor`,
used the tram icon for cable cars and funiculars, and drew a shared track in the
first line's colour only.

## Line identity

`TransitLineIdentity` is the one model used by the planner cards, the journey
timeline, the departure board, the map layer and live vehicles:

```swift
provider, feedID, agencyID, routeID,
shortName, longName, headsign,
mode, routeType,
officialColor, officialTextColor,
operatorName, source, freshness
```

Two agencies running a "1" are different lines because the key includes provider,
feed, agency, route id, short name and mode. The same line keeps the same key
everywhere.

`TransitLeg.identity` resolves an identity even for a leg built by hand (for
example a departure-board row): the stored identity wins, otherwise the leg's
mode, colour and provider fields are used.

## Colour rules

1. `routeColor` from the Transitous answer for that exact line.
2. Official GTFS `route_color` for the same provider and route id.
3. Verified provider metadata.
4. A neutral **mode** colour when no official colour exists.

The fallback is never labelled official. `TransitLineIdentity.source` is
`provider`, `gtfs`, `metadata` or `modeFallback`, and `colorIsOfficial` is false
for a fallback.

Hex is accepted with or without `#`, validated as six hex digits and inside the
24-bit range. `routeTextColor` is respected when its WCAG contrast on the line
colour is at least 3:1; otherwise black or white is chosen for readability. The
line identity itself is never changed to make the text work.

### Mode fallback colours

| Mode | Fallback |
| --- | --- |
| Bus | blue |
| Trolleybus | teal |
| Coach | dark blue |
| Tram | red |
| Light rail | red-orange |
| Metro | violet |
| Subway | deep violet |
| Suburban rail | teal-green |
| Regional train | green |
| Long-distance train | slate |
| High-speed rail | near-black |
| Ferry | ocean blue |
| Funicular / cable car / aerial lift | amber/brown |
| Monorail | magenta |
| Bike | green |
| Unknown | neutral grey |

These are deliberately not one blue. They are a fallback, not an official
identity.

## Modes

`TransitMode` separates:

walk, bus, trolleybus, coach, tram, light rail, metro, subway, suburban rail,
regional train, long-distance train, high-speed rail, ferry, funicular, cable
car, aerial lift, monorail, bike, unknown.

It maps both Transitous mode strings and standard/extended GTFS `route_type`
values. A line's name never decides its mode: `S1` on `RAIL` is a regional train,
not a metro.

## Icons

| Mode | SF Symbol |
| --- | --- |
| Walk | `figure.walk` |
| Bus / coach / trolleybus | `bus.fill` (+ bolt for trolleybus) |
| Tram / light rail / monorail | `tram.fill` (+ badges) |
| Metro / subway | `tram.fill.tunnel` |
| Rail | `train.side.front.car` (+ `s`/`l`/bolt badges) |
| Ferry | `ferry.fill` |
| Funicular / cable car / aerial lift | `cablecar` |
| Bike | `bicycle` |
| Unknown | `questionmark.circle.fill` |

All symbols exist on iOS 16.2. An unknown mode never borrows the tram icon.

## LineChip 3.0

A compact badge with:

- mode icon (and a small badge where modes share a symbol),
- line short name (truncated at a sane width, never breaking a card),
- official colour when present, otherwise the mode fallback,
- readable text in light and dark mode,
- an accessibility label that names the mode and the line.

## Trip cards

`TripRow` is a card with:

- departure–arrival and total duration;
- a wrapped row of line chips and walk segments;
- "Direct" or "N changes" plus walking minutes;
- the first ride's direction;
- delay, live freshness and tight-transfer warnings.

The card never grows unbounded: line names truncate, the chip row wraps, and the
summary is one line.

## Journey timeline

`TransitSteps` is a vertical timeline:

- a coloured rail per ride, in the line's official colour;
- a dotted neutral rail per walk;
- a filled node for a ride, a ring for a walk, a double ring for a transfer;
- board/exit stops, platform changes, intermediate stops, alerts and metro
  entrances/exits as before.

The timeline is a view of the same legs as the card, so colour and mode cannot
drift between them.

## Map layer

`Transitous.parseLines` now returns one entry per distinct line on a geometry,
not one entry per geometry:

- metro, tram, light rail, suburban/regional/long-distance/high-speed rail;
- buses, trolleybuses, coaches and ferries from zoom 13 when the service sends
  them;
- each line carries `mode`, `offset` and a stable `routeKey`;
- lines sharing a track get a small pixel offset and a mode-dependent width, so
  a shared corridor shows every colour instead of the first one.

A two-point "shape" over 700 m is treated as a straight chord between stops and
is not drawn as a precise alignment.

Live vehicles use the mode's own map icon, not the tram icon for everything.

## Live data

Delay, cancellation, platform changes, freshness, vehicles, transfers,
GTFS-Realtime and automatic feed discovery are unchanged. The line colour does
not change with delay; freshness is a separate indicator.

## Tests

`TransitLineIdentityTests.swift` covers:

- GTFS route types and Transitous mode strings;
- `S1` not becoming a metro from its name;
- mode-specific fallback colours;
- official vs fallback colour source;
- invalid hex rejection;
- text contrast (white on yellow becomes black);
- same number at two agencies being different lines;
- parser identity and official colours;
- shared track keeping every line with offsets;
- buses only at close zoom;
- departure-board identity;
- distinct mode icons and unknown-mode fallback.

`TransitTests` continues to cover plan parsing, stop times, line parsing and
station access.

## Known limits

- The Transitous route-map endpoint does not always publish per-line geometry;
  where it does not, Kite does not draw a precise line.
- Bus geometry is included only where the endpoint provides it and at close
  zoom, for performance.
- Official colours come from the feed. If a provider publishes no colour, Kite
  shows a mode colour and says so in the model; it does not claim it is official.
- Live Activity currently carries the navigation instruction, not a coloured
  transit card. The model is ready for it; the activity layout is not changed in
  v31.
