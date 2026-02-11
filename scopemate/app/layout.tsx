import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "ScopeMate — Scope of Works Generator",
  description: "Generate detailed scopes of work from a quick site visit.",
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
