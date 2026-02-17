import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';
import matter from 'gray-matter';

const salaryGuidesDirectory = join(process.cwd(), 'content/salary-guides');

export interface SalaryGuide {
  slug: string;
  title: string;
  city: string;
  state: string;
  description: string;
  lastUpdated: string;
  averageSalary: {
    apprentice: string;
    journeyman: string;
    master: string;
    contractor: string;
  };
  costOfLivingIndex: number;
  marketConditions: {
    demand: 'Low' | 'Moderate' | 'High' | 'Very High';
    growth: string;
    keyIndustries: string[];
  };
  majorEmployers: string[];
  trainingPrograms: string[];
  unionPresence: {
    active: boolean;
    mainUnion: string;
    coverage: string;
  };
  licensing: {
    required: boolean;
    authority: string;
    requirements: string[];
  };
  content: string;
}

export function getSalaryGuide(slug: string): SalaryGuide {
  const fullPath = join(salaryGuidesDirectory, `${slug}.md`);
  const fileContents = readFileSync(fullPath, 'utf8');
  const { data, content } = matter(fileContents);

  return {
    slug,
    ...data,
    content,
  } as SalaryGuide;
}

export function getAllSalaryGuides(): SalaryGuide[] {
  const slugs = getSalaryGuideSlugs();
  const guides = slugs
    .map((slug) => getSalaryGuide(slug))
    .sort((a, b) => a.city.localeCompare(b.city));

  return guides;
}

export function getSalaryGuideSlugs(): string[] {
  return readdirSync(salaryGuidesDirectory)
    .filter((file) => file.endsWith('.md'))
    .map((file) => file.replace(/\.md$/, ''));
}

export function getGuidesByState(): Record<string, SalaryGuide[]> {
  const guides = getAllSalaryGuides();
  const byState: Record<string, SalaryGuide[]> = {};

  guides.forEach((guide) => {
    if (!byState[guide.state]) {
      byState[guide.state] = [];
    }
    byState[guide.state].push(guide);
  });

  return byState;
}