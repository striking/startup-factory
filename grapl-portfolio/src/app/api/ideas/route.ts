import { NextResponse } from "next/server";
import crypto from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";

export const runtime = "nodejs";

type IdeaSubmission = {
  id: string;
  createdAt: string;
  idea: string;
  email: string;
  name?: string;
  meta: {
    userAgent?: string;
    referer?: string;
  };
};

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function isEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

async function storeSubmission(submission: IdeaSubmission): Promise<void> {
  // NOTE: This is an intentionally simple placeholder store.
  // Production should forward to Sheets/Webhook/DB.
  const defaultPath = path.join(
    process.env.TMPDIR ?? "/tmp",
    "grapl-ideas.jsonl",
  );

  const storePath = process.env.GRAPL_IDEA_STORE_PATH ?? defaultPath;
  await fs.mkdir(path.dirname(storePath), { recursive: true });
  await fs.appendFile(storePath, JSON.stringify(submission) + "\n", "utf8");
}

export async function POST(request: Request) {
  let payload: unknown;

  try {
    payload = await request.json();
  } catch {
    return NextResponse.json(
      { ok: false, error: "Invalid JSON body" },
      { status: 400 },
    );
  }

  const idea = asTrimmedString((payload as { idea?: unknown })?.idea);
  const email = asTrimmedString((payload as { email?: unknown })?.email).toLowerCase();
  const name = asTrimmedString((payload as { name?: unknown })?.name);

  if (!idea || idea.length < 10) {
    return NextResponse.json(
      { ok: false, error: "Please describe your idea (10+ characters)." },
      { status: 400 },
    );
  }

  if (idea.length > 5_000) {
    return NextResponse.json(
      { ok: false, error: "Idea is too long (max 5000 characters)." },
      { status: 400 },
    );
  }

  if (!email || !isEmail(email)) {
    return NextResponse.json(
      { ok: false, error: "Please enter a valid email address." },
      { status: 400 },
    );
  }

  const submission: IdeaSubmission = {
    id: crypto.randomUUID(),
    createdAt: new Date().toISOString(),
    idea,
    email,
    name: name || undefined,
    meta: {
      userAgent: request.headers.get("user-agent") ?? undefined,
      referer: request.headers.get("referer") ?? undefined,
    },
  };

  try {
    await storeSubmission(submission);
  } catch (error) {
    console.error("Failed to store idea submission", error);
    return NextResponse.json(
      { ok: false, error: "Failed to store submission" },
      { status: 500 },
    );
  }

  return NextResponse.json({ ok: true, id: submission.id });
}
