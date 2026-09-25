# App Store listing — Tally

Everything to paste into App Store Connect for the first submission. Character
limits are Apple's; counts are noted where they're tight. Screenshots are in
[`brand/app-store/`](../brand/app-store/) (see its `build.py`).

## App information

| Field | Value |
|---|---|
| Name (30) | **Tally: Receipts & Spending** (26) |
| Subtitle (30) | **Snap receipts, see spending** (27) |
| Bundle ID | `com.vipreshpatel.tally` |
| SKU | `tally-ios` |
| Primary category | **Finance** |
| Secondary category | Productivity |
| Content rights | Does not contain third-party content |
| Age rating | **4+** (answer "None" / "No" to every questionnaire item) |
| Copyright | `2026 DATA EAVER INC.` |
| Price | Free, no in-app purchases |
| Availability | All territories (or Canada + US to start) |

If "Tally: Receipts & Spending" is taken, fall back to
**Tally — Receipt Scanner** (23).

## URLs

| Field | URL |
|---|---|
| Privacy Policy URL | https://tally.dataeaver.ca/privacy |
| Support URL | https://dataeaver.ca/#contact |
| Marketing URL | https://tally.dataeaver.ca |

## Version page (1.0)

**Promotional text** (170; editable any time without a review):

> Snap a receipt and Tally reads the store, total, tax and every item for you, then shows where your month went. No bank linking, no ads, no tracking.

**Keywords** (100 chars, comma-separated, no spaces). Apple already indexes
the words in the name and subtitle, so they aren't repeated here (95):

```
scanner,expense,tracker,budget,money,bills,grocery,tax,finance,subscription,OCR,wallet,shopping
```

**Description** (4000):

```
Tally turns the receipts in your wallet into a clear picture of where your money goes.

Take a photo of a receipt, or pick one from your library, and Tally reads the store, date, total, tax, category and every line item for you. Check it, fix anything with a tap, and it's saved.

YOUR MONTH AT A GLANCE
See what you've spent so far this month, how it compares with last month, and a six-month trend. Switch to quarter or year view any time.

WHERE IT WENT
A category breakdown shows exactly where the money went: groceries, restaurants, transport, utilities and more.

INSIGHTS IN PLAIN WORDS
Tally tells you what actually changed: a category that jumped, spending that has risen three months in a row, or your biggest category this month.

EVERY RECEIPT, ONE SEARCH AWAY
Search by store or by item ("coffee beans"), filter by category, and edit anything later. Tally also spots charges that repeat each month, so subscriptions don't hide.

MONTH OVER MONTH
Browse your full history, with each month's total and how it moved.

BUDGETS
Set a monthly limit for any category and see how close you are. Budgets need a free account.

START WITHOUT AN ACCOUNT
Your first scans need no sign-up. Sign in with Apple, Google or email when you want to keep going, and your receipts sync to the Tally web app at tally.dataeaver.ca.

PRIVATE BY DESIGN
No ads, no tracking, no bank linking. You can delete your account and all your data from inside the app at any time.
```

**What's New** (first version): `First release.`

**Version number**: `ios/project.yml` has `MARKETING_VERSION "0.1.0"`. Bump it
to `1.0.0` before archiving the submission build (and `CURRENT_PROJECT_VERSION`
for every upload).

## Screenshots

6.9" iPhone (1320 × 2868). Apple scales these down for the smaller iPhone
sizes, so no other set is required. The app is iPhone-only
(`TARGETED_DEVICE_FAMILY = "1"`), so no iPad set is needed either.

| # | File | Shows |
|---|---|---|
| 1 | `brand/app-store/out/01-scan.png` | A receipt read into its fields (the core loop) |
| 2 | `brand/app-store/out/02-dashboard.png` | This month's total + trend |
| 3 | `brand/app-store/out/03-insights.png` | Where it went + insights |
| 4 | `brand/app-store/out/04-receipts.png` | Receipts list, light mode |
| 5 | `brand/app-store/out/05-history.png` | Month history, light mode |

The raw captures are in `brand/app-store/raw/`: iPhone 17 Pro Max simulator,
status bar overridden to 9:41, and sample data from the debug-only
`-seedSampleReceipts` launch argument. The scanned receipt is a made-up store
(Northfield Market) run through the real extraction backend.

## App Privacy ("nutrition label")

**Tracking: No.** Every answer below matches
`ios/AIReceiptApp/PrivacyInfo.xcprivacy`, so change both together.

| Apple category → type | Collected | Linked to identity | Purpose | Why |
|---|---|---|---|---|
| Contact Info → Email Address | Yes | Yes | App Functionality | Account (Auth0) |
| Contact Info → Name | Yes | Yes | App Functionality | Account profile from Apple/Google |
| User Content → Photos or Videos | Yes | Yes | App Functionality | Receipt images (stored for signed-in users) |
| User Content → Other User Content | Yes | Yes | App Functionality | Extracted receipt text and line items |
| Purchases → Purchase History | Yes | Yes | App Functionality | Receipts are purchase records |
| Identifiers → Device ID | Yes | **No** | App Functionality | Per-install ID that counts free anonymous scans; never joined to an account |
| Diagnostics → Crash Data | Yes | No | App Functionality | Backend error telemetry (Application Insights) |
| Diagnostics → Performance Data | Yes | No | App Functionality | Backend request timings (Application Insights) |
| Usage Data → Product Interaction | Yes | No | Analytics | Backend request telemetry |

Everything else is **Not collected**: location, contacts, health, financial
info (no card or bank numbers), browsing history, search history, audio,
advertising data, sensitive info.

## App Review information

**Sign-in required?** No. Enter a demo account anyway so the reviewer can
check sync and Budgets. Create it yourself in Auth0 (email/password, e.g.
`appreview@dataeaver.ca`), then put its credentials in the Sign-in
Information fields. Don't commit them here.

**Contact**: Vipresh Patel, contact@dataeaver.ca, and a phone number.

**Notes** (paste as is):

```
Tally works without an account. To try the core flow: open the Scan tab, choose "Take photo" or "Choose from library" and pick any receipt. The store, date, total, tax, category and line items are read by our server and shown for confirmation. Tap Save and the receipt appears on the Dashboard and in Receipts.

Without an account, a device gets 15 free scans. Signing in (Sign in with Apple, Google or email via Auth0) removes that limit and syncs receipts to our web app (tally.dataeaver.ca). The Budgets tab needs an account; the demo account above has one set up.

Account deletion: Account tab > Delete account. It removes the account, all receipts and their images from our servers.

The first scan after a quiet period can take 10 to 20 seconds while our server starts up.
```

Before submitting: sign in to the demo account and add a budget, so the
Budgets tab has something to show.
