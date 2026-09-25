# Launch checklist — Tally

Everything between "works on the dev environment" and "live on the App Store +
a real domain". **⛔ = hard blocker, 🟡 = needed but not blocking a TestFlight
build, ✅ = already done.**

---

## 1. Identity & branding

- ✅ Name: **Tally**. Display name set (`ios/project.yml` → `CFBundleDisplayName`,
  `web/app/layout.tsx` → `metadata.title`).
- ✅ App icon: `ios/.../AppIcon.appiconset/icon-1024.png` (1024², opaque). Web
  favicon `web/app/icon.svg`. Sources in `design/logo/`, exports in `brand/`.
- ✅ **Bundle identifier**: `com.vipreshpatel.tally` (main),
  `com.vipreshpatel.tally.tests` (tests) — a personal namespace, not tied to a
  domain (you're publishing as an **Individual**, not an org; no domain
  required for this). Set in `ios/project.yml`; the `CFBundleURLTypes` scheme
  follows it automatically. **Add the new Auth0 callback URL** (keep the old
  one during the switch):
  `com.vipreshpatel.tally://dev-…auth0.com/ios/com.vipreshpatel.tally/callback`.
  When you enroll in the Apple Developer Program, register this exact id as an
  Explicit App ID and create the App Store Connect record with it.
- ✅ App Store name, subtitle, description, keywords, URLs, review notes —
  ready to paste from [`APP_STORE.md`](APP_STORE.md).
- ✅ Screenshots (6.5" + 6.9") — `brand/app-store/out/<size>/`, rebuilt by
  `brand/app-store/build.py`.

## 2. Apple / iOS

- ✅ **Apple Developer Program** enrollment — done, enrolled as an
  **Individual** (Vipresh Patel). 🟡 **Converting to an Organization
  account (DATA EAVER INC.)** is in progress, so the App Store seller name
  matches the legal docs' operator instead of reading "Vipresh Patel". Apple's
  "Convert to Organization" migration (submitted from the Developer account,
  `developer.apple.com/contact/request/migrate-individual-account`) keeps the
  existing Team ID / app records — it's not a fresh enrollment — but needs a
  D-U-N-S number + Tax ID for DATA EAVER INC. and Apple's verification
  turnaround (days). Apple also requires a public organization website on a
  domain tied to the company — **https://dataeaver.ca** (repo `vipresh007/dataeaver-site`, Azure
  Static Web App) went live 2026-09-24 for this. Replied to Apple's
  migration email 2026-09-24; waiting on Apple (Certificates, IDs & Profiles is unavailable
  while it runs; App Store Connect stays up). Next concrete steps now that the account exists: register
  the Explicit App ID (`com.vipreshpatel.tally`) under Certificates, IDs &
  Profiles, and create the App Store Connect app record.
- ✅ **Sign in with Apple** — done on both iOS (native `ASAuthorizationController`
  + `AppleSignInButton`, Auth0 `apple` connection keyed by the bundle id) and
  web (Auth0 `apple-web` connection keyed by the `com.vipreshpatel.tally.web`
  Services ID, routed through Universal Login — no web code changes needed).
  Satisfies App Review guideline 4.8. Google and Apple sign-in with the same
  email resolve to the same account (backend links by email on first sight —
  see `backend/app/api/deps.py`); an Apple "Hide My Email" address won't match
  and gets a separate account, which is expected.
- ✅ **In-app account deletion.** `DELETE /v1/auth/me` wipes expenses,
  receipts, budgets, the `users` row, and (best-effort) the Blob images.
  UI: iOS Account → "Delete account" (confirmation dialog); web `/account` →
  danger zone (type `DELETE`). Both sign out afterwards.
- ✅ **Privacy manifest** `PrivacyInfo.xcprivacy` — email, name, photos,
  other user content, purchase history (linked); device ID, crash,
  performance, product interaction (not linked); required-reason APIs
  (UserDefaults `CA92.1`, file timestamp `0A2A.1`).
- ✅ **App Privacy answers** — the table in [`APP_STORE.md`](APP_STORE.md),
  matched to the manifest line for line. Enter them in App Store Connect.
- ✅ Age rating 4+, category Finance, support/marketing/privacy URLs — in
  `APP_STORE.md`.
- 🟡 Create an App Review demo account (email/password) and add a budget to
  it — see `APP_STORE.md` → App Review information.
- ✅ `MARKETING_VERSION` 1.0.0; `ITSAppUsesNonExemptEncryption = false`.
- ✅ `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` — reworded
  to be user-facing.
- ✅ Launch screen — ink background + centred gold/teal Tally mark
  (`LaunchBackground` / `LaunchMark` assets, regenerated from `design/logo/`).
