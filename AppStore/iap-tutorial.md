# BizLinq In-App Purchases — Complete Setup Tutorial

Yes, dashboard setup is **required**. The app knows the product IDs (`bizlinq.poster.monthly`, `bizlinq.poster.annual`), but Apple doesn't know the prices, durations, or terms until you create the products. Nothing is purchasable — not even in sandbox testing — until this is done.

Total time: ~30 minutes, plus waiting on Apple's review.

---

## Part 0 — Agreements, Tax & Banking (do this first)

Paid subscriptions cannot sell — or even be tested properly — until this is complete.

1. App Store Connect → **Agreements, Tax, and Banking**.
2. Under **Agreements**, accept the **Paid Applications** agreement (all active agreements must show as Active/Effective).
3. Under **Tax Forms** and **Banking**, complete US tax forms and add your bank account (Genysis IQ LLC). Banking verification can take days — start now even if the app isn't ready.

If banking isn't done, you can still create the products and test in sandbox, but Apple will not approve them.

---

## Part 1 — Create the subscription group

1. Open your **BizLinq** app → **Monetization → Subscriptions**.
2. Click **Create** (or "+") → **Create Subscription Group**.
3. Reference Name: `BizLinq Poster` (internal only, users never see it).
4. Click Create. You'll add the two products inside this group.

---

## Part 2 — Create Poster Monthly ($10)

Inside the "BizLinq Poster" group → **Create Subscription**:

| Field | Value |
|---|---|
| Reference Name | `Poster Monthly` (internal) |
| Product ID | `bizlinq.poster.monthly` — must match **exactly**, it's what the app asks Apple for |
| Duration | 1 Month |
| Price | $10.00 (pick the $10.00 tier; set other countries later or leave USD-only if the app is US-only) |

Then add the **Subscription Display Name + Description** (Add Localization → English (U.S.)):

- Display Name: `Poster Monthly`
- Description: `Post a networking meeting every week. Cancel anytime.`

Then add the **Introductory Offer** (this is the 14-day free trial):

1. In the subscription's settings → **Introductory Offers** → **+**.
2. Offer type: **Free Trial**. Duration: **2 Weeks** (14 days).
3. Save. (One trial per subscription group is standard — a user who trials Monthly won't get a second trial on Annual.)

Save the subscription.

---

## Part 3 — Create Poster Annual ($99)

Same group → **Create Subscription**:

| Field | Value |
|---|---|
| Reference Name | `Poster Annual` |
| Product ID | `bizlinq.poster.annual` — exact match again |
| Duration | 1 Year |
| Price | $99.00 tier |

Localization → English (U.S.):

- Display Name: `Poster Annual`
- Description: `Post a networking meeting every week. About 2 months free vs monthly.`

Add the same **Introductory Offer** as Monthly: **Free Trial**, **2 Weeks**. Because both products live in one group, a user gets a single 14-day trial total, then pays for whichever plan they picked.

Save.

---

## Part 4 — Group ranking (upgrade/downgrade behavior)

Open the **BizLinq Poster** group → set subscription levels:

- Poster Monthly → **Level 1**
- Poster Annual → **Level 2**

Effect: Monthly → Annual counts as an **upgrade** (switches immediately, Apple prorates), Annual → Monthly counts as a **downgrade** (switches at next renewal). This is the standard setup for same-service plans.

---

## Part 5 — Availability

Subscriptions are only buyable where your app is available. If you limited the app to **United States only** (recommended for v1), the subscriptions follow automatically. No extra step unless you want to exclude specific regions.

---

## Part 6 — Attach them to version 1.0 for review

New subscriptions must be submitted **together with an app version** — they can't go live alone.

1. App Store → **iOS App 1.0** (Prepare for Submission page).
2. Scroll to **In-App Purchases and Subscriptions** → **+** → add both products.
3. They'll show as "Waiting for Review" alongside the version.

Price or availability edits later do **not** need review. Name/description edits do.

---

## Part 7 — Test before review (sandbox)

Real purchases should never be tested with your real Apple ID.

1. App Store Connect → **Users and Access → Sandbox → Testers** → **+** → create a tester (any fake email, e.g. `bizlinq-test@genysis.iq`).
2. On your iPhone: Settings → App Store → **Sandbox Account** → sign in with the tester.
3. Install the TestFlight build, go to Post → buy Monthly.
4. Sandbox subscriptions renew fast (1 month ≈ 5 minutes) — verify the plan activates, expires, and that **Restore purchase** brings it back.
5. Also test in the iOS Simulator: Xcode → Scheme → Run → Options → StoreKit Configuration → select `BizLinq.storekit` (in the project root), then purchase in-simulator for free.

If the app says "product not found": the Product ID in the dashboard doesn't exactly match the app's, or you're signed into the wrong sandbox account.

---

## Part 8 — What App Review checks (we're already covered)

- Prices in the app ($10 / $99) match the dashboard — they do.
- Subscription terms visible before purchase — the paywall states weekly-posting limits, auto-renewal, and App Store cancellation.
- A working **Restore purchase** button — present on the paywall.
- Account deletion path exists — Support page + in-app/Terms.

---

## Troubleshooting

| Symptom | Cause → Fix |
|---|---|
| "Product not found" in app | Product ID typo, or products not yet created → compare dashboard IDs character-by-character |
| Purchase fails immediately | Paid Applications agreement / tax / banking incomplete → Part 0 |
| Sandbox asks for real payment | Signed into real Apple ID, not the sandbox tester → Settings → App Store → Sandbox Account |
| Products stuck "Ready to Submit" | Not attached to a version → Part 6 |
| Review rejection on subscriptions | Usually missing restore button or terms — both already in the app; reply pointing to them |

Related files: `AppStore/release-checklist.md` (full launch order), `AppStore/metadata.md` (version-page values), `BizLinq.storekit` (simulator testing config).
