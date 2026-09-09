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
- ⛔ **Real bundle identifier.** Currently `com.example.AIReceiptApp` — a
  placeholder. Pick a permanent reverse-DNS id you control (e.g.
  `com.<yourdomain>.tally` or `app.tally.ios`). Change `bundleIdPrefix` +
  `PRODUCT_BUNDLE_IDENTIFIER` in `ios/project.yml`, and the Auth0 **Native**
  app's callback URL + the `CFBundleURLTypes` scheme. It can never change once
  shipped.
- 🟡 App Store name (30 chars) + subtitle (30). "Tally" alone may be taken —
  plan a qualified store name like `Tally: Receipts & Spending`.
- 🟡 Marketing site copy, screenshots, an App Store description + keywords.

## 2. Apple / iOS

- ⛔ **Apple Developer Program** enrollment ($99/yr) — required for TestFlight
  and the App Store. Nothing iOS ships without it.
- ⛔ **Sign in with Apple.** App Review guideline 4.8: if you offer a
  third-party sign-in (we offer Google) you must also offer Sign in with Apple.
  Add it: Auth0 Apple connection (needs a Services ID, a Sign-in-with-Apple key
  `.p8`, Team ID) + a native `ASAuthorizationController` button, or route it
  through Auth0 Universal Login. See `docs/AUTH.md`.
- ⛔ **In-app account deletion.** Guideline 5.1.1(v): any app with account
  creation must let users delete their account (and data) from inside the app.
  Needs a backend `DELETE /v1/me` (cascade receipts, expenses, blobs, the
  `users` row) + an iOS/web "Delete account" flow.
- 🟡 **Privacy manifest** `PrivacyInfo.xcprivacy` in the app bundle — now
  required. Declare data collected (photos = user content, email, coarse
  usage) and required-reason APIs (UserDefaults, file timestamp, etc.).
- 🟡 **App Privacy answers** in App Store Connect ("nutrition label"): we
  collect email (account), photos/receipts (app functionality), and diagnostics
  via App Insights. Not used for tracking.
- 🟡 Screenshots for 6.9"/6.7" iPhone (and 13" iPad if you keep iPad — the app
  is iPhone-only today: `TARGETED_DEVICE_FAMILY = "1"`).
- 🟡 Age rating (4+), primary category **Finance**, support URL, marketing URL.
- 🟡 `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` — present;
  reword to be user-facing and specific before review.
- 🟡 Launch screen is a bare `UILaunchScreen: {}` — add a simple branded one.
- 🟢 Later: crash reporting, `CFBundleShortVersionString` / build-number bump
  process, an App Store Connect API key for CI upload (`xcrun altool` /
  `fastlane`).

## 3. Web → production

- ⛔ **Custom domains + TLS** for the web app and the API (e.g. `tally.app`
  and `api.tally.app`). Add custom domains to both Container Apps, managed
  certs, and update `APP_BASE_URL` / `AUTH0` allowed URLs / iOS
  `EXTRACTION_API_HOST`.
- 🟡 **Account deletion** on web too (shares the backend `DELETE /v1/me`).
- 🟡 **Lock CORS** — `settings.cors_origins` should be exactly the web origin,
  not `*`.
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
- ⛔ **Rotate the secrets that were shared in plaintext**: Auth0 client secret,
  Google OAuth client secret, `AUTH0_SECRET`, and the Postgres admin password.
  Do this before any public exposure.
- ⛔ **A production environment** separate from `rg-ai-receipt-dev`: its own
  resource group, Postgres, Blob, Key Vault, Container Apps, Auth0
  tenant/application, Azure OpenAI deployment. `infra/provision.sh` +
  `infra/deploy.sh` are parameterised on `ENV` — run with `ENV=prod`.
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

## 5. Legal & data

- ⛔ **Privacy Policy** — public URL, required by both Apple and Auth0/Google.
  Cover: what's collected (email, name, receipt images + extracted data,
  diagnostics), why, where it's stored (Azure, region), third parties (Auth0,
  Azure OpenAI, Google sign-in), retention, and how to delete.
- ⛔ **Account & data deletion** mechanism (see §2) — and honour it end to end
  (DB rows + blobs + any backups policy).
- 🟡 **Terms of Service**.
- 🟡 Decide the **publishing entity** (personal name vs a company) — it shows on
  the App Store and in the policy.
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

1. Rotate secrets (§4) + real bundle id (§1) — cheap, unblock everything.
2. Apple Developer Program (§2) — has a lead time.
3. Backend: `DELETE /v1/me` + account-deletion UI (§2/§3/§5) — needed for review.
4. Sign in with Apple (§2).
5. Privacy Policy + Terms (§5), hosted on the marketing site.
6. Production env + custom domains (§3/§4).
7. `PrivacyInfo.xcprivacy`, launch screen, screenshots, store listing (§2).
8. TestFlight → external testers → submit.