- 🟢 Later: crash reporting, `CFBundleShortVersionString` / build-number bump
  process, an App Store Connect API key for CI upload (`xcrun altool` /
  `fastlane`).

## 3. Web → production

- ✅ **Custom domain + TLS** for the web app: **tally.dataeaver.ca**, bound to
  the Container App with a managed cert. `APP_BASE_URL` and the API's
  `CORS_ORIGINS` both updated (`infra/deploy.sh` now sets these from
  `WEB_CUSTOM_DOMAIN`, so future deploys keep using it automatically). **Still
  needed**: add `https://tally.dataeaver.ca/auth/callback` (and the logout URL
  + web origin) to the **Auth0 Web application's** allowed URLs — that's an
  Auth0-dashboard change only you can make; see `docs/AUTH.md`. The API itself
  (`EXTRACTION_API_HOST` for iOS) still uses its raw `*.azurecontainerapps.io`
  hostname — a custom domain there is optional, not needed for the web fix.
  Done: `https://tally.dataeaver.ca/auth/callback` + logout URL + web origin
  are in the Auth0 Web application's allowed URLs.
- ✅ **Account deletion** on web — `/account` danger zone.
- ✅ **CORS** — `cors_origins` no longer defaults to `*`; `deploy.sh` sets
  `CORS_ORIGINS` to the web FQDN. Update it when the custom domain lands.
- 🟡 Cookie / consent banner if you'll have EU users (Auth0 sets a session
  cookie; that's essential-only, but analytics would need consent).
- 🟡 SEO: `metadata` per route, `opengraph-image`, `robots`, `sitemap`.
- 🟢 Analytics (privacy-friendly, e.g. Plausible) if wanted.

## 4. Backend & infra hardening

- ✅ Migrations run on startup (`app/db_migrate.bootstrap_schema`) — no more
  `AUTO_CREATE_TABLES` drift. Keep `AUTO_CREATE_TABLES=true` (it now also
  triggers `alembic upgrade head`) **or** move the `alembic upgrade` into the
  container entrypoint and drop the flag.
- ✅ Per-IP + per-device anonymous rate limiting on `/v1/extract`.
- 🟡 **Secrets** — the dev env keeps its current values (dev-only, no real
  users). **Prod must get brand-new secrets**, not copies: a separate Auth0
  prod application (own client secret), a separate Google OAuth client, a fresh
  `AUTH0_SECRET`, and a new Postgres password. The values used in dev are
  effectively public and must never guard real user data.
- ✅ **Decision (2026-09-25): the current environment (`rg-ai-receipt-dev`)
  is production for launch.** It costs little, and a separate prod stack
  (`ENV=prod` with `infra/provision.sh` + `infra/deploy.sh`) only makes sense
  once there are enough users to justify double the bill. Moving later means
  a data migration (pg_dump/restore + blob copy) and repointing
  `tally.dataeaver.ca` and the iOS `EXTRACTION_API_HOST` (a new app build).
  Before real users, the dev env still needs the essentials in
  "Keep-as-prod essentials" below.
- 🟡 **Postgres**: enable automated backups + point-in-time restore, set a
  retention window, consider zone-redundant HA, and **remove the "allow all
  Azure services" firewall rule** — scope to the Container App's outbound IPs
  or use VNet integration + private endpoint.
- 🟡 **Secrets → Key Vault**: today they're Container App secrets/plain env.
  Move `AUTH0_*`, `AZURE_OPENAI_API_KEY`, `AZURE_STORAGE_CONNECTION_STRING`,
  DB URL into Key Vault with a managed identity.
- 🟡 **Blob**: private container (it is), lifecycle rule to delete receipt
  images after N months (they're PII), and confirm the download path
  (`GET /v1/receipts/{id}/image`) is the only way in.
- 🟡 **Azure OpenAI**: set a spending cap / budget alert, confirm content
  filter config, and a fallback when it's unavailable (extraction already
  returns 502 cleanly).
- 🟡 **Monitoring**: App Insights is wired — add alerts (5xx rate, p95 latency,
  DB connection failures, OpenAI error rate) and a dashboard.
- 🟡 **Scale**: API `minReplicas` is 0 (cold starts ~3–8s after idle). Bump to
  1 for prod (`az containerapp update --min-replicas 1`) — ~$15–30/mo.
- 🟢 Structured request logging, a `/version` endpoint, DB connection pool
  tuning.

### Keep-as-prod essentials (applied 2026-09-25)

What the resources had, and what was done:

