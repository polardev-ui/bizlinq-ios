# BizLinq SwiftUI Redesign — Completion Report

Branch: `redesign-eight-screen` (reviewable, pushed to `polardev-ui/bizlinq-ios`).
Screenshots: `redesign/screenshots/01–08` (+ 2 extras). All shots use fictional
SampleData with future dates on iPhone 17 simulator, plus one dark-mode shot.

## What changed and where

**Design system** — `BizLinq/Views/BizDesign.swift` (new): teal/ink/canvas/hairline
tokens (ink + hairline adapt to dark mode), `BizPrimaryButton`,
`BizSecondaryButton`, `BizChip`, `BizCostBadge`, `BizMeetingCard`,
`BizMetaRow`, `BizGroupHeader`, `BizMetricTile`, `BizMetricUnavailable`,
`BizStateView`, `BizFormSection`.

**Navigation** — `App/ContentView.swift`: four tabs now Discover / My Meetings /
Host / Profile. Posting moved into Host (sheet); owned posts moved out of the
My Meetings tab.

**Screen 1 Discover** — `Views/BrowseView.swift` rewritten: "Find your next
business connection" headline, tappable location card, search + Filters button
with active-count badge, horizontal category chips (same filter state),
`BizMeetingCard` rows with cost badges, result count, preserved
refresh/error/blocking/curated/upcoming-only behavior, actionable empty states.

**Screen 2 Filters** — `FiltersSheet` (same file): "Find your fit", Clear all,
draft state (Cancel/swipe never applies), Show meetings commits, ZIP + place,
5/10/25/50/100mi + Nationwide, all 5 categories, Any/In person/Online,
Any/Free/Paid cost (unknown fees count as Paid, stated in UI), Nearest/Soonest.
New store state: `CostFilter`, `activeFilterCount`, `clearFilters()`.

**Screen 3 Details** — `Views/MeetingDetailView.swift` rewritten: category +
format + cost badges, audience line, timezone-aware date ("EDT…Local time on
your device"), cost before RSVP ("RSVP for free" vs "RSVP" + fee, no in-app
payment), map for in-person only, group header + "View group profile", About,
curated source links, bottom safe-area RSVP + text Share (no deep link exists
yet), report/block preserved. Also fixed a false claim: online events no
longer say "link sent after RSVP".

**Screen 4 Group profile** — `Views/GroupProfileView.swift` (new): derived only
from genuinely upcoming same-`groupName` meetings; next-meeting card, listed
venues labeled as listed (never "usual schedule"), more upcoming, event-page
links. No manufactured activity; research rows untouched.

**Screen 5 Host dashboard** — `Views/HostDashboardView.swift` (new):
signed-out explainer + sign-in, first-time setup state (not an empty chart),
owned group + public-profile link, trial/subscription eligibility, next
published meeting, **Post next meeting** (prefills from previous listing),
owned posts with Edit/Cancel, Reach metrics: live-post count + RSVP taps
(genuine sums, footnoted) alongside honest "tracking isn't collected yet"
tiles for views/website taps. No graphs, no demo numbers.

**My Meetings tab** — `Views/AttendeeMeetingsView.swift` (new): the
attendee's RSVP'd upcoming meetings (`store.myRSVPs`, new) with cancel/undo
via context menu; signed-out and empty states.

**Screens 6–7 Post → Review → Publish** — `Models/MeetingDraft.swift` (new
shared draft: validation, fee math, contact parse/build, future-date copy),
`Views/MeetingFormFields.swift` (shared fields: group, distinct meeting
title, audience, category, contact, date/time + device-tz note, in-person /
online with access info, Free/Paid + amount + USD/EUR/GBP/CAD/AUD),
`Views/ReviewMeetingView.swift` (previews exact submitted data with visitor
components; single Publish), `Views/PostMeetingView.swift` rewritten
(prefill banner "Copied from your previous listing. Review and update.",
discard-draft action, trial gates kept), `Views/EditMeetingView.swift`
rewritten on the draft (edits PATCH, never creates a second post).

