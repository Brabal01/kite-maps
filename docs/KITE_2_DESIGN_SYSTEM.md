# Kite Design System 2.0

Source of truth: `App/Sources/KiteDesignSystem.swift`.
Legacy colour names (`Vela.teal`, `Vela.accent(scheme)`, …) now resolve to these
tokens, so every existing screen shares one palette while it is migrated.

## Colour

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `KiteColor.accent` | `#0FA79A` | `#2DD4BF` | primary action, active tab, selected route card |
| `KiteColor.onAccent` | `#04241F` | `#04241F` | text/icons on an accent fill |
| `KiteColor.accentText` | `#0B7A70` | `#5EEAD4` | teal text/icons on a normal surface |
| `KiteColor.accentSoft` | `#D9F5F0` | `#123B38` | selected chips, icon tiles, secondary buttons |
| `KiteColor.canvas` | `#F3F6F9` | `#0B1320` | page background |
| `KiteColor.surface` | `#FFFFFF` | `#16212F` | sheets, cards, floating controls |
| `KiteColor.fill` | `#E9EFF5` | `#253345` | chips, segmented controls, inactive buttons |
| `KiteColor.ink` | `#0F172A` | `#F1F5F9` | primary text |
| `KiteColor.inkSecondary` | `#526173` | `#A9B7C6` | supporting text |
| `KiteColor.route` | `#2563EB` | `#60A5FA` | route line, transit accent |
| `KiteColor.danger` | `#B91C1C` | `#F87171` | end trip, closures |
| `KiteColor.warning` | `#B45309` | `#FBBF24` | caution chips, close follow-up turn |
| `KiteColor.camera` | `#EA580C` | `#FB923C` | speed cameras |

Rules:

- Teal means "go" or "selected". It is never used for decoration.
- Red is only danger or a destructive action. Amber is caution, never "new".
- Dark mode is a separate palette (near-black canvas, blue-grey surfaces), not
  an inversion of light mode.
- A colour must be read through a token, not written as a hex literal in a new
  screen. Existing hex literals are legacy and are replaced as screens migrate.

## Type

`KiteText`: `display` (34, heavy, rounded), `title` (26, bold), `headline` (19),
`body` (17), `label` (15), `caption` (13), `digits(size, weight)` for anything
that changes while driving. Numbers use monospaced digits so the ETA and
distance do not jitter.

The app keeps `kiteType()` (rounded design, minimum `xLarge` dynamic type) so
text stays readable in a phone holder. New screens use `KiteText`, which
supports Dynamic Type through the same system font scaling.

## Space, radius, elevation

- Space: 4 / 8 / 12 / 16 / 20 / 24 / 32 (`KiteSpace`).
- Radius: 12 chip, 16 button, 22 card, 28 sheet, 34 floating sheet.
- Elevation: low (map chips), medium (cards), high (sheets over the map).

A card is always `kiteCard()`: one padding, one border, one shadow. A floating
control is `kiteGlass()` or `KiteCircleButton(material: true)`. No screen may
invent a second corner radius for the same kind of surface.

## Controls

- `KitePrimaryButtonStyle` — one accent action per screen (Go, Directions,
  Carry on). Height 52–62.
- `KiteSecondaryButtonStyle` — neutral filled action.
- `KiteChip` — filters and facts.
- `KiteCircleButton` — 38–56 pt targets; map variants set `material: true`.
- `KiteEmptyState` — every empty list uses it, so an empty state never looks
  like an error.
- `KiteSectionHeader` — title + optional subtitle + one trailing text action.

## Motion

`KiteMotion.snap` (selection), `.sheet`, `.gentle`, `.banner`.
`KiteMotion.travel(reduce:)` turns a slide into a fade when Reduce Motion is on.
The dock reads `accessibilityReduceMotion` and skips its spring. The navigation
HUD relies on value-driven animations only; it never animates continuously.

## Accessibility

- Minimum 44×44 targets; the dock items are at least 52 pt tall.
- Icons carry labels; decorative icons are hidden.
- The instruction banner combines its children and exposes one sentence
  ("In 200 metres, turn right onto …") plus a "Repeat instruction" action.
- The lane strip labels every lane as recommended or other.
- Contrast: ink on surface and onAccent on accent are both designed to pass
  WCAG AA for body text; warning chips use warning-on-warningSoft, not amber on
  white.

## What is intentionally not here

- No custom font files: system rounded keeps Dynamic Type and scripts working
  worldwide.
- No icon set: SF Symbols only, so symbols follow OS updates and accessibility
  settings.
- No second navigation bar: the dock is the only page switcher.
