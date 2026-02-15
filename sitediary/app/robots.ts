import { MetadataRoute } from 'next'

export default function robots(): MetadataRoute.Robots {
  const baseUrl = 'https://sitediary.grapl.ai'

  return {
    rules: {
      userAgent: '*',
      allow: '/',
    },
    sitemap: "${baseUrl}/sitemap.xml",
  }
}
