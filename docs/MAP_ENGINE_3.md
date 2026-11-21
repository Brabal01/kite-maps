# Map Engine 3.0

Status: implemented and compiling in the v30 branch. Visual quality is checked
by simulator screenshots; physical-device frame rate and battery are not yet
measured.

## Presets

`MapPresetCatalog` in VelaCore defines seven coherent profiles:

| Preset | POI | Minor labels | Buildings | 3D | Transit | Paths | Terrain | Traffic |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Classic | yes | yes | yes | yes | no | yes | no | yes |
| Navigation | no | no | yes | yes | no | no | no | yes |
| Minimal | no | no | no | no | no | no | no | no |
| Explore | yes | yes | yes | yes | yes | yes | no | yes |
| Transit | yes | yes | yes | no | yes | yes | no | yes |
| Outdoors | yes | yes | yes | yes | no | yes | yes | no |
| Satellite | yes | yes | yes | yes | no | no | no | yes |

The user's preset is persisted (`mapPreset`). Selecting one applies the
coherent satellite/terrain/transit choices through `AppSettings.applyMapPreset`.
The old individual switches remain stored, so downgrading loses nothing.

## MapLibre

`MapStyler.preset` changes only the categories the preset owns. It restores
visibility when switching back to a richer preset, rather than leaving a
minimal map stuck on screen. Buildings, 3D extrusions, POI symbols, house
numbers, minor labels, paths, rail and minor-road opacity are covered.

During driving the effective preset is Navigation unless the user chose
Minimal. The route layers stay above the base map and keep their existing
identity (`vela-route-*`), so a preset change does not rebuild the renderer.

## 3D buildings

Buildings stay visible in Navigation and Highway; they no longer disappear just
because guidance started. The 3D extrusion minimum zoom is 14.5 when the preset
allows 3D, otherwise 22 (effectively off). The existing `navBuildings` setting
still applies during guidance.

## Apple Maps

The MapKit surface applies the same POI inclusion/exclusion and building/traffic
choices. It cannot reproduce every MapLibre styling detail; this difference is
explicit in Settings.

## Not done

- A full custom MapLibre style JSON per preset. The current implementation
  filters the Liberty style, which is safer and keeps road geometry intact.
- Offline map areas. See `docs/OFFLINE_STRATEGY.md`.
- Physical-device performance measurements for rapid preset switching.
