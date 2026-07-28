# Notch Capture

Notch Capture is a private, local-first macOS capture inbox that lives in the notch. It is a Swift 6 agent app with no Dock icon, menu-bar item, ordinary app window, or analytics. The app makes no network requests except three narrow ones: fetching Spotify album artwork for the now-playing display, directly retrieving a page title and favicon when a new web link is captured, and checking the project's own [appcast](https://lipefxo.github.io/notch-capture/appcast.xml) for updates via the bundled Sparkle framework.

## Default shortcut

- `Control–Shift–N` opens the composer and inbox.

The shortcut can be changed from the notch-hosted Settings surface.

## Capturing

The composer bar is a single field for both search and capture: typing filters the ledger live, and pressing Return (or `⌘Return` when matches exist) captures the text as a new item. Beyond plain text, the composer accepts:

- **Links** — a lone URL is captured as a link, and its page title and favicon are fetched once at capture time.
- **Images** — paste images directly into the composer.
- **Drops** — files, images, URLs, and text dragged onto the surface become captures with attachments.
- **`@` tags** — write `@tag` anywhere in a capture; tags autocomplete while typing and get their own color.
- **Slash commands** — `/folder <name>` creates a folder, `/clear` moves all completed tasks to Trash. Suggestions appear as soon as the text starts with `/`.

## Organizing

Items are notes or tasks. Tasks can be completed (with a short completion hold before they leave the main page), pinned to the top, and given due dates. The ledger offers All, Tasks, Due, Completed, Archive, and Trash filters plus folder and tag views. Rows can be reordered by dragging and dropped into folders; file and image attachments get QuickLook thumbnails.

## Now playing and pomodoro

The expanded surface includes a utility shelf:

- **Now playing** — shows and controls Apple Music and Spotify via Automation (AppleScript). The album art doubles as a play/pause button with a waveform overlay, and a draggable scrubber seeks within the track (rendered with Liquid Glass on macOS 26+).
- **Pomodoro** — a focus timer with 15/25/45/60-minute presets (custom durations from 1 to 180 minutes), pause/resume, and a completion chime with a dedicated finish screen. It survives sleep and wake.

While idle, active music or a running timer shows in a compact activity pill in the notch.

## Mirror

A camera glyph in the notch — present on both compact pills and in the expanded header — opens a live webcam preview. It is a mirror only: nothing is recorded, captured, or sent anywhere. Unlike the inbox surfaces it never takes keyboard focus and does not close when you click elsewhere, so it stays put while you get ready for a call; the same glyph, the header's close button, or a click on the notch itself puts it away and turns the camera off. The first use asks for camera access (macOS ties that grant to the build's signature, so development builds re-prompt).

Cameras that publish UVC controls also get zoom and a recenter button in the mirror's header, and gimbal cameras can be aimed by dragging the preview — the scene follows the pointer, and the throw scales with the zoom level so a magnified view still moves precisely. AVFoundation exposes none of these on macOS, so they are read and written through CoreMediaIO, whose control objects hang off the capture device. Cameras without them (the built-in FaceTime camera) simply show no extra chrome. Gimbal webcams get one more accommodation: they park in whatever orientation they were last left in and override the requested format when the stream opens, so the mirror re-asserts a landscape format once frames are flowing — a camera already in landscape is never touched.

## Build and run

Requirements: Apple Silicon Mac, macOS 14 or newer, and Xcode with the macOS 14 SDK.

```sh
Scripts/run-app.sh
```

The development runner stops the copy previously launched from this worktree before rebuilding and keeps the app attached to the shell so stopping or archiving a Conductor workspace cannot leave an orphaned process behind. Use `Scripts/run-app.sh --stop` to stop only this worktree's app.

Open `Package.swift` in Xcode for development. Run tests with:

```sh
swift test
```

The first launch shows a four-step tour of the main features (capture, organizing, music, pomodoro). It resumes where you left off until finished.

## Idle behavior

Notch Capture keeps a compact pill available in the notch while idle. Its size is configurable (Minimal or Extended) in Settings. Both pills carry the mirror toggle. The optional external-display setting hides that pill on displays without a hardware notch; the global shortcut still opens the composer.

## Settings

The Settings surface (opened from the expanded inbox) covers launch at login, the external-display pill behavior, pill size, 12/24-hour timestamps, the composer shortcut, library import/export, update checks, and quitting the app.

## Updating

Release builds check the project's appcast for updates (Sparkle asks once whether to check automatically; "Check for Updates…" also lives in Settings, next to the running version).

Installing a release for the first time: current builds are not yet notarized, so macOS will refuse to open the app directly. Go to System Settings → Privacy & Security and click "Open Anyway" (macOS 15 removed the old right-click → Open bypass). Updates applied through Sparkle don't need this again.

Until releases are signed with a stable Developer ID, macOS also ties the Automation permission (used to control Apple Music and Spotify) to each build's ad-hoc signature — expect to re-grant it after an update.

Releases are published by pushing a `v*` tag; see `.github/workflows/release.yml` and `Scripts/package-release.sh`.

## Local data

SwiftData is stored at `~/Library/Application Support/NotchCapture/NotchCapture.store`. Attachments and cached favicons live in the adjacent `Attachments` directory. `.notchcapture` package import/export is available from Settings; the package is a directory with a `manifest.json` and copied attachments, and imports are additive with duplicate detection.

## Repository layout

- `Sources/NotchCapture` — the app (App, UI, ViewModels, Services, Infrastructure, Models).
- `Tests` — unit tests (`swift test`).
- `Scripts` — build and release packaging scripts.
- `web` — the Next.js landing page (statically exported; not yet wired to a deploy).
