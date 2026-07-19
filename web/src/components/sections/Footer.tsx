export function Footer({ version }: { version: string }) {
  return (
    <footer>
      <span>Notch Capture {version}</span>
      <span>Made for the notch.</span>
      <a href="https://github.com/lipefxo/notch-capture">GitHub</a>
    </footer>
  );
}
