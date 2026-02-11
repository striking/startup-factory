import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "SiteDiary — Digital Site Diaries for Construction",
  description: "Voice-to-text daily site diaries. Compliant, fast, no paperwork.",
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
