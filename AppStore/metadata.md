# BizLinq — App Store Connect values (v1.0)

## Product Page Information — English (U.S.)

**Promotional Text** (optional, editable without review):
```
Find business networking meetings near you. Hosts post free for 14 days, then $10/mo.
```

**Description:**
```
BizLinq makes business networking easy to find.

Discover networking meetings, mixers, and meetups near you — search by ZIP code and driving distance, anywhere in the United States. Browsing is always free.

FOR ATTENDEES (FREE)
• Find founders coffees, tech mixers, real estate roundtables, sales breakfasts, and more
• See who's going, where it's happening, and what's on the agenda
• RSVP in seconds with a free account
• Virtual events from all over the country

FOR HOSTS
• Advertise your networking group to people actively looking for events — they don't need to know your group's name, they just need to be looking for their next connection
• One simple poster plan — $10/month or $99/year, with a 14-day free trial
• Unlimited live posts, and edit any live listing anytime
• Track RSVPs and grow your group week after week

HOW IT WORKS
1. Enter your ZIP code and how far you'll drive
2. Browse upcoming meetings near you
3. RSVP free, show up, and grow your network

Download BizLinq and find your people.
```

**Keywords** (100 max, no spaces — 88 used):
```
networking,business,meetups,founders,startups,entrepreneur,referrals,events,mixer,social
```

**Support URL:** `https://bizlinq.app/support` (must be live — host `privacy-policy.md` plus a contact email there)
**Marketing URL:** leave blank
**Copyright:** `2026 Genysis IQ LLC`

## Screenshots

Upload `AppStore/screenshots/00-onboarding.png`, `01-discover.png`, `02-detail.png`, `03-paywall.png` (1320×2868, iPhone 6.9"), plus the exact-size sets in `AppStore/screenshots/upload/` (1179×2556 and 1206×2622). iPhone-only app → no iPad screenshots needed. Landscape slots (2556×1179, 2622×1206) are optional — capture manually if wanted: open the app in Simulator → Device → Rotate Left → screenshot (the `-shotBrowse` / `-shotDetail` / `-shotPaywall` launch args still apply).

## Build

Xcode → Product → Archive → Distribute App → App Store Connect, with Team = Genysis IQ LLC. Then select the build on this page. (Export compliance is pre-answered in-app: standard HTTPS only.)

## App Review Information

- **Sign-in required:** YES (posting and RSVPing need an account; browsing does not)
- **User name / Password:** leave blank — sign-in is Sign in with Apple only
- **Notes:**
```
Sign in with Apple only (no passwords). To test posting or RSVPing, tap Post or RSVP and sign in with your review Apple ID. Browsing needs no sign-in. Test search: ZIP 10001, radius 25 mi. Flagging: every meeting detail screen has a report/block menu for user-posted content.
```
- **Contact:** your name, phone, and an email you actually answer during review week.

## App Store Version Release

Choose **Manually release this version** for v1 (you control launch day).

## Also fill (sidebar)

- **App Privacy:** collect = Name (display name), User ID (Apple identifier), Coarse Location (ZIP), Other User Content (posts/RSVPs). All linked to user identity, App Functionality purpose, NOT used for tracking. Privacy Policy URL = hosted `privacy-policy.md`.
- **Age rating questionnaire:** answer honestly (no objectionable content expected; UGC is reportable/blockable in-app).
- **Monetization → Subscriptions:** create group "BizLinq Poster", then products `bizlinq.poster.monthly` ($10/1 month) and `bizlinq.poster.annual` ($99/1 year). Add them for review with this version.
