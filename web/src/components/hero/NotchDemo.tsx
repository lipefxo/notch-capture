"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { CheckIcon, LinkIcon, NoteIcon, PauseIcon, SkipBackIcon, SkipForwardIcon } from "@phosphor-icons/react";
import { notchMotion } from "@/styles/motion";

type Scene = "idle" | "composer" | "typing" | "ledger" | "complete" | "shelf";
const scenes: { scene: Scene; duration: number }[] = [
  { scene: "idle", duration: 900 },
  { scene: "composer", duration: 950 },
  { scene: "typing", duration: 1600 },
  { scene: "ledger", duration: 1300 },
  { scene: "complete", duration: 1450 },
  { scene: "shelf", duration: 1700 },
];

export function NotchDemo() {
  const reduced = useReducedMotion();
  const rootRef = useRef<HTMLDivElement>(null);
  const [sceneIndex, setSceneIndex] = useState(0);
  const [reduceScene, setReduceScene] = useState(false);
  const [visible, setVisible] = useState(true);
  const scene = reduceScene ? "ledger" : scenes[sceneIndex].scene;

  useEffect(() => {
    const frame = window.requestAnimationFrame(() => setReduceScene(Boolean(reduced)));
    return () => window.cancelAnimationFrame(frame);
  }, [reduced]);

  useEffect(() => {
    const node = rootRef.current;
    if (!node) return;
    const observer = new IntersectionObserver(([entry]) => setVisible(entry.isIntersecting), { threshold: 0.15 });
    observer.observe(node);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (reduceScene || !visible) return;
    const timer = window.setTimeout(
      () => setSceneIndex((current) => (current + 1) % scenes.length),
      scenes[sceneIndex].duration,
    );
    return () => window.clearTimeout(timer);
  }, [reduceScene, sceneIndex, visible]);

  const isOpen = scene !== "idle";
  const showsLedger = scene === "ledger" || scene === "complete";

  return (
    <div ref={rootRef} className="notchDemo">
      <motion.div
        className={`notchSurface scene-${scene}`}
        animate={{ height: isOpen ? (scene === "shelf" ? 122 : showsLedger ? 316 : 108) : 44, width: isOpen ? 420 : 162 }}
        transition={reduceScene ? notchMotion.reducedMotion : isOpen ? notchMotion.surfaceExpansion : notchMotion.surfaceContraction}
      >
        <AnimatePresence mode="wait">
          {scene === "idle" ? (
            <motion.div key="idle" className="idlePill" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
              <span className="idleDot" />
              <span>Ready to capture</span>
              <kbd>⌃⇧N</kbd>
            </motion.div>
          ) : scene === "shelf" ? (
            <motion.div key="shelf" className="shelf" initial={{ opacity: 0, y: -4 }} animate={{ opacity: 1, y: 0 }}>
              <span className="albumArt" aria-hidden="true" />
              <div><strong>On the Move</strong><small>Notch Capture Radio</small></div>
              <div className="shelfControls" aria-hidden="true">
                <SkipBackIcon size={16} weight="bold" />
                <span className="shelfControl"><PauseIcon size={13} weight="bold" /></span>
                <SkipForwardIcon size={16} weight="bold" />
              </div>
            </motion.div>
          ) : showsLedger ? (
            <motion.div key="ledger" className="miniLedger" initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} transition={notchMotion.surfaceContent}>
              <header><strong>Inbox</strong><span>⌕ &nbsp; ⚙</span></header>
              <div className="miniComposer"><span>Quick capture</span><span>↵</span></div>
              <div className="miniTabs"><span>All</span><span>Tasks</span><span>⌁</span></div>
              <small className="groupLabel">TODAY</small>
              <div className={`ledgerLine taskLine ${scene === "complete" ? "isComplete" : ""}`}>
                <motion.span className="check" animate={scene === "complete" ? { scale: [1, 1.3, 1], borderColor: "#3ac780" } : { scale: 1 }} transition={notchMotion.completionCheckPop}>
                  {scene === "complete" ? <CheckIcon weight="bold" /> : null}
                </motion.span>
                <NoteIcon /><div><strong>Book studio time</strong><small>Today</small></div>
                {scene === "complete" ? <motion.span className="completionWash" initial={{ scaleX: 0 }} animate={{ scaleX: 1 }} transition={{ ...notchMotion.completionReveal, delay: 0.04 }} /> : null}
              </div>
              <div className="ledgerLine"><span className="thumb" /><div><strong>IMG_2147.jpg</strong><small>1.2 MB · 9:36 AM</small></div></div>
              <div className="ledgerLine"><LinkIcon /><div><strong>cal.com/studio</strong><small>9:28 AM</small></div></div>
            </motion.div>
          ) : (
            <motion.div key="composer" className="captureComposer" initial={{ opacity: 0, y: -5 }} animate={{ opacity: 1, y: 0 }} transition={notchMotion.surfaceContent}>
              <span className="scanCorners" aria-hidden="true" />
              <span className="typedText">
                {scene === "typing" ? "Review launch notes #work" : "Capture a thought"}
              </span>
              <kbd>↵</kbd>
            </motion.div>
          )}
        </AnimatePresence>
      </motion.div>
    </div>
  );
}
