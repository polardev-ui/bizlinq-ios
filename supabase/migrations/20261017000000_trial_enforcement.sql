-- BizLinq: enforce the 14-day posting trial on the server.
--
-- Before this migration can_post() returned true for everyone, so the trial
-- only existed inside the app, and profiles.trial_started_at was writable by
-- its owner (a trial could be reset by clearing it).
--
-- What this does:
--   1. poster_trials: the authoritative trial start, written only by the
--      meetings insert trigger (security definer). Users can read their own.
--      profiles.trial_started_at is kept as a read-only mirror for the app.
--   2. poster_entitlements: App Store subscriptions verified by the
--      verify-subscription edge function (Apple JWS signature checked).
--      Only the service role writes it.
--   3. can_post(): true while the trial is running (14 days; 30 for trials
--      that began before the 2026-10-17 cutover) or with a verified,
--      unexpired subscription. False otherwise — no client can bypass it.
--   4. Hosts can still edit/cancel their own meetings, but edits after the
--      trial need can_post too (otherwise an old listing could be re-dated
--      into a free new post). Cancelling is always allowed.
--   5. profiles.host_rules_accepted_at: when the host agreed to the rules.
--
-- Existing meetings are untouched: nothing here hides or deletes listings.
-- Rollback script at the bottom.

-- 1. Trial start --------------------------------------------------------
create table if not exists public.poster_trials (
  user_id uuid primary key references auth.users (id) on delete cascade,
  started_at timestamptz not null default now()
);

alter table public.poster_trials enable row level security;

drop policy if exists "read own trial" on public.poster_trials;
create policy "read own trial" on public.poster_trials
  for select using (user_id = auth.uid());

insert into public.poster_trials (user_id, started_at)
select id, trial_started_at from public.profiles where trial_started_at is not null
on conflict (user_id) do nothing;

-- Profiles mirror the trial table; client writes to the column are ignored.
create or replace function public.profiles_mirror_trial()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  new.trial_started_at := (select t.started_at from public.poster_trials t where t.user_id = new.id);
  return new;
end $$;

drop trigger if exists profiles_mirror_trial on public.profiles;
create trigger profiles_mirror_trial
  before insert or update on public.profiles
  for each row execute function public.profiles_mirror_trial();

-- First post starts the trial (replaces the old profile-only version).
create or replace function public.set_trial_start()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.host_id is null then
    return new;
  end if;
  insert into public.poster_trials (user_id) values (new.host_id)
  on conflict (user_id) do nothing;
  -- Touch the profile so its mirror column refreshes.
  update public.profiles set id = id where id = new.host_id;
  return new;
end $$;

-- 2. Verified subscriptions -----------------------------------------------
create table if not exists public.poster_entitlements (
  user_id uuid primary key references auth.users (id) on delete cascade,
  product_id text not null,
  original_transaction_id text not null unique,
  expires_at timestamptz not null,
  environment text not null,
  updated_at timestamptz not null default now()
);

alter table public.poster_entitlements enable row level security;

drop policy if exists "read own entitlement" on public.poster_entitlements;
create policy "read own entitlement" on public.poster_entitlements
  for select using (user_id = auth.uid());

-- 3. The posting gate -------------------------------------------------------
create or replace function public.can_post(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select
    exists (
      select 1 from public.poster_entitlements e
      where e.user_id = p_user and e.expires_at > now()
    )
    or coalesce((
      select t.started_at > now() - case
        when t.started_at < timestamptz '2026-10-17 00:00:00+00' then interval '30 days'
        else interval '14 days'
      end
      from public.poster_trials t
      where t.user_id = p_user
    ), true) -- no trial yet: the first post starts it
$$;

-- Policies evaluate it as the signed-in user; nobody else needs to call it.
revoke execute on function public.can_post(uuid) from public, anon;
grant execute on function public.can_post(uuid) to authenticated, service_role;

-- 4. Edits after the trial need a plan; cancelling never does -------------
-- Hosts must be able to read their own rows: an UPDATE's new row has to stay
-- visible to the updater, and "public read live" hides cancelled rows, so
-- without this cancelling a meeting fails with an RLS error.
drop policy if exists "host read own" on public.meetings;
create policy "host read own" on public.meetings
  for select using (host_id = auth.uid());

-- RESTRICTIVE so it is ANDed with every permissive update/insert policy
-- (e.g. "host update own", "host link own group"), not ORed past.
drop policy if exists "posting needs trial or plan (update)" on public.meetings;
create policy "posting needs trial or plan (update)" on public.meetings
  as restrictive for update
  using (true)
  with check (status = 'cancelled' or public.can_post(auth.uid()));

drop policy if exists "posting needs trial or plan (insert)" on public.meetings;
create policy "posting needs trial or plan (insert)" on public.meetings
  as restrictive for insert
  with check (public.can_post(auth.uid()));

-- 5. Host rules ---------------------------------------------------------------
alter table public.profiles
  add column if not exists host_rules_accepted_at timestamptz;

-- Rollback ------------------------------------------------------------------
-- drop policy if exists "posting needs trial or plan (update)" on public.meetings;
-- drop policy if exists "posting needs trial or plan (insert)" on public.meetings;
-- drop policy if exists "host read own" on public.meetings;
-- create or replace function public.can_post(p_user uuid) returns boolean
--   language sql stable security definer set search_path to '' as $$ select true $$;
-- drop trigger if exists profiles_mirror_trial on public.profiles;
-- drop function if exists public.profiles_mirror_trial();
-- drop table if exists public.poster_entitlements;
-- drop table if exists public.poster_trials;
-- alter table public.profiles drop column if exists host_rules_accepted_at;
