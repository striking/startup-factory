import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { resolveSupabaseConfig } from "@/lib/supabase";

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

// Supabase configuration is now handled by shared utility in @/lib/supabase

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

  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(emailInput)) {
    return NextResponse.json(
      { ok: false, error: "Please enter a valid email address." },
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
