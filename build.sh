#!/bin/bash
#
# Builds KeyboardLocker.app, gives it an icon and code signature, and installs
# it into /Applications so it shows up in Launchpad and Spotlight.
#
#   ./build.sh            build + install + launch
#   ./build.sh --no-open  build + install, do not launch
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Keyboard Locker"
BIN_NAME="KeyboardLocker"
APP="dist/$APP_NAME.app"

echo "▸ Building release binary…"
swift build -c release

echo "▸ Assembling the app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Icon: best effort. A missing icon never breaks the build.
ICON_DIR="$(mktemp -d)"
trap 'rm -rf "$ICON_DIR"' EXIT
if swift tools/make-icon.swift "$ICON_DIR/base.png" >/dev/null 2>&1; then
  ICONSET="$ICON_DIR/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for pair in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
              "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
              "512 512x512" "1024 512x512@2x"; do
    set -- $pair
    sips -z "$1" "$1" "$ICON_DIR/base.png" --out "$ICONSET/icon_$2.png" >/dev/null 2>&1 || true
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true
else
  echo "  (icon generation skipped)"
fi

echo "▸ Signing…"
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(.*\)"/\1/p' \
  | grep -E '^(Developer ID Application|Apple Development|Mac Developer)' \
  | head -1 || true)"

if [ -n "$IDENTITY" ]; then
  codesign --force --timestamp=none --sign "$IDENTITY" "$APP"
  echo "  signed with: $IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "  signed ad-hoc (no signing certificate found)"
fi

echo "▸ Installing…"
pkill -x "$BIN_NAME" 2>/dev/null || true
sleep 0.3

TARGET_DIR="/Applications"
if ! rm -rf "$TARGET_DIR/$APP_NAME.app" 2>/dev/null || ! cp -R "$APP" "$TARGET_DIR/" 2>/dev/null; then
  TARGET_DIR="$HOME/Applications"
  mkdir -p "$TARGET_DIR"
  rm -rf "$TARGET_DIR/$APP_NAME.app"
  cp -R "$APP" "$TARGET_DIR/"
  echo "  /Applications not writable, installed to ~/Applications instead"
fi

INSTALLED="$TARGET_DIR/$APP_NAME.app"
# Refresh Launch Services so the icon and name show up immediately.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$INSTALLED" >/dev/null 2>&1 || true

echo "✓ Installed: $INSTALLED"

if [ "${1:-}" != "--no-open" ]; then
  open "$INSTALLED"
fi
