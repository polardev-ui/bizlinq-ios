# BizLinq Meeting Sources Playbook

Goal: every top-100 US metro has 10+ upcoming meetings; rural ZIPs fall back to
nearest metro + virtual. Strategy: recurring + high-volume community sources,
re-synced weekly. Facts only (title, time, venue, RSVPs) with a source link on
every listing; descriptions truncated. Polite fetching (1.5s+ delays, identified
user agent, robots.txt honored).

## Live pipeline (built)

- `supabase/functions/sync-meetings/` — Deno edge function, deployed. Reads the
  `source_groups` watchlist (oldest first, 60/run), re-imports each group's
  upcoming events, expires past one-offs, rolls `recurrence='weekly'` rows
  forward, logs to `sync_runs`.
- Schedule: pg_cron `bizlinq-weekly-sync`, Mondays 06:00 UTC (calls the function
  with the anon JWT; writes use the function's own service-role secret).
- Add a group: insert its Meetup URL into `source_groups` (or run
  `tools/meetup_import.py`, which seeds both meetings and the watchlist).
- Manual trigger: POST the function URL with `{"limit_groups": N}`.

## Source ranking

| Source | Yield | Access | Status |
|---|---|---|---|
| Meetup group pages (`__NEXT_DATA__` JSON) | 140k groups indexed; thousands relevant | Sitemap + polite fetch, robots-OK for group pages | LIVE — importer + weekly sync |
| Eventbrite discovery + event pages (`__NEXT_DATA__` JSON, venue coords included) | Dozens per metro + suburbs | Polite fetch with attribution + link-back on every listing | LIVE — `tools/eventbrite_import.py` (d/{state}--{city}/networking/ + event pages) |
| Metro chambers (GrowthZone/ChamberMaster calendars) | 100s per metro | Public calendars, per-chamber parsing | Next adapter (needs per-site markup check) |
| 1 Million Cups chapters | ~150 weekly | Salesforce-walled; needs browser automation or partnership | Blocked on tooling |
| SCORE workshops | 100s/month rotating | Bot-walled (403) | Blocked; revisit with partnership |
| BNI chapters (~600, weekly) | High | JS finder; no bulk endpoint found | Blocked; revisit |
| Eventbrite / Luma / LinkedIn | Huge | No public API; ToS bans scraping | Do not scrape; apply for Eventbrite API partnership instead |
| PredictHQ / commercial aggregators | Huge, clean | Paid API key | Scale-up option when budget allows |

## The real engine (beyond scraping)

Imported listings bootstrap the directory, but organizers posting directly is
the durable supply. Funnels already in place: in-app Post flow, paywall,
website organizer messaging. Next highest-ROI moves: (1) email top group
organizers inviting them to claim/post, (2) "Add your group" suggest form
feeding the watchlist, (3) chamber partnership outreach.

## Adding a source adapter

1. Add a fetcher to `tools/meetup_import.py` (one-off backfill) mirroring the
   Meetup normalizer output fields.
2. Mirror the same parsing in `supabase/functions/sync-meetings/index.ts`
   for the weekly run; redeploy with `supabase functions deploy sync-meetings
   --project-ref qzmtchjjmcdlzwwfvrwd`.
3. Every row needs: title, starts_at (future, with TZ), city, coords, source,
   source_url (unique, used for upsert dedupe), last_verified_at.
4. Never import without a verifiable source_url. Never copy full descriptions
   (truncate ≤500 chars). Never invent venues, times, or RSVP counts.
