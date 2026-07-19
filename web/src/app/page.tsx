import { Bento } from "@/components/sections/Bento";
import { Download } from "@/components/sections/Download";
import { FeatureRow } from "@/components/sections/FeatureRow";
import { Footer } from "@/components/sections/Footer";
import { Hero } from "@/components/sections/Hero";
import { Nav } from "@/components/sections/Nav";
import { getLatestRelease } from "@/lib/release";

export const dynamic = "force-static";

export default async function Home() {
  const release = await getLatestRelease();
  return (
    <main>
      <Nav downloadUrl={release.url} />
      <Hero downloadUrl={release.url} />
      <FeatureRow
        eyebrow="CAPTURE"
        title="One shortcut away."
        copy={<><p>Press Control–Shift–N from anywhere. Capture text, paste an image, save a link or grab a screenshot—then get right back to what you were doing.</p><p className="textLink">Capture without context switching ›</p></>}
        image="/media/implementation-floating-glass-v2.png"
        imageAlt="Notch Capture composer and ledger"
        imageWidth={840}
        imageHeight={1120}
        tone="gray"
      />
      <FeatureRow
        eyebrow="ORGANIZE"
        title="A ledger, not a junk drawer."
        copy={<><p>Pin what matters. Filter tasks. Add due dates and tags. When the work is done, a soft mint wave closes the loop.</p><p className="textLink">Everything stays findable ›</p></>}
        image="/media/implementation-expanded-v3.png"
        imageAlt="Notch Capture ledger with notes, tasks, screenshots and links"
        imageWidth={840}
        imageHeight={1120}
        reverse
      />
      <FeatureRow
        eyebrow="PRIVATE BY DESIGN"
        title="Local-first. Actually."
        copy={<><p>No accounts. No sync. No analytics. Your ledger and attachments live on your Mac, with a portable export whenever you want one.</p><p className="privacyNote">The only network calls are album artwork, favicons for captured links and the project’s own Sparkle appcast.</p></>}
        image="/media/selected-hugged-ledger.png"
        imageAlt="Notch Capture attached to a MacBook hardware notch"
        imageWidth={1488}
        imageHeight={1052}
        tone="gray"
        className="privacyFeature"
      />
      <Bento />
      <Download downloadUrl={release.url} version={release.version} />
      <Footer version={release.version} />
    </main>
  );
}
