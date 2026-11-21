# Kite v29 screenshots

Captured on the iOS simulator (iPhone 16, light by default) by the
`iOS simulator smoke test` workflow, from branch `iphone-custom-v29-redesign`.

| File | Screen | Build |
| --- | --- | --- |
| `home.jpg` | map home, light, quick actions | 1088 |
| `home-dark.jpg` | map home, dark | 1088 |
| `routes.jpg` | new Routes page | 1088 |
| `place.jpg` | new place sheet | 1088 |
| `directions.jpg` | route planning with a real route | 1087 |
| `navigation-light.jpg` | Navigation HUD 2.0, light | 1088 |
| `navigation-dark.jpg` | Navigation HUD 2.0, dark | 1088 |
| `settings.jpg` | settings list and dock | 1088 |

`directions.jpg` is from the run immediately before the final one: the last
simulator run did not receive a location fix before capturing the planning
screen (the app correctly showed its "waiting for your location" state). The
planning UI is unchanged between 1087 and 1088, but the image is labelled here
rather than pretending every frame came from one run.

What the screenshots show honestly:

- The map home is the redesigned screen, with the Routes dock tab selected in
  `routes.jpg`.
- The navigation frames include a live route planned by the open router, the
  camera alert, the trip bar and the route-event timeline. The timeline icons
  fall back to dots on this simulator runtime; they are not blank, but the
  specific sign glyph is not available there.
- The simulator has no real GPS; the position is injected. A physical phone is
  still required for compass, locked-screen, battery and SideStore checks.

Full-size PNGs are in the workflow artifact `Kite-v29-Simulator-Screenshots`
for the run linked from `docs/TEST_RESULTS.md`.
