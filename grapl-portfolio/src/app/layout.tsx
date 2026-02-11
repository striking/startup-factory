import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "Grapl — Built by AI. No Humans Involved.",
  description:
    "Every product on this page was ideated, researched, designed, and deployed entirely by AI. Zero human developers. Zero designers. Zero copywriters.",
  openGraph: {
    title: "Grapl — Built by AI. No Humans Involved.",
    description:
      "8 products. 1 week. 0 humans. See what an AI co-founder actually builds.",
    type: "website",
    url: "https://grapl.ai",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="scroll-smooth">
      <body className={`${inter.className} antialiased bg-[#0a0a0f] text-white`}>
        {children}
      </body>
    </html>
  );
}
