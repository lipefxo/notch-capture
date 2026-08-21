#!/bin/zsh
set -euo pipefail

# package-release.sh <marketing-version>
#
# Turns the current tree into publishable artifacts in dist/: a Sparkle-signed
# .zip update archive, a drag-to-Applications .dmg, and an updated appcast.xml.
#
# One-time EdDSA setup (keys sign every update archive):
#   Scripts/package-release.sh --fetch-tools   # download Sparkle CLI tools only
#   .build/sparkle-tools/bin/generate_keys     # prints public key, stores
#                                              # private key in login Keychain
#   → put the public key in Support/Info.plist (SUPublicEDKey)
#   → for CI: generate_keys -x /tmp/key && add contents as the
#     SPARKLE_ED_PRIVATE_KEY GitHub secret
#
# Env:
#   CODESIGN_IDENTITY        Developer ID string to sign + notarize; unset/"-"
#                            skips notarization (un-notarized ad-hoc build:
#                            testers use System Settings → Privacy & Security →
#                            "Open Anyway" on first install; macOS 15+ removed
#                            the right-click→Open bypass).
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD   notarytool credentials.
#   SPARKLE_ED_KEY_FILE      Private key file for generate_appcast ("-" reads
#                            stdin); defaults to the login Keychain.
#   BUILD_NUMBER             CFBundleVersion (default: final numeric component
#                            of the marketing version).

ROOT="${0:A:h:h}"
# Keep in sync with the resolved Sparkle package version (Package.resolved).
SPARKLE_TOOLS_VERSION="${SPARKLE_TOOLS_VERSION:-2.9.4}"
TOOLS_DIR="$ROOT/.build/sparkle-tools"
DIST="$ROOT/dist"
APPCAST_WORK="$ROOT/.build/appcast-release"
DMG_STAGE="$ROOT/.build/dmg-release"
REPO_SLUG="lipefxo/notch-capture"
APPCAST_URL="https://lipefxo.github.io/notch-capture/appcast.xml"

fetch_tools() {
  if [[ -x "$TOOLS_DIR/bin/generate_appcast" ]]; then
    return
  fi
  echo "Fetching Sparkle $SPARKLE_TOOLS_VERSION CLI tools…"
  mkdir -p "$TOOLS_DIR"
  local archive="$TOOLS_DIR/Sparkle-$SPARKLE_TOOLS_VERSION.tar.xz"
  curl -fsSL -o "$archive" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_TOOLS_VERSION/Sparkle-$SPARKLE_TOOLS_VERSION.tar.xz"
  tar -xf "$archive" -C "$TOOLS_DIR"
}

if [[ "${1:-}" == "--fetch-tools" ]]; then
  fetch_tools
  echo "$TOOLS_DIR/bin"
  exit 0
fi

if [[ $# -lt 1 ]]; then
  echo "usage: package-release.sh <marketing-version> | --fetch-tools" >&2
  exit 64
fi
VERSION="$1"
IDENTITY="${CODESIGN_IDENTITY:--}"
BUILD_NUMBER="${BUILD_NUMBER:-${VERSION##*.}}"

if [[ ! "$VERSION" =~ '^0\.1\.[1-9][0-9]*$' ]]; then
  echo "error: version must match 0.1.<positive-build-number> (got '$VERSION')" >&2
  exit 64
fi
if [[ ! "$BUILD_NUMBER" =~ '^[1-9][0-9]*$' ]]; then
  echo "error: BUILD_NUMBER must be a positive integer (got '$BUILD_NUMBER')" >&2
  exit 64
fi

fetch_tools

APP_DIR="$(
  MARKETING_VERSION="$VERSION" \
  BUILD_NUMBER="$BUILD_NUMBER" \
  CODESIGN_IDENTITY="$IDENTITY" \
  "$ROOT/Scripts/build-app.sh" release | tail -1
)"

rm -rf "$DIST" "$APPCAST_WORK" "$DMG_STAGE"
mkdir -p "$DIST" "$APPCAST_WORK" "$DMG_STAGE"
ZIP="$DIST/NotchCapture-$VERSION.zip"
DMG="$DIST/NotchCapture-$VERSION.dmg"

if [[ "$IDENTITY" != "-" ]]; then
  : "${APPLE_ID:?APPLE_ID required for notarization}"
  : "${APPLE_TEAM_ID:?APPLE_TEAM_ID required for notarization}"
  : "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD required for notarization}"
  echo "Notarizing…"
  ditto -c -k --keepParent "$APP_DIR" "$DIST/notarize-upload.zip"
  xcrun notarytool submit "$DIST/notarize-upload.zip" \
    --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" --wait
  xcrun stapler staple "$APP_DIR"
  rm "$DIST/notarize-upload.zip"
else
  echo "warning: ad-hoc identity — skipping notarization." >&2
  echo "warning: testers must use Privacy & Security → 'Open Anyway' on first install." >&2
fi

ditto -c -k --keepParent "$APP_DIR" "$ZIP"

# Preserve published history: generate_appcast updates an existing appcast,
# only appending the new archive's entry. Keep the DMG outside this directory
# so Sparkle sees exactly one update archive for the new version.
cp "$ZIP" "$APPCAST_WORK/"
curl -fsSL -o "$APPCAST_WORK/appcast.xml" "$APPCAST_URL" || true

typeset -a appcast_args
appcast_args=(
  --download-url-prefix "https://github.com/$REPO_SLUG/releases/download/v$VERSION/"
)
if [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
  appcast_args+=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
fi
"$TOOLS_DIR/bin/generate_appcast" "${appcast_args[@]}" "$APPCAST_WORK"
cp "$APPCAST_WORK/appcast.xml" "$DIST/appcast.xml"

# Finder-friendly first install: mount, then drag the app onto Applications.
ditto "$APP_DIR" "$DMG_STAGE/Notch Capture.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create \
  -volname "Notch Capture" \
  -srcfolder "$DMG_STAGE" \
  -format UDZO \
  -ov \
  "$DMG"

echo ""
echo "Artifacts to publish:"
echo "  $ZIP                → GitHub Release asset for tag v$VERSION"
echo "  $DMG                → GitHub Release asset for tag v$VERSION"
echo "  $DIST/appcast.xml   → GitHub Pages (served at $APPCAST_URL)"
