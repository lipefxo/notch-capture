# Design QA — Option 3 Quick Snippets

## Comparison

- Selected visual source: `/Users/lipe/.codex/generated_images/019fa538-60e1-7803-8db6-119f32889d26/call_4hkrtrVOES0J8eicoAxBIshr.png` (970 × 1621 pixels).
- Final native implementation: `.context/qa/quick-snippets/implementation-v3.png`.
- Full-view combined evidence: `.context/qa/quick-snippets/source-vs-implementation-small.png` (source left, implementation right).
- Focused equal-canvas shelf evidence: `.context/qa/quick-snippets/focused-snippet-shelf-comparison.png` (source left, implementation right).
- Additional states: `.context/qa/quick-snippets/snippet-draft.png` and `.context/qa/quick-snippets/empty-state.png`.
- Viewport and density: native panel window 460 × 640 points at 2× (920 × 1280 pixels).
- State: root Inbox, All snippets, three visible snippet rows, one active Copied confirmation, populated Recent captures, and the existing unified composer.

## Findings

- No actionable P0/P1/P2 findings remain.
- The implementation preserves the approved Option 3 hierarchy: fixed Quick snippets shelf, tabbed custom categories with counts, three immediately reusable rows, explicit Copy/Copied feedback, and a separate Recent captures section.
- The shelf remains fixed at three 62-point rows and scrolls internally when more snippets exist. The final native overlay scroller does not consume row width or create a persistent visual gutter.
- Quick snippets are ordinary captures with reusable metadata, so edits, archive/trash state, export/import, tags, and links stay synchronized. Root All/search deduplicates shelf items from Recent captures; folder and lifecycle views continue to show the ordinary capture row.
- The mock's second, top capture field is intentionally not duplicated. The approved implementation constraint was to keep the existing capture experience intact, so `/snippet` enters a dedicated reusable-snippet state in the established bottom composer.
- The 640-point expanded height is limited to open Inbox/Drop/Settings surfaces and makes the complete three-row shelf, Recent captures hierarchy, and composer simultaneously legible.

## Required Fidelity Surfaces

- Fonts and typography: native SF typography follows the existing size and weight ramp. Shelf title, category tabs, row title/preview, and copy action retain the source hierarchy without introducing a new font.
- Spacing and layout: the shelf uses the existing 20-point content column, compact 28-point category tabs, 62-point rows, 30-point leading icon tiles, and an internally scrolling 186-point list region.
- Colors and tokens: the existing ink/graphite/control/text system is preserved. The selected category uses the production accent treatment and Copied uses the existing completion green.
- Image quality and assets: no raster assets were required; code-native SF Symbols stay sharp at 2× and inherit production optical weights.
- Copy and content: titles, category names, previews, counts, `Copy`, `Copied`, `Quick snippets`, and `Recent captures` match the approved content model. Clipboard payloads preserve stored text exactly, including line breaks and mentions; link-only snippets copy their URL text.
- Empty and authoring states: a fresh library seeds no categories or snippets, retains All and the add-category action, and teaches `/snippet`. The composer draft state names its optional category and provides a clear exit back to normal capture.

## Comparison History

1. The first 460 × 560-point implementation exposed a P2 hierarchy issue: the fixed shelf left too little of Recent captures visible.
2. The open-surface height was increased to 640 points so the shelf, Recent captures, and composer read as one view.
3. The second pass exposed a P2 native-scroll issue: a persistent dark gutter reduced usable shelf width.
4. The shelf was moved to the native overlay scroller configuration. The final full-view and focused comparisons show no remaining P0/P1/P2 fidelity issues.

## Interaction and Accessibility Checks

- Explicit Copy writes the exact snippet payload, keeps the panel open, moves the item to the front by `lastCopiedAt`, and returns from Copied to Copy after 1.2 seconds.
- Category create, rename, delete, filter, count, and optional assignment paths are wired. Deleting a category leaves its snippets available under All.
- Existing eligible text/link captures expose Add to Quick snippets; reusable captures expose category reassignment and removal. Image/file captures are rejected.
- Shelf Edit opens the shared inline editor in place, so saving updates both the reusable shelf and the underlying capture.
- `/snippet` enters the dedicated composer mode, Return saves, and Escape exits while retaining the typed text as a normal draft.
- Buttons include native focus/activation behavior, help text, accessibility labels, selected traits, and Reduce Motion-aware category transitions.

