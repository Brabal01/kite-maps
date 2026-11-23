# Kite v36 device test checklist

Mandatory physical-device checks to close before announcing v36 as fully verified.
These cannot be run in a Linux/CI environment and must be done on an iPhone
running the signed SideStore build from this PR's final commit.

## Roundabout exit accuracy (Olomouc)

- [ ] Drive the Vejdovského/Kapounky approach at Hodolany, Olomouc, approaching
      from the south-west.
- [ ] Expect the banner to read the correct exit for the *actual* route — for the
      through drive to the north-east continuation, the **2nd** exit, not "1st".
- [ ] While 150–300 m out with the map still loading, confirm a late OSM answer
      does not leave an obviously wrong "1st exit" frozen:
      - the banner updates to the confirmed number before the turn;
      - nothing is re-spoken after the number has already been said;
      - banner, picture, voice and Live Activity agree.
- [ ] Re-drive leaving by the first (service) arm — it must still say **1st**.
- [ ] Confirm a roundabout with no usable exit number shows the direction
      ("… směrem na …") rather than an invented number.

## Live traffic without navigation

- [ ] Open the map with no route planned.
- [ ] Traffic toggle on, MapKit renderer: congestion appears across the visible
      roads; the map stays in its normal mode.
- [ ] Background the app and reopen it: the traffic overlay is still present.
- [ ] Switch MapKit → MapLibre: with Google available, the tile overlay shows;
      with `noGoogle` on, the inspector reports no-coverage honestly (no fake layer).
- [ ] Toggle off/on while browsing: the layer appears/disappears without flicker
      after moving the map.
- [ ] Enter a heavy area (or town centre) and confirm colours update as you span.

## Regression

- [ ] Car navigation still hides the transit layer; ending the navigation restores it
      on both MapKit and MapLibre (the v35 test scenario, now on a device).
- [ ] Place, planning, transit, route preview and settings screens still render.

## Distribution / packaging

- [ ] Install the SideStore IPA (no extension, no Live Activity) on a device.
- [ ] Install the Full IPA (with NavigationWidget) and confirm Live Activity works.
- [ ] Confirm existing saved places survive the v35 → v36 update.
- [ ] Confirm the build number is the same for Full and SideStore from this final
      commit.

## Battery / performance

- [ ] Map FPS while browsing with traffic on.
- [ ] GPS/network behaviour with the screen locked during navigation.
- [ ] Resume from background without a stale traffic overlay.