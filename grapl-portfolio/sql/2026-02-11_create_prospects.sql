-- 2026-02-11_create_prospects.sql
-- Purpose: store prospect records for daily prospecting + multi-channel engagement.
-- Project: grapl-growth (spwkdgmnedaqlkzpambv)

begin;

-- Extensions used for UUID generation.
create extension if not exists pgcrypto;

-- Basic enums for pipeline.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'prospect_status') then
    create type prospect_status as enum (
      'new',            -- imported / discovered
      'queued',         -- queued for outreach
      'contacted',      -- at least one touchpoint logged
      'responded',      -- replied / engaged
      'qualified',
      'disqualified',
      'won',
      'lost'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'prospect_priority') then
    create type prospect_priority as enum ('low','medium','high');
  end if;
end $$;

create table if not exists public.prospects (
  id uuid primary key default gen_random_uuid(),

  -- Identity / de-dupe
  place_id text unique,
  name text not null,
  phone text,
  -- Generated columns to support deterministic de-dupe when no place_id.
  name_lc text generated always as (lower(name)) stored,
  phone_digits text generated always as (regexp_replace(coalesce(phone,''), '\\D', '', 'g')) stored,

  website text,

  -- Location & enrichment
  formatted_address text,
  city_search text,
  category text,
  google_maps_url text,
  rating numeric(3,2),
  review_count integer,

  -- Pipeline / ops
  status prospect_status not null default 'new',
  priority prospect_priority not null default 'medium',
  source text not null default 'quotefollow',
  source_ref text, -- e.g. filename or batch id

  owner text,      -- optional: sales owner name/email
  notes text,

  last_contacted_at timestamptz,
  next_action_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Helpful indexes
create index if not exists prospects_status_idx on public.prospects (status);
create index if not exists prospects_next_action_idx on public.prospects (next_action_at);
create index if not exists prospects_last_contacted_idx on public.prospects (last_contacted_at);
create index if not exists prospects_category_idx on public.prospects (category);

-- De-dupe fallback when no place_id: normalized name+phone.
-- NOTE: this is best-effort; consider moving normalization to generated cols.
-- NOTE: This is a PARTIAL unique index, which PostgREST cannot reference in `on_conflict`.
-- It's still useful to prevent accidental dupes created by non-REST processes.
create unique index if not exists prospects_name_phone_uniq
  on public.prospects (name_lc, phone_digits)
  where place_id is null and phone_digits <> '';

-- updated_at trigger
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists prospects_set_updated_at on public.prospects;
create trigger prospects_set_updated_at
before update on public.prospects
for each row execute function public.set_updated_at();

commit;
