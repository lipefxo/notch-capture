# Notch Capture

Notch Capture is a private, local-first macOS capture inbox that lives in the notch. It is a Swift 6 agent app with no Dock icon, menu-bar item, ordinary app window, or analytics. The app makes no network requests except two narrow ones: fetching Spotify album artwork for the now-playing display, and checking the project's own [appcast](https://lipefxo.github.io/notch-capture/appcast.xml) for updates via the bundled Sparkle framework.

## Default shortcut

- `Control–Shift–N` opens the composer and inbox.

The shortcut can be changed from the notch-hosted Settings surface.

## Build and run

Requirements: Apple Silicon Mac, macOS 14 or newer, and Xcode with the macOS 14 SDK.

```sh
Scripts/build-app.sh debug
open ".build/Notch Capture.app"
```

Open `Package.swift` in Xcode for development. Run tests with:

```sh
swift test
```

The first launch walks through the composer shortcut and optional launch-at-login setup.

## Idle behavior

Notch Capture keeps a compact pill available in the notch while idle. The optional external-display setting hides that pill on displays without a hardware notch; the global shortcut still opens the composer.

## Updating

Release builds check the project's appcast for updates (Sparkle asks once whether to check automatically; "Check for Updates…" also lives in Settings, next to the running version).

Installing a release for the first time: current builds are not yet notarized, so macOS will refuse to open the app directly. Go to System Settings → Privacy & Security and click "Open Anyway" (macOS 15 removed the old right-click → Open bypass). Updates applied through Sparkle don't need this again.

Until releases are signed with a stable Developer ID, macOS also ties permission grants (Screen Recording, Automation) to each build's ad-hoc signature — expect to re-grant them after an update.

Releases are published by pushing a `v*` tag; see `.github/workflows/release.yml` and `Scripts/package-release.sh`.

## Local data

SwiftData is stored at `~/Library/Application Support/NotchCapture/NotchCapture.store`. Attachments live in the adjacent `Attachments` directory. `.notchcapture` package import/export is available from Settings.
