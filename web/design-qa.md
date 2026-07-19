# Notch Capture landing page — design QA

## Comparison target

- Source visual truth: `/Users/lipe/.codex/generated_images/019f7c0b-5405-76c3-b59f-e729147033b6/exec-eb5957b7-9b0d-4e0c-a915-aa0be707f9c2.png` (selected ideation option 1).
- Implementation URL: `http://localhost:4173/`.
- Desktop screenshot: `.qa/implementation-desktop.png`.
- Tablet screenshot: `.qa/implementation-tablet.png`.
- Mobile screenshot: `.qa/implementation-mobile.png`.
- Full-view comparison evidence: `.qa/full-comparison.png`.
- Focused hero comparison evidence: `.qa/hero-comparison.png`.
- Viewports: 1440 × 1024, 768 × 1024 and 390 × 844; full-page captures at 1× device scale.
- State: light theme; reduced-motion captures use the populated static ledger state. A separate no-preference run exercised the animated scene loop.

## Findings

- No actionable P0, P1 or P2 issues remain.
- [P3] The production page is longer than the generated concept board.
  Location: full page.
  Evidence: the concept compresses supporting copy and cards into a presentation board; the implementation includes all three planned feature chapters, six supporting capabilities, the download requirements and the required “Open Anyway” note at readable product sizes.
  Impact: scrolling is longer, but the selected hierarchy and section rhythm remain intact.
  Follow-up: if a shorter campaign page is preferred later, remove one supporting bento row rather than shrinking type or media.

## Required fidelity surfaces

- Fonts and typography: uses the requested Apple system stack, large semibold display type, negative optical tracking and compact leading. Body copy remains 16–19px in the implementation and does not clip at any tested viewport.
- Spacing and layout rhythm: centered hero, full MacBook product theater, alternating two-column chapters and compact light bento grid match option 1. Desktop content stays within the 1180px wide grid; all tested viewports report document width equal to viewport width.
- Colors and visual tokens: page white, #f5f5f7 alternation, #1d1d1f text, #6e6e73 secondary text and #3AC780 accent match the brief. Dark product surfaces use the Swift token-derived ink and graphite ramp.
- Image quality and asset fidelity: the three lower-page visuals are copied from the repository’s real Design references. The hero is the planned live HTML/CSS/React recreation using the app’s real geometry, color and Motion profiles; mobile intentionally falls back to the checked-in expanded inbox poster.
- Copy and content: hero, feature headings, privacy disclosure, requirements, release version fallback and “Open Anyway” instructions are present. The latest-release URL is fetched at build time with a graceful 0.1.0 fallback.

## Focused comparison

The hero needed a focused comparison because its type scale, MacBook crop, hardware-notch alignment and app-surface proportions are too small to judge in the full-page composite. `.qa/hero-comparison.png` confirms the same centered hierarchy, light field, dark MacBook centerpiece and notch-attached ledger. The implementation keeps the CTA beside the keyboard hint, while the concept places only the keyboard hint in that row; this is an intentional conversion improvement already specified by the plan.

## Interaction and browser checks

- The hero advanced from `scene-idle` to `scene-typing` in the no-preference run.
- Reduced motion settled into a static populated ledger without hydration mismatch.
- The primary CTA accepted keyboard focus and resolved to `https://github.com/lipefxo/notch-capture/releases/latest`.
- Three release/download links are present.
- Desktop, tablet and mobile captures had no horizontal overflow.
- Browser console warnings, errors and page errors: none in the final run.

## Comparison history

### Iteration 1

- [P1] Reduced-motion hydration mismatch: the server rendered the idle scene while the first client render selected the ledger. Fixed by deferring the media-query-derived scene change until after hydration, using a requestAnimationFrame callback.
- [P2] Lower screenshots appeared blank in an initial full-page capture because native lazy loading had not been triggered. Confirmed as capture-only, then fixed the QA harness to scroll through the page before recording evidence.
- [P2] The first bento pass used fully dark cards and excessive vertical density. Fixed by switching to option 1’s light outlined cards with dark product interiors, a 3-column desktop grid and tighter section heights.
- [P2] The mobile hero poster made the product too small. Fixed by using the repository’s expanded inbox reference as the under-480px static poster.

### Iteration 2

- Re-captured all three viewports after the fixes.
- Confirmed no overflow, no browser errors, a working animated scene transition and a keyboard-focusable download path.
- Post-fix visual evidence: `.qa/implementation-desktop.png`, `.qa/implementation-tablet.png`, `.qa/implementation-mobile.png`, `.qa/full-comparison.png` and `.qa/hero-comparison.png`.
- No actionable P0/P1/P2 findings remain.

## Implementation checklist

- [x] Selected option 1 reproduced as a responsive Next.js page.
- [x] Live notch hero and reduced-motion fallback implemented.
- [x] Real product media placed in every planned feature chapter.
- [x] Primary navigation and download links work.
- [x] TypeScript, ESLint and static export build pass.
- [x] Production dependency audit reports zero vulnerabilities.
- [x] Desktop, tablet and mobile browser evidence captured.

## Follow-up polish

- Optional P3: replace stills with the matching MP4/WebM captures when Screen Recording and Accessibility permissions are available; `shot-list.md` documents the swap.

final result: passed
