#!/usr/bin/env bash
# Ad-hoc sign a built Kite.app so sideloaders see a complete, sealed bundle.
#
# Order matters: nested code first (extension frameworks, the extension, the
# app's frameworks), the app last. Signing the app before its PlugIns/Frameworks
# leaves an invalid seal, and `codesign --verify --deep --strict` then fails.
#
# Usage: sign-app.sh <path/to/Kite.app> <build-number> [display-name]
set -euo pipefail

APP="${1:?app path}"
BUILD="${2:?build number}"
NAME="${3:-Kite}"

if [ ! -d "$APP" ]; then
  echo "No app at $APP" >&2
  exit 1
fi

stamp() { # stamp <Info.plist>
  local plist="$1"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$plist"
  # A sideloader re-signs with the user's certificate; a leftover provisioning
  # profile from somebody else's team makes that fail.
  rm -f "$(dirname "$plist")/embedded.mobileprovision"
}

sign() { # sign <bundle>
  codesign --force --sign - --timestamp=none --generate-entitlement-der "$1"
}

stamp "$APP/Info.plist"

# Inner code first.
for fw in "$APP"/Frameworks/*.framework; do
  [ -e "$fw" ] || continue
  sign "$fw"
done

for ext in "$APP"/PlugIns/*.appex; do
  [ -e "$ext" ] || continue
  stamp "$ext/Info.plist"
  for fw in "$ext"/Frameworks/*.framework; do
    [ -e "$fw" ] || continue
    sign "$fw"
  done
  sign "$ext"
done

# Then the app, whose seal covers everything above.
sign "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Signed $NAME $BUILD ($APP)"
