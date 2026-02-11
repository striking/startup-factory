import { NextResponse } from "next/server";

export const runtime = "nodejs";

const APPS_SCRIPT_URL =
  "https://script.google.com/macros/s/AKfycbzIILh_VC9k-NWo3lU_4H5SXPiP_ZhmOCyyqWCdIaE7_TyS8-YY2iRxFnvcdYzf0snM/exec";

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

  try {
    const upstream = await fetch(APPS_SCRIPT_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      redirect: "follow",
    });

    const text = await upstream.text();

    if (!upstream.ok) {
      return NextResponse.json(
        {
          ok: false,
          error: `Upstream error: ${upstream.status}`,
          upstreamBody: text.slice(0, 500),
        },
        { status: 502 },
      );
    }

    try {
      return NextResponse.json(JSON.parse(text));
    } catch {
      // Some Apps Script responses are non-JSON (HTML). Treat 200 as success.
      return NextResponse.json({ ok: true });
    }
  } catch (error) {
    console.error("Waitlist proxy error", error);
    return NextResponse.json(
      { ok: false, error: "Internal Server Error" },
      { status: 500 },
    );
  }
}
