# AI Receipt

[![CI](https://github.com/vipresh007/ai-receipt-app/actions/workflows/ci.yml/badge.svg)](https://github.com/vipresh007/ai-receipt-app/actions/workflows/ci.yml)

Snap a photo of a receipt → AI reads it → the expense is saved and categorized.

A personal expense tracker built around one core action. The MVP goal: make
expense tracking *easier than manually entering a transaction*.

- Product spec — [`docs/SPEC.md`](docs/SPEC.md)
- Architecture & stack — [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- iOS ⇄ backend extraction contract — [`docs/EXTRACTION_API.md`](docs/EXTRACTION_API.md)
- Working in this repo with Claude Code — [`CLAUDE.md`](CLAUDE.md)

## Monorepo

| Path | What | Stack | README |
|------|------|-------|--------|
| [`ios/`](ios) | iOS app | Swift · SwiftUI · SwiftData · Swift Charts · XcodeGen | [ios/README.md](ios/README.md) |
| [`backend/`](backend) | REST API | Python 3.12 · FastAPI · SQLAlchemy 2 (async) · Alembic | [backend/README.md](backend/README.md) |
| [`infra/`](infra) | Azure provisioning | `az` CLI scripts | [infra/README.md](infra/README.md) |
| [`docs/`](docs) | Specs & contracts | — | — |

**External services:** Azure OpenAI (extraction, insights) · PostgreSQL · Azure
Blob Storage (receipt images) · Azure Application Insights (telemetry).

## Quick start

**iOS** (needs Xcode):
```bash
cd ios && xcodegen generate && open AIReceiptApp.xcodeproj
```

**Backend** (needs Python 3.12 + Docker):
```bash
cd backend
python3.12 -m venv .venv && .venv/bin/pip install -e ".[dev]"
cp .env.example .env
docker compose up -d db
.venv/bin/uvicorn app.main:app --reload      # http://localhost:8000/docs
```

## Status

- **iOS** — full capture → confirm → save → dashboard flow, runs on
  `MockReceiptExtractor` with no backend; switches to the real API when
  `EXTRACTION_API_HOST` is set. Builds + tests green in CI.
- **Backend** — FastAPI skeleton: auth (JWT), `POST /v1/extract` (Azure OpenAI
  structured outputs), receipts/expenses/insights, SQLAlchemy models + Alembic,
  Dockerized, tests on SQLite (no Azure needed). Lint + tests green in CI.
- **Infra** — `az` scripts under [`infra/`](infra).

## Roadmap

- [x] iOS scaffold + extraction client
- [x] FastAPI backend skeleton (auth, extract, models, migrations, tests)
- [x] CI: iOS + backend
- [ ] Provision Azure resources & deploy the backend
- [ ] iOS sign-in flow → real bearer token on `/v1/extract`
- [ ] Server-side receipt persistence + SwiftData sync
- [ ] Free-tier scan limit + paywall (freemium)
- [ ] Azure OpenAI natural-language insights
- [ ] CSV / PDF export; shared expenses; bank syncing (later)

## Business model (planned)

Freemium: free users get a limited number of receipt scans per month; a paid
tier unlocks unlimited scanning, advanced insights, exports, shared expenses,
and eventually bank syncing.

---

© 2026. All rights reserved.
