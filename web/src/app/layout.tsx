import type { Metadata } from "next";
import "@/styles/tokens.css";
import "./globals.css";

export const metadata: Metadata = {
  title: "Notch Capture — The capture inbox in your notch",
  description:
    "A private, local-first capture inbox for notes, tasks, links and screenshots on your Mac.",
  openGraph: {
    title: "Notch Capture",
    description: "The capture inbox in your notch.",
    type: "website",
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
