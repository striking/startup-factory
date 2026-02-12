-- 2026-02-12_add_followup_scheduling.sql
-- Purpose: follow-up scheduling + queues for relay outreach.
-- Project: grapl-growth (spwkdgmnedaqlkzpambv)
-- NOTE: Base schema must exist (prospect_status already created) before running.

-- Extend prospect_status enum (backward-compatible).
alter type prospect_status add value if not exists 'replied';
alter type prospect_status add value if not exists 'booked';

begin;

-- Follow-up scheduling fields on touchpoints.
alter table public.prospect_touchpoints
  add column if not exists followup_1_due_at timestamptz,
  add column if not exists followup_2_due_at timestamptz,
  add column if not exists followup_1_sent_at timestamptz,
  add column if not exists followup_2_sent_at timestamptz;

-- Auto-schedule followups for outbound sent touchpoints.
create or replace function public.set_touchpoint_followups()
returns trigger as $$
begin
  if new.occurred_at is null then
    new.occurred_at := now();
  end if;

  if new.direction = 'outbound' and new.outcome = 'sent' then
    if new.followup_1_due_at is null then
      new.followup_1_due_at := new.occurred_at + interval '4 days';
    end if;
    if new.followup_2_due_at is null then
      new.followup_2_due_at := new.occurred_at + interval '11 days';
    end if;
  end if;

  return new;
end;
$$ language plpgsql;

drop trigger if exists prospect_touchpoints_set_followups on public.prospect_touchpoints;
create trigger prospect_touchpoints_set_followups
before insert on public.prospect_touchpoints
for each row execute function public.set_touchpoint_followups();

-- Keep prospect last_contacted_at in sync with touchpoints.
create or replace function public.update_prospect_last_contacted_at()
returns trigger as $$
declare
  occurred_at timestamptz;
begin
  occurred_at := coalesce(new.occurred_at, now());

  update public.prospects
  set last_contacted_at = greatest(coalesce(last_contacted_at, occurred_at), occurred_at)
  where id = new.prospect_id;

  return null;
end;
$$ language plpgsql;

drop trigger if exists prospect_touchpoints_update_last_contacted on public.prospect_touchpoints;
create trigger prospect_touchpoints_update_last_contacted
after insert on public.prospect_touchpoints
for each row execute function public.update_prospect_last_contacted_at();

-- Optionally update prospect status based on touchpoint outcome.
create or replace function public.set_prospect_status_from_touchpoint()
returns trigger as $$
declare
  new_status prospect_status;
begin
  if new.outcome = 'replied' then
    new_status := 'replied';
  elsif new.outcome = 'booked_call' then
    new_status := 'booked';
  else
    return null;
  end if;

  update public.prospects
  set status = new_status
  where id = new.prospect_id
    and status not in ('won', 'lost', 'disqualified', 'booked');

  return null;
end;
$$ language plpgsql;

drop trigger if exists prospect_touchpoints_set_status on public.prospect_touchpoints;
create trigger prospect_touchpoints_set_status
after insert on public.prospect_touchpoints
for each row execute function public.set_prospect_status_from_touchpoint();

-- Indexes for follow-up scheduling.
create index if not exists prospect_touchpoints_followup1_due_idx
  on public.prospect_touchpoints (followup_1_due_at)
  where followup_1_due_at is not null and followup_1_sent_at is null;

create index if not exists prospect_touchpoints_followup2_due_idx
  on public.prospect_touchpoints (followup_2_due_at)
  where followup_2_due_at is not null and followup_2_sent_at is null;

create index if not exists prospect_touchpoints_direction_outcome_idx
  on public.prospect_touchpoints (direction, outcome, occurred_at desc);

-- Follow-up queue view (one row per follow-up).
create or replace view public.followup_queue as
select
  p.id as prospect_id,
  p.name as prospect_name,
  p.status as prospect_status,
  coalesce(p.last_contacted_at, tp.occurred_at) as last_touch_at,
  tp.id as touchpoint_id,
  tp.occurred_at as touchpoint_occurred_at,
  f.followup_number,
  f.followup_due_at,
  f.followup_sent_at
from public.prospect_touchpoints tp
join public.prospects p on p.id = tp.prospect_id
cross join lateral (
  values
    (1, tp.followup_1_due_at, tp.followup_1_sent_at),
    (2, tp.followup_2_due_at, tp.followup_2_sent_at)
) as f(followup_number, followup_due_at, followup_sent_at)
where tp.direction = 'outbound'
  and tp.outcome = 'sent'
  and f.followup_due_at is not null
  and f.followup_sent_at is null
  and f.followup_due_at <= now()
  and p.status not in ('responded', 'replied', 'booked', 'won', 'lost', 'disqualified');

-- Queue of prospects eligible for outreach today.
create or replace function public.today_send_queue(limit integer default 30)
returns table (
  prospect_id uuid,
  name text,
  status prospect_status,
  priority prospect_priority,
  last_contacted_at timestamptz,
  next_action_at timestamptz,
  source text,
  owner text
)
language sql
stable
as $$
  select
    p.id,
    p.name,
    p.status,
    p.priority,
    p.last_contacted_at,
    p.next_action_at,
    p.source,
    p.owner
  from public.prospects p
  where (p.last_contacted_at is null or p.last_contacted_at < now() - interval '30 days')
    and p.status not in ('won', 'lost', 'disqualified', 'booked', 'responded', 'replied')
  order by p.last_contacted_at nulls first, p.created_at asc
  limit $1;
$$;

commit;
