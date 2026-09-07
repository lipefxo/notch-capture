# Notch Capture

Notch Capture is a private, local-first macOS capture inbox that lives in the notch. It is a Swift 6 agent app with no Dock icon, menu-bar item, ordinary app window, or analytics. The app makes no network requests except four narrow ones: fetching Spotify album artwork for the now-playing display, directly retrieving a page title and favicon when a new web link is captured, checking the project's own [appcast](https://lipefxo.github.io/notch-capture/appcast.xml) for updates via the bundled Sparkle framework, and reading remaining ChatGPT/Codex and Cursor usage from those products when they are already signed in on this Mac.

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

The composer shows the current search scope and the available Return actions. At the root it searches across every folder; inside a folder it searches that folder by default, and the scope control can broaden the query to all items while keeping the folder as the capture destination. When matches exist, the visible hints explain that Return opens the first result and `⌘Return` adds a new item anyway. With no matches, Return adds the thought to the current destination. `Shift–Return` inserts a line break in the composer and in inline item editing.

A leading `/` opens the command suggestions, where Return runs the selected action. Type `//` when the slash is part of a literal search or capture instead of a command.

Drops keep the providers that succeed and report partial failures with the items that need a manual retry; if every provider fails, the composer reports that nothing was captured.

## Organizing

Items are notes or tasks. Tasks can be completed (with a short completion hold before they leave the main page), pinned to the top, and given due dates. The Inbox title opens a view selector with Inbox, Tasks, Due, Completed, Archive, and Trash. The filtered views include matching items from every folder, so archived and trashed captures remain reachable for recovery. Rows in Archive and Trash offer Restore, while permanent deletion requires confirmation and cannot be undone. After archiving, moving an item to Trash, or clearing completed tasks, an Undo banner appears for the latest ledger change.

The Utilities shelf and Folders section start collapsed so the ledger has more room. Click Utilities to reveal audio and playback controls, or click Folders to reveal folder rows and their drop targets. Their expanded or collapsed state is remembered.

Rows can be reordered by dragging and dropped into folders; file and image attachments get QuickLook thumbnails. With keyboard navigation, Return activates the selected row (opening a link-only capture or entering editing), while Space completes or reopens a task. F2 edits a selected capture, and Shift–F10 opens its action menu. Arrow keys move the selection and Escape returns focus to the composer.

## Now playing

The expanded surface includes a collapsible utility shelf:

- **Now playing** — click Utilities to show controls for Apple Music and Spotify via Automation (AppleScript). The album art doubles as a play/pause button with a waveform overlay, and a draggable scrubber seeks within the track (rendered with Liquid Glass on macOS 26+).

While idle, active music shows in a compact activity pill in the notch.

## Audio output

The expanded surface includes a persistent three-way output strip for this Mac's AirPods, EDIFIER M60 speakers, and the headphones connected through the `fifine Ampli1` interface. Available devices switch both normal app audio and system sounds with one click; disconnected devices remain visible but disabled so each target stays in a predictable position. The strip follows changes made in Control Center and updates automatically when Bluetooth or USB devices appear or disappear.

A volume row below the output strip controls the current default output and toggles mute. The compact media activity pill exposes the same control through a speaker button that morphs into a focused volume surface without taking keyboard focus; Back or a click elsewhere returns to the current idle notch. Outputs with physical-only controls stay visible and explain that their device controls should be used instead.

Switching output reads both the media and system defaults first. If the second route fails, Notch Capture restores the previous routes when readback confirms success; if the outputs remain split, it directs you to Control Center before retrying.

The integration uses Apple's Core Audio hardware properties directly. It does not record audio, request microphone access, initiate Bluetooth connections, or install an audio driver.

## Mirror

A camera glyph in the expanded header opens a live webcam preview. It is a mirror only: nothing is recorded, captured, or sent anywhere. Unlike the inbox surfaces it never takes keyboard focus and does not close when you click elsewhere, so it stays put while you get ready for a call; the same glyph, the header's close button, or a click on the notch itself puts it away and turns the camera off. The first use asks for camera access (macOS ties that grant to the build's signature, so development builds re-prompt).

