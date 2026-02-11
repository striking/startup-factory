import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "SnapPunch — Photo Punch Lists for Builders",
  description: "Take a photo, AI creates the punch list. Built for builders.",
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
