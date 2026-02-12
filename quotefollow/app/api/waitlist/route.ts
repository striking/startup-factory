import { NextResponse } from 'next/server';

const SUPABASE_URL = (process.env.SUPABASE_URL || 'https://spwkdgmnedaqlkzpambv.supabase.co').trim();

// Prefer service role on the server to avoid requiring permissive RLS for public inserts.
// Falls back to anon key if service role is not configured.
const SUPABASE_SERVICE_ROLE_KEY = (process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
const SUPABASE_ANON_KEY = (process.env.SUPABASE_ANON_KEY || '').trim();
const SUPABASE_KEY = SUPABASE_SERVICE_ROLE_KEY || SUPABASE_ANON_KEY;

function safeString(value: unknown, maxLen: number): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.length > maxLen ? trimmed.slice(0, maxLen) : trimmed;
}

function normalizeEmail(value: unknown): string | null {
  const email = safeString(value, 320)?.toLowerCase();
  if (!email) return null;
  // Lightweight validation (full RFC compliance is not needed here)
  if (!email.includes('@') || email.startsWith('@') || email.endsWith('@')) return null;
  return email;
}

export async function POST(request: Request) {
  if (!SUPABASE_KEY) {
    console.error('Supabase key not configured (SUPABASE_SERVICE_ROLE_KEY or SUPABASE_ANON_KEY)');
    return NextResponse.json({ error: 'Server misconfigured' }, { status: 500 });
  }

  const contentType = request.headers.get('content-type') || '';
  if (!contentType.includes('application/json')) {
    return NextResponse.json({ error: 'Expected application/json' }, { status: 415 });
  }

  const supabaseHeaders = {
    apikey: SUPABASE_KEY,
    Authorization: `Bearer ${SUPABASE_KEY}`,
    'Content-Type': 'application/json',
  };

  try {
    const body: unknown = await request.json();

    const email = normalizeEmail((body as any)?.email);
    const name = safeString((body as any)?.name, 128);
    const product = safeString((body as any)?.product, 64);
    const referrer = safeString((body as any)?.referrer, 1024);
    const utmSource = safeString((body as any)?.utmSource, 128);
    const utmMedium = safeString((body as any)?.utmMedium, 128);
    const utmCampaign = safeString((body as any)?.utmCampaign, 256);

    if (!email) {
      return NextResponse.json({ error: 'Valid email is required' }, { status: 400 });
    }

    // Look up product_id from slug (optional — lead inserts work without it)
    let productId: number | null = null;
    if (product) {
      const productRes = await fetch(
        `${SUPABASE_URL}/rest/v1/products?slug=eq.${encodeURIComponent(product)}&select=id&limit=1`,
        { headers: supabaseHeaders }
      );

      if (productRes.ok) {
        const products = (await productRes.json()) as Array<{ id: number }>;
        if (products.length > 0) productId = products[0].id;
      } else {
        // Non-fatal; still capture email.
        console.warn('Supabase product lookup failed:', await productRes.text());
      }
    }

    const leadRes = await fetch(`${SUPABASE_URL}/rest/v1/leads`, {
      method: 'POST',
      headers: {
        ...supabaseHeaders,
        // If a unique constraint exists on email, keep UX smooth.
        Prefer: 'return=minimal,resolution=merge-duplicates',
      },
      body: JSON.stringify({
        email,
        name: name || null,
        product_id: productId,
        source: 'waitlist',
        referrer: referrer || null,
        utm_source: utmSource || null,
        utm_medium: utmMedium || null,
        utm_campaign: utmCampaign || null,
      }),
    });

    if (!leadRes.ok) {
      const errText = await leadRes.text();
      console.error('Supabase insert failed:', errText);

      // Treat “already exists” as success if a unique constraint is enforced.
      if (leadRes.status === 409) {
        return NextResponse.json({ success: true, message: "You're on the list!" });
      }

      return NextResponse.json({ error: 'Failed to save' }, { status: 502 });
    }

    return NextResponse.json(
      { success: true, message: "You're on the list!" },
      { headers: { 'Cache-Control': 'no-store' } }
    );
  } catch (error) {
    console.error('Waitlist error:', error);
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
  }
}
