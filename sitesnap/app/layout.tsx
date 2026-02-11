import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "SiteSnap — Construction Photo Documentation",
  description: "Photo documentation with AI-powered progress tracking.",
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
