import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "TextTime — Automated Client Follow-ups for Tradies",
  description: "Automated SMS follow-ups that win more jobs. Built for Australian tradies.",
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
