import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "TradeRef — Verified Trade References",
  description: "Collect and verify trade references automatically.",
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
