#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${1:-debug}"
APP_DIR="$ROOT/.build/Notch Capture.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

swift build --package-path "$ROOT" -c "$CONFIGURATION"

BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)"
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
cp "$ROOT/Support/Info.plist" "$CONTENTS/Info.plist"
cp "$BIN_DIR/NotchCapture" "$MACOS/NotchCapture"
chmod +x "$MACOS/NotchCapture"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
