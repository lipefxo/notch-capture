import { ArrowClockwiseIcon, ExportIcon, KeyboardIcon, MusicNotesIcon, TagIcon, TimerIcon } from "@phosphor-icons/react/ssr";

const cards = [
  { icon: TagIcon, title: "Tags that find themselves.", copy: "Iridescent tags stay fast to scan and easy to filter.", kind: "tags" },
  { icon: MusicNotesIcon, title: "Now playing, nearby.", copy: "Control the soundtrack without leaving your flow.", kind: "music" },
  { icon: TimerIcon, title: "Focus with a pulse.", copy: "A Pomodoro timer that warms from mint to amber to red.", kind: "timer" },
  { icon: KeyboardIcon, title: "Your shortcut.", copy: "Rebind capture to the keys that already feel natural.", kind: "shortcut" },
  { icon: ArrowClockwiseIcon, title: "Quiet updates.", copy: "Sparkle keeps the app current without getting in the way.", kind: "updates" },
  { icon: ExportIcon, title: "Take it with you.", copy: "Export and import a portable .notchcapture package.", kind: "export" },
];

export function Bento() {
  return (
    <section className="bentoSection">
      <div className="sectionHeading">
        <p className="eyebrow">THE SMALL THINGS</p>
        <h2>Built for your flow.</h2>
        <p>Useful when you need it. Nearly invisible when you don’t.</p>
      </div>
      <div className="bentoGrid">
        {cards.map(({ icon: Icon, title, copy, kind }) => (
          <article className="bentoCard" key={title}>
            <div className="bentoText"><Icon size={26} weight="regular" /><h3>{title}</h3><p>{copy}</p></div>
            <div className={`bentoVisual visual-${kind}`} aria-hidden="true">
              {kind === "tags" ? <div className="tagStack"><span>#work</span><span>#ideas</span><span>#later</span></div> : null}
              {kind === "music" ? <div className="musicPill"><span className="albumMini" /><div><b>On the Move</b><small>Notch Capture Radio</small></div><span>Ⅱ</span></div> : null}
              {kind === "timer" ? <div className="timerPill">24:23</div> : null}
              {kind === "shortcut" ? <div className="shortcutKeys"><kbd>⌃</kbd><kbd>⇧</kbd><kbd>N</kbd></div> : null}
              {kind === "updates" ? <div className="updateLine"><span>0.1.0</span><b>Up to date</b></div> : null}
              {kind === "export" ? <div className="exportSheet"><span>Export as .notchcapture</span><span>Import package</span></div> : null}
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}
