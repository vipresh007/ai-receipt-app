# AI Receipt — backend

FastAPI service: auth, receipt extraction (Azure OpenAI), expenses, insights.

## Requirements

- Python **3.12** (`brew install python@3.12`)
- Docker (for local Postgres), or a Postgres you point `DATABASE_URL` at
- Optional: Azure OpenAI + Blob + App Insights credentials (unset ⇒ those paths
  are skipped / mocked)

## Setup

```bash
cd backend
python3.12 -m venv .venv
.venv/bin/pip install -e ".[dev]"
cp .env.example .env            # then fill in as needed
```

## Run

```bash
# Postgres only, app from your venv (hot reload)
docker compose up -d db
.venv/bin/alembic upgrade head          # or rely on AUTO_CREATE_TABLES=true
.venv/bin/uvicorn app.main:app --reload

# …or the whole stack in Docker
docker compose up --build
```

- API docs: <http://localhost:8000/docs>
- Health: <http://localhost:8000/healthz>

## Test / lint

```bash
.venv/bin/ruff check .
.venv/bin/ruff format --check .
.venv/bin/pytest -q
```

Tests run on in-memory SQLite with dependency overrides — **no Postgres, no
Azure, no network**. `FakeExtractor` (in `tests/conftest.py`) stands in for
Azure OpenAI.

## Layout

```
app/
  main.py             FastAPI app, router wiring, lifespan
  config.py           Settings (pydantic-settings) — get_settings() everywhere
  db.py               async engine / session / create_all
  telemetry.py        Azure Application Insights (best-effort, never fatal)
  core/security.py    bcrypt + JWT
  models/             SQLAlchemy 2.0 ORM (users, receipts, expenses, categories, insights)
  schemas/            Pydantic v2 request/response + the LLM contract (extraction.py)
  api/
    deps.py           get_current_user, get_extractor
    routes/           health, auth, receipts (+ /extract), expenses, insights
  services/
    azure_openai.py   AzureOpenAIExtractor — chat.completions.parse, strict schema
    blob_storage.py   receipt image upload
    extraction.py     orchestration: blob → OpenAI → persist Receipt + Expense
    insights.py       rule-based month-over-month insights
alembic/              migrations (0001_initial covers all tables)
tests/
```

## Endpoints (v1)

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET  | `/healthz` | – | status + which integrations are configured |
| POST | `/v1/auth/register` | – | → `{ access_token, token_type, expires_in }` |
| POST | `/v1/auth/login` | – | → same |
| POST | `/v1/extract` | ✅ | the iOS contract — see [`docs/EXTRACTION_API.md`](../docs/EXTRACTION_API.md) |
| GET  | `/v1/receipts` | ✅ | recent receipts |
| GET  | `/v1/expenses` | ✅ | recent expenses |
| GET  | `/v1/expenses/summary` | ✅ | month total + by-category + prev month |
| GET  | `/v1/insights` | ✅ | stored insights |
| POST | `/v1/insights/generate` | ✅ | run rule-based generation now |

## Not done yet

- Free-tier scan-limit enforcement on `/v1/extract` (`# TODO` in the route)
- `POST /v1/receipts` to persist a user-confirmed receipt as source of truth
- Azure OpenAI NL insights (`generated_by="azure_openai"`)
- Rate limiting, refresh tokens, structured request logging
