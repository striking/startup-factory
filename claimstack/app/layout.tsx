import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "ClaimStack — Progress Claims for Subcontractors",
  description: "Progress claims made simple for subcontractors.",
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
