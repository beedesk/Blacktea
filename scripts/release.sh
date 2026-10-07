#!/bin/bash
# Build a release of BlackTea, run the self-test, and package it as .zip and .dmg.
#   BLACKTEA_DIST_DIR  where to publish (default: /Users/Shared/BlackTea)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
REL="$ROOT/.build/release"
DIST="${BLACKTEA_DIST_DIR:-/Users/Shared/BlackTea}"
APP_NAME="BlackTea.app"
BASE="BlackTea-$VERSION"

rm -rf "$REL"; mkdir -p "$REL"
BLACKTEA_OUT_DIR="$REL" "$ROOT/build.sh"
APP="$REL/$APP_NAME"

echo "==> Self-test"
"$APP/Contents/MacOS/BlackTea" --self-test | tail -1

echo "==> Packaging zip"
( cd "$REL" && ditto -c -k --norsrc --noextattr --noqtn --keepParent "$APP_NAME" "$BASE.zip" )

echo "==> Packaging dmg"
STAGE="$REL/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "BlackTea $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$REL/$BASE.dmg" >/dev/null
for i in 1 2 3 4 5; do  # hdiutil verify is occasionally "temporarily unavailable"
  hdiutil verify "$REL/$BASE.dmg" >/dev/null 2>&1 && break
  [[ $i -eq 5 ]] && { echo "dmg verify failed" >&2; exit 1; }
  sleep 3
done

echo "==> Publishing to $DIST"
mkdir -p "$DIST"
rm -rf "$DIST/$APP_NAME"
ditto "$APP" "$DIST/$APP_NAME"
cp -f "$REL/$BASE.zip" "$REL/$BASE.dmg" "$DIST/"
( cd "$DIST" && shasum -a 256 "$BASE.zip" "$BASE.dmg" > "$BASE.sha256" )
chmod 755 "$DIST"
chmod -R a+rX "$DIST/$APP_NAME" "$DIST/$BASE.zip" "$DIST/$BASE.dmg" "$DIST/$BASE.sha256"
codesign --verify --deep --strict "$DIST/$APP_NAME"
ls -la "$DIST"
