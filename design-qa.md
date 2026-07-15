# Design QA — Hugged Ledger

## Comparison

- Selected source: `Design/selected-hugged-ledger.png` (1487 × 1058)
- User-supplied crop: `.context/attachments/8oYXJS/CleanShot 2026-07-15 at 16.55.02@2x.jpg`
- Expanded implementation: `Design/qa/implementation-expanded-v3.png` (420 × 560 points at 2×)
- Confirmation implementation: `Design/qa/implementation-confirmation-v3.png` (280 × 56 points at 2× inside a 300 × 72 panel)
- Same-input comparison: `Design/qa/source-and-implementation-v3.png`
- Environment: native AppKit `NSPanel` hosting SwiftUI, macOS 26.5.2, 2560 × 1440 display

## QA history

1. The original implementation drifted into a card-heavy, mint-accented dashboard treatment. Rebuilt it as the source's flat graphite ledger with a black header, restrained gray controls, section separators, and edge-to-edge rows.
2. Matched the source hierarchy and copy: “Inbox,” the 60-point Quick capture field, neutral All/Tasks/filter controls, Pinned and Today sections, reference task data, an image attachment, and a link row.
3. Preserved the selected direction's centered notch-hug connector and exposed the requested inline completion, pin, tag, and trash controls only on the selected task row.
4. A second comparison exposed an unbounded filter icon, locale-dependent timestamps, an under-emphasized completion action, and an oversized confirmation. Fixed all four before the final render.
5. Compared the selected direction and final native surfaces in one image. Typography, spacing, graphite colors, imagery, copy, SF Symbols, row geometry, and the mint interaction accent now match the reference closely at the intended panel size.
6. Verified all body text and controls remain inside the 420 × 560 surface without clipping or horizontal overflow. Keyboard focus, accessible labels and hints, Reduce Motion behavior, and increased-contrast hierarchy remain implemented.

## Coexistence evidence

- Dormant with NotchFlow 1.2.2: NotchFlow was the only on-screen notch window; Notch Capture had no visible window or hit surface.
- Explicit session: Notch Capture used a tightly bounded 420 × 560 panel at window layer 29, above NotchFlow’s layer 27.
- Dismissal: Notch Capture ordered out completely; NotchFlow immediately returned to being the only on-screen notch window.

## Result

The native implementation now faithfully carries the selected hugged-ledger direction while retaining functional capture controls, real data states, inline task actions, and notch ownership behavior.

final result: passed
