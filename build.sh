#!/bin/bash
# Build BlackTea.app (release, universal arm64+x86_64, ad-hoc signed).
#   BLACKTEA_OUT_DIR  output folder (default: ./.build)
#   BLACKTEA_ARCHS    architectures (default: "arm64 x86_64")
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/.build"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD_NUM="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
OUT_DIR="${BLACKTEA_OUT_DIR:-$BUILD}"
OUT="$OUT_DIR/BlackTea.app"
ARCHS="${BLACKTEA_ARCHS:-arm64 x86_64}"
MIN_VER="13.0"   # SMAppService.mainApp
BUNDLE_ID="com.beedesk.blacktea"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$BUILD" "$OUT_DIR"

echo "==> BlackTea $VERSION ($BUILD_NUM), archs: $ARCHS"
printf 'enum BuildInfo { static let version = "%s" }\n' "$VERSION" > "$BUILD/BuildInfo.swift"
BIN="$BUILD/BlackTea"
slices=()
for arch in $ARCHS; do
  swiftc "$ROOT"/Sources/*.swift "$BUILD/BuildInfo.swift" -sdk "$SDK_PATH" -target "${arch}-apple-macosx${MIN_VER}" \
    -framework Cocoa -framework IOKit -framework ServiceManagement \
    -O -file-prefix-map "$ROOT=." -o "$BIN.$arch"
  slices+=("$BIN.$arch")
done
lipo -create "${slices[@]}" -output "$BIN"
rm -f "${slices[@]}"

echo "==> App icon"
ICON_PNG="$ROOT/Resources/AppIcon-1024.png"
if [[ ! -f "$ICON_PNG" ]]; then
  swiftc "$ROOT/scripts/make-icon.swift" -o "$BUILD/make-icon"
  "$BUILD/make-icon" "$ICON_PNG"
fi
ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz "$ICON_PNG" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) "$ICON_PNG" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"

echo "==> Assembling $OUT"
rm -rf "$OUT"
CONTENTS="$OUT/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/BlackTea"
cp "$BUILD/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
chmod 755 "$CONTENTS/MacOS/BlackTea"

cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>BlackTea</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>BlackTea</string>
  <key>CFBundleDisplayName</key><string>BlackTea</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUM}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key><string>${MIN_VER}</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>BlackTea ${VERSION}</string>
</dict>
</plist>
PLIST
echo -n 'APPL????' > "$CONTENTS/PkgInfo"

xattr -cr "$OUT"
codesign -s - --force --identifier "$BUNDLE_ID" "$OUT"
codesign --verify --deep --strict "$OUT"
echo "==> Done: $OUT"
lipo -archs "$CONTENTS/MacOS/BlackTea"
echo "    CLI: \"$OUT/Contents/MacOS/BlackTea\" --self-test | --version"
