# Relay Outreach Dashboard

## Overview
Generates a Telegram-friendly daily dashboard from Supabase (prospects, touchpoints, follow-up queue).

## Behavior Notes
- `followup_queue` only returns followups due now (`followup_due_at <= now()`) where `followup_sent_at` is null.
- `today_send_queue(limit)` defaults to `30` and excludes replied/responded/booked/won/lost/disqualified prospects.
- `prospects.last_contacted_at` auto-updates on every touchpoint insert (max of existing and touchpoint time).

## SQL Setup (Run Manually in Supabase)
Run these SQL files in order using the Supabase SQL editor:

1. `sql/2026-02-11_create_prospects.sql`
2. `sql/2026-02-11_create_prospect_touchpoints.sql`
3. `sql/2026-02-12_add_followup_scheduling.sql`

Do not run these in production automatically. Apply manually when ready.

## Environment Variables
Required:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY` (preferred)

Fallback:

- `SUPABASE_ANON_KEY` (only works if RLS allows the required reads)

## Run The Dashboard Script
From the project directory:

```bash
cd projects/startup-factory/grapl-portfolio
SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
  python3 scripts/relay-outreach-dashboard.py
```

The script prints a Telegram Markdown dashboard to stdout.

## Cron Recommendation (Do Not Install Here)
Run daily at **08:05 AEST**.

Example crontab entry:

```bash
# 08:05 AEST daily
5 8 * * * TZ=Australia/Brisbane SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
  /usr/bin/python3 /path/to/projects/startup-factory/grapl-portfolio/scripts/relay-outreach-dashboard.py
```
