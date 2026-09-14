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
- 🟡 App Store name (30 chars) + subtitle (30). "Tally" alone may be taken —
  plan a qualified store name like `Tally: Receipts & Spending`.
- 🟡 Marketing site copy, screenshots, an App Store description + keywords.

## 2. Apple / iOS

- ⛔ **Apple Developer Program** enrollment ($99/yr) — required for TestFlight
  and the App Store. Nothing iOS ships without it. Enroll as an **Individual**
  (your legal name, Vipresh Patel, shows as the seller) — no D-U-N-S number or
  business registration needed, unlike an Organization account.
- ⛔ **Sign in with Apple.** App Review guideline 4.8: if you offer a
  third-party sign-in (we offer Google) you must also offer Sign in with Apple.
  Add it: Auth0 Apple connection (needs a Services ID, a Sign-in-with-Apple key
  `.p8`, Team ID) + a native `ASAuthorizationController` button, or route it
  through Auth0 Universal Login. See `docs/AUTH.md`.
- ✅ **In-app account deletion.** `DELETE /v1/auth/me` wipes expenses,
  receipts, insights, the `users` row, and (best-effort) the Blob images.
  UI: iOS Account → "Delete account" (confirmation dialog); web `/account` →
  danger zone (type `DELETE`). Both sign out afterwards.
- ✅ **Privacy manifest** `PrivacyInfo.xcprivacy` — in the bundle. First pass:
  declares email/name/photos/other-user-content (app functionality) + crash/
  perf/interaction, and required-reason APIs (UserDefaults `CA92.1`, file
  timestamp `0A2A.1`). **Reconcile with the App Privacy answers below.**
- 🟡 **App Privacy answers** in App Store Connect ("nutrition label"): we
  collect email (account), photos/receipts (app functionality), and diagnostics
  via App Insights. Not used for tracking. Must match `PrivacyInfo.xcprivacy`.
- 🟡 Screenshots for 6.9"/6.7" iPhone (and 13" iPad if you keep iPad — the app
  is iPhone-only today: `TARGETED_DEVICE_FAMILY = "1"`).
- 🟡 Age rating (4+), primary category **Finance**, support URL, marketing URL.
- ✅ `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` — reworded
  to be user-facing.
- ✅ Launch screen — brand-blue background + centred Tally mark
  (`LaunchBackground` / `LaunchMark` assets).
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

- 🟡 **Privacy Policy** — drafted at `/privacy` (`web/content/legal/privacy.md`),
  filled in (**DATA EAVER INC.**, contact@dataeaver.ca, tally.dataeaver.ca, no
  mailing address). Get it **legally reviewed**, then it's a ✅.
- ✅ **Account & data deletion** mechanism (see §2) — DB rows + best-effort
  blob cleanup. Confirm your backup policy also purges deleted accounts.
- 🟡 **Terms of Service** — drafted at `/terms` (`web/content/legal/terms.md`),
  same as above; needs the same legal review.
- 🟡 **Publishing entity**: legal docs now name **DATA EAVER INC.** as
  operator, but your Apple Developer Program is enrolled as an **Individual**
  (Vipresh Patel) — the App Store's own "seller" would still read your name,
  not the company's. Fine for dev/TestFlight; resolve before a real App Store
  listing (either keep the docs as an individual, or upgrade the Apple account
  to an Organization — needs a D-U-N-S number). Details in
  `docs/legal/README.md`.
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
