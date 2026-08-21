# Design QA — Persistent Audio Output Strip

## Comparison

- Source visual truth: `/Users/lipe/.codex/generated_images/01a01ca9-addb-7382-a850-7cd3e3f7ede9/exec-eeb8d107-1772-48ae-8079-67a28e18509d.png` (1086 × 1449 pixels).
- Native implementation: `.context/qa/audio-output/expanded-strip-final-clean.png` (920 × 1280 pixels; 460 × 640 points at 2×).
- Full-view comparison: `.context/qa/audio-output/reference-vs-implementation.png` (1888 × 1280 pixels).
- Focused header/strip comparison: `.context/qa/audio-output/reference-vs-implementation-strip.png` (1888 × 460 pixels).
- Density normalization: the generated source was proportionally normalized to the implementation's 920-pixel width; both focused regions cover the top 230 points at the implementation's 2× density.
- State: expanded inbox, AirPods unavailable, Edifier selected, interface headphones available.

## Findings

- No actionable P0/P1/P2 findings remain.
- The native 44-point strip preserves the selected direction's three equal controls, stable ordering, inset dividers, dimmed unavailable state with disconnect badge, violet selected icon/text, and 2-point underline.
- The implementation intentionally keeps the production app's current header utilities, tags, folders, ledger, and floating composer rather than replacing them with the older conceptual content generated around the strip.
- Typography uses native SF at the app's compact control scale. Canvas-resolved labels preserve the intended weights while avoiding the persistent AppKit host's first-commit glyph omission.
- Spacing and layout match the reference rhythm: the strip sits immediately below the header, fills the existing 20-point content column, keeps 44-point hit targets, and does not clip any label or icon.
- Colors map to existing tokens: ink background, hairline separators, secondary/tertiary text states, and the established violet `dueAccent` for the active output.
- No raster assets were required. Device artwork uses template-rendered SF Symbols with native antialiasing and a code-native unavailable badge.
- Copy is concise and matches the selected direction: `AirPods`, `Edifier`, and `Headphones`.

## Interaction and Accessibility Checks

- Available controls route through the ViewModel into the Core Audio service; unavailable controls are disabled and cannot write hardware state.
- Selection writes both media and system-sound defaults, then publishes hardware readback rather than an optimistic state. External device/default listeners refresh the strip.
- Preview actions update only preview state and cannot change the Mac's real output.
- Accessibility coverage exposes the `Audio output` group, current device, per-device availability, selected traits, and switching hints.
- Isolated tests cover selection, split-default failures, device disappearance, external notifications, hook forwarding, and visible accessibility states without touching real audio hardware.

## Comparison History

1. The first native capture exposed a P2 rendering defect: the persistent AppKit host omitted the Edifier and Headphones static labels on first commit. The three labels were moved to compact Canvas rendering, and the next capture showed all labels consistently.
2. The first focused comparison exposed a P2 state-color mismatch: the selected speaker glyph remained white while the source used violet. The SF Symbol was forced into template/monochrome rendering and changed to the outlined speaker variant. The final focused comparison shows icon, label, and underline sharing the selected token.
3. The post-fix full and focused comparisons found no remaining P0/P1/P2 typography, spacing, color, icon, copy, or clipping issues.

## Verification

- `swift test --quiet`: 371 tests, zero failures.
- Debug application bundle builds successfully and passes strict code-signature verification.
- Native preview capture uses `--preview-audio-output-strip` to keep the evidence deterministic and prevent composer keystrokes from changing the comparison state.

final result: passed

---

# Design QA — Expanded Header Center-to-Collapse

## Comparison

- Hardware-notch expanded capture: `.context/qa/native-display-compact-activity/expanded-center-collapse-hardware.png`.
- External-display expanded capture: `.context/qa/native-display-compact-activity/expanded-center-collapse-external.png`.
- Viewport and density: 460 × 560 points at 2× (920 × 1120 pixels).
- State: expanded inbox with music active.

## Findings

- No actionable P0/P1/P2 findings remain.
- The centered 156-point collapse target is visually absent in both captures; header typography, spacing, controls, content rows, and composer are unchanged.
- The target is mounted behind the foreground header controls and is exposed to accessibility as `Collapse Notch Capture`, with the hint `Returns to the compact surface`.
- Live hardware-notch and external-display passes confirmed the center target contracts to the context-appropriate compact activity surface.
- Foreground regression checks passed: New Folder opens its modal, Settings navigates to the settings surface, and presentation scrims intercept outside clicks without collapsing the inbox.
- View-model coverage confirms capture-pill, activity, and dormant destinations; successful inline edits save before collapse, while failed saves preserve the edit and keep the inbox expanded.

