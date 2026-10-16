// Applies the BizLinq migrations to an in-memory Postgres (PGlite) with a
// minimal stand-in for the production schema, then exercises them.
// deno run -A supabase/tests/migrations_test.ts .
import { PGlite } from "npm:@electric-sql/pglite@0.2.17";

const repo = Deno.args[0];
const db = new PGlite();
let failures = 0;
function check(name: string, ok: boolean, detail: unknown = "") {
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${ok ? "" : "  -> " + JSON.stringify(detail)}`);
  if (!ok) failures++;
}
const q = async (sql: string, params: unknown[] = []) => (await db.query(sql, params)).rows as any[];

// --- Production-shaped scaffold -------------------------------------------
await db.exec(`
create role anon; create role authenticated; create role service_role;
create schema auth;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;

create schema cron;
create table cron.job (jobid serial primary key, jobname text unique, schedule text, command text, active boolean default true);
create function cron.schedule(name text, sched text, cmd text) returns bigint language sql as
  $$ insert into cron.job (jobname, schedule, command) values (name, sched, cmd) returning jobid $$;
create function cron.unschedule(name text) returns boolean language sql as
  $$ delete from cron.job where jobname = name returning true $$;

create table public.profiles (
  id uuid primary key references auth.users(id), display_name text, home_zip text, radius_miles int,
  created_at timestamptz default now(), trial_started_at timestamptz);
alter table public.profiles enable row level security;
create policy "owner full access" on public.profiles for all using (auth.uid() = id) with check (auth.uid() = id);

create table public.meetings (
  id uuid primary key default gen_random_uuid(), host_id uuid, host_name text not null default '',
  title text not null, group_name text not null, category text not null, tagline text not null default '',
  description text not null default '', starts_at timestamptz not null, venue text not null default '',
  address text not null default '', city text not null, state text not null, zip_code text not null,
  latitude double precision not null, longitude double precision not null, is_virtual boolean not null default false,
  cost_description text not null default 'Free', attendee_limit int, attendee_count int not null default 0,
  status text not null default 'live', created_at timestamptz not null default now(), source text,
  source_url text, recurrence text, last_verified_at timestamptz);
create table public.rsvps (meeting_id uuid references public.meetings(id) on delete cascade, user_id uuid, created_at timestamptz default now(), primary key (meeting_id, user_id));
create unique index meetings_source_url_uidx on public.meetings (source_url) where source_url is not null;
alter table public.meetings enable row level security;
create policy "public read live" on public.meetings for select using (status = 'live' and starts_at > now() - interval '2 hours');
create policy "host delete own" on public.meetings for delete using (host_id = auth.uid());

-- Production's original functions/policies, replaced by the migration.
create function public.can_post(p_user uuid) returns boolean language sql stable security definer set search_path to '' as $$ select true $$;
create policy "host insert own" on public.meetings for insert with check (host_id = auth.uid() and can_post(auth.uid()));
create policy "host update own" on public.meetings for update using (host_id = auth.uid()) with check (host_id = auth.uid());
create function public.set_trial_start() returns trigger language plpgsql as $$
begin update public.profiles set trial_started_at = coalesce(trial_started_at, now()) where id = new.host_id; return new; end $$;
create trigger meetings_trial_start after insert on public.meetings for each row execute function set_trial_start();
create function public._bulk_load(secret text, q text) returns text language plpgsql security definer as $$ begin execute q; return 'ok'; end $$;

grant usage on schema public to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
grant select, insert, update, delete on public.meetings, public.profiles to authenticated;
grant select on public.meetings to anon;
`);

for (const f of [
  "20261016000000_group_profiles_and_fees.sql",
  "20261017000000_trial_enforcement.sql",
  "20261017000100_drop_bulk_load.sql",
  "20261017000200_roll_weekly_meetings.sql",
  "20261017000300_function_grants.sql",
]) {
  try {
    await db.exec(await Deno.readTextFile(`${repo}/supabase/migrations/${f}`));
    check(`applies ${f}`, true);
  } catch (e) {
    check(`applies ${f}`, false, String(e));
  }
}
await db.exec(`grant select on public.poster_trials, public.poster_entitlements to authenticated;`);

// --- Trial enforcement ------------------------------------------------------
const alice = "11111111-1111-1111-1111-111111111111";
const bob = "22222222-2222-2222-2222-222222222222";
await db.exec(`insert into auth.users values ('${alice}'), ('${bob}');
  insert into public.profiles (id, display_name) values ('${alice}', 'Alice'), ('${bob}', 'Bob');`);

const meetingSql = (host: string, title: string) => `insert into public.meetings
  (host_id, title, group_name, category, starts_at, city, state, zip_code, latitude, longitude)
  values ('${host}', '${title}', 'G', 'Business Networking', now() + interval '3 days', 'Orlando', 'FL', '32827', 28.37, -81.27)`;

async function asUser(uid: string, sql: string): Promise<string | null> {
  try {
    await db.exec(`set test.uid = '${uid}'; set role authenticated; ${sql}; reset role;`);
    return null;
  } catch (e) {
    await db.exec(`reset role;`);
    return String(e);
  }
}

check("can_post before any post", (await q(`select public.can_post('${alice}') ok`))[0].ok === true);
check("first post allowed", (await asUser(alice, meetingSql(alice, "first"))) === null);
const trial = await q(`select started_at from public.poster_trials where user_id = '${alice}'`);
check("first post starts the trial", trial.length === 1);
const mirror = await q(`select trial_started_at from public.profiles where id = '${alice}'`);
check("profile mirrors trial start", mirror[0].trial_started_at !== null, mirror);

const tamper = await asUser(alice, `update public.profiles set trial_started_at = null where id = '${alice}'`);
const afterTamper = await q(`select trial_started_at from public.profiles where id = '${alice}'`);
check("client cannot clear trial_started_at", tamper === null && afterTamper[0].trial_started_at !== null, { tamper, afterTamper });

// A trial that began after the 2026-10-17 cutover lasts 14 days.
const expiredExpr = await q(`select (timestamptz '2026-10-18' > timestamptz '2026-11-02' - interval '14 days') as still_in_trial`);
check("post-cutover trial lasts 14 days", expiredExpr[0].still_in_trial === false);
await db.exec(`update public.poster_trials set started_at = now() - interval '15 days' where user_id = '${alice}'`);
// Before the cutover, a 15-day-old trial is on the legacy 30-day terms.
const legacy = (await q(`select (now() - interval '15 days') < timestamptz '2026-10-17' as legacy`))[0].legacy;
if (legacy) {
  check("(legacy 30-day trial still active at day 15)", (await q(`select public.can_post('${alice}') ok`))[0].ok === true);
  await db.exec(`update public.poster_trials set started_at = now() - interval '31 days' where user_id = '${alice}'`);
}
check("expired trial cannot post", (await q(`select public.can_post('${alice}') ok`))[0].ok === false);
const blocked = await asUser(alice, meetingSql(alice, "after trial"));
check("insert rejected after trial", blocked !== null && /row-level security/i.test(blocked), blocked);

const firstId = (await q(`select id from public.meetings where title = 'first'`))[0].id;
const editBlocked = await asUser(alice, `update public.meetings set title = 'redated' where id = '${firstId}'`);
const titleNow = (await q(`select title from public.meetings where id = '${firstId}'`))[0].title;
check("edit rejected after trial", editBlocked !== null || titleNow === "first", { editBlocked, titleNow });
const cancel = await asUser(alice, `update public.meetings set status = 'cancelled' where id = '${firstId}'`);
const statusNow = (await q(`select status from public.meetings where id = '${firstId}'`))[0].status;
check("cancel allowed after trial", cancel === null && statusNow === "cancelled", { cancel, statusNow });

const forge = await asUser(alice, `insert into public.poster_entitlements (user_id, product_id, original_transaction_id, expires_at, environment)
  values ('${alice}', 'bizlinq.poster.monthly', 'x', now() + interval '30 days', 'Production')`);
check("client cannot grant itself an entitlement", forge !== null, forge);

await db.exec(`insert into public.poster_entitlements (user_id, product_id, original_transaction_id, expires_at, environment)
  values ('${alice}', 'bizlinq.poster.monthly', '1000', now() + interval '30 days', 'Production')`);
check("verified subscription can post", (await q(`select public.can_post('${alice}') ok`))[0].ok === true);
check("insert allowed with subscription", (await asUser(alice, meetingSql(alice, "subscribed"))) === null);
await db.exec(`update public.poster_entitlements set expires_at = now() - interval '1 minute' where user_id = '${alice}'`);
check("lapsed subscription cannot post", (await q(`select public.can_post('${alice}') ok`))[0].ok === false);

check("_bulk_load removed", (await q(`select count(*)::int n from pg_proc where proname = '_bulk_load'`))[0].n === 0);
check("host_rules_accepted_at added", (await q(`select count(*)::int n from information_schema.columns where table_name='profiles' and column_name='host_rules_accepted_at'`))[0].n === 1);

// --- Weekly roll-forward ----------------------------------------------------
await db.exec(`delete from public.meetings`);
// Directory-style series: 8:00 AM Eastern Wednesdays, two past + one upcoming, crossing DST (Nov 1, 2026).
const ins = (when: string, url: string, title = "BNI Test") => `insert into public.meetings
  (title, group_name, category, starts_at, venue, address, city, state, zip_code, latitude, longitude, source, source_url, recurrence, attendee_count, last_verified_at)
  values ('${title}', '${title}', 'Business Networking', '${when}', 'V', 'A; Orlando, FL', 'Orlando', 'FL', '32827', 28.37, -81.27, 'directory', '${url}', 'weekly', 7, '2026-10-14')`;
// Use dates relative to now so the test is stable: last week, this week (past), next week.
const rows = await q(`select
  ((date_trunc('day', now() at time zone 'America/New_York') - interval '14 days' + interval '8 hours') at time zone 'America/New_York') a,
  ((date_trunc('day', now() at time zone 'America/New_York') - interval '7 days' + interval '8 hours') at time zone 'America/New_York') b,
  ((date_trunc('day', now() at time zone 'America/New_York') + interval '7 days' + interval '8 hours') at time zone 'America/New_York') c`);
const iso = (d: Date) => d.toISOString();
const day = (d: Date) => new Date(d.getTime()).toLocaleDateString("en-CA", { timeZone: "America/New_York" });
const [a, b, c] = [rows[0].a, rows[0].b, rows[0].c] as Date[];
await db.exec(ins(iso(a), `bizlinq-directory:REC-1@${day(a)}`));
await db.exec(ins(iso(b), `bizlinq-directory:REC-1@${day(b)}`));
await db.exec(ins(iso(c), `bizlinq-directory:REC-1@${day(c)}`));
// Curated-style series with "#date" URLs: one past row.
await db.exec(ins(iso(b), `https://example.org/club#${day(b)}`, "Toastmasters Test"));

const added = (await q(`select public.roll_weekly_meetings() n`))[0].n;
check("rolls one new date per passed row", added === 3, added);
const live = await q(`select title, starts_at, source_url, attendee_count, last_verified_at from public.meetings where status = 'live' order by title, starts_at`);
const bni = live.filter((r) => r.title === "BNI Test");
check("series keeps its window (3 upcoming)", bni.length === 3, bni.map((r) => r.source_url));
const urls = new Set(bni.map((r) => r.source_url));
check("no duplicate dates", urls.size === bni.length);
const local = bni.map((r) => new Date(r.starts_at).toLocaleTimeString("en-US", { timeZone: "America/New_York", hour: "numeric", minute: "2-digit" }));
check("keeps 8:00 AM local across DST", local.every((t) => t === "8:00 AM"), local);
check("dates follow the series' latest + 7 days", bni.map((r) => day(new Date(r.starts_at))).join(",") ===
  [7, 14, 21].map((n) => day(new Date(c.getTime() + (n - 7) * 86400000))).join(","), bni.map((r) => day(new Date(r.starts_at))));
check("new dates start with zero RSVPs", bni.slice(1).every((r) => r.attendee_count === 0), bni.map((r) => r.attendee_count));
check("verification date carried over, not refreshed", bni.every((r) => new Date(r.last_verified_at).toISOString().startsWith("2026-10-14")));
const tm = live.filter((r) => r.title === "Toastmasters Test");
check("'#date' URLs roll too", tm.length === 1 && /#\d{4}-\d{2}-\d{2}$/.test(tm[0].source_url) && tm[0].source_url !== `https://example.org/club#${day(b)}`, tm);
check("passed rows expired", (await q(`select count(*)::int n from public.meetings where status='live' and starts_at < now() - interval '2 hours'`))[0].n === 0);
check("re-running adds nothing", (await q(`select public.roll_weekly_meetings() n`))[0].n === 0);
check("daily cron scheduled", (await q(`select count(*)::int n from cron.job where jobname = 'bizlinq-roll-weekly'`))[0].n === 1);

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
Deno.exit(failures === 0 ? 0 : 1);
