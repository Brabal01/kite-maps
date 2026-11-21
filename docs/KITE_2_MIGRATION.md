# Kite 2.0 migration

## Strategy: migrate in place, not two apps

v29 changes screens where they already live. There is no parallel navigation
engine, no second map, and no hidden "new UI" flag that can drift from the old
one.

Why:

- Kite's riskiest code is the navigation state machine. Two implementations
  would double the surface for divergence and bugs.
- The redesign is mostly presentation: tokens, hierarchy, one banner, one trip
  bar. Keeping the data flow intact is what makes it safe.
- Rollback is per commit (`git revert`), not a cached flag that still runs
  half the new code.

The commits are deliberately small and individually buildable:

1. packaging/signing foundation;
2. design tokens + home + dock + Routes;
3. navigation HUD + place + planning + tested alternatives;
4. documentation, screenshots, verification.

## What moved, and what did not

| Area | v28 | v29 |
| --- | --- | --- |
| Palette | `Vela` hex constants | `KiteColor` adaptive tokens; `Vela` delegates |
| Home search | capsule bar | one 58 pt surface, voice in a tinted circle |
| Home shortcuts | Home/Work inside the search panel | contextual quick-action row, user editable |
| Bottom navigation | Map / Saved / Settings | Map / Routes / Saved / Settings |
| Routes | none | new page: plan, resume, favourites, recent |
| Duplicate map buttons | Just drive + parking FABs | removed; quick actions own them |
| Camera start | London, then first fix | restored area → fix → neutral world |
| Instruction banner | two dense variants | one hierarchy + signed exit panel + lane row + then row |
| Trip bar | 64 pt capsule | 68+ pt surface with add stop |
| Place header | reviews/photos buttons mixed with actions | one action row + Directions/Go |
| Route alternatives | all router answers | `RouteAlternatives.distinct`, tested |
| Alerts | `alertsUp` inline | unchanged (extraction listed as next step) |

## User data

- Bundle identifier unchanged: `app.vela.ios`.
- Existing keys are read exactly as before: `saved`, `home`, `work`, `parking`,
  `recents`, `recentPlaces`, `trip`, `theme`, `units`, `language`, Waze, camera
  and transit settings.
- New keys are additive: `quickActions`, `lastMapCenter`, `lastMapZoom`.
  Missing `quickActions` loads the default five; unknown raw values are dropped
  instead of crashing. No key is removed.
- The new Routes page does not copy or rewrite recent places; it reads the
  existing list.

## Settings that changed meaning

- `parkingButton` is still stored, but the map no longer has a separate parking
  FAB. Parking is now one of the editable shortcuts. The old value is preserved
  so a downgrade loses nothing.
- The Quick actions editor is in **Settings → Map & display → Shortcuts on the
  map**. Order follows the order shortcuts are added; reordering is not in v29
  (listed as remaining work).

## Rollback

- Revert the commit that introduced a screen; no data migration runs backwards,
  because no destructive migration exists.
- `quickActions` and the camera keys are ignored by v28 if it is reinstalled.

## Not migrated yet

- Map style presets (Classic / Navigation / Minimal) as one setting.
- A dedicated motorway-junction diagram beyond the existing signed exit panel.
- AlertCoordinator extraction and its tests.
- Saved journeys (only recent places + the resumable trip exist today).