## Verification

- `swift test`: 297 tests, zero failures.
- Repository coverage includes snippet/category CRUD, text/link eligibility, lifecycle visibility, root deduplication, search/category filtering, copy ordering/feedback, and schema-v5 package round trips.
- Native AppKit-hosted SwiftUI captures cover populated, Copied, snippet-draft, and fresh-empty states.
- The debug application bundle builds successfully and passes strict code-signature verification.

final result: passed

---

# Design QA — Expanded Header Center-to-Collapse

## Comparison

- Hardware-notch expanded capture: `.context/qa/native-display-compact-activity/expanded-center-collapse-hardware.png`.
- External-display expanded capture: `.context/qa/native-display-compact-activity/expanded-center-collapse-external.png`.
- Viewport and density: 460 × 560 points at 2× (920 × 1120 pixels).
- State: expanded inbox with music and Pomodoro active.

## Findings

- No actionable P0/P1/P2 findings remain.
- The centered 156-point collapse target is visually absent in both captures; header typography, spacing, controls, content rows, and composer are unchanged.
- The target is mounted behind the foreground header controls and is exposed to accessibility as `Collapse Notch Capture`, with the hint `Returns to the compact surface`.
- Live hardware-notch and external-display passes confirmed the center target contracts to the context-appropriate compact activity surface.
- Foreground regression checks passed: New Folder opens its modal, Pomodoro opens its menu, Settings navigates to the settings surface, and presentation scrims intercept outside clicks without collapsing the inbox.
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
- State: expanded inbox with music and Pomodoro active.

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

- Current native implementation: `.context/qa/native-display-compact-activity/hardware-both-tight.png`.
- Viewport and density: native hardware-notch panel window 384 × 44 points at 2× (768 × 88 pixels); visible surface 384 × 36 points.
- State: playing music plus running Pomodoro with a simulated 156-point hardware notch.

## Findings

- No actionable P0/P1/P2 findings remain.
- Each symmetric hardware-notch wing is now 104 points, down from 116 points. The 80-point music cluster and 54-point timer remain centered without clipping or overlap.
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
- Native implementation: `.context/qa/native-display-compact-activity/hardware-both-extended.png`.
- Focused equal-canvas comparison: `.context/qa/native-display-compact-activity/reference-vs-implementation.png` (source left, implementation right).
- Viewport and density: native hardware-notch panel window 408 × 44 points at 2× (816 × 88 pixels); visible surface 408 × 36 points. The normalized source and implementation were both cropped to 816 × 88 pixels before comparison.
- State: playing music plus running Pomodoro, resting pointer state. Additional captures cover music-only, timer-only, playing hover, music paused, timer paused, media recovery, external Minimal/Extended, and expanded.

## Findings

- No actionable P0/P1/P2 findings remain.
- The hardware-notch shell stays top-anchored, uses equal 116-point wings, preserves the physical notch gap, and keeps the 16-point compact corner treatment at both Minimal and Extended settings.
- Music is confined to the left wing: 22-point artwork, the existing waveform/hover transport treatment, and independent previous/next controls. The timer is confined to the right wing and keeps the existing monospaced urgency-color treatment.
- Music-only and timer-only captures retain the same fixed wing positions; the unused wing remains blank instead of recentering the remaining activity.
- External Minimal (300 × 34-point visible surface) and Extended (440 × 56-point visible surface) captures preserve their existing metadata, transport, progress, and timer layouts. The expanded 440 × 560-point surface is unchanged.

## Required Fidelity Surfaces

