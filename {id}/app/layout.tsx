import type { Metadata } from "next";
import { config } from "@/config";
import "./globals.css";

export const metadata: Metadata = {
  title: `${config.name} — ${config.tagline}`,
  description: config.description,
  openGraph: {
    title: `${config.name} — ${config.tagline}`,
    description: config.description,
    url: `https://${config.domain}`,
    siteName: config.name,
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: `${config.name} — ${config.tagline}`,
    description: config.description,
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <head>
        {config.analyticsUrl && config.analyticsId && (
          <script
            defer
            src={config.analyticsUrl}
            data-website-id={config.analyticsId}
          />
        )}
      </head>
      <body className="bg-slate-950 text-white antialiased">{children}</body>
    </html>
  );
}
