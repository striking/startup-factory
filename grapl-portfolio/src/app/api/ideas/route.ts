import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";

export const runtime = "nodejs";

const MAX_IDEA_LENGTH = 5000;
const MAX_EMAIL_LENGTH = 320;
const MAX_NAME_LENGTH = 200;

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function firstForwardedIp(value: string | null): string | null {
  if (!value) return null;
  const first = value.split(",")[0]?.trim();
  return first ? first : null;
}

function resolveSupabaseConfig(): { url: string; key: string } | { error: string } {
  const url = process.env.SUPABASE_URL?.trim();
  if (!url) {
    return { error: "Missing SUPABASE_URL environment variable." };
  }

  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  if (serviceRoleKey) {
    return { url, key: serviceRoleKey };
  }

  const anonKey = process.env.SUPABASE_ANON_KEY?.trim();
  if (anonKey) {
    return { url, key: anonKey };
  }

  return {
    error:
      "Missing SUPABASE_SERVICE_ROLE_KEY (or SUPABASE_ANON_KEY fallback) environment variable.",
  };
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
  const emailInput = asTrimmedString((payload as { email?: unknown })?.email);
  const nameInput = asTrimmedString((payload as { name?: unknown })?.name);

  if (!idea) {
    return NextResponse.json(
      { ok: false, error: "Idea is required." },
      { status: 400 },
    );
  }

  if (idea.length > MAX_IDEA_LENGTH) {
    return NextResponse.json(
      { ok: false, error: "Idea is too long (max 5000 characters)." },
      { status: 400 },
    );
  }

  if (!emailInput) {
    return NextResponse.json(
      { ok: false, error: "Email is required." },
      { status: 400 },
    );
  }

  if (emailInput.length > MAX_EMAIL_LENGTH) {
    return NextResponse.json(
      { ok: false, error: "Email is too long (max 320 characters)." },
      { status: 400 },
    );
  }

  if (nameInput.length > MAX_NAME_LENGTH) {
    return NextResponse.json(
      { ok: false, error: "Name is too long (max 200 characters)." },
      { status: 400 },
    );
  }

  const email = emailInput.toLowerCase();
  const name = nameInput ? nameInput : null;

  const userAgent = asTrimmedString(request.headers.get("user-agent")) || null;
  const referer = asTrimmedString(request.headers.get("referer")) || null;
  const ip = firstForwardedIp(request.headers.get("x-forwarded-for"));

  const config = resolveSupabaseConfig();
  if ("error" in config) {
    return NextResponse.json(
      { ok: false, error: config.error },
      { status: 500 },
    );
  }

  const supabase = createClient(config.url, config.key, {
    auth: { persistSession: false },
  });

  const { data, error } = await supabase
    .from("idea_submissions")
    .insert({
      idea,
      email,
      name,
      user_agent: userAgent,
      referer,
      ip,
    })
    .select("id")
    .single();

  if (error || !data) {
    return NextResponse.json(
      { ok: false, error: "Database error while saving submission." },
      { status: 500 },
    );
  }

  return NextResponse.json({ ok: true, id: data.id });
}