- Fonts and typography: native SF typography is preserved. The timer remains 11-point semibold monospaced text with monospaced digits; no metadata is rendered in the hardware-notch layout.
- Spacing and layout: the normalized source and implementation agree on compact total width, top-edge attachment, equal left/right regions, one-row density, and absence of below-notch content. Native control spacing follows the production 116-point wing geometry from the approved plan.
- Colors and tokens: the implementation uses the existing ink shell, primary/secondary text ramp, timer urgency colors, and shadowless compact chrome.
- Image quality and assets: live album artwork continues through `NSImage` with high-quality interpolation, a 5-point continuous mask, and the existing adaptive overlay color. The preview fixture differs from the mock's album subject but exercises the real production asset path.
- Copy and content: only dynamic activity content is shown. No song title, artist, duration, progress text, labels, or additional controls leak into the hardware-notch state.
- Icons and interactions: SF Symbols preserve the existing optical weights. Artwork play/pause, previous, next, and timer pause/resume retain their native Button actions, help text, accessibility labels, keyboard focus, pressed feedback, and Reduce Motion behavior.
- Recovery: the frozen artwork remains visible but dimmed and non-interactive, previous/next collapse to the existing accessible Retry action, and the opposite timer remains active.

## Comparison History

1. The first native single-activity captures exposed a P2 layout issue: SwiftUI removed an `EmptyView` wing, shifting music-only 58 points right and timer-only 58 points left.
2. Both wings were changed to persistent clear 116-point layout regions with activity content overlaid at center.
3. Post-fix pixel evidence matches the mixed state: music occupies x=58...203 in both mixed and music-only captures; the timer occupies x=647...712 in both mixed and timer-only captures.
4. The final equal-canvas comparison found no remaining P0/P1/P2 differences. The source's generated dimensions were normalized to the originally requested CleanShot scale before width and placement were judged.

## Verification

- Hardware captures: `hardware-both-minimal.png`, `hardware-both-extended.png`, `hardware-music-only.png`, `hardware-timer-only.png`, `hardware-playing-hover.png`, `hardware-music-paused.png`, `hardware-timer-paused.png`, and `hardware-music-recovery.png` under `.context/qa/native-display-compact-activity/`.
- External regression captures: `external-both-minimal.png` and `external-both-extended.png` in the same directory, produced with the debug-only external-display preview override.
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

# Design QA — Text-Only Pomodoro Toggle

## Comparison

- Source visual truth: `/Users/lipe/.codex/generated_images/019f7b71-2d79-75a3-b72e-6dfa3840f8ee/exec-08ee969c-106a-4434-82c7-2a2308d6dad5.png`
- Combined source and native implementation comparison: `.context/qa/pomodoro-toggle/source-vs-implementation.png`
- External-display states: `.context/qa/pomodoro-toggle/external-rest.png`, `external-hover.png`, `external-focus.png`, `external-pressed.png`, `external-paused.png`, and `external-paused-hover.png`
- Hardware-notch states: `.context/qa/pomodoro-toggle/hardware-rest.png`, `hardware-hover.png`, and `hardware-paused.png`
- Mixed activity layouts: `.context/qa/pomodoro-toggle/external-combined.png` and `hardware-combined.png`
- Completion and expanded surfaces: `.context/qa/pomodoro-toggle/completion.png` and `expanded.png`
- Environment: native AppKit `NSPanel` hosting SwiftUI, 2× snapshots; external compact pill and simulated 156-point hardware notch with 116-point content wings

## Findings

- No actionable P0/P1/P2 findings remain.
- The compact timer is plain monospaced text at rest, with no timer icon, persistent capsule, border, progress line, or transport glyph.
- Hover and keyboard focus reveal the same tightly fitted 54 × 28-point, 7-point-radius control-tint backdrop. The pressed snapshot confirms a stronger tint and the existing 120 ms press treatment without layout shift.
- Running states preserve the existing mint urgency color. Paused states freeze at the deterministic preview value and use the neutral secondary-text token.
- External Pomodoro-only layouts center the hit target; hardware-notch layouts right-align it inside the 116-point wing. Music-plus-Pomodoro snapshots retain transport controls and show no clipping.
- Typography, spacing, color tokens, corner geometry, and alignment match the selected Quiet Hit Area direction. No source image assets were needed because this is a code-native control treatment.
- The expanded header remains visually unchanged, while the completion surface fits both Done and Restart without truncation.

