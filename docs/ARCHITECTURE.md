# Architecture

```
                          iPhone
                     Swift / SwiftUI
                  (camera, confirm, dashboard)
                            │  HTTPS + Bearer JWT
                            ▼
                     Python FastAPI  ── Azure Application Insights
                   (REST, auth, business logic)      (errors, AI latency/cost, usage)
                            │
             ┌──────────────┼───────────────┐
             ▼              ▼                ▼
       PostgreSQL     Azure OpenAI     Azure Blob Storage
   users, receipts,  receipt → struct   original receipt
   expenses, cats,   categorization     images
   insights          insights
                            │
                            ▼
                   Structured expense
                            │
                            ▼
                     AI insights
```

## Components

| Layer | Tech | Responsibility |
|-------|------|----------------|
| **Client** | Swift / SwiftUI (`ios/`) | Capture or pick a receipt image, on-device OCR for hint text, confirm/edit screen, expense dashboard, insights. Talks only to the backend. |
| **API** | Python 3.12 + FastAPI (`backend/`) | REST API, JWT auth, receipt-processing orchestration, expense/category/insight logic, freemium scan limits. |
| **AI** | Azure OpenAI (vision + structured outputs) | Receipt image → `ExtractedReceipt` JSON. Later: richer NL insights, financial agents. |
| **Database** | PostgreSQL | `users`, `receipts`, `expenses`, `categories`, `insights`. |
| **Object storage** | Azure Blob Storage | Original receipt images (`<user_id>/<request_id>.jpg`). |
| **Monitoring** | Azure Application Insights | API errors, AI call latency/cost, usage metrics (OpenTelemetry). |

## Request flow: scanning a receipt

1. iOS captures/loads a `UIImage`, runs Vision OCR for hint lines.
2. `POST /v1/extract` with `{ imageBase64, ocrLines, clientRequestID }` + `Authorization: Bearer <jwt>`.
3. Backend (`services/extraction.process_receipt`):
   1. uploads the image to Blob Storage (best-effort),
   2. calls Azure OpenAI (`chat.completions.parse`, strict `ExtractedReceipt`),
   3. persists a `Receipt` + derived `Expense`.
4. Backend returns the extraction JSON (`merchant, date, total, tax, category, items, confidence`).
5. iOS shows the confirm screen; on save it currently writes to local SwiftData.
   *(Planned: `POST /v1/receipts` to persist server-side as the source of truth,
   with SwiftData as an offline cache.)*

## Data model (backend)

- **User** — email, hashed password, `plan` (`free` | `pro`).
- **Receipt** — merchant, purchased_at, total, tax, currency, category_slug,
  `image_blob_url`, `raw_ocr`, `extraction_confidence`, `line_items` (JSON).
- **Expense** — normalized spend row; `receipt_id` nullable (manual entries
  allowed); merchant, amount, category_slug, spent_at.
- **Category** — slug + name; `user_id` NULL = system default.
- **Insight** — kind (`up`/`down`/`streak`/`summary`), message, period,
  `generated_by` (`rules` | `azure_openai`).

## Environments

- **Local**: `docker compose up` (FastAPI + Postgres). Azure OpenAI / Blob /
  App Insights are optional — unset means "skip" (mock paths, no telemetry).
- **Cloud**: see [`infra/`](../infra) for the `az` provisioning scripts.

## Open decisions

- Hosting for the FastAPI app (Azure Container Apps vs. App Service).
- Azure OpenAI model/deployment (`gpt-5-mini` vs. `gpt-5-nano` vs. `gpt-5`) — cost vs. accuracy
  on real receipts, see [`docs/EXTRACTION_API.md`](EXTRACTION_API.md).
- Auth: home-grown JWT now; consider Azure AD B2C / Entra External ID later.
- Server-side receipt persistence + sync protocol with the iOS SwiftData cache.
