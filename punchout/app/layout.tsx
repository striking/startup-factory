import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "PunchOut — Digital Punch Lists for Construction",
  description: "Digital punch lists that close out faster.",
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
