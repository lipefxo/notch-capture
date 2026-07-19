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

## Coexistence evidence

- Dormant with NotchFlow 1.2.2: NotchFlow was the only on-screen notch window; Notch Capture had no visible window or hit surface.
- Explicit session: Notch Capture used a tightly bounded 420 × 560 panel at window layer 29, above NotchFlow’s layer 27.
- Dismissal: Notch Capture ordered out completely; NotchFlow immediately returned to being the only on-screen notch window.

## Result

The native implementation faithfully matches the requested floating-bottom layout and adds a balanced glass fade that preserves both ledger continuity and composer prominence.

## Motion and interaction QA

- Visible surface changes now use one persistent SwiftUI host and a top-centered AppKit frame morph: 220 ms expansion and 160 ms contraction with a strong ease-out curve. In-flight frame changes retarget from their current value.
- Dormant/NotchFlow handoff remains immediate. A contraction to the owned idle pill stops intercepting pointer input before its visual settle completes.
- Reduce Motion disables window resizing motion and uses short opacity-only content changes. Existing Reduce Transparency and Increased Contrast fallbacks remain intact.
- Inbox/Settings navigation, onboarding direction, drop targeting, filter selection, press feedback, and row-hover actions use scoped transitions; typing and search-result updates remain immediate.
- The composer takes focus after expansion and after returning from Settings. Confirmation expiry pauses while Undo is hovered and resumes from the remaining duration.
- Static expanded and confirmation snapshots render without clipping regressions. The debug build is ad-hoc signed, and the complete test suite passes with 37 tests.

final result: passed
