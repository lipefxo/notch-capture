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
#   MARKETING_VERSION  Overrides CFBundleShortVersionString (release packaging
#                      supplies it; local builds keep the plist value).
#   BUILD_NUMBER       Overrides CFBundleVersion. Release builds default to the
#                      commit count; debug builds use 1 so they cannot reserve a
#                      future merge-driven Sparkle release number.

ROOT="${0:A:h:h}"
CONFIGURATION="${1:-debug}"
APP_DIR="$ROOT/.build/Notch Capture.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
FRAMEWORKS="$CONTENTS/Frameworks"
RESOURCES="$CONTENTS/Resources"
IDENTITY="${CODESIGN_IDENTITY:--}"
if [[ -z "${BUILD_NUMBER:-}" ]]; then
  if [[ "$CONFIGURATION" == "release" ]]; then
    BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD)"
  else
    BUILD_NUMBER=1
  fi
fi

if [[ ! "$BUILD_NUMBER" =~ '^[1-9][0-9]*$' ]]; then
  echo "error: BUILD_NUMBER must be a positive integer (got '$BUILD_NUMBER')" >&2
  exit 64
fi

swift build --package-path "$ROOT" -c "$CONFIGURATION"

BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIGURATION" --show-bin-path)"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$FRAMEWORKS" "$RESOURCES"
cp "$ROOT/Support/Info.plist" "$CONTENTS/Info.plist"
cp "$BIN_DIR/NotchCapture" "$MACOS/NotchCapture"
chmod +x "$MACOS/NotchCapture"

RESOURCE_BUNDLE="$BIN_DIR/NotchCapture_NotchCapture.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  ditto "$RESOURCE_BUNDLE" "$RESOURCES/NotchCapture_NotchCapture.bundle"
fi

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
if [[ "$IDENTITY" == "-" ]]; then
  # launchd rejects ad-hoc apps that claim restricted iCloud entitlements,
  # even after the user approves the app in Privacy & Security. Keep local and
  # unsigned release builds launchable; CloudKit sync requires a real identity.
  sign "$APP_DIR"
else
  sign --entitlements "$ROOT/Support/NotchCapture.entitlements" "$APP_DIR"
fi

echo "$APP_DIR"
