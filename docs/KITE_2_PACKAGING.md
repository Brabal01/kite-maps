# Kite v29 — packaging, signing and SideStore

This document records what is actually built and verified. It is deliberately
separate from "it works on my phone": every claim below is either a CI check or
an explicit "not verified".

## Why v28 could build but not install

The v28 build passed and the IPA inspected cleanly, yet SideStore would not
install it at first. Two independent defects were found in the packaging:

1. **Mismatched minimum iOS version.** The app target was built for iOS 16.0 and
   the `NavigationWidget` extension for 16.2. iOS refuses a package whose
   embedded extension requires a newer system than the app. The build log does
   not care; the installer does.
2. **The `Build iPhone app` workflow never signed the widget.** It ad-hoc signed
   the frameworks and the app, then verified with `--deep --strict`. The
   embedded extension was still unsigned, so the verification failed on v28
   while the custom workflow (which does sign the widget) passed. Two workflows
   reported different truths about the same commit.

## What v29 changes

- App and extension share one deployment target: **iOS 16.2**, the real floor
  for Live Activities (`ActivityContent`, Dynamic Island). Devices on 16.0/16.1
  are therefore not supported by either variant; saying so is better than
  shipping a package the installer rejects.
- One signing implementation, `.github/scripts/sign-app.sh`, used by both
  workflows. Order is nested-first: extension frameworks → extension →
  app frameworks → app.
- One packaging implementation, `.github/scripts/pack-ipa.sh`, producing two
  variants from the same build.
- One structural verifier, `.github/scripts/verify-ipa.sh`, which fails the
  build on: wrong bundle id, non-arm64 or emulator slices, unsigned framework or
  extension, extension minimum OS different from the app, extension build or
  version different from the app, foreign provisioning profile, and a SideStore
  build that still contains an extension or advertises Live Activities.
- One build number for both workflows: `1000 + git commit count`
  (`.github/scripts/build-number.sh`). It keeps growing instead of resetting per
  workflow run.
- The app identifier stays `app.vela.ios`, so saved places, settings and the
  existing installation are preserved.

## The two variants

| | Kite Full | Kite SideStore |
| --- | --- | --- |
| Source commit | same | same |
| Map, GPS, search, routing, navigation | yes | yes |
| Transit, places, saved places, settings | yes | yes |
| `NavigationWidget.appex` | yes | no |
| Live Activities / Dynamic Island | yes | not advertised |
| Minimum iOS | 16.2 | 16.2 |
| Artifact | `Kite-v29-Full-ipa` | `Kite-v29-SideStore-ipa` |

The SideStore variant does not silently lose navigation features. It only drops
the optional widget extension, which is the part that needs a second
provisioning profile when sideloading. `NSSupportsLiveActivities` is set to
false there, so the system does not promise a Live Activity that cannot render.

## Installation

1. Download the `.ipa` from the workflow run (Actions → run → Artifacts).
2. SideStore → My Apps → `+` → choose the file.
3. If Full fails to install, use SideStore Compatibility and report which
   variant failed; that distinction is the whole point of shipping both.

## What is verified automatically

- `swift test` in `VelaCore`.
- Release build for `generic/platform=iOS`.
- Ad-hoc signature valid with `codesign --verify --deep --strict`.
- Both IPA variants unpack, contain only arm64, have matching identifiers,
  matching build/version numbers, matching minimum OS, and no provisioning
  profile.
- A simulator launch smoke test (normal, denied location, safe mode).

## What is not verified here

- Installation through SideStore on a physical phone. It cannot be performed in
  this environment and is not claimed.
- App Store review, notarization, or any distribution outside sideloading.
- Locked-screen GPS, battery drain and CarPlay, which need a device.
