-- Keep weekly recurring listings alive.
--
-- Weekly directory groups are stored as a short run of dated rows
-- (recurrence = 'weekly', source_url "…@YYYY-MM-DD"). The roll-forward in the
-- sync-meetings edge function never worked: it copied source_url unchanged,
-- so every insert hit meetings_source_url_uidx, and its cron job is disabled.
-- Without a roller every weekly listing disappears after its last dated row
-- (2026-11-10 for the current directory import).
--
-- roll_weekly_meetings(): for every weekly row that has passed, add the next
-- occurrence after the series' latest row (so each series keeps the same
-- number of upcoming dates and never duplicates one), then expire the past
-- row. Times roll in local wall-clock time, so 8:00 AM stays 8:00 AM across
-- daylight-saving changes. RSVP counts start at zero on each new date, and
-- last_verified_at is carried over (copying is not re-verification).
-- Runs daily via pg_cron, entirely inside Postgres.

create or replace function public.roll_weekly_meetings()
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare
  r public.meetings%rowtype;
  tz text;
  latest timestamptz;
  next_at timestamptz;
  added integer := 0;
begin
  for r in
    select * from public.meetings
    where status = 'live' and recurrence = 'weekly' and starts_at < now() - interval '2 hours'
    order by starts_at
  loop
    -- Florida's panhandle west of the Apalachicola is on Central time.
    tz := case when r.state = 'FL' and r.longitude < -85.0 then 'America/Chicago' else 'America/New_York' end;

    select max(m.starts_at) into latest
    from public.meetings m
    where m.status = 'live' and m.recurrence = 'weekly'
      and m.group_name = r.group_name and m.title = r.title and m.address = r.address;

    next_at := ((greatest(latest, r.starts_at) at time zone tz) + interval '7 days') at time zone tz;
    while next_at < now() loop
      next_at := ((next_at at time zone tz) + interval '7 days') at time zone tz;
    end loop;

    insert into public.meetings (
      host_id, host_name, title, group_name, category, tagline, description, starts_at,
      venue, address, city, state, zip_code, latitude, longitude, is_virtual,
      cost_description, attendee_limit, attendee_count, status, source, source_url,
      recurrence, last_verified_at
    ) values (
      r.host_id, r.host_name, r.title, r.group_name, r.category, r.tagline, r.description, next_at,
      r.venue, r.address, r.city, r.state, r.zip_code, r.latitude, r.longitude, r.is_virtual,
      r.cost_description, r.attendee_limit, 0, 'live', r.source,
      -- Per-occurrence URLs end in "@YYYY-MM-DD" (directory) or "#YYYY-MM-DD"
      -- (curated); keep the separator and swap in the new date.
      case
        when r.source_url is null then null
        when r.source_url ~ '[@#]\d{4}-\d{2}-\d{2}$'
          then regexp_replace(r.source_url, '([@#])\d{4}-\d{2}-\d{2}$', '\1') || to_char(next_at at time zone tz, 'YYYY-MM-DD')
        else r.source_url || '#' || to_char(next_at at time zone tz, 'YYYY-MM-DD')
      end,
      'weekly', r.last_verified_at
    )
    on conflict (source_url) where source_url is not null do nothing;
    if found then
      added := added + 1;
    end if;

    update public.meetings set status = 'expired' where id = r.id;
  end loop;
  return added;
end $$;

revoke all on function public.roll_weekly_meetings() from public, anon, authenticated;

-- Daily at 09:30 UTC (5:30 AM Eastern). Replaces the disabled edge-function roll.
select cron.unschedule('bizlinq-roll-weekly')
where exists (select 1 from cron.job where jobname = 'bizlinq-roll-weekly');
select cron.schedule('bizlinq-roll-weekly', '30 9 * * *', $cron$select public.roll_weekly_meetings()$cron$);

-- Catch up on anything that has already passed.
select public.roll_weekly_meetings();
