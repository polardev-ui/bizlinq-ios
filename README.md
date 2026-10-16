# BizLinq (Production)

iOS SwiftUI app for discovering business networking meetings across the US.

**Business rules:**
- Free to view and join. Costs money to post ($10/mo or $99/yr via In-App Purchase).
- 14-day free posting trial, then a plan is required to post — enforced by Postgres RLS, mirrored in-app.
- Users enter a **ZIP code + driving radius** (5–100 mi, or Nationwide).

## Run it

1. Open `BizLinq.xcodeproj` in Xcode 26+, set Team to Genysis IQ LLC.
2. Pick an iPhone simulator → Run. (First run: pick the `BizLinq.storekit` config in Scheme → Run → Options for local purchase testing.)

## Architecture

```
BizLinq/
  App/       BizLinqApp.swift (wiring), ContentView.swift, ScreenshotHarness.swift (DEBUG only)
  Backend/   Config.swift, SupabaseRESTClient.swift (zero third-party deps),
             BackendService.swift (protocol + live impl), AuthManager.swift (Apple → Supabase session, Keychain tokens)
  Models/    Meeting.swift (snake-case Codable, tolerant dates)
  Data/      ZipDatabase.swift, SampleData.swift (DEBUG only)
  Stores/    MeetingStore.swift (search/filter/schedule + backend sync),
             SubscriptionManager.swift (StoreKit 2 entitlements)
  Views/     Onboarding, Browse, Detail (map + RSVP + report/block), Post,
             Paywall, My Posts, Profile, SignIn, ZipSearch
BizLinqTests/  12 unit tests (haversine, Codable, filters, weekly limit, RSVP)
```

No backend SDK: the app talks to Supabase Auth + PostgREST over `URLSession`, so there is nothing to audit, update, or break at build time.

## Backend (Supabase "BizLinq Production")

Tables `profiles`, `meetings`, `rsvps`, `reports` with RLS (see migrations in the Supabase dashboard). Key rules:

- Anyone (anon included) can read live upcoming meetings and RSVP rows.
- Only the host's authenticated user can insert/update/delete their meetings; inserts and edits require `can_post(auth.uid())` (trial running or verified subscription). Cancelling is always allowed.
- RSVP rows belong to their author; a trigger maintains `meetings.attendee_count`.
- Reports are insert-only for authenticated users; review them in the dashboard.

## Posting trial (enforced server-side)

- A host's first post starts a **14-day free posting trial** (trials begun before 2026-10-17 keep 30 days). Before that first post, hosts accept the **host rules** once (full-screen, `HostRules` in `Stores/Trial.swift`; also stored as `profiles.host_rules_accepted_at`).
- After day 14 without a plan, `TrialEndedView` appears once: **View plans**, **I'll just browse** (stops prompts), or **Remind me tomorrow** — a local notification at the same time the next day. Tapping it opens **Ready to move forward?** (`ReadyToMoveForwardView`); "Keep browsing" schedules the next day's reminder again. All in `Views/HostTrialViews.swift`.
- Existing listings stay live after the trial; only new posts and edits are locked.
- The database enforces it: `can_post()` checks `poster_trials` (not user-writable) and `poster_entitlements`, which only the `verify-subscription` edge function writes after checking Apple's JWS signature. See `supabase/migrations/20261017000000_trial_enforcement.sql`.
- Tests: `deno test -A supabase/functions/verify-subscription/` and `deno run -A supabase/tests/migrations_test.ts .`

## Weekly listings

Weekly groups are short runs of dated rows (`recurrence = 'weekly'`). `roll_weekly_meetings()` (pg_cron, daily 09:30 UTC) replaces each passed date with the next one after the series' latest, in local time. The old edge-function roll never ran (cron disabled; it also collided with `source_url`).

## Lake Nona hunt (October 2026)

`tools/lake_nona_import.py` builds `tools/seed_lake_nona.sql` (+ `tools/lake_nona_report.csv`) from hand-checked Lake Nona listings (Chamber, Rotary, Toastmasters, BNI, Crema at Nona, St. Cloud Chamber) plus Eventbrite/Meetup imports within 15 miles of 32827/32832.

## Screenshots (App Store)

DEBUG-only harness driven by launch arguments: `-shotBrowse`, `-shotDetail`, `-shotPaywall`, `-shotZip <zip>`. Captures live in `AppStore/screenshots/` (6.9"). Never compiled into Release.

## Submission

Follow `AppStore/release-checklist.md` and paste version-page values from `AppStore/metadata.md`. Legal texts: `AppStore/privacy-policy.md`, `AppStore/terms.md` (have a lawyer review; host the privacy policy for the Privacy Policy URL field).

## Florida research directory (build 8)

The Directory tab and Discover shortcut expose the October 13, 2026 research
edition offline: 539 stable record IDs, published schedules and costs, organizer
contacts, verification caveats, and 895 source links. Search by group, city, ZIP,
host or record ID and filter by format, advertised cost and purpose. Virtual-only
records sort after city listings. The separate 92-city Primerica contact index
and historical restricted event are available under Directory notes.

Research listings are separate from dated upcoming events: no dates, map pins,
RSVPs, verified activity, or free membership are inferred from uncertain evidence.
Paid memberships offering free guest visits remain in the paid filter. Venue
text is searchable even when it differs from the PDF's chapter/city heading.

`tools/import_florida_directory.py /path/to/BizLinq_Florida_Networking_Directory_Rebuilt.pdf`
rebuilds the bundled JSON using pdfplumber, retains PDF page references and the
source SHA-256, and asserts complete ID coverage and required fields. Run from
the project root after creating `tmp/pdfs`. The PDF is not needed at app runtime.
`DirectoryTests` checks completeness, revised CLG/CREMA details, Primerica purpose
and timezone distinctions, filters, URL safety and appendix separation.
