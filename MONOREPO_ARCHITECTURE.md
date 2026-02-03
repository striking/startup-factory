# Startup Factory - Monorepo Architecture

Single Vercel project hosting all experiment landing pages.

## Structure

```
startup-factory-sites/
├── app/
│   ├── layout.tsx              # Shared layout
│   ├── page.tsx                # Homepage (list of experiments)
│   └── [slug]/
│       └── page.tsx            # Dynamic experiment pages
├── experiments/
│   ├── quotemate/
│   │   ├── config.json         # Experiment metadata
│   │   └── page.tsx            # Landing page component
│   ├── jobtrack/
│   │   ├── config.json
│   │   └── page.tsx
│   └── ...
├── lib/
│   ├── experiments.ts          # Load experiment configs
│   ├── analytics.ts            # Vercel Analytics wrapper
│   └── waitlist.ts             # Email capture (Sheets/Resend)
├── components/
│   ├── WaitlistForm.tsx        # Reusable email capture
│   ├── PricingSection.tsx      # Configurable pricing
│   └── ...
└── data/
    └── experiments.json        # Experiment registry
```

## Experiment Config

Each experiment has a `config.json`:

```json
{
  "slug": "quotemate",
  "name": "QuoteMate",
  "tagline": "Voice to Quote in Minutes",
  "status": "active",
  "created": "2026-02-04",
  "pricing": {
    "model": "usage",
    "display": "$2 per quote sent",
    "earlyBird": "First 100 users: 50% off"
  },
  "analytics": {
    "vercelAnalytics": true,
    "conversionGoal": "waitlist_signup"
  },
  "traffic": {
    "budget": 50,
    "sources": ["facebook", "reddit"]
  }
}
```

## URLs

With parent domain `tryapp.au`:
- `tryapp.au/quotemate`
- `tryapp.au/jobtrack`
- `tryapp.au/invoicemate`

## Benefits

1. **One Vercel project** - No clutter
2. **Shared components** - Consistent quality
3. **Centralized analytics** - Easy comparison
4. **Single deploy** - Add experiments by adding folders
5. **Easy cleanup** - Delete folder = remove experiment

## Email Capture

All experiments share the same waitlist infrastructure:
- Google Sheets (one sheet per experiment tab)
- Or Resend audience (tagged by experiment)

## Weekly Review Dashboard

Homepage (`tryapp.au/`) shows:
- All active experiments
- Signups per experiment
- Traffic sources
- Conversion rates
