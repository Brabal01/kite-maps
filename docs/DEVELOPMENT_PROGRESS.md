# Kite Maps iPhone custom build — development progress

Updated: 2026-11-20

## Branch and base

- Working branch: `iphone-custom-v24`
- Base: `iphone-custom-v23` at `ed88cb5abc726b6ba64937ef564b24f3b8c9397c`
- Base commit name: `Open Google Maps reviews, photos and transit inside Kite`
- The last verified v23 build is GitHub Actions run
  [44728196650](https://github.com/Brabal01/kite-maps/actions/runs/44728196650) (success, 5m14s).

## What changed in v24

### 1. The nine historical patches are now ordinary source

The v23 workflow applied these files, in this order, on every build:

1. `Kite-0.7.16-custom.patch`
2. `Kite-v16-changes.patch`
3. `Kite-v17-changes.patch`
4. `Kite-v18-changes.patch`
5. `Kite-v19-changes.patch`
6. `Kite-v20-changes.patch`
7. `Kite-v21-changes.patch`
8. `Kite-v22-changes.patch`
9. `Kite-v23-changes.patch`

The patched tree is now checked in (commit "Materialize v23 customizations as versioned sources").
The patch files stay in `.github/workflows/` as history, but the workflow must not apply them
again: the source already contains every change, and a second application would duplicate it.

This removes the main long-term hazard: a change could previously exist in a patch but not in a
reviewable source file, and a newly added source edit could be silently overwritten by the next
patch in the chain.

### 2. Workflow

`.github/workflows/custom-iphone.yml` now:

- no longer applies the historical patches;
- verifies that the versioned customization files are present;
- runs `swift test` in `VelaCore`;
- builds with Xcode 27.1 / iOS 27.1 SDK on the `xcode-27` runner;
- stamps `CFBundleVersion`, ad-hoc signs the app, the widget and the frameworks;
- packages `Payload/Kite.app` into `Kite.ipa`;
- uploads the `Kite-custom-ipa` artifact;
- runs on `workflow_dispatch` and on pushes to `iphone-custom-v23` or `iphone-custom-v24`.

The app and widget identifiers are unchanged (`app.vela.ios`, `app.vela.ios.navigation`), so
SideStore can still install and re-sign the package.

### 3. Native place details

- Native reviews are shown first. The Google web page is now an explicit fallback at the bottom,
  labelled as the Google Maps website, not as native content.
- Reviews are deduplicated by Google's review resource name, then by author and text.
- The sheet shows the rating and rating count when available.
- A stale async answer can no longer replace the reviews of a place opened later.
- Photos remain native (`PhotoStrip` thumbnails, full-screen `PhotoViewer`), with the Google web
  page offered only for the complete Google gallery.
- The UI states that Google provides only a sample without a Places API key. No scraping,
  CAPTCHA bypass, consent bypass, account or paid key is required for the native path.

### 4. Place identity

`Place.matchesNearby` now treats two different non-empty Google place IDs as different places,
even when the names are identical and they are within 150 m. This prevents two branches of a
chain, or two units in a shopping centre, from being merged into one saved place or detail card.

### 5. Faster-route offer

The faster-route card no longer takes the new route by itself after 30 seconds. If it is left
alone it expires and the current route stays; switching is always an explicit "Take it" tap.
Rerouting after leaving the route is unchanged.

### 6. VelaCore testability

`VelaCore` now imports `FoundationNetworking` conditionally, and `GoogleJSON.isBool` has a
swift-corelibs-foundation path. This lets the pure navigation/search/transit tests run on Linux.

## Verification

- VelaCore unit tests on Linux (Swift 6.0, scratch copy without the two Darwin-only zlib tests and
  the `vela-probe` executable): **177 tests, 0 failures, 1 skipped**.
- New regression test: `PlaceMatchingTests.testSameNameButDifferentGooglePlacesStayApart`.
- First v24 GitHub Actions run:
  [44746989805](https://github.com/Brabal01/kite-maps/actions/runs/44746989805) — **success, 4m24s**
  on commit `4b8c28b98f4a2613e227ffbf7e7173b6a7d8d1e0`.
  - Artifact `Kite-custom-ipa` (ZIP containing `Kite.ipa`) was downloaded and inspected.
  - `Payload/Kite.app/Kite` and `Payload/Kite.app/PlugIns/NavigationWidget.appex/NavigationWidget`
    are both `Mach-O 64-bit arm64`.
  - `CFBundleIdentifier` is still `app.vela.ios`; the widget is `app.vela.ios.navigation`.
  - `CFBundleVersion` is `1032`, one above the verified v23 build 1031.
  - The app and widget carry `_CodeSignature`; the workflow's `codesign --verify --deep --strict`
    step passed.
  - `MapLibre.framework` and the Czech `cs.lproj` resources are inside the IPA.
- Physical-device checks (locked screen, background voice, Live Activity, Dynamic Island, real GPS
  loss): **not performed here**.

## Known limitations / open work

- **Google reviews and photos without a key**: only the sample embedded in search results is
  available natively. The full list needs either the optional Places API key or the Google Maps
  web page. This is now stated in the UI.
- **Transit**: Transitous is the only structured transit source wired in. A second keyless source
  (GTFS/GTFS-RT or another planner) still needs to be added and tested; the current fallback only
  widens the access walk around Transitous.
- **Native photo swiping for API photos**: the existing strip and viewer work, but Places API
  photos are resolved one by one; collecting all links before opening the viewer would make
  swiping across the complete Google sample smoother.
- The historical patch files should eventually move to `docs/patches/` with a README, or be
  deleted once the history is considered fully captured by source control. They are kept for now
  to preserve provenance.
