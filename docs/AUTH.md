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

### Two modes

| | Anonymous (default) | Signed in |
|---|---|---|
| Identity | random device UUID (Keychain) sent as `X-Device-Id` | Auth0 access token (Keychain) sent as `Authorization: Bearer` |
| Source of truth | on-device SwiftData | **backend** — SwiftData is a read-through cache (no offline write queue in v1) |
| Scan quota | `anon_scan_limit` (15) total, enforced server-side per device | plan-based (enforced later, server-side) |
| Server persistence | none — `/v1/extract` returns the parse and forgets it | `Receipt` + `Expense` rows, image in Blob |
| Web access | no | yes |

### Anonymous requests

`POST /v1/extract` is **auth-optional**. With no bearer token the caller must
send `X-Device-Id: <uuid>`. The backend keeps a counter in `anon_devices`
(`device_id` unique, `scan_count`); each successful call increments it and the
response carries `scans_remaining`. Past the limit the endpoint returns **402**
with a "sign in to keep scanning" message — the app shows a soft wall (history
stays browsable, the shutter is disabled). Anonymous parses are **not** stored
server-side. See [`EXTRACTION_API.md`](EXTRACTION_API.md) for the wire contract.

### Sign-in / migration flow

1. `Auth0.swift` `WebAuthentication` login (audience `https://api.ai-receipt`) →
   store the access token in the Keychain.
2. `POST /v1/receipts/import` (bearer) with the local receipts as
   `{ merchant, date, total, tax, category, currency, items[], imageBase64? }`.
   The backend creates a `Receipt` + `Expense` per item and uploads each image
   to Blob. Returns the created `ReceiptOut[]` (201).
3. Switch the app to signed-in mode: backend becomes source of truth, refill
   SwiftData from `GET /v1/receipts`, drop the `X-Device-Id` counter (left as a
   dead row; not reused).

### One-time Auth0 setup for iOS

- Register a **Native** application in Auth0. Callback / logout URL:
  `com.example.AIReceiptApp://<AUTH0_DOMAIN>/ios/com.example.AIReceiptApp/callback`.
- Add the URL scheme `com.example.AIReceiptApp` to the app target's Info.
- Add the `Auth0.swift` SPM package; `AuthManager` (`@Observable`) holds
  `.anonymous(deviceId)` / `.signedIn(token, profile)` and the Keychain I/O.
- `ReceiptExtractionAPIClient` gains a `deviceId` field and sends whichever of
  the two headers applies.
- Sign in with Apple on iOS uses the native `ASAuthorizationController`; Auth0
  accepts that assertion.
