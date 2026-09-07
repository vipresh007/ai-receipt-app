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
- Auth: the backend JWT is stored in an **httpOnly `session` cookie** by
  `app/api/auth/*` route handlers; `app/api/proxy/[...path]` forwards browser
  calls to the backend with the bearer attached. The token never reaches client
  JS.

## Run

```bash
cd web
cp .env.example .env.local          # BACKEND_URL=http://localhost:8000
npm install
npm run dev                          # http://localhost:3000
```

Needs the backend running (`cd ../backend && uvicorn app.main:app --reload`)
and a Postgres (`docker compose up -d db` in `backend/`). Register at
`/register`, then scan.

## Layout

```
app/
  (app)/            authed shell — dashboard / scan / receipts
  login, register   AuthForm
  api/auth/*        login / register (set cookie) / logout
  api/proxy/[...]   bearer-injecting reverse proxy to the backend
components/ui/*     button, card, input, label, skeleton
components/*        app-nav, metric-tile, category-breakdown, insight-list, receipt-row
lib/*              api client, session (server), types, categories, format
middleware.ts       redirects unauthed users to /login
```

## Notes / not done

- `/v1/extract` currently persists on the backend, so the scan screen shows the
  result as **already saved** — there's no "edit before save" yet (needs a
  backend extract-without-persist + create, or a `PATCH /v1/receipts/{id}`).
- No optimistic UI, no pagination on the receipts list, no receipt detail page.
- Deploy target: Azure Static Web Apps (not wired yet).
