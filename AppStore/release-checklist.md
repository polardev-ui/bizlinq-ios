# BizLinq v1.0 — Release Checklist

## Done in the repo

- [x] Supabase project "BizLinq Production" (`qzmtchjjmcdlzwwfvrwd`, us-west-1): profiles, meetings, rsvps, reports tables; RLS; server-side 1-post-per-7-days; RSVP count triggers
- [x] iOS client: guest browsing, Sign in with Apple, StoreKit 2 ($10/mo, $99/yr), report/block (Guideline 1.2), privacy manifest, AppIcon, entitlements, export-compliance flag, iPhone-only
- [x] 12 unit tests passing; unsigned Release archive validates; 6.9" screenshots captured

## You do in Apple Developer / App Store Connect

1. [ ] App ID `com.bizlinq.app` with Sign in with Apple + In-App Purchase (Register an App ID)
2. [ ] Services ID (e.g. `com.bizlinq.app.service`) with Sign in with Apple → configure in Supabase Dashboard → Authentication → Sign In with Apple (Identifier + private key)
3. [ ] App Store Connect → BizLinq → Subscriptions: group "BizLinq Poster" + `bizlinq.poster.monthly` ($10) + `bizlinq.poster.annual` ($99)
4. [ ] Host `AppStore/privacy-policy.md` and a support contact page → Support URL + Privacy Policy URL
5. [ ] Fill the v1.0 version page from `AppStore/metadata.md`; fill App Privacy + age rating
6. [ ] Xcode: open `BizLinq.xcodeproj`, set Team = Genysis IQ LLC, Archive → Distribute → App Store Connect
7. [ ] Internal TestFlight build → invite yourself → verify: browse (empty nationwide), Apple sign-in, test purchase in sandbox, post a meeting, RSVP from a second account, report flow
8. [ ] External TestFlight (optional beta) → Submit for Review (manual release)

## After approval

- Post 3–5 real seed meetings (your own groups) so day-one users see content
- Monitor Supabase → Authentication (signups) and the `reports` table (moderation)
- Add for Review the subscription products with each version until approved once