## Verification

- `swift test`: 291 tests, zero failures.
- Hardware and external expanded captures remain 920 × 1120 pixels with no visible collapse affordance.
- Live accessibility-driven interaction pass: center collapse, modal, menu, Settings, and presentation interception passed.

final result: passed

---

# Design QA — Expanded Notch Clearance

## Comparison

- Current expanded implementation: `.context/qa/native-display-compact-activity/expanded-wide.png`.
- Viewport and density: 460 × 560 points at 2× (920 × 1120 pixels).
- State: expanded inbox with music active.

## Findings

- No actionable P0/P1/P2 findings remain.
- The expanded content body increases from 420 to 440 points, moving the left and right header groups 10 points farther away from the centered hardware notch.
- The outer expanded shell increases from 440 to 460 points. Height, top anchoring, bottom radii, row density, and composer geometry remain unchanged.
- Expanded, Drop, Settings, and Onboarding share the same 460-point shell width, avoiding a horizontal jump during navigation.
- Hardware-notch compact activity and external Minimal/Extended activity widths remain unchanged.

## Verification

- `swift test`: 289 tests, zero failures.
- Geometry coverage asserts the 460 × 560-point expanded/settings shell, 460 × 500-point onboarding shell, and matching shadow canvas.

final result: passed

---

# Design QA — Compact Activity Spacing and Expansion Target

## Comparison

- Current native implementation: `.context/qa/native-display-compact-activity/hardware-music-tight.png`.
- Viewport and density: native hardware-notch panel window 384 × 44 points at 2× (768 × 88 pixels); visible surface 384 × 36 points.
- State: playing music with a simulated 156-point hardware notch.

## Findings

- No actionable P0/P1/P2 findings remain.
- Each symmetric hardware-notch wing is now 104 points, down from 116 points. The 80-point music cluster and mirror control remain centered without clipping or overlap.
- The full hardware-notch shell exposes an accessible `Open Notch Capture` background button. Its hit target follows the complete notch-hug shape, including the outer flare regions.
- Existing foreground actions remain independent above the background target. A live accessibility-driven interaction pass confirmed that the background target opens the inbox, while Previous leaves the surface collapsed and invokes only its transport action.
- External compact activity, the idle capture pill, and expanded geometry remain unchanged.

## Verification

- `swift test`: 289 tests, zero failures.
- Hardware geometry coverage now asserts equal 104-point wings and identical Minimal/Extended metrics.
- Live SwiftUI/AppKit interaction pass: expansion target passed; foreground transport isolation passed.

final result: passed

---

# Design QA — Native-Display Compact Activity

## Comparison

- Source visual truth: `/Users/lipe/.codex/generated_images/019f93d5-cc8d-7662-8368-4aa2c819a3bc/call_HHfcVY2iOPuwYeUSvDXjYSN8.png` (1719 × 915 pixels as generated).
- Normalized source: `.context/qa/native-display-compact-activity/reference-full-normalized.png` (2146 × 1142 pixels, matching the requested CleanShot scale).
- Native implementation: `.context/qa/native-display-compact-activity/hardware-music-extended.png`.
- Focused equal-canvas comparison: `.context/qa/native-display-compact-activity/reference-vs-implementation.png` (source left, implementation right).
- Viewport and density: native hardware-notch panel window 408 × 44 points at 2× (816 × 88 pixels); visible surface 408 × 36 points. The normalized source and implementation were both cropped to 816 × 88 pixels before comparison.
- State: playing music, resting pointer state. Additional captures cover music-only, playing hover, music paused, media recovery, external Minimal/Extended, and expanded.

## Findings

- No actionable P0/P1/P2 findings remain.
- The hardware-notch shell stays top-anchored, uses equal 104-point wings, preserves the physical notch gap, and keeps the 16-point compact corner treatment at both Minimal and Extended settings.
- Music is confined to the left wing: 22-point artwork, the existing waveform/hover transport treatment, and independent previous/next controls. The mirror toggle remains in the right wing.
- Music-only captures retain fixed wing positions; the trailing wing keeps the mirror control without reserving unused space.
- External Minimal (300 × 34-point visible surface) and Extended (440 × 56-point visible surface) captures preserve their existing metadata, transport, and progress layouts. The expanded 440 × 560-point surface is unchanged.

## Required Fidelity Surfaces

