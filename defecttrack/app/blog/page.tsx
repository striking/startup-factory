import { getAllPosts } from "@/lib/blog";
import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Blog — DefectTrack",
  description:
    "Expert guides on construction defect tracking, punch list management, and quality assurance for builders and contractors.",
};

export default async function BlogIndex() {
  const posts = await getAllPosts();
  return (
    <main className="mx-auto max-w-3xl px-4 py-16">
      <h1 className="mb-8 text-4xl font-bold">Blog</h1>
      <p className="mb-12 text-lg text-gray-600">
        Expert guides on construction defect tracking, quality management, and
        punch list software for builders and contractors.
      </p>
      <ul className="space-y-8">
        {posts.map((post) => (
          <li key={post.slug}>
            <Link
              href={`/blog/${post.slug}`}
              className="group block rounded-lg border p-6 transition hover:border-blue-500"
            >
              <h2 className="text-2xl font-semibold group-hover:text-blue-600">
                {post.title}
              </h2>
              <p className="mt-2 text-gray-600">{post.meta_description}</p>
              <span className="mt-3 inline-block text-sm text-blue-600">
                Read more →
              </span>
            </Link>
          </li>
        ))}
      </ul>
    </main>
  );
}
