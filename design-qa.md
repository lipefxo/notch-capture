# Design QA — Hugged Ledger

## Comparison

- Selected source: `Design/selected-hugged-ledger.png` (1487 × 1058)
- Expanded implementation: `Design/qa/implementation-expanded.png` (420 × 560 points at 2×)
- Confirmation implementation: `Design/qa/implementation-confirmation.png` (344 × 62 points at 2×)
- Same-input comparison: `Design/qa/source-and-implementation.png`
- Environment: native AppKit `NSPanel` hosting SwiftUI, macOS 26.5.2, 2560 × 1440 display

## QA history

1. The first internal render exposed AppKit-backed controls as placeholders and did not lay out the lazy feed. Replaced the synthetic render with a capture of the live `NSHostingView` backing the actual panel.
2. Simplified the top title to “Inbox,” retained the centered notch-hug connector, and selected a preview row so the requested inline actions are visible.
3. Compared the selected direction and both implemented surfaces together. Geometry, hierarchy, graphite glass treatment, mint accent, quick capture, filters, grouped ledger, inline controls, and compact Undo confirmation align with the target.
4. Verified the companion label remains legible without competing with the title. All body text and controls remain inside the 420 × 560 surface with no clipping or horizontal overflow.
5. Verified keyboard focus, accessible labels/hints, Reduce Motion-aware press feedback, and dark high-contrast hierarchy in code and in the rendered surface.

## Coexistence evidence

- Dormant with NotchFlow 1.2.2: NotchFlow was the only on-screen notch window; Notch Capture had no visible window or hit surface.
- Explicit session: Notch Capture used a tightly bounded 420 × 560 panel at window layer 29, above NotchFlow’s layer 27.
- Dismissal: Notch Capture ordered out completely; NotchFlow immediately returned to being the only on-screen notch window.

## Result

The native implementation faithfully carries the selected visual direction while adding the requested companion status, inline task controls, real data states, and notch ownership behavior.

final result: passed
