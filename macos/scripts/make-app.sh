#!/usr/bin/env bash
# Build the Catalina-only x86_64 Swift executable, embed Node + cli, assemble
# Switchboard.app, and sign every Mach-O ad hoc from the inside out.
set -euo pipefail

MACOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP="$MACOS_DIR/build/Switchboard.app"
VERSION="${VERSION:-0.1.0}"
BUILD_VERSION="${BUILD_VERSION:-$VERSION}"
BUNDLE_ID="${BUNDLE_ID:-org.lfkdsk.switchboard.legacy}"
export MACOSX_DEPLOYMENT_TARGET="10.15"

if [ "$(uname -m)" != "x86_64" ]; then
  echo "legacy build must run on an Intel (x86_64) macOS host" >&2
  exit 1
fi
if [[ ! "$BUILD_VERSION" =~ ^[0-9]{1,4}(\.[0-9]{1,2}){0,2}((d|a|b|fc)([1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5]))?$ ]]; then
  echo "invalid CFBundleVersion: $BUILD_VERSION" >&2
  exit 1
fi

echo "▸ swift build -c $CONFIG --arch x86_64 (target 10.15)"
( cd "$MACOS_DIR" && swift build -c "$CONFIG" --arch x86_64 )
BIN_DIR="$(cd "$MACOS_DIR" && swift build -c "$CONFIG" --arch x86_64 --show-bin-path)"
BIN="$BIN_DIR/Switchboard"
[ -x "$BIN" ] || { echo "build produced no binary at $BIN" >&2; exit 1; }

echo "▸ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Switchboard"

# Swift concurrency is not part of the OS before macOS 12. The binary links
# @rpath/libswift_Concurrency.dylib (weak), and the only rpath that holds it
# points into the build machine's Xcode, so on Catalina every Task/await
# crashes at launch. Ship Apple's back-deployment copy inside the bundle.
echo "▸ embedding Swift concurrency back-deployment library"
BACKDEPLOY="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-5.5/macosx"
[ -f "$BACKDEPLOY/libswift_Concurrency.dylib" ] \
  || { echo "missing $BACKDEPLOY/libswift_Concurrency.dylib" >&2; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
cp "$BACKDEPLOY/libswift_Concurrency.dylib" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Switchboard"

# Every @rpath dependency must resolve inside the bundle; build-machine rpaths
# (Xcode toolchain, /usr/lib/swift for libraries Catalina lacks) do not count.
while read -r dep; do
  lib="${dep#@rpath/}"
  [ -f "$APP/Contents/Frameworks/$lib" ] \
    || { echo "unbundled @rpath dependency: $dep" >&2; exit 1; }
done < <(otool -L "$APP/Contents/MacOS/Switchboard" | awk '/@rpath\//{print $1}')

ICON_PLIST=""
if [ -f "$MACOS_DIR/Resources/AppIcon.icns" ]; then
  cp "$MACOS_DIR/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  ICON_PLIST="  <key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>Switchboard</string>
  <key>CFBundleExecutable</key><string>Switchboard</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Switchboard</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_VERSION</string>
$ICON_PLIST
  <key>LSArchitecturePriority</key><array><string>x86_64</string></array>
  <key>LSMinimumSystemVersion</key><string>10.15</string>
  <key>LSRequiresNativeExecution</key><true/>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

if [ -z "${SKIP_RUNTIME:-}" ]; then
  echo "▸ embedding Node v20.18.0 x64 runtime"
  "$MACOS_DIR/scripts/fetch-runtime.sh" "$APP/Contents/Resources/runtime"
else
  echo "▸ SKIP_RUNTIME set — development bundle will use env/PATH Node"
fi

echo "▸ ad-hoc signing nested Mach-O files"
while IFS= read -r -d '' file_path; do
  file -b "$file_path" | grep -q 'Mach-O' || continue
  codesign --force --sign - "$file_path"
  echo "    signed ${file_path#"$APP/Contents/"}"
done < <(find "$APP/Contents/Resources" -type f -print0)
codesign --force --sign - "$APP/Contents/Frameworks/libswift_Concurrency.dylib"
codesign --force --sign - "$APP/Contents/MacOS/Switchboard"
codesign --force --sign - "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

echo "✓ built $APP"
