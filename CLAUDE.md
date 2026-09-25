# CLAUDE.md

Guidance for Claude Code working in this repo.

## What this is

**Tally** — a personal expense tracker (formerly "AI Receipt"). Core loop: photo of a receipt →
AI extracts structured data → user confirms → expense saved → dashboard +
insights. Product spec: [`docs/SPEC.md`](docs/SPEC.md). Architecture:
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Monorepo layout

| Path | What | Stack |
|------|------|-------|
| `ios/` | iOS app | Swift, SwiftUI, SwiftData, Swift Charts. XcodeGen (`project.yml`). |
| `backend/` | REST API | Python 3.12, FastAPI, SQLAlchemy 2 (async), Alembic, Pydantic v2. |
| `web/` | Web app | Next.js 15 (App Router) + TS + Tailwind 3.4 + shadcn-style `components/ui` + Recharts + TanStack Query. Full parity with iOS. |
| `org-site/` | dataeaver.ca — DATA EAVER INC. company page | One static `index.html`, no build. Azure Static Web App `dataeaver-site` (`rg-dataeaver-site`), deployed by `deploy-org-site.yml`. |
| `design/` | Shared design tokens | `tokens.json` (canonical) → `tokens.css` + `tailwind-preset.js`; language in `docs/DESIGN.md`. |
| `infra/` | Azure provisioning | `az` CLI scripts. |
| `docs/` | Specs & contracts | Markdown. |
| `.github/workflows/` | CI + CD | `ci.yml` (lint/test, path-gated) · `deploy-backend.yml` / `deploy-web.yml` (OIDC → `infra/deploy.sh`, path-gated so a one-sided change deploys one side). |

External services: **Azure OpenAI** (receipt extraction, insights),
**PostgreSQL**, **Azure Blob Storage** (receipt images), **Azure Application
Insights** (telemetry).

## iOS (`ios/`)

- Generate the Xcode project before opening: `cd ios && xcodegen generate`.
  `AIReceiptApp.xcodeproj` is git-ignored — re-run after adding/moving files.
- `AIReceiptApp/Generated/Info.plist` is generated too (ignored).
- Backend URL comes from `EXTRACTION_API_HOST` in `ios/Config/Secrets.xcconfig`
  (git-ignored; copy from `Secrets.example.xcconfig`). With it unset, the app
  uses `MockReceiptExtractor` and the whole flow still runs.
- Local-first auth: the app runs anonymously (device UUID → `X-Device-Id`, capped
  free scans); optional Auth0 Universal Login (`Auth0` SPM package, `AuthManager`
  — Google + email/password) unlocks the web app. On sign-in, local receipts are
  imported and then `AccountSync` keeps SwiftData reconciled with the account
  (`pull()` on launch/foreground/refresh; create/edit/delete pushed). Auth0
  config (`AUTH0_*`, public native client) lives in `Config/AIReceiptApp.xcconfig`;
  empty → the Account screen just hides sign-in. See [`docs/AUTH.md`](docs/AUTH.md).
- Build/test locally needs full Xcode (App Store). CI verifies every push.
- Test: `xcodebuild test -scheme AIReceiptApp -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'`
  (adjust the simulator name to whatever's installed locally — Xcode drops
  older models from `xcodebuild -destination` support on each major update).

## Web (`web/`)

- Node 20+. `cd web && cp .env.example .env.local && npm install && npm run dev`
  (needs the backend + its Postgres running). Build/lint: `npm run build`, `npm run lint`.
- Design tokens: `design/tokens.css` is copied to `web/app/tokens.css` by
  `scripts/sync-tokens.mjs` on `predev`/`prebuild` (that file is git-ignored).
  `tailwind.config.ts` pulls in `../design/tailwind-preset.js`.
- Auth: **Auth0** (`@auth0/nextjs-auth0` v4). `lib/auth0.ts` + `middleware.ts`
  (`auth0.middleware()` auto-mounts `/auth/login|logout|callback|access-token`
  and holds an encrypted httpOnly session cookie). `app/api/proxy/[...path]`
  attaches `auth0.getAccessToken()` as the bearer. Route protection in
  `middleware.ts` + `app/(app)/layout.tsx`. Full setup: [`docs/AUTH.md`](docs/AUTH.md).
