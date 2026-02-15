import { MetadataRoute } from 'next'

export default function robots(): MetadataRoute.Robots {
  const baseUrl = 'https://punchout.grapl.ai'

  return {
    rules: {
      userAgent: '*',
      allow: '/',
    },
    sitemap: "${baseUrl}/sitemap.xml",
  }
}
