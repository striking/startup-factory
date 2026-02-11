-- 2026-02-11_create_prospect_touchpoints.sql
-- Purpose: log outreach/engagement touchpoints against prospects.

begin;

create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'touchpoint_channel') then
    create type touchpoint_channel as enum (
      'email',
      'sms',
      'phone_call',
      'voicemail',
      'linkedin',
      'instagram',
      'facebook',
      'google_review',
      'in_person',
      'other'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'touchpoint_direction') then
    create type touchpoint_direction as enum ('outbound','inbound');
  end if;

  if not exists (select 1 from pg_type where typname = 'touchpoint_outcome') then
    create type touchpoint_outcome as enum (
      'sent',
      'delivered',
      'opened',
      'clicked',
      'replied',
      'left_message',
      'no_answer',
      'bounced',
      'blocked',
      'booked_call',
      'not_interested',
      'other'
    );
  end if;
end $$;

create table if not exists public.prospect_touchpoints (
  id uuid primary key default gen_random_uuid(),
  prospect_id uuid not null references public.prospects(id) on delete cascade,

  occurred_at timestamptz not null default now(),
  channel touchpoint_channel not null,
  direction touchpoint_direction not null default 'outbound',
  outcome touchpoint_outcome,

  subject text,
  body text,

  -- optional references to external systems (gmail message id, twilio sid, etc.)
  external_ref text,

  meta jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now()
);

create index if not exists prospect_touchpoints_prospect_idx on public.prospect_touchpoints (prospect_id, occurred_at desc);
create index if not exists prospect_touchpoints_channel_idx on public.prospect_touchpoints (channel);
create index if not exists prospect_touchpoints_external_ref_idx on public.prospect_touchpoints (external_ref);

commit;
