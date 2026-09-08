# AI Receipt — web

Next.js (App Router) web client for the [FastAPI backend](../backend). Full
parity with the iOS app: auth, scan → extract, dashboard, insights, receipts.

## Stack

- **Next.js 15** + React 19 + TypeScript
- **Tailwind CSS 3.4**, themed entirely from [`../design`](../design)
  (`tokens.css` is copied to `app/tokens.css` on `predev`/`prebuild`;
  `tailwind-preset.js` maps the scale onto Tailwind)
- **shadcn-style primitives** (`components/ui/*`) — CVA + `tailwind-merge`, no CLI
- **TanStack Query** for data, **Recharts** for the category chart
  *(swap-in point for Tremor if wanted — it's isolated to
  `components/category-breakdown.tsx`)*
- Auth: **Auth0** (`@auth0/nextjs-auth0` v4). `middleware.ts` runs
  `auth0.middleware()` — mounts `/auth/login|logout|callback|access-token` and
  holds an encrypted httpOnly session cookie. `app/api/proxy/[...path]` attaches
  `auth0.getAccessToken()` as the bearer to backend calls. Set up an Auth0
  tenant per [`../docs/AUTH.md`](../docs/AUTH.md).

## Run

```bash
cd web
cp .env.example .env.local          # fill AUTH0_* (see ../docs/AUTH.md) + BACKEND_URL
npm install
npm run dev                          # http://localhost:3000
```

Needs the backend running (`cd ../backend && uvicorn app.main:app --reload`)
and a Postgres (`docker compose up -d db` in `backend/`). Register at
`/auth/login` (Google / Apple / email), then scan.

## Layout

```
app/
  (app)/            authed shell — dashboard / scan / receipts
  api/proxy/[...]   bearer-injecting reverse proxy to the backend
components/ui/*     button, card, input, label, skeleton
components/*        app-nav, metric-tile, category-breakdown, insight-list, receipt-row
lib/*              api client, auth0, backend url, types, categories, format
middleware.ts       auth0.middleware() + redirects unauthed users to /auth/login
```

## Notes / not done

- `/v1/extract` currently persists on the backend, so the scan screen shows the
  result as **already saved** — there's no "edit before save" yet (needs a
  backend extract-without-persist + create, or a `PATCH /v1/receipts/{id}`).
- No optimistic UI, no pagination on the receipts list, no receipt detail page.
- Deploy target: Azure Static Web Apps (not wired yet).