- Fonts and typography: native SF typography is preserved; no metadata is rendered in the hardware-notch layout.
- Spacing and layout: the normalized source and implementation agree on compact total width, top-edge attachment, equal left/right regions, one-row density, and absence of below-notch content. Native control spacing follows the production 116-point wing geometry from the approved plan.
- Colors and tokens: the implementation uses the existing ink shell, primary/secondary text ramp, and shadowless compact chrome.
- Image quality and assets: live album artwork continues through `NSImage` with high-quality interpolation, a 5-point continuous mask, and the existing adaptive overlay color. The preview fixture differs from the mock's album subject but exercises the real production asset path.
- Copy and content: only dynamic activity content is shown. No song title, artist, duration, progress text, labels, or additional controls leak into the hardware-notch state.
- Icons and interactions: SF Symbols preserve the existing optical weights. Artwork play/pause, previous, next, and mirror controls retain their native Button actions, help text, accessibility labels, keyboard focus, pressed feedback, and Reduce Motion behavior.
- Recovery: the frozen artwork remains visible but dimmed and non-interactive, while previous/next collapse to the existing accessible Retry action.

## Comparison History

1. The first native single-activity captures exposed a P2 layout issue: SwiftUI removed an `EmptyView` wing and shifted the music cluster.
2. Both wings were changed to persistent clear 104-point layout regions with music and mirror content overlaid at center.
3. Post-fix pixel evidence keeps the music cluster in the same position in both external and hardware-notch music-only captures.
4. The final equal-canvas comparison found no remaining P0/P1/P2 differences. The source's generated dimensions were normalized to the originally requested CleanShot scale before width and placement were judged.

## Verification

- Hardware captures: `hardware-music-minimal.png`, `hardware-music-extended.png`, `hardware-music-only.png`, `hardware-playing-hover.png`, `hardware-music-paused.png`, and `hardware-music-recovery.png` under `.context/qa/native-display-compact-activity/`.
- External regression captures: `external-music-minimal.png` and `external-music-extended.png` in the same directory, produced with the debug-only external-display preview override.
- Top-edge placement remains enforced by the existing `NotchGeometry.panelFrame` contract and its unit coverage.
- The full Swift package suite passes 289 tests with zero failures.
- The debug application bundle builds successfully and passes strict code-signature verification.

final result: passed

---

# Design QA — Adaptive Album Playback Control

## Comparison

- Source visual truth: `/Users/lipe/.codex/generated_images/019f7aff-1a34-7880-8ccf-48a886dfa905/exec-58ad5f97-8750-42df-ae0d-14a988d62bb0.png` (1536 × 1024 pixels)
- Implementation state board: `.context/qa/album-control-implementation-state-board.png` (1536 × 1024 pixels)
- Full-view comparison: `.context/qa/album-control-full-comparison.png` (source board beside the full expanded playing surface)
- Focused comparison: `.context/qa/album-control-focused-comparison.png` (source state board beside all eight focused implementation states)
- Expanded captures: `.context/qa/album-control-expanded-playing-final.png`, `.context/qa/album-control-expanded-playing-hover-final.png`, `.context/qa/album-control-expanded-paused-final.png`, `.context/qa/album-control-expanded-paused-hover-final.png`
- Compact captures: `.context/qa/album-control-compact-playing-final.png`, `.context/qa/album-control-compact-playing-hover-final.png`, `.context/qa/album-control-compact-paused-final.png`, `.context/qa/album-control-compact-paused-hover-final.png`
- Hardware-notch captures: `.context/qa/album-control-hardware-playing-final.png`, `.context/qa/album-control-hardware-playing-hover-final.png`
- Viewports: expanded 568 × 640 points at 2×; compact 300 × 34 points at 2×; simulated hardware-notch 800 × 36 points at 2×
- States: playing/rest, playing/hover-or-focus, paused/rest, and paused/hover-or-focus

## Findings

- No actionable P0/P1/P2 findings remain.
- The 40 × 40 and 22 × 22 album tiles preserve the established radii, spacing, system typography, graphite surface, mint progress control, and separate previous/next affordances.
- Playing/rest displays four lightweight activity bars inside the artwork. Playing/hover-or-focus replaces them with Pause; paused/rest leaves the cover unobstructed; paused/hover-or-focus displays Play.
- The activity bars and transport glyph are the only blended pixels. Their base color is extracted from the cover's dominant usable hue, with a high-brightness neutral fallback for monochrome artwork, and difference compositing supplies local contrast without a cover-wide veil.
- Compact metadata now contains title and artist only. The prior duration/current-time line is intentionally absent per the final direction, and the two-line stack remains legible in both external and hardware-notch layouts.
- Expanded elapsed and total timestamps remain unchanged around the progress control. Previous and next remain independent controls; the standalone play/pause control and external waveform are removed.
- Typography, spacing, color, artwork crop quality, SF Symbol weight, and copy were compared in the combined evidence. The implementation remains denser than the conceptual board because it preserves the production player's existing dimensions and spacing as requested.

