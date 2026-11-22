# Kite v34 reliability

## Geographic camera alert gate

Country polygons are from the public-domain Natural Earth 1:50m Admin 0 Countries dataset. They are approximate and represent the dataset's view of boundaries. GPS uncertainty, a 5 km border/coast buffer, ambiguous polygons and missing geographic coverage suppress speed camera alerts. This may also suppress warnings in small countries and islands. The inherited policy list remains incomplete, and a country being recognized is no assurance that specific alerts are permitted.

Source snapshot: [Natural Earth data at ca96624](https://github.com/nvkelso/natural-earth-vector/blob/ca96624a56bd078437bca8184e78163e5039ad19/geojson/ne_50m_admin_0_countries.geojson). Regenerate with `python3 .github/scripts/generate-country-boundaries.py path/to/ne_50m_admin_0_countries.geojson`.

## v33 CI evidence

- [45009581543](https://github.com/Brabal01/kite-maps/actions/runs/45009581543) failed loading the CoreSimulator default device set with a `devicePair` assertion, before the app build.
- [45009586482](https://github.com/Brabal01/kite-maps/actions/runs/45009586482) completed the planning, v31, and v33 UI tests and repeated launches. The screenshot sequence was canceled. The logs do not give a cancellation cause.
- [45006863863](https://github.com/Brabal01/kite-maps/actions/runs/45006863863) passed at 13a78f4.

## Capture a regression after a drive

1. Before setting off, enable Detailed diagnostics if a reproducible issue needs recording.
2. After stopping safely, keep guidance open and choose Diagnostics → Capture the last manoeuvre. This keeps a short local extract in memory. Enter the expected exit or traffic-light count if known.
3. Choose Include captured incident in export, read the precise-location notice and confirm. Generate the archive and inspect each file before sharing it. The ordinary technical report excludes the incident unless separately authorized.
4. Extract `navigation-incident.json` and import it from Diagnostics. Compare recorded and replayed guidance and the expected numbers. The replay uses the recorded route instructions and signal candidates. It does not request new upstream data or re-run the original roundabout topology resolution.
5. To make a repository regression test, replace coordinates and identifying text with synthetic equivalents and use `NavigationReplayIncident.decode` and `replay()` in `GPSReplayTests`. Assert the expected exit, signal count and off-route state. Keep personally identifying fixtures out of the repository.

## UX audit

| Flow | v34 decision |
| --- | --- |
| Find a destination | Existing search and favourite entry points serve different intents. |
| Select an alternative | The existing route summary and cards provide access to alternatives and preview. |
| Add a stop | Existing category search now ranks routed estimates by added drive time. Results missing an estimate follow ranked results. |
| Switch driving, walking, cycling or transit | The existing planner shares its origin across modes and already has simulator regression coverage. |
| Start and stop | Existing planning and dashboard actions remain the entry points. Replay controls stop only the replay. |
| Open a saved journey | The Routes page offers an explicit discard action for the interrupted journey. |
| Arrival | Existing entrance and parking data can feed a new walking plan from the current location. |

The detour estimate compares the routed approach-to-rejoin time with and without the stop. The candidate set is limited to the existing search corridor and the first 12 matching places. It is not a global search for the cheapest detour.

## Verify on an iPhone

- Install both variants independently with the intended signer. Upgrade from v33 and verify saved places and preferences survive in the signed app's container. Confirm the Full widget and SideStore's app-only installation.
- With Full, lock the screen while guiding a drive, a walk and a transit ride. Check background prompts, Live Activity updates and that arrival or Stop ends the activity.
- Drive a cross-border route with and without internet. Verify speed camera alerts disappear in the uncertainty buffer and the country changes after leaving it. Test reduced-accuracy permission, GPS loss and recovery.
- Force-quit during an active journey, enable Airplane Mode and relaunch. Resume from a changed position, check the maneuver list, leave the saved route and restore connectivity. Confirm the online reroute starts from the current position. Discard a second interrupted journey and relaunch again.
- Check replay during a real trip. Confirm the real location, history and Full Live Activity keep using the real drive, and export both an ordinary technical archive and a separately consented incident.
- Verify precise signal placement and direction, 3D buildings at guidance start and return to the foreground, landscape controls, text sizing and walking handoff from the arrival screen.
- For battery and FPS, compare v33 and v34 using the same physical iPhone, route, time, map style, screen brightness, network condition and location settings. Measure with Instruments and log the device, OS, thermal state and test duration.
