export function Download({ downloadUrl, version }: { downloadUrl: string; version: string }) {
  return (
    <section className="downloadSection" id="download">
      <p className="eyebrow">READY WHEN YOU ARE</p>
      <h2>Download for macOS.</h2>
      <p>Free, private and made for the notch.</p>
      <a className="primaryButton large" href={downloadUrl}>Download {version} · .zip</a>
      <p className="requirements">Free · Apple Silicon · macOS 14+</p>
      <div className="openAnyway">
        <strong>Opening it for the first time?</strong>
        <p>Notch Capture isn’t notarized yet. In System Settings → Privacy &amp; Security, choose “Open Anyway.” Sparkle updates won’t ask again.</p>
      </div>
    </section>
  );
}
