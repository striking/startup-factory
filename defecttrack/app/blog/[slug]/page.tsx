import { getAllSlugs, getPost } from "@/lib/blog";
import type { Metadata } from "next";

interface Props {
  params: Promise<{ slug: string }>;
}

export async function generateStaticParams() {
  return getAllSlugs().map((slug) => ({ slug }));
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const post = await getPost(slug);
  return {
    title: `${post.title} — DefectTrack`,
    description: post.meta_description,
    openGraph: {
      title: post.title,
      description: post.meta_description,
      type: "article",
      publishedTime: post.publication_date,
    },
    twitter: {
      card: "summary_large_image",
      title: post.title,
      description: post.meta_description,
    },
  };
}

export default async function BlogPost({ params }: Props) {
  const { slug } = await params;
  const post = await getPost(slug);
  return (
    <main className="mx-auto max-w-3xl px-4 py-16">
      <article>
        <header className="mb-8">
          <p className="mb-2 text-sm text-gray-500">{post.publication_date}</p>
          <h1 className="text-4xl font-bold leading-tight">{post.title}</h1>
          <p className="mt-4 text-lg text-gray-600">{post.meta_description}</p>
        </header>
        <div
          className="prose prose-lg max-w-none"
          dangerouslySetInnerHTML={{ __html: post.contentHtml }}
        />
      </article>
    </main>
  );
}
