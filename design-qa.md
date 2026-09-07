**Comparison Target**

- Source visual truth: `/Users/lipe/.codex/generated_images/01a07c0a-574f-7be0-846b-898cca6107fa/exec-05a6ffbc-25af-4dda-a0eb-a61e2fad488e.png`
- Implementation screenshot: `/Users/lipe/conductor/workspaces/notch-capture/ankara/.context/model-usage-audit/09-collapsed-liquid-fill.png`
- Full-view comparison: `/Users/lipe/conductor/workspaces/notch-capture/ankara/.context/model-usage-audit/qa/full-comparison.png` (source left, implementation right)
- Focused provider comparison: `/Users/lipe/conductor/workspaces/notch-capture/ankara/.context/model-usage-audit/qa/provider-comparison.png` (source left, implementation right)
- Viewport/state: extended collapsed media activity on a simulated external display; OpenAI 68% remaining and Cursor 38% remaining; settled animation state.
- Source pixels: 1915 × 821. The notch region was cropped and normalized to 944 × 112 at 1× for comparison.
- Implementation pixels: 944 × 112 at 2× backing density (472 × 56 points). A 72-DPI metadata copy was used only for equal-pixel focused comparison.

**Findings**

- No actionable P0, P1, or P2 differences remain.
- Fonts and typography: the native implementation preserves the existing SF system type, weights, hierarchy, truncation, and time-label positioning. It is sharper than the generated reference, as expected from native rendering.
- Spacing and layout rhythm: shell size, artwork, title block, progress track, transport controls, provider placement, and notch radii remain unchanged from the existing compact layout. Removing the collapsed volume control leaves the intended breathing room.
- Colors and visual tokens: the implementation stays within the existing monochrome notch palette. The dim full-logo silhouette, bright quota fill, gradient depth, and highlighted meniscus preserve contrast without introducing a new semantic color.
- Image quality and asset fidelity: the supplied OpenAI outline SVG and filled Cursor SVG remain crisp template assets. The liquid layer is clipped to those real marks rather than approximating either logo.
- Copy and content: no new compact-state text was introduced. Existing hover help and accessibility values continue to expose the exact remaining percentage.
- Interaction and accessibility: quota changes use a 0.78-second damped settling wave and spring-driven level transition. Reduced Motion pauses the timeline and presents the final liquid level statically. The settled screenshot was visually verified; hover help remains connected through native SwiftUI `.help`, but the debug executable could not be selected independently from the installed app by the UI automation surface, so the tooltip was not captured.

**Comparison History**

- Initial implementation matched the selected composition and showed distinct 68%/38% fill levels. Focused inspection found only a P3 polish opportunity: the resting meniscus was nearly straight at compact scale.
- The resting amplitude was increased from 0.32 to 0.48 points while keeping the animated peak unchanged. The final focused comparison shows a subtle curved surface without reducing logo recognition.

**Implementation Checklist**

- [x] Preserve the outline OpenAI and filled Cursor source assets.
- [x] Encode remaining allowance as bottom-up liquid height.
- [x] Keep a dim complete silhouette for recognition at low quota.
- [x] Add restrained depth, meniscus highlight, and update-only settling motion.
- [x] Preserve exact-percentage hover and accessibility values.
- [x] Respect Reduce Motion.
- [x] Verify the complete Swift test suite.

**Follow-up Polish**

- P3: if future testing shows the meniscus is too subtle on lower-density displays, increase only the resting amplitude or crest opacity; do not enlarge the compact logos.

final result: passed