## Comparison history

1. The first live SwiftUI difference-blend pass produced correct rest states but exposed a persistent-host rendering defect in static hover captures, where sibling labels and controls disappeared.
2. The overlay was moved into an offscreen artwork render using Core Graphics difference compositing. The shared control was then reduced to one mounted visual state at a time, preserving the quick crossfade while stopping hidden waveform updates.
3. Final expanded, compact, and simulated hardware-notch captures retain every surrounding label and control in hover/focus states. The waveform and Play/Pause glyph remain confined to the artwork, with no global dimming layer.

## Interaction and accessibility checks

- The artwork is its own button and routes directly to the existing play/pause intent; compact metadata remains a separate button that opens the expanded surface.
- Pointer hover and keyboard focus share the same visible transport state. Help text, accessibility labels, and the playing/paused accessibility value describe the artwork action.
- Reduce Motion freezes the playing waveform and uses the existing reduced-motion transition. The control keeps a static playback indicator rather than removing state information.
- Dominant-hue extraction is keyed to artwork identity instead of running on every animation frame. The animated renderer is mounted only while playing at rest.
- Existing view-model hook coverage confirms music intents route without changing the surface. Added color-extraction tests cover dominant chromatic artwork and monochrome fallback.

## Verification

- Native AppKit-hosted SwiftUI snapshots cover all eight expanded/compact playback combinations plus the simulated hardware-notch playing and hover states.
- The complete Swift package suite passes 207 tests with zero failures.
- The debug app is rebuilt and ad-hoc signed for native snapshot verification.

final result: passed

---

# Design QA — Music Timing + Paused Visualization

## Selected references and native captures

- Current app structure: `.context/attachments/qmpRhp/CleanShot 2026-07-19 at 10.37.21@2x.jpg`
- Reported reduced player: `.context/attachments/7ozLwb/CleanShot 2026-07-19 at 11.37.30@2x.jpg`
- Reported expanded player: `.context/attachments/3NsZmQ/CleanShot 2026-07-19 at 11.39.20@2x.jpg`
- Native external music capture: `.context/qa/reduced-music-controls.png`
- Native hardware-notch music capture: `.context/qa/reduced-music-controls-notch.png`
- Native expanded capture: `.context/qa/expanded-seekable-progress.png`
- Focused expanded-player comparison capture: `.context/qa/expanded-seekable-progress-band.png`
- Final expanded playing capture: `.context/qa/timing-expanded-playing-final.png`
- Final expanded paused capture: `.context/qa/timing-expanded-paused-final.png`
- Focused playing/paused bands: `.context/qa/timing-expanded-playing-band-final.png`, `.context/qa/timing-expanded-paused-band-final.png`
- External reduced music-only playing/paused: `.context/qa/timing-external-music-playing.png`, `.context/qa/timing-external-music-paused.png`
- Hardware-notch music-only playing/paused: `.context/qa/timing-notch-music-playing.png`, `.context/qa/timing-notch-music-paused.png`

## Findings

- The external reduced surface remains 300 × 34 points. Music-only uses the recovered empty width for track metadata while retaining artwork, audio bars, and all three controls.
- Music-only keeps previous, play/pause, next, and mirror controls visible without clipping.
- Hardware-notch layouts use equal content wings around the centered 156-point simulated notch gap. Music metadata stays on the left; transport stays with the artwork and the mirror control stays on the right.
- Artwork, metadata, and audio bars remain one expand target. Each transport icon is an independent 28-point press target and does not expand the panel.
- The expanded player preserves the selected 3-point visual line inside a 14-point scrub target. The rendered fill visibly reflects the preview position; hover/drag reveals a mint thumb.
- The reduced player shows a protected monospaced total duration on the artist row. Artist text yields first when the hardware wing constrains width.
- Playing compact states retain the mint audio bars; paused states remove the bars and reclaim their width without moving or clipping transport or mirror controls.
- The open player shows timestamp-derived elapsed time on the left of the seek line and total duration on the right. Paused captures hold the elapsed value while changing the center control to Play.
- SF Symbols, native system typography, ink/graphite/mint tokens, press styles, reduced-motion handling, and accessibility labels reuse the existing design system.
- Side-by-side visual comparison of the reported states and all playing/paused native captures found no P0/P1/P2 clipping, spacing, hierarchy, or legibility issues.

