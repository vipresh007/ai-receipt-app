# CLAUDE.md

Guidance for Claude Code working in this repo.

## What this is

**AI Receipt** — a personal expense tracker. Core loop: photo of a receipt →
AI extracts structured data → user confirms → expense saved → dashboard +
insights. Product spec: [`docs/SPEC.md`](docs/SPEC.md). Architecture:
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Monorepo layout

| Path | What | Stack |
|------|------|-------|
| `ios/` | iOS app | Swift, SwiftUI, SwiftData, Swift Charts. XcodeGen (`project.yml`). |
| `backend/` | REST API | Python 3.12, FastAPI, SQLAlchemy 2 (async), Alembic, Pydantic v2. |
| `web/` | Web app *(planned)* | Next.js + TS + Tailwind + shadcn/ui + Tremor, full parity with iOS. |
| `design/` | Shared design tokens | `tokens.json` (canonical) → `tokens.css` + `tailwind-preset.js`; language in `docs/DESIGN.md`. |
| `infra/` | Azure provisioning | `az` CLI scripts. |
| `docs/` | Specs & contracts | Markdown. |
| `.github/workflows/ci.yml` | CI | `ios` (macOS) + `backend` (ubuntu) jobs, each gated by a `dorny/paths-filter` so a one-sided change only runs that job. |

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
- Build/test locally needs full Xcode (App Store). CI verifies every push.
- Test: `xcodebuild test -scheme AIReceiptApp -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'`

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
- `get_settings()` is `lru_cache`d; never read env directly elsewhere.
- The Azure OpenAI call is `client.chat.completions.parse(..., response_format=ExtractedReceipt)`
  (structured outputs). `tests/test_azure_openai_wiring.py` guards the SDK path.

## The iOS ⇄ backend contract

`POST /v1/extract` — the one endpoint both sides must agree on. Request/response
shapes and the Azure OpenAI prompt live in
[`docs/EXTRACTION_API.md`](docs/EXTRACTION_API.md). The iOS side is
`ios/AIReceiptApp/Services/ReceiptExtractionAPIClient.swift`; the backend side is
`backend/app/api/routes/receipts.py` + `services/extraction.py`. Change both
together.

## Conventions

- Commit messages end with the `Co-Authored-By` trailer.
- Don't commit `.env`, `Secrets.xcconfig`, or generated Xcode files.
- Keep `docs/EXTRACTION_API.md` in sync whenever the extract request/response
  changes.
