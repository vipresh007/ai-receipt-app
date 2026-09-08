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

## iOS (not built yet)

Add the [`Auth0.swift`](https://github.com/auth0/Auth0.swift) SPM package, use
`WebAuthentication` for login, store the access token in the Keychain, and pass
it to `ReceiptExtractionAPIClient(authToken:)`. Register a **Native** application
in Auth0 with callback `com.example.AIReceiptApp://<domain>/ios/...`. Sign in
with Apple on iOS uses the native `ASAuthorizationController`; Auth0 can accept
that assertion.
