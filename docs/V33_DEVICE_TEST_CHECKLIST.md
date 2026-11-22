# V33 — what still needs a physical iPhone

Nothing in this list was verified in this workspace: the environment is Linux, with no Mac, no
iPhone and no Xcode. Simulator CI can prove a build launches and that deterministic UI flows work;
it cannot prove the following.

## Must check before release

1. **SideStore install.** Install both IPAs from the same commit on a real device with SideStore.
   Confirm the SideStore variant has no widget extension and that Live Activities are not advertised.
   The CI verifier checks structure and signatures only.
2. **Background / lock.** Start navigation, lock the phone for ten minutes, unlock, and confirm the
   arrow, remaining distance and camera recover. Repeat with the app killed by the system.
3. **Live Activity.** Full variant only: line, colour, next stop, exit and delay on the lock screen
   and in Dynamic Island, including on a locked phone. SideStore must not crash without it.
4. **GPS replay in a moving car.** Check that a replay can be paused, sped up and skipped, that the
   orange banner is impossible to miss, and that no replayed position ends up in saved journeys,
   the resumable trip or shared diagnostics.
5. **Offline resume.** Turn on airplane mode, end the app during navigation, restart, and accept the
   resume offer. Confirm the saved geometry is shown and that the UI says no offline reroute is
   possible. Reconnect and confirm the online recalculation replaces it.
6. **Camera jurisdiction.** Drive (or simulate a GPS route) across a border. Confirm camera warnings
   stop in a restricted country, that unknown locations default to no warning, and that the
   acknowledgement switch behaves as the settings text says.
7. **Roundabout and signal resolution at a real junction.** The v31 algorithms were left unchanged;
   verify a wrong router exit number and an opposite-direction traffic light on a real drive. The
   developer diagnostics export contains only relative distances, so no precise location is shared.
8. **Battery and map FPS.** Measure on-device over a representative drive. The benchmark artifact
   contains pure-algorithm microbenchmarks only; no battery or FPS figures are claimed here.
9. **Dynamic Type, VoiceOver, dark mode, landscape, small and large displays.** Especially the new
   route preview, replay controls and diagnostics preview.
10. **Long route memory.** Drive or replay a 400 km route; check memory growth and that road-event
    data behind the car is released.