**Screen 8 Subscription** — `Views/PaywallView.swift`: "Help local
professionals find your group" + the owner's tagline, benefits
(location/category discovery, details + free RSVPs, unlimited editable posts),
"14 days free" / per-plan afterward hierarchy, "Start your free trial"
(StoreKit trial) vs paid Continue for ineligible users, hosting-vs-attending
distinction, Restore + Terms/Privacy links. Monthly emphasized, **annual kept
purchasable** (`$99/year`, Best value).

**Model + backend client** — `Models/Meeting.swift`: optional `feeCents`,
`feeCurrency`, `audience` (decoder-tolerant, encoder-optional), `isFreeEntry`
(unknown ≠ free), `costBadgeText`, `audienceLine`, `currencySymbol`,
`fullWithZone` formatter, `shortName` chips. `SupabaseRESTClient`:
`updateMeeting` PATCHes editable fields only with `return=representation`;
`MeetingStore.saveEdits` refreshes the row in place.

**Trial correctness** — `Stores/Trial.swift`: pre-cutover (Oct 17 2026) trials
keep 30-day terms via `lengthDays(for:)`; newer trials 14 days; notifications
and UI follow. Tests cover both eras.

## Fully functional vs externally dependent

Functional now: all 8 screens, filters, cost model, draft/prefill/review/
publish/edit, RSVP, report/block, trial math + grandfathering, honest
metrics, dark mode, VoiceOver labels, 44pt targets, Reduce Motion (native
controls; no custom animation to gate).

Dependent on external configuration (unchanged by this branch):
- App Store Connect intro offer must be **Free Trial / 2 Weeks** on both
  products (tutorial updated: `AppStore/iap-tutorial.md`).
- Attach build + both subscription products to v1.0 and submit.
- `supabase/migrations/20261016000000_group_profiles_and_fees.sql` is
  **prepared, NOT applied**: `groups` table + `meetings.group_id` link +
  fee/audience columns + `meeting_events` intake + `host_meeting_stats`
  + host-scoped RLS. Group profiles currently derive from meeting rows;
  persistent profiles light up after this migration is reviewed and applied.
- No reference boards were attached; implementation follows the written spec.

## Build/test results and limits

- `xcodebuild test -only-testing:BizLinqTests`: **all pass** (incl. new cost-filter,
  draft-validation, and trial-era tests).
- Ran on iPhone 17 simulator (iOS 26.5), light + dark; 8 labeled screenshots
  + attendee + dark extras in `redesign/screenshots/`.
- Not run: physical device, TestFlight, VoiceOver audit beyond labels,
  large-text/Dynamic-Type pass beyond system controls, second device for
  cross-device checks, production backend against new columns (migration not
  applied — app tolerates their absence).

## Pricing/trial/legacy handling

- 14-day trial for new hosts; pre-cutover trials keep 30 days (date-based,
  server stamp is source of truth).
- No posting cooldown anywhere (owner direction; spec's 7-day copy replaced
  with unlimited-posting copy on all 8 screens, site, and metadata).
- Startups stays merged into Networking; legacy `"Business Start Ups"` /
  `"Founders & Startups"` decode to Networking.
- Active monthly/annual entitlements, restore, and grace behavior untouched.
- No destructive merges; curated/research rows unchanged; no claim-group flow
  invented (imported groups can't be claimed by sign-in).

## Deviations from the mockups/spec

1. No 7-day cooldown UI (owner: no limits) — Review/Host/Paywall say unlimited.
2. Boards absent — hierarchy/palette implemented from the written spec.
3. No graphs — summary + unavailable tiles per spec's minimal-metrics clause.
4. Single currency symbol enforced; legacy free-text costs preserved as
   "Fee varies", never relabeled Free.
5. Draft persists in-memory through validation/sign-in (native sheets keep
   state); deliberate Discard added. No cross-launch draft store.

## Remaining production steps (owner/ASC, not done here)

1. Review + apply the migration file in staging first.
2. ASC: 2-week intro offers on both products; attach build + products to v1.0.
3. Submit for review (manual release); host the website for Support/Privacy URLs.
4. Optional follow-ups: deep-link scheme for Share, server-side view/tap
   collection to light up the unavailable tiles, cross-launch draft persistence.
