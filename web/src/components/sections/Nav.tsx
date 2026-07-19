export function Nav({ downloadUrl }: { downloadUrl: string }) {
  return (
    <nav className="siteNav" aria-label="Primary navigation">
      <div className="navInner">
        <a className="wordmark" href="#top" aria-label="Notch Capture home">
          <span className="wordmarkIcon" aria-hidden="true" />
          <span>Notch Capture</span>
        </a>
        <div className="navLinks">
          <a href="https://github.com/lipefxo/notch-capture">GitHub</a>
          <a className="navDownload" href={downloadUrl}>Download</a>
        </div>
      </div>
    </nav>
  );
}
