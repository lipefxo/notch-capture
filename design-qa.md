# Design QA — Floating Glass Composer

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

final result: passed
