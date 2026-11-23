# Kite v36 roundabout exit accuracy

## The reported bug (Olomouc, Vejdovského)

An iPhone user nearing the roundabout at the northern end of Vejdovského street,
Olomouc (Hodolany), saw:

> „70 m — Na kruhovém objezdu použijte výjezd číslo 1 na Vejdovského.“

but the blue route clearly went **round the right-hand side of the circle and out
through the top arm** — the 2nd usable exit, not the 1st.

## What we verified (not assumed)

### The resolver is correct *given the mapped circle*

We captured the real roundabout from OpenStreetMap (overpass `out geom`) as a
golden fixture: `VelaCore/Tests/Fixtures/olomouc_vejdovskeho_roundabout.json`.
It is an irregular, fragmented **seven-way ring** (ways 4924580, 1344866057/58/59/60/64/67)
with dual-carriageway and one-way arms:

- Vejdovského approach from the south-west (way 1344866047),
- Vejdovského continuation to the north-east (way 1344866048),
- a residential branch (1344866054/63),
- one-way service roads (1344866055/68).

Regression tests (`RoundaboutExitResolverTests`, `OlomoucRoundaboutTests`) prove:

- `testVejdovskoeRouteThroughTakesSecondNotFirst` — entering at 1344866047 and
  leaving at 1344866048 resolves to **exit 2** and overrides the router's "1st".
- `testVejdovskoeFirstArmIsStillFirst` — a route leaving by the first (service)
  arm still resolves to **exit 1**.
- `testOsmOverridesWrongRouterWhenTopologyConfirmed` — the full `Roundabouts.resolved`
  pipeline keeps number, words and picture in step with the corrected count.

So the topology math was **already right**. The bug was display/timing, not counting.

## Root cause (confirmed two paths)

1. **A lone unconfirmed router number was shown as if it were the answer.** When
   the map had not yet answered, `withoutTopology()` kept the router's number
   (confidence 0.55) and the banner/voice read `maneuver.exit` directly, so a wrong
   "1st exit" appeared as a firm instruction.

2. **A late, correct OSM answer was frozen.** `Navigator.loadRoundabouts()` only
   applied a corrected roundabout while `spokenStage < 2`. By the time the map
   answered (Overpass is slow), the "in 200 yards" heads-up had already been spoken
   (stage 2), so the number never reached the driver, even though there was still
   time to act.

## The fix

### 1. Do not present an unconfirmed number as certain (§3.7)

`Roundabouts.resolved` now shows an exit number only when `resolved.isCertain`
(the map counted it, or the map and router corroborated). A not-certain number is
dropped from the banner and the words; the **direction** ("toward Vejdovského")
stays, and the router's guess is kept as `routerExit` evidence for the late-map
correction. Test: `testUnconfirmedNumberShowsDirectionNotAGuess`.

### 2. Narrow the freeze so a late correct answer can still land (§3.8)

`Navigator.loadRoundabouts` freezes a roundabout only once its turn is actually
being said — stage 3, or within the "say it now" distance. Before that, a late
confirmed OSM answer replaces the number in the banner, words, picture and Live
Activity together. The voice is never re-read, so nothing sounds contradictory.

### 3. Deterministic fixture is not gated by zoom (simulator test)

The v35 simulator test failed because the rail-demo fixture was installed behind a
`zoom >= 10` gate; after navigation ended the camera reset dropped the zoom and the
layer never reappeared. The fixture now installs regardless of zoom (see
`docs/V35_MAP_TRAFFIC_TRANSIT.md`).

## One authoritative result (§3.6)

All of banner, diagram, voice, "then" row, Route Preview and Live Activity read the
same `Maneuver.exit` + `instruction`, which `Roundabouts.resolved` sets together, so
the map, the words and the number can never disagree for the same maneuver.

## Verified vs. not yet verified

- Resolver counting on the real Olomouc fixture: **unit-verified** (container/CI).
- Display fix compiles in the app target: depends on the iOS build CI result.
- Live physical drive at that roundabout: **not yet verified on a device** — see
  `docs/V36_DEVICE_TEST_CHECKLIST.md`.