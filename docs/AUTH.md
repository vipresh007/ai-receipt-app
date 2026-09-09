# Authentication — Auth0

Sign-in for the web app (and later iOS) is handled by **Auth0**. It issues an
access token; the FastAPI backend verifies that token against Auth0's JWKS and
maps the identity to a local `users` row.

```
browser ──▶ Auth0 Universal Login (Google / Apple / email+password)
        ◀── sets an encrypted session cookie (httpOnly) via @auth0/nextjs-auth0
browser ──▶ Next.js /api/proxy/*  ──(Bearer <access token>)──▶  FastAPI
                                     FastAPI verifies RS256 against
                                     https://<domain>/.well-known/jwks.json,
                                     then upserts users(auth0_sub, email, …)
```

The backend no longer stores passwords or mints tokens. The `users` table keeps
app data only (`auth0_sub`, `email`, `display_name`, `plan`); receipts/expenses
still FK to `users.id`.

---

## One-time Auth0 setup

Do this in the [Auth0 dashboard](https://manage.auth0.com) (free tier is fine).

### 1. Application (for the web app)

- **Applications → Create Application** → *Regular Web Application*.
- Note the **Domain**, **Client ID**, **Client Secret**.
- **Settings →**
  - **Allowed Callback URLs**:
    `http://localhost:3000/auth/callback, https://<your-web-fqdn>/auth/callback`
  - **Allowed Logout URLs**:
    `http://localhost:3000, https://<your-web-fqdn>`
  - **Allowed Web Origins**: same two origins.

### 2. API (represents the backend)

- **APIs → Create API**. Identifier (audience): `https://api.ai-receipt`
  (any stable URI; it does not need to resolve). Signing algorithm **RS256**.
- **API → Settings → Application Access Policy → User-delegated Access → set to
  "Authorized"** (all applications). Without this the login fails with
  `Client "…" is not authorized to access resource server "https://api.ai-receipt"`
  and the app shows *"An error occurred during the authorization flow."* For
  stricter control later, use "Per-app authorization" and grant just the web app
  under the API's **Application Access** tab (User-delegated column).

### 3. Connections (the login methods)

- **Authentication → Social → Google** — enable, and paste the Google **Client
  ID + Secret** here (the web app never sees them). Enable the connection for
  the "ai-receipt" application (its **Applications** tab).
  - In **Google Cloud Console**, the OAuth client's **Authorized redirect URIs**
    must contain `https://<YOUR_AUTH0_DOMAIN>/login/callback` (not your app's
    URL — Google redirects to Auth0, then Auth0 redirects to the app). JavaScript
    origins can be left blank. Configure the OAuth consent screen first.
- **Authentication → Social → Apple** — enable. Needs an Apple Developer account:
  a Services ID, a Sign in with Apple key (`.p8`), and your Team ID. Follow
  Auth0's Apple setup guide.
- **Authentication → Database → `Username-Password-Authentication`** — keep
  enabled for email + password.
- Under the **Application → Connections** tab, make sure Google, Apple and the
  database connection are all toggled on for this application.

### 4. Fill env and deploy

`web/.env.local` (copy from `web/.env.example`):

```
APP_BASE_URL=http://localhost:3000
AUTH0_DOMAIN=your-tenant.us.auth0.com
AUTH0_CLIENT_ID=...
AUTH0_CLIENT_SECRET=...
AUTH0_SECRET=<openssl rand -hex 32>
AUTH0_AUDIENCE=https://api.ai-receipt
BACKEND_URL=http://localhost:8000
```

`backend/.env`:

```
AUTH0_DOMAIN=your-tenant.us.auth0.com
AUTH0_AUDIENCE=https://api.ai-receipt
```

Then redeploy — `infra/deploy.sh` reads these and wires them into both Container
Apps (`AUTH0_CLIENT_SECRET` / `AUTH0_SECRET` become Container App secrets):

```bash
./infra/deploy.sh
```

`APP_BASE_URL` for the deployed web app is set automatically to its own HTTPS
FQDN. Remember to add `https://<web-fqdn>/auth/callback` to the Allowed Callback
URLs (step 1).

---

## How it works in code

| Piece | File |
|---|---|
| Auth0 client | `web/lib/auth0.ts` |
| Login/logout/callback routes (auto-mounted at `/auth/*`) + session cookie | `web/middleware.ts` → `auth0.middleware()` |
| Route protection | `web/middleware.ts` (redirect to `/auth/login`) and `web/app/(app)/layout.tsx` (`auth0.getSession()`) |
| Attach the token to API calls | `web/app/api/proxy/[...path]/route.ts` → `auth0.getAccessToken()` |
| Token verification | `backend/app/core/security.py` → `verify_access_token()` (PyJWT + `PyJWKClient`) |
| Identity → local user (upsert on first sight, calls `/userinfo` once) | `backend/app/api/deps.py` → `get_current_user` / `_provision_user` |
| Confirm session / get profile | `GET /v1/auth/me` |

**Optional optimization:** add an Auth0 [Action](https://auth0.com/docs/customize/actions)
on the *Login* flow that copies `email` into the access token as a namespaced
claim. Then `_provision_user` can skip the `/userinfo` round-trip.

## iOS — local-first, optional sign-in

The iOS app works **without an account**. Sign-in is a one-way upgrade that
unlocks the web app, cross-device sync, a higher scan quota, and cloud backup.
The app opens Auth0 **Universal Login** with no connection filter, so it offers
every method enabled on the tenant — today **Google + email/password**. (Apple
is deferred until there's an Apple Developer membership.)

### Two modes

| | Anonymous (default) | Signed in |
|---|---|---|
| Identity | random device UUID (Keychain) sent as `X-Device-Id` | Auth0 access token (Keychain, via `CredentialsManager`) sent as `Authorization: Bearer` |
| Source of truth | on-device SwiftData | **backend** — `AccountSync.pull()` reconciles `GET /v1/receipts` into SwiftData on launch / foreground / pull-to-refresh; local create + edit + delete are pushed as they happen. No offline write queue: a failed push is dropped and the next pull re-aligns. |
| Scan quota | `anon_scan_limit` (15) total, enforced server-side per device | plan-based (enforced later, server-side) |
| Server persistence | none — `/v1/extract` returns the parse and forgets it | `Receipt` + `Expense` rows, image in Blob |
| Web access | no | yes |

Receipt **images** stay on the device that scanned them — rows pulled from the
server on another device show without a thumbnail (the original is in Blob; v1
doesn't re-download it).

### Code map (iOS)

| Piece | File |
|---|---|
| Identity + Auth0 Universal Login + token refresh | `ios/AIReceiptApp/Services/AuthManager.swift` |
| Device-ID keychain | `ios/AIReceiptApp/Services/KeychainStore.swift` |
| Header selection (`Bearer` vs `X-Device-Id`), `scans_remaining`, 402, receipt CRUD | `ios/AIReceiptApp/Services/ReceiptExtractionAPIClient.swift` |
| Sign-in import + `pull()` / `pushUpdate()` / `delete()` reconcile | `ios/AIReceiptApp/Services/AccountSync.swift` |
| `Receipt.remoteID` links a local row to its server row | `ios/AIReceiptApp/Models/Receipt.swift` |
| Account tab / quota wall / sign-in button | `ios/AIReceiptApp/Features/Account/` |
| Config (`AUTH0_DOMAIN` / `AUTH0_CLIENT_ID` / `AUTH0_AUDIENCE`) | `ios/Config/AIReceiptApp.xcconfig` → Info.plist → `AppConfig` |

### Anonymous requests

`POST /v1/extract` is **auth-optional**. With no bearer token the caller must
send `X-Device-Id: <uuid>`. The backend keeps a counter in `anon_devices`
(`device_id` unique, `scan_count`); each successful call increments it and the
response carries `scans_remaining`. Past the limit the endpoint returns **402**
with a "sign in to keep scanning" message — the app shows a soft wall (history
stays browsable, the shutter is disabled). Anonymous parses are **not** stored
server-side. See [`EXTRACTION_API.md`](EXTRACTION_API.md) for the wire contract.

### Sign-in / sync flow

1. `Auth0.swift` `WebAuth` Universal Login — audience `https://api.ai-receipt`,
   scope `openid profile email offline_access`, no `.connection(...)` filter. The
   access + refresh tokens go into the keychain via `CredentialsManager`.
2. `AccountSync.importLocalReceiptsIfNeeded` runs once: `POST /v1/receipts/import`
   (bearer) with every receipt that has no `remoteID` yet. The backend creates a
   `Receipt` + `Expense` per item (uploading each image to Blob) and returns the
   rows; the app writes each new `remoteID` back onto its local row.
3. `AccountSync.pull()` then reconciles `GET /v1/receipts` into SwiftData, and
   keeps doing so on every launch / foreground / pull-to-refresh.
4. Ongoing: a signed-in scan uses `/v1/extract` (persists, returns `id`); the
   confirm screen's edits are `PATCH`ed and a discard `DELETE`s the row. Receipt
   detail edits `PATCH` on close; list deletes `DELETE`.

### One-time Auth0 setup for iOS (done for the dev tenant)

- A **Native** application `AI Receipt iOS` (client ID
  `fO5rWCD0FHGA13ty7Y9pKXXWnrw86ES0`, committed in `AIReceiptApp.xcconfig` — it's
  a public client, not a secret). Allowed Callback + Logout URLs:
  `com.example.AIReceiptApp://dev-nvjgstqap8b8wb68.us.auth0.com/ios/com.example.AIReceiptApp/callback`
  (Auth0.swift's default custom-scheme callback; `useHTTPS()` is **not** used, so
  no associated-domain entitlement is needed).
- Connections enabled for that application: `google-oauth2` and
  `Username-Password-Authentication`.
- The `CFBundleURLTypes` scheme (`= $(PRODUCT_BUNDLE_IDENTIFIER)`) is registered
  in `project.yml`.
- Sign in with Apple would use the native `ASAuthorizationController`; deferred
  until the Apple Developer Program membership exists.
