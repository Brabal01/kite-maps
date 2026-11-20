#!/usr/bin/env bash
# Package Kite.app into an .ipa in one of two documented variants.
#
#   full      — the app plus NavigationWidget (Live Activities / Dynamic Island).
#   sidestore — the same source and the same navigation core, without the
#               optional widget extension. Live Activities are switched off in
#               Info.plist instead of being advertised but missing.
#
# Both variants come from one build and one commit. Nothing else differs.
#
# Usage: pack-ipa.sh <Kite.app> <full|sidestore> <output.ipa>
set -euo pipefail

APP_SRC="${1:?built app}"
VARIANT="${2:?full or sidestore}"
OUT="${3:?output ipa}"

case "$VARIANT" in
  full|sidestore) ;;
  *) echo "Unknown variant: $VARIANT" >&2; exit 1 ;;
esac

# zip runs inside a temporary directory; make the output path absolute first.
OUT_DIR="$(cd "$(dirname "$OUT")" && pwd)"
OUT="$OUT_DIR/$(basename "$OUT")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/Payload"
ditto "$APP_SRC" "$WORK/Payload/Kite.app"
APP="$WORK/Payload/Kite.app"

if [ "$VARIANT" = "sidestore" ]; then
  # The only difference from Full: no app extension to provision.
  rm -rf "$APP/PlugIns"
  /usr/libexec/PlistBuddy -c "Set :NSSupportsLiveActivities false" "$APP/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :NSSupportsLiveActivities bool false" "$APP/Info.plist"
  # The seal changed when Info.plist did.
  codesign --force --sign - --timestamp=none --generate-entitlement-der "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
fi

( cd "$WORK" && zip -qr -X "$OUT" Payload )
unzip -tq "$OUT"
echo "Packaged $VARIANT: $OUT"
