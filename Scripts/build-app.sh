#!/bin/zsh
set -euo pipefail

# build-app.sh [debug|release]
#
# Env:
#   CODESIGN_IDENTITY  Signing identity (default "-", ad-hoc). Note: TCC keys
#                      permission grants to the signing identity, and the ad-hoc
#                      identity changes every build — Automation/Screen Recording
#                      re-prompts between dev builds are expected until releases
#                      are signed with a stable Developer ID.
#   MARKETING_VERSION  Overrides CFBundleShortVersionString (releases derive it
#                      from the build number; local builds keep the plist value).
#   BUILD_NUMBER       Overrides CFBundleVersion (default: commit count). This
#                      is useful for installing an older local baseline before
#                      testing the next merge-driven Sparkle update.

ROOT="${0:A:h:h}"
CONFIGURATION="${1:-debug}"
APP_DIR="$ROOT/.build/Notch Capture.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
FRAMEWORKS="$CONTENTS/Frameworks"
IDENTITY="${CODESIGN_IDENTITY:--}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD)}"

if [[ ! "$BUILD_NUMBER" =~ '^[1-9][0-9]*$' ]]; then
  echo "error: BUILD_NUMBER must be a positive integer (got '$BUILD_NUMBER')" >&2
  exit 64
fi

swift build --package-path "$ROOT" -c "$CONFIGURATION"

BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$FRAMEWORKS"
cp "$ROOT/Support/Info.plist" "$CONTENTS/Info.plist"
cp "$BIN_DIR/NotchCapture" "$MACOS/NotchCapture"
chmod +x "$MACOS/NotchCapture"

SPARKLE_FRAMEWORK="$(find "$ROOT/.build" -type d -name 'Sparkle.framework' -path '*macos*' | head -1)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
  echo "error: Sparkle.framework not found under $ROOT/.build" >&2
  exit 1
fi
ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS/Sparkle.framework"

# Sparkle decides "is newer" from CFBundleVersion; it must increase every build.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
if [[ -n "${MARKETING_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$CONTENTS/Info.plist"
fi

sign() {
  local -a flags=(--force --sign "$IDENTITY")
  if [[ "$IDENTITY" != "-" ]]; then
    # Hardened runtime and ad-hoc signing don't mix; only harden real identities.
    flags+=(--options runtime --timestamp)
  fi
  codesign "${flags[@]}" "$@"
}

# Sign inside-out. --deep would re-sign Sparkle's nested helpers with the outer
# app's flags and break its installer, so each component is signed explicitly.
SPARKLE_B="$FRAMEWORKS/Sparkle.framework/Versions/B"
for xpc in "$SPARKLE_B"/XPCServices/*.xpc(N); do
  sign --preserve-metadata=entitlements "$xpc"
done
if [[ -e "$SPARKLE_B/Autoupdate" ]]; then
  sign --preserve-metadata=entitlements "$SPARKLE_B/Autoupdate"
fi
if [[ -e "$SPARKLE_B/Updater.app" ]]; then
  sign --preserve-metadata=entitlements "$SPARKLE_B/Updater.app"
fi
sign "$FRAMEWORKS/Sparkle.framework"
sign "$APP_DIR"

echo "$APP_DIR"
