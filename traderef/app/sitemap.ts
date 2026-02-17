import { MetadataRoute } from 'next'
import { getAllSalaryGuides } from '@/lib/salary-guides'

export const dynamic = 'force-static'

export default function sitemap(): MetadataRoute.Sitemap {
  const baseUrl = 'https://traderef.grapl.ai'
  const guides = getAllSalaryGuides()

  const staticPages = [
    {
      url: baseUrl,
      lastModified: new Date(),
      changeFrequency: 'weekly' as const,
      priority: 1,
    },
    {
      url: `${baseUrl}/electrician-salary`,
      lastModified: new Date(),
      changeFrequency: 'weekly' as const,
      priority: 0.8,
    },
  ]

  const guidePages = guides.map((guide) => ({
    url: `${baseUrl}/electrician-salary/${guide.slug}`,
    lastModified: new Date(guide.lastUpdated),
    changeFrequency: 'monthly' as const,
    priority: 0.7,
  }))

  return [...staticPages, ...guidePages]
}