Cameras that publish UVC controls also get zoom and a recenter button in the mirror's header, and gimbal cameras can be aimed by dragging the preview — the scene follows the pointer, and the throw scales with the zoom level so a magnified view still moves precisely. Three large, numbered controls below the mirror recall per-camera position presets containing pan, tilt, and zoom; the adjacent save control captures the current framing into a slot. The selected preset is restored whenever the mirror opens, while ordinary framing adjustments remain temporary until explicitly saved. AVFoundation exposes none of these controls on macOS, so they are read and written through CoreMediaIO, whose control objects hang off the capture device. Cameras without them (the built-in FaceTime camera) simply show no extra chrome. Gimbal webcams get two more accommodations: the mirror keeps its starting placeholder visible until the landscape rotation and saved framing have physically settled, preventing a portrait flash, and it restores each physical camera's last pan/tilt position after the camera wakes from Privacy Mode or the app restarts.

## Studio light (experimental)

Notch Capture can pair with one ZHIYUN MOLUS G60 over Bluetooth Low Energy. Pairing and troubleshooting live in Settings; after pairing, the lightbulb control in the expanded header provides standby on/off, 0–100% brightness, and 2700–6500 K color-temperature controls. The saved light reconnects automatically when the app launches or the connection temporarily drops.

This integration uses an unofficial, reverse-engineered G60 protocol, independently implemented in Swift from the behavior documented by the [`zhiyun-cli` project](https://github.com/robinebers/zhiyun-cli), and may be affected by fixture firmware changes. The fixture must remain physically powered: “off” is the light's Bluetooth standby state, not a way to switch disconnected mains power. Disconnect the G60 from the ZY Vega phone app before connecting from Notch Capture because the light may accept only one controller at a time.

Pairing reads the fixture's assigned control address instead of assuming a fixed address. A freshly Bluetooth-reset G60 reports that it is unregistered; Notch Capture registers the single supported light directly before reading its state. If discovery or synchronization stalls, close ZY Vega, disable Bluetooth on the phone, triple-press the G60 Bluetooth reset control, and pair again from Settings.

The integration is implemented directly with Apple's CoreBluetooth framework. It does not install a background agent or require a third-party Bluetooth runtime. Only the light's macOS Bluetooth identifier and display name are stored locally in `UserDefaults`; Forget removes both. No Bluetooth mesh keys, scenes, or Zhiyun account data are stored.

## Model usage

The Utilities shelf and collapsed media activity show OpenAI and Cursor marks with a liquid fill that tracks the remaining allowance. The fill settles with a short depth animation after updates, leaves a quiet inactive silhouette at 0%, and shows the exact percentage on hover. Settings keeps the detailed usage and reset information. Usage appears when those products are already signed in on this Mac.

- **OpenAI** — reads the local Codex login (`~/.codex/auth.json`, or the Codex keychain item) and asks ChatGPT for the current 5-hour and weekly windows.
- **Cursor** — reads the Cursor app or CLI login and asks Cursor for plan usage, including how much is left in the current billing cycle.

Notch Capture never stores those tokens. It only makes the usage request when a local login is present, and a Refresh control in Settings can fetch again. The endpoints are the same ones those products use for their own usage displays; they are unofficial and may change.

## Build and run

Requirements: Apple Silicon Mac, macOS 14 or newer, and Xcode with the macOS 14 SDK. MOLUS G60 control additionally requires Bluetooth access.

```sh
Scripts/run-app.sh
```

The development runner stops the copy previously launched from this worktree before rebuilding and keeps the app attached to the shell so stopping or archiving a Conductor workspace cannot leave an orphaned process behind. Use `Scripts/run-app.sh --stop` to stop only this worktree's app.

Open `Package.swift` in Xcode for development. Run tests with:

```sh
swift test
```

## iPhone and Apple Watch companion

The companion project lives at `Apps/NotchCaptureCompanion.xcodeproj` and contains native iOS 17 and watchOS 10 targets. The iPhone app supports quick note/task capture, search, editing, pinning, completion, Archive, and Trash. The Watch app is intentionally text-first: dictate or scribble a capture, review recent items, and complete tasks with a tap.

Both companions are offline-first. Changes are written to a local JSON cache and durable outbox immediately, then reconciled through the private CloudKit database for `iCloud.com.lipe.notchcapture`. The Mac app mirrors the existing SwiftData ledger every 20 seconds and keeps attachment files local; attachment transfer is not part of the first companion release.

Before running on devices:

1. Open `Apps/NotchCaptureCompanion.xcodeproj` in Xcode and select your Apple Developer team for both targets.
2. Create or select the `iCloud.com.lipe.notchcapture` container in Signing & Capabilities, with CloudKit enabled, for the Mac, iOS, and Watch bundle identifiers.
3. Run each app once against the Development environment. CloudKit creates the private `CaptureRecord` record type from the fields written by the app.
4. In CloudKit Console, promote the schema to Production before distributing a build.

With matching iOS and watchOS simulator runtimes installed, check the complete embedded app without signing with:

```sh
xcodebuild -project Apps/NotchCaptureCompanion.xcodeproj \
  -scheme "Notch Capture" -destination "generic/platform=iOS Simulator" \
  SYMROOT="$PWD/.context/CompanionBuild" \
  OBJROOT="$PWD/.context/CompanionIntermediates" \
  CODE_SIGNING_ALLOWED=NO build
```

The Watch target can also be compiled on its own:

```sh
xcodebuild -project Apps/NotchCaptureCompanion.xcodeproj \
  -target "Notch Capture Watch" -sdk watchsimulator \
  SYMROOT="$PWD/.context/CompanionBuild" \
  OBJROOT="$PWD/.context/CompanionIntermediates" \
  -arch arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
```

The combined iPhone scheme embeds the Watch app. On physical devices, all three apps must be signed by the same team and use the same iCloud container. iCloud failures never block local capture; queued edits retry on the next sync.

The first launch shows a three-step tour of the main features (capture, organizing, music). It resumes where you left off until finished.

## Idle behavior

Notch Capture keeps a content-free notch silhouette available while idle. It matches the physical notch on supported Mac displays and uses a compact virtual notch on external displays; clicking it or using the global shortcut opens the composer. Active media uses the configurable Minimal or Extended activity size. When a window fills the display hosting the activity — full screen or maximized — an Extended activity smoothly reduces to Minimal and returns to Extended once the display is no longer occupied; the saved preference does not change. The optional external-display setting hides the resting notch on displays without a hardware notch; the global shortcut still opens the composer.

## Settings

The Settings surface (opened from the expanded inbox) covers launch at login, the external-display notch behavior, media activity size, 12/24-hour timestamps, remaining OpenAI and Cursor usage, MOLUS G60 Bluetooth pairing, the composer shortcut, library import/export, update checks, and quitting the app.

## Updating

Release builds check the project's appcast hourly and notify before installing a newer build. "Check for Updates…" also lives in Settings, next to the running version.

For the first install, download `NotchCapture-<version>.dmg` from the [latest GitHub release](https://github.com/lipefxo/notch-capture/releases/latest), open it, and drag Notch Capture onto the Applications shortcut. Current builds are not yet notarized, so macOS will refuse to open the downloaded app directly. Go to System Settings → Privacy & Security and click "Open Anyway" (macOS 15 removed the old right-click → Open bypass). Updates applied through Sparkle don't need this again.

Until releases are signed with a stable Developer ID, companion CloudKit sync is unavailable and macOS ties the Automation permission (used to control Apple Music and Spotify) to each build's ad-hoc signature — expect to re-grant it after an update. Ad-hoc builds omit the restricted iCloud entitlements because macOS refuses to launch an ad-hoc app that claims them.

Every successful push to `master` publishes an immutable `v0.1.<build>` GitHub release. The build number is the Git commit count, and each release contains a first-install DMG plus the Sparkle ZIP. The workflow can also be rerun manually on `master`; reruns repair the existing release instead of creating duplicate tags. See `.github/workflows/release.yml` and `Scripts/package-release.sh`.

Local debug builds deliberately use bundle build number `1`. Sparkle compares bundle build numbers, so this keeps a locally built copy from appearing as new as a later merge-driven release. Set `BUILD_NUMBER` explicitly only when testing a particular update path.

## Local data

SwiftData is stored at `~/Library/Application Support/NotchCapture/NotchCapture.store`. Attachments and cached favicons live in the adjacent `Attachments` directory. `.notchcapture` package import/export is available from Settings; the package is a directory with a `manifest.json` and copied attachments, and imports are additive with duplicate detection.

## Repository layout

- `Sources/NotchCapture` — the app (App, UI, ViewModels, Services, Infrastructure, Models).
- `Tests` — unit tests (`swift test`).
- `Scripts` — build and release packaging scripts.
- `web` — the Next.js landing page (statically exported; not yet wired to a deploy).
