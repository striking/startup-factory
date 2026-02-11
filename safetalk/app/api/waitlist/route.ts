import { NextResponse } from 'next/server';

const APPS_SCRIPT_URL = 'https://script.google.com/macros/s/AKfycbzIILh_VC9k-NWo3lU_4H5SXPiP_ZhmOCyyqWCdIaE7_TyS8-YY2iRxFnvcdYzf0snM/exec';

export async function POST(request: Request) {
  try {
    const body = await request.json();
    
    // Forward the request to Google Apps Script
    // We must follow redirects because Apps Script redirects to a content serving URL
    const response = await fetch(APPS_SCRIPT_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
      redirect: 'follow',
    });

    if (!response.ok) {
      return NextResponse.json(
        { error: `Upstream error: ${response.status}` },
        { status: 502 }
      );
    }

    // Apps Script might return HTML or JSON depending on how it's written
    // We'll try to parse as JSON, but if it fails, we assume success if status was 200
    const text = await response.text();
    try {
      const data = JSON.parse(text);
      return NextResponse.json(data);
    } catch (e) {
      // If valid 200 OK but not JSON, treat as success (common with simple Apps Scripts)
      console.log('Apps Script returned non-JSON:', text.substring(0, 100));
      return NextResponse.json({ ok: true, message: "Submission accepted" });
    }
  } catch (error) {
    console.error('Waitlist proxy error:', error);
    return NextResponse.json(
      { error: 'Internal Server Error' },
      { status: 500 }
    );
  }
}
