import fs from "fs";
import path from "path";
import matter from "gray-matter";
import { remark } from "remark";
import html from "remark-html";

const contentDir = path.join(process.cwd(), "content/blog");

export interface BlogPost {
  slug: string;
  title: string;
  meta_description: string;
  primary_keyword: string;
  secondary_keywords: string[];
  content_type: string;
  publication_date: string;
  contentHtml: string;
}

export function getAllSlugs(): string[] {
  return fs.readdirSync(contentDir)
    .filter((f) => f.endsWith(".md"))
    .map((f) => f.replace(/\.md$/, ""));
}

export async function getPost(slug: string): Promise<BlogPost> {
  const filePath = path.join(contentDir, `${slug}.md`);
  const raw = fs.readFileSync(filePath, "utf8");
  const { data, content } = matter(raw);
  const result = await remark().use(html).process(content);
  return {
    slug: data.slug || slug,
    title: data.title,
    meta_description: data.meta_description || "",
    primary_keyword: data.primary_keyword || "",
    secondary_keywords: data.secondary_keywords || [],
    content_type: data.content_type || "article",
    publication_date: data.publication_date || "",
    contentHtml: result.toString(),
  };
}

export async function getAllPosts(): Promise<BlogPost[]> {
  const slugs = getAllSlugs();
  const posts = await Promise.all(slugs.map(getPost));
  return posts.sort((a, b) => (a.publication_date > b.publication_date ? -1 : 1));
}
