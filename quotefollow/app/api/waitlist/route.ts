import { NextResponse } from 'next/server';

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://spwkdgmnedaqlkzpambv.supabase.co';
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || '';

const IS_PROD = process.env.VERCEL_ENV === 'production';
const SUPABASE_KEY = SUPABASE_SERVICE_ROLE_KEY || (!IS_PROD ? SUPABASE_ANON_KEY : '');

function safeString(value: unknown, maxLen: number): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.length > maxLen ? trimmed.slice(0, maxLen) : trimmed;
}

function normalizeEmail(value: unknown): string | null {
  const email = safeString(value, 320)?.toLowerCase();
  if (!email) return null;
  if (!email.includes('@') || email.startsWith('@') || email.endsWith('@')) return null;
  return email;
}

export async function POST(request: Request) {
  if (!SUPABASE_KEY) {
    console.error('Supabase key not configured. Set SUPABASE_SERVICE_ROLE_KEY (required in production).');
    return NextResponse.json({ error: 'Server misconfigured' }, { status: 500 });
  }

  if (!SUPABASE_SERVICE_ROLE_KEY) {
    console.warn('SUPABASE_SERVICE_ROLE_KEY missing; using anon key fallback (non-production only).');
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
    const product = safeString((body as any)?.product, 64) || 'quotefollow';
    const referrer = safeString((body as any)?.referrer, 1024);
    const utmSource = safeString((body as any)?.utmSource, 128);
    const utmMedium = safeString((body as any)?.utmMedium, 128);
    const utmCampaign = safeString((body as any)?.utmCampaign, 256);

    if (!email) {
      return NextResponse.json({ error: 'Valid email is required' }, { status: 400 });
    }

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
        console.warn('Supabase product lookup failed:', await productRes.text());
      }
    }

    const leadRes = await fetch(`${SUPABASE_URL}/rest/v1/leads`, {
      method: 'POST',
      headers: {
        ...supabaseHeaders,
        Prefer: 'return=minimal',
        'Resolution-Prefer': 'merge-duplicates',
      },
      body: JSON.stringify({
        email,
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