## Verification

- Native external and simulated hardware-notch states were rendered through the AppKit-hosted SwiftUI snapshot path for music-only.
- The expanded player was rendered with a timestamp-derived non-zero progress fill.
- Formatter and model coverage now includes zero, negative, unavailable, minute, hour, live elapsed, paused elapsed, and scrub-preview values.
- The complete Swift package suite passes 205 tests, and the release app passes strict ad-hoc signature verification.

---

# Previous Design QA — Floating Glass Composer

## Comparison

- Source visual truth: `.context/attachments/eRQXEY/CleanShot 2026-07-15 at 17.33.57@2x.jpg` (1030 × 1166 crop)
- Final implementation: `Design/qa/implementation-floating-glass-v2.png` (420 × 560 points at 2×)
- Full-view comparison: `Design/qa/source-and-implementation-floating-glass-v2.png`
- Focused bottom-region comparison: `Design/qa/focused-floating-glass-v2.png`
- State: expanded Inbox, All filter, populated ledger, empty focused unified input
- Environment: native AppKit `NSPanel` hosting SwiftUI, macOS 26.5.2, 2560 × 1440 display

## Findings

- No actionable P0/P1/P2 findings remain.
- Typography uses the existing native system hierarchy and matches the reference's weight, density, and truncation behavior.
- Spacing matches the intended structure: fixed header and filters, full-height ledger, 18-point composer margins, 60-point height, and 16-point radius.
- The graphite/ink palette, restrained border, shadow, native material, and 110-point masked fade preserve the established tokens while adding the requested balanced glass treatment.
- The source contains dynamic user notes while the preview contains reference fixture notes and one image attachment; this is an intentional content-state difference, not an image-quality substitution.
- Copy and SF Symbols remain consistent with the functional app. The input, filters, attachment row, and screenshot/settings affordances remain interactive and accessible.

## Comparison history

1. The first floating render (`implementation-floating-glass-v1.png`) matched the bottom geometry and showed the ledger underlap clearly, but the new surface did not explicitly strengthen its edge under Increased Contrast.
2. The final render added a 1.5-point higher-contrast border fallback without changing the default appearance. The full and focused comparisons confirm the composer remains visually detached while the bottom link progressively softens and darkens beneath it.
3. The source crop omits the hardware-notch connector and uses different live content, so comparison judgment was limited to the shared header, filters, ledger rhythm, bottom margins, composer shape, and underlap treatment.

## Interaction and accessibility checks

- The ledger scroll region continues behind the overlay and includes a 96-point terminal spacer, allowing the final row to clear the composer.
- Search matches, unmatched-text Add, Return submission, paste responder routing, repeated additions, Escape, and outside-click behavior remain connected to the unchanged view model and panel controller.
- The glass layer ignores hit testing and accessibility. Reduce Transparency receives an opaque graphite-to-ink fallback; Increased Contrast strengthens the field border; the static effect introduces no Reduce Motion dependency.
- Empty, error, filtered, attachment, and drop-target branches retain their existing controls; the drop target remains the topmost full-panel overlay.

## Result

The native implementation faithfully matches the requested floating-bottom layout and adds a balanced glass fade that preserves both ledger continuity and composer prominence.

## Motion and interaction QA

- Visible surface changes now use one persistent SwiftUI host and a top-centered AppKit frame morph: 220 ms expansion and 160 ms contraction with a strong ease-out curve. In-flight frame changes retarget from their current value.
- A contraction to the idle pill stops intercepting pointer input before its visual settle completes.
- Reduce Motion disables window resizing motion and uses short opacity-only content changes. Existing Reduce Transparency and Increased Contrast fallbacks remain intact.
- Inbox/Settings navigation, onboarding direction, drop targeting, filter selection, press feedback, and row-hover actions use scoped transitions; typing and search-result updates remain immediate.
- The composer takes focus after expansion and after returning from Settings. Confirmation expiry pauses while Undo is hovered and resumes from the remaining duration.
- Static expanded and confirmation snapshots render without clipping regressions. The debug build is ad-hoc signed, and the complete test suite passes with 37 tests.

final result: passed