| Item | Today | Fix | Cost |
|---|---|---|---|
| Blob lifecycle | No rule, though the privacy policy promises deletion after 24 months | ✅ `delete-receipt-images-after-24-months`: blobs under `receipts/` deleted 730 days after last change | Free |
| Blob soft delete | Off | ✅ 7 days (privacy policy notes it) | ~Free |
| Postgres backups | 7 days, locally redundant | ✅ 35 days (privacy policy notes it) | Backup storage beyond 32 GB only |
| Postgres storage auto-grow | Off (32 GB) | ✅ On | Free until used |
| Postgres firewall | "Allow all Azure services" | Keep. A Consumption environment has hundreds of shared outbound IPs, so scoping is impractical. The real fix (VNet + private endpoint) needs a new Container Apps environment, so it's part of a future prod stack. Mitigate with a fresh DB password | — |
| Secrets | Dev values, some seen in terminal output | ✅ Rotated the Postgres password, both Azure OpenAI keys, both storage keys, and `AUTH0_SECRET` (in Azure, GitHub secrets, `infra/.env.infra`, `backend/.env`, `web/.env.local`). 🟡 Auth0 web client secret still to rotate | Free |
| API cold start | `minReplicas 0` (10–20 s first scan) | ✅ API `minReplicas 1` (web stays 0). `deploy.sh` only sets replicas when it creates an app, so this sticks | ≈$10/mo |
| Log Analytics | No daily cap | ✅ 0.5 GB/day | Free |
| Spend | No budget alert | ✅ Budget `tally-monthly`, $50/mo on the resource group: email at 80% and 100% actual, and 100% forecast | Free |

Geo-redundant backup and zone HA can't be added to this Postgres server
after creation. Accept that on the single-server plan.

## 5. Legal & data

- ✅ **Privacy Policy** — `/privacy` (`web/content/legal/privacy.md`), filled in
  (**DATA EAVER INC.**, contact@dataeaver.ca, tally.dataeaver.ca, no mailing
  address). Reviewed and accepted as final by the business owner 2026-09-18 —
  not run past outside legal counsel; see `docs/legal/README.md` for the
  accepted-risk note and remaining known gaps (governing-law assumption, no
  mailing address).
- ✅ **Account & data deletion** mechanism (see §2) — DB rows + best-effort
  blob cleanup. Confirm your backup policy also purges deleted accounts.
- ✅ **Terms of Service** — `/terms` (`web/content/legal/terms.md`), same
  status as the Privacy Policy above.
- 🟡 **Publishing entity**: legal docs name **DATA EAVER INC.** as operator;
  the Apple seller name is being brought in line with that via the
  Individual → Organization conversion (see §2 above and
  `docs/legal/README.md`). Not blocking TestFlight either way — resolve before
  a real App Store listing.
- ✅ **No EU at launch (2026-09-25).** The EU Digital Services Act "trader"
  declaration (App Store Connect → Business) was left unset, so Apple keeps
  the app off EU storefronts. As a company, declaring would publish a business
  address and phone number on the EU product page, and the privacy policy
  doesn't cover GDPR yet. To add the EU later: declare trader status, add a
  GDPR section + sub-processor list, then re-enable the EU countries in
  Pricing and Availability.
- 🟡 Data Processing / sub-processor list if you'll have EU/UK users (GDPR).
- 🟢 "Export my data" (JSON dump) — nice, not required.

## 6. Monetisation (only if charging at launch)

- The freemium model is designed but **no billing is built**. To charge:
  - iOS: StoreKit 2 in-app purchase / subscription + App Store Connect
    products; server-side receipt validation.
  - Web: Stripe Checkout + webhook → `users.plan`.
  - Enforce `plan` limits server-side (there's a `TODO` in
    `routes/receipts.py` for the signed-in scan cap).
- Simplest path: **launch free**, add billing later.

---

## Suggested order

Done: real bundle id, Apple Developer Program enrollment, account deletion,
Privacy Policy + Terms, `PrivacyInfo.xcprivacy`, launch screen, **Sign in with
Apple** (both platforms), custom domain + Auth0 web callback URLs. Remaining,
in order:

1. Confirm the Explicit App ID is registered + create the App Store Connect
   app record (§2) if not already done.
2. Individual → Organization conversion for the Apple seller name (§2/§5) —
   submit it now if not already; it runs in the background while you do
   everything else.
3. ~~Screenshots, App Store listing copy, App Privacy answers (§2).~~ Done
   and entered in App Store Connect (2026-09-25), with the review demo
   account. Only the build is missing.
4. TestFlight build → internal testing → submit for review.
5. The keep-as-prod essentials (§4). They can trail TestFlight, but must
   land before real users sign up.
