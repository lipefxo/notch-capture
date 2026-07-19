# Notch Capture

Notch Capture is a private, local-first macOS capture inbox that lives in the notch. It is a Swift 6 agent app with no Dock icon, menu-bar item, ordinary app window, network access, analytics, or third-party runtime dependencies.

## Default shortcuts

- `Control–Shift–Space` captures the current selection.
- `Control–Shift–N` opens the composer and inbox.

Both shortcuts can be changed from the notch-hosted Settings surface.

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

The first launch walks through Accessibility and optional launch-at-login setup.

## Idle behavior

Notch Capture keeps a compact pill available in the notch while idle. The optional external-display setting hides that pill on displays without a hardware notch; global shortcuts still open capture and composer sessions normally.

## Local data

SwiftData is stored at `~/Library/Application Support/NotchCapture/NotchCapture.store`. Attachments live in the adjacent `Attachments` directory. `.notchcapture` package import/export is available from Settings.
