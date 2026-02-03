import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'

const inter = Inter({ subsets: ['latin'] })

export const metadata: Metadata = {
  title: 'InvoiceAI - AI-Powered Invoicing for Tradies',
  description: 'Snap a photo. Get a professional invoice in seconds. Built for Australian tradies.',
  openGraph: {
    title: 'InvoiceAI - AI-Powered Invoicing for Tradies',
    description: 'Snap a photo. Get a professional invoice in seconds.',
    type: 'website',
  }
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className={inter.className}>{children}</body>
    </html>
  )
}
