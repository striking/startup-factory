import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "SafeTalk — Toolbox Talks Made Simple",
  description: "AI-generated toolbox talks. Site-specific, compliant, 30 seconds.",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
