import type { Transition } from "motion/react";

// Ported from Sources/NotchCapture/UI/NotchTheme.swift (NotchMotion).
export const notchMotion = {
  surfaceExpansion: { type: "spring", duration: 0.56, bounce: 0.16 } as Transition,
  surfaceContraction: { type: "spring", duration: 0.48, bounce: 0.12 } as Transition,
  surfaceContent: { type: "spring", duration: 0.38, bounce: 0.07 } as Transition,
  completionCheckPop: { type: "spring", duration: 0.4, bounce: 0.3 } as Transition,
  completionReveal: { duration: 0.4, ease: [0.23, 1, 0.32, 1] } as Transition,
  reducedMotion: { duration: 0.12, ease: "easeOut" } as Transition,
} as const;
