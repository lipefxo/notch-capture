# Notch Capture

Notch Capture is a private, local-first macOS capture inbox designed to coexist with NotchFlow. It is a Swift 6 agent app with no Dock icon, menu-bar item, ordinary app window, network access, analytics, or third-party runtime dependencies.

## Default shortcuts

- `Control–Shift–Space` captures the current selection.
- `Control–Shift–N` opens the composer and inbox.
- `Control–Shift–S` starts a region screenshot.

All three shortcuts can be changed from the notch-hosted Settings surface.

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

The first launch walks through Accessibility and optional launch-at-login setup. Screen Recording is requested only when region capture is used.

## Coexistence behavior

Automatic ownership is the default. When `com.benshih.notchFlow` occupies the pointer display, Notch Capture orders out its idle panel and removes its hit target. A shortcut creates a temporary foreground session above NotchFlow; save, Escape, or an outside click orders it out immediately.

NotchFlow is observed only through public process and window metadata. Notch Capture never hides, terminates, automates, or modifies it.

## Local data

SwiftData is stored at `~/Library/Application Support/NotchCapture/NotchCapture.store`. Attachments live in the adjacent `Attachments` directory. `.notchcapture` package import/export is available from Settings.