- Keep `lib/types.ts` in sync with `backend/app/schemas`.
- The scan screen shows results as already-saved (backend `/v1/extract`
  persists). Merchant/date/category/total/tax/line-items are all editable
  after the fact via `PATCH /v1/receipts/{id}` — `/receipts/[id]/page.tsx` on
  web, `ReceiptDetailView` on iOS.

## Backend (`backend/`)

- Python **3.12** (`brew install python@3.12`). Setup:
  ```bash
  cd backend
  python3.12 -m venv .venv && .venv/bin/pip install -e ".[dev]"
  cp .env.example .env
  ```
- Run: `.venv/bin/uvicorn app.main:app --reload` (docs at `/docs`).
- Local Postgres: `docker compose up db` (or full stack: `docker compose up`).
- Migrations: `.venv/bin/alembic upgrade head`. With `AUTO_CREATE_TABLES=true`
  (default) the app also creates tables on startup for convenience.
- Lint/format/test (all must pass in CI):
  ```bash
  .venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/pytest -q
  ```
- Tests use in-memory SQLite + dependency overrides — **no Postgres or Azure
  needed**. `FakeExtractor` stands in for Azure OpenAI.

### Backend conventions

- Layout: `app/api/routes/*` (thin) → `app/services/*` (logic) → `app/models/*`
  (SQLAlchemy) / `app/schemas/*` (Pydantic).
- Money is **decimal strings** on every wire boundary (LLM output, REST JSON) and
  `Decimal` / `Numeric(12,2)` internally. Never floats.
- Category slugs are shared with the iOS `ExpenseCategory` raw values — keep the
  list in `app/models/category.py`, `app/schemas/extraction.py`, and the iOS enum
  in sync.
- `get_settings()` is `lru_cache`d; never read env directly elsewhere. Tests set
  `AI_RECEIPT_TEST=1` (in `conftest.py`) so `Settings` skips `.env`.
- Auth: **Auth0** issues tokens, the backend verifies them.
  `core/security.verify_access_token` (PyJWT + JWKS) → `api/deps.get_current_user`
  upserts a `users` row keyed by `auth0_sub`. No passwords, no token minting.
  Endpoints: `GET /v1/auth/me`, `DELETE /v1/auth/me` (account deletion — wipes
  the user's rows + Blob images). See [`docs/AUTH.md`](docs/AUTH.md).
- The Azure OpenAI call is `client.chat.completions.parse(..., response_format=ExtractedReceipt)`
  (structured outputs). `tests/test_azure_openai_wiring.py` guards the SDK path.

## The iOS ⇄ backend contract

`POST /v1/extract` (parse; persists for signed-in) plus the receipt CRUD
(`GET/POST /v1/receipts`, `PATCH/DELETE /v1/receipts/{id}`, `GET
/v1/receipts/{id}/image`, `POST /v1/receipts/import`) that iOS sync uses.
`GET /v1/receipts` also takes `month`, `q` (merchant + line-item search),
`category`, `min_amount`/`max_amount`. Beyond the core loop: `GET
/v1/receipts/recurring` (same-merchant-across-months detection, mirrored in
`app/services/recurring.py` and iOS's `RecurringDetector`), `GET /v1/expenses/
summary|trend`, and `GET/PUT/DELETE /v1/budgets/{category}` (per-category
monthly limits). Request/response shapes and the Azure OpenAI prompt live in
[`docs/EXTRACTION_API.md`](docs/EXTRACTION_API.md). The iOS side is
`ios/AIReceiptApp/Services/ReceiptExtractionAPIClient.swift`; the backend side is
`backend/app/api/routes/receipts.py` + `services/extraction.py`. Change both
together.

## Conventions

- Commit messages end with the `Co-Authored-By` trailer.
- Don't commit `.env`, `Secrets.xcconfig`, or generated Xcode files.
- Keep `docs/EXTRACTION_API.md` in sync whenever the extract request/response
  changes.
