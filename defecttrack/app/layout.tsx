import type { Metadata } from "next";
import { Analytics } from '@vercel/analytics/react';
import { SpeedInsights } from '@vercel/speed-insights/next';
import "./globals.css";

export const metadata: Metadata = {
  title: "DefectTrack — Construction Defect Management",
  description: "Track, assign, and close out defects. Photo evidence built in.",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        {children}
        <Analytics />
        <SpeedInsights />
      </body>
    </html>
  );
}
