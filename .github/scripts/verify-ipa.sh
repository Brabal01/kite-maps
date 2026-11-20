#!/usr/bin/env bash
# Inspect a packaged Kite.ipa the way a sideloader would, and fail loudly when
# something that used to install would not install any more.
#
# Exit code 0 means the package passed every structural check. It is not a
# claim that SideStore accepted it on a physical phone.
#
# Usage: verify-ipa.sh <ipa> <full|sidestore>
set -euo pipefail

IPA="${1:?ipa}"
VARIANT="${2:?full or sidestore}"

fail() { echo "FAIL: $*" >&2; exit 1; }
note() { echo "  $*"; }

[ -f "$IPA" ] || fail "missing $IPA"
unzip -tq "$IPA" >/dev/null || fail "zip is corrupt"
note "zip OK ($(du -h "$IPA" | cut -f1))"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q "$IPA" -d "$WORK"

APP="$WORK/Payload/Kite.app"
[ -d "$APP" ] || fail "no Payload/Kite.app"
PLIST="$APP/Info.plist"
[ -f "$PLIST" ] || fail "no app Info.plist"

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$2"; }

APP_ID="$(plist CFBundleIdentifier "$PLIST")"
[ "$APP_ID" = "app.vela.ios" ] || fail "app identifier changed: $APP_ID"
APP_BUILD="$(plist CFBundleVersion "$PLIST")"
APP_VERSION="$(plist CFBundleShortVersionString "$PLIST")"
APP_MIN="$(plist MinimumOSVersion "$PLIST")"
note "app $APP_ID $APP_VERSION ($APP_BUILD), iOS >= $APP_MIN"

# The executable must be a device arm64 binary and nothing emulator-only.
EXE="$APP/$(plist CFBundleExecutable "$PLIST")"
[ -f "$EXE" ] || fail "no app executable"
ARCHS="$(lipo -archs "$EXE")"
case " $ARCHS " in *" arm64 "*) ;; *) fail "app executable is not arm64 ($ARCHS)";; esac
case " $ARCHS " in *" x86_64 "*) fail "app executable contains an emulator slice ($ARCHS)";; esac
note "app executable arm64"

# All embedded frameworks are arm64 and signed.
for fw in "$APP"/Frameworks/*.framework; do
  [ -e "$fw" ] || continue
  name="$(basename "$fw" .framework)"
  binary="$fw/$name"
  [ -f "$binary" ] || fail "$name.framework has no binary"
  lipo -archs "$binary" | grep -q arm64 || fail "$name.framework is not arm64"
  codesign --verify --strict "$fw" || fail "$name.framework signature is invalid"
  note "framework $name arm64, signed"
done

# Extensions: identifiers, versions and minimum OS must agree with the app.
EXT_COUNT=0
for ext in "$APP"/PlugIns/*.appex; do
  [ -e "$ext" ] || continue
  EXT_COUNT=$((EXT_COUNT + 1))
  EP="$ext/Info.plist"
  EID="$(plist CFBundleIdentifier "$EP")"
  EBUILD="$(plist CFBundleVersion "$EP")"
  ESHORT="$(plist CFBundleShortVersionString "$EP")"
  EMIN="$(plist MinimumOSVersion "$EP")"
  case "$EID" in "$APP_ID".*) ;; *) fail "extension $EID is outside $APP_ID";; esac
  [ "$EBUILD" = "$APP_BUILD" ] || fail "extension $EID build $EBUILD != app $APP_BUILD"
  [ "$ESHORT" = "$APP_VERSION" ] || fail "extension $EID version $ESHORT != app $APP_VERSION"
  # A newer minimum OS than the app is refused by iOS at install time.
  [ "$EMIN" = "$APP_MIN" ] || fail "extension $EID needs iOS $EMIN but app needs $APP_MIN"
  codesign --verify --strict "$ext" || fail "extension $EID signature is invalid"
  note "extension $EID $ESHORT ($EBUILD), iOS >= $EMIN, signed"
done

case "$VARIANT" in
  full)
    [ "$EXT_COUNT" -ge 1 ] || fail "Full build has no widget extension"
    plist NSSupportsLiveActivities "$PLIST" | grep -qi true || fail "Full build lost NSSupportsLiveActivities"
    ;;
  sidestore)
    [ "$EXT_COUNT" -eq 0 ] || fail "SideStore build still contains $EXT_COUNT extension(s)"
    # Be honest: no widget, so Live Activities are not advertised.
    if plist NSSupportsLiveActivities "$PLIST" | grep -qi true; then
      fail "SideStore build advertises Live Activities without the widget"
    fi
    ;;
  *) fail "unknown variant $VARIANT" ;;
esac

# No foreign provisioning profile or development artefacts.
find "$APP" -name embedded.mobileprovision | grep -q . && fail "embedded.mobileprovision left in the bundle"
find "$APP" \( -name '*.dSYM' -o -name '*.xcarchive' \) | grep -q . && fail "build artefacts inside the app"

codesign --verify --deep --strict --verbose=2 "$APP" 2>/dev/null || fail "app signature is invalid"

echo "OK: $VARIANT variant passed structure checks"