## Interaction and accessibility checks

- The compact action routes through `togglePomodoro()` and preserves `surfaceState`; service tests cover running → paused → running with a stable remaining value.
- Native Button behavior retains Return/Space activation. Pointer hover and keyboard focus share the same visible treatment, and Reduce Motion removes the press scale animations.
- Help and accessibility action copy changes between Pause and Resume according to phase. The remaining time is exposed in spoken minute/second units.
- The complete Swift test suite passes 220 tests. The native snapshot matrix covers rest, hover, keyboard focus, press, running, paused, external, hardware-notch, mixed activity, expanded, and completion states.

final result: passed

---

# Design QA — Music Timing + Paused Visualization

## Selected references and native captures

- Current app structure: `.context/attachments/qmpRhp/CleanShot 2026-07-19 at 10.37.21@2x.jpg`
- Reported reduced player: `.context/attachments/7ozLwb/CleanShot 2026-07-19 at 11.37.30@2x.jpg`
- Reported expanded player: `.context/attachments/3NsZmQ/CleanShot 2026-07-19 at 11.39.20@2x.jpg`
- Native external music-only capture: `.context/qa/reduced-music-controls.png`
- Native hardware-notch music-only capture: `.context/qa/reduced-music-controls-notch.png`
- Native external music + Pomodoro capture: `.context/qa/reduced-music-timer-controls.png`
- Native hardware-notch music + Pomodoro capture: `.context/qa/reduced-music-timer-controls-notch.png`
- Native expanded capture: `.context/qa/expanded-seekable-progress.png`
- Focused expanded-player comparison capture: `.context/qa/expanded-seekable-progress-band.png`
- Final expanded playing capture: `.context/qa/timing-expanded-playing-final.png`
- Final expanded paused capture: `.context/qa/timing-expanded-paused-final.png`
- Focused playing/paused bands: `.context/qa/timing-expanded-playing-band-final.png`, `.context/qa/timing-expanded-paused-band-final.png`
- External reduced music-only playing/paused: `.context/qa/timing-external-music-playing.png`, `.context/qa/timing-external-music-paused.png`
- External reduced music + Pomodoro playing/paused: `.context/qa/timing-external-both-playing.png`, `.context/qa/timing-external-both-paused.png`
- Hardware-notch music-only playing/paused: `.context/qa/timing-notch-music-playing.png`, `.context/qa/timing-notch-music-paused.png`
- Hardware-notch music + Pomodoro playing/paused: `.context/qa/timing-notch-both-playing.png`, `.context/qa/timing-notch-both-paused.png`

## Findings

- The external reduced surface remains 300 × 34 points. Music-only uses the recovered empty width for track metadata while retaining artwork, audio bars, and all three controls.
- Music + Pomodoro keeps previous, play/pause, next, and the ring-free numeric timer visible without clipping.
- Hardware-notch layouts use equal 116-point content wings around the centered 156-point simulated notch gap. Music metadata stays on the left; transport and timer controls stay on the right.
- Artwork, metadata, and audio bars remain one expand target. Each transport icon is an independent 28-point press target and does not expand the panel.
- The expanded player preserves the selected 3-point visual line inside a 14-point scrub target. The rendered fill visibly reflects the preview position; hover/drag reveals a mint thumb.
- The reduced player shows a protected monospaced total duration on the artist row. Artist text yields first when the hardware wing or Pomodoro state constrains width.
- Playing compact states retain the mint audio bars; paused states remove the bars and reclaim their width without moving or clipping transport and Pomodoro controls.
- The open player shows timestamp-derived elapsed time on the left of the seek line and total duration on the right. Paused captures hold the elapsed value while changing the center control to Play.
- SF Symbols, native system typography, ink/graphite/mint tokens, press styles, reduced-motion handling, and accessibility labels reuse the existing design system.
- Side-by-side visual comparison of the reported states and all playing/paused native captures found no P0/P1/P2 clipping, spacing, hierarchy, or legibility issues.

## Verification

- Native external and simulated hardware-notch states were rendered through the AppKit-hosted SwiftUI snapshot path for music-only and music + Pomodoro.
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
