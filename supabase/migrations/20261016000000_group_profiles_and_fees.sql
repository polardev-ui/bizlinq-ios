-- BizLinq redesign: host group profiles + structured listing fields.
-- REVIEW ONLY. Do not apply to production without separate authorization.
--
-- What this does:
--   1. Adds public.groups: one row per host-owned group profile.
--   2. Adds meetings.group_id (nullable FK) so dated meetings can link to a
--      group without merging or touching legacy rows. research/curated rows
--      keep group_id NULL and stay exactly as they are.
--   3. Adds structured meetings columns the redesigned post form writes:
--      fee_cents, fee_currency, audience. All nullable/additive; the app
--      decodes them optionally so old rows keep working.
--   4. Adds meeting_events: minimal privacy-respecting analytics intake
--      (listing views, website taps). RSVPs remain the source of truth and
--      are already queryable from rsvps; aggregates below are per-host only.
--
-- Rollback: drop tables/columns in reverse order (script at the bottom).

-- 1. Groups ---------------------------------------------------------------
create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  tagline text not null default '',
  description text not null default '',
  audience text,
  website text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists groups_owner_idx on public.groups (owner_id);

alter table public.groups enable row level security;

-- Owners manage their own groups. Anyone (incl. anon) can read them:
-- group profiles are intentionally public marketing surfaces.
drop policy if exists "owner manage groups" on public.groups;
create policy "owner manage groups" on public.groups
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists "public read groups" on public.groups;
create policy "public read groups" on public.groups
  for select using (true);

-- 2. Meeting -> group link (nullable, never backfilled by guess) ----------
alter table public.meetings
  add column if not exists group_id uuid references public.groups (id) on delete set null,
  add column if not exists fee_cents integer,
  add column if not exists fee_currency text,
  add column if not exists audience text;

create index if not exists meetings_group_upcoming_idx
  on public.meetings (group_id, starts_at)
  where status = 'live';

-- Hosts may set group_id only to groups they own; everyone else's writes
-- are rejected. Reads keep the existing "public read live" policy.
drop policy if exists "host link own group" on public.meetings;
create policy "host link own group" on public.meetings
  for update using (
    host_id = auth.uid()
    and (group_id is null or exists (
      select 1 from public.groups g where g.id = group_id and g.owner_id = auth.uid()
    ))
  )
  with check (
    host_id = auth.uid()
    and (group_id is null or exists (
      select 1 from public.groups g where g.id = group_id and g.owner_id = auth.uid()
    ))
  );

-- 3. Minimal analytics intake (views + taps; RSVPs stay in rsvps) ---------
create table if not exists public.meeting_events (
  id bigint generated always as identity primary key,
  meeting_id uuid not null references public.meetings (id) on delete cascade,
  kind text not null check (kind in ('view', 'website_tap')),
  created_at timestamptz not null default now()
);

create index if not exists meeting_events_meeting_time_idx
  on public.meeting_events (meeting_id, created_at);

alter table public.meeting_events enable row level security;

-- Anyone may append an event (no PII stored). Only the owning host reads them.
drop policy if exists "anyone append events" on public.meeting_events;
create policy "anyone append events" on public.meeting_events
  for insert with check (true);
drop policy if exists "host read own events" on public.meeting_events;
create policy "host read own events" on public.meeting_events
  for select using (exists (
    select 1 from public.meetings m
    where m.id = meeting_id and m.host_id = auth.uid()
  ));

-- Per-host daily aggregates for the dashboard (last N days).
-- Usage: select * from host_meeting_stats('2026-10-01'::timestamptz);
create or replace function public.host_meeting_stats(since timestamptz)
returns table (meeting_id uuid, views bigint, website_taps bigint, rsvps bigint)
language sql stable security definer set search_path to '' as $$
  select m.id,
    (select count(*) from public.meeting_events e
      where e.meeting_id = m.id and e.kind = 'view' and e.created_at >= since),
    (select count(*) from public.meeting_events e
      where e.meeting_id = m.id and e.kind = 'website_tap' and e.created_at >= since),
    (select count(*) from public.rsvps r where r.meeting_id = m.id)
  from public.meetings m
  where m.host_id = auth.uid();
$$;

-- --- Rollback (run only if this migration must be reverted) ---------------
-- drop function if exists public.host_meeting_stats(timestamptz);
-- drop table if exists public.meeting_events;
-- drop policy if exists "host link own group" on public.meetings;
-- alter table public.meetings
--   drop column if exists group_id,
--   drop column if exists fee_cents,
--   drop column if exists fee_currency,
--   drop column if exists audience;
-- drop table if exists public.groups;
