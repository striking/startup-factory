-- 2026-02-11_create_idea_submissions.sql
-- Purpose: persist "Got an idea?" form submissions.

begin;

create extension if not exists pgcrypto;

-- Status values for downstream processing.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'idea_submission_status') then
    create type idea_submission_status as enum (
      'new',          -- received, not processed
      'acked',        -- user emailed + backlog created
      'in_progress',
      'done',
      'spam',
      'error'
    );
  end if;
end $$;

create table if not exists public.idea_submissions (
  id uuid primary key default gen_random_uuid(),

  created_at timestamptz not null default now(),

  -- User input
  idea text not null,
  email text not null check (email ~ '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'),
  name text,

  -- App metadata
  user_agent text,
  referer text,
  ip inet,

  status idea_submission_status not null default 'new',
  acked_at timestamptz,

  -- Optional: set when a backlog artifact is created.
  backlog_ref text,

  meta jsonb not null default '{}'::jsonb
);

create index if not exists idea_submissions_status_idx on public.idea_submissions (status, created_at desc);
create index if not exists idea_submissions_email_idx on public.idea_submissions (email);

commit;
