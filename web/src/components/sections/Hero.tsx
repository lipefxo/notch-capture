import { MacBook } from "@/components/hero/MacBook";

export function Hero({ downloadUrl }: { downloadUrl: string }) {
  return (
    <section className="hero" id="top">
      <div className="heroCopy">
        <p className="eyebrow">Private. Instant. In your notch.</p>
        <h1>The capture inbox<br />in your notch.</h1>
        <p className="heroLead">
          Press ⌃⇧N, type the thought, get back to work. Notes, tasks, links and screenshots — saved on your Mac, and only your Mac.
        </p>
        <div className="heroActions">
          <a className="primaryButton" href={downloadUrl}>Download for macOS</a>
          <span className="shortcutHint" aria-label="Control Shift N">
            <kbd>⌃</kbd><kbd>⇧</kbd><kbd>N</kbd>
          </span>
        </div>
      </div>
      <MacBook />
    </section>
  );
}
