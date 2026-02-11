import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "QuoteFollow — Never Lose a Quote Again",
  description: "Automated quote follow-up sequences that close more jobs.",
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
