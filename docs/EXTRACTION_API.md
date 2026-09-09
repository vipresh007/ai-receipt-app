# Receipt Extraction API — contract

## Architecture

```
iOS app  ──POST /v1/extract──▶  FastAPI backend  ──▶  Azure OpenAI (vision + structured outputs)
     Bearer JWT  *or*  X-Device-Id    │  │
                                      │  └──▶ Azure Blob Storage (original image)  ┐ signed-in
                                      └─────▶ PostgreSQL (Receipt + Expense)       ┘ only
```

The app never holds an Azure key. It calls the backend with a bearer token *or*,
when the user hasn't signed in, an `X-Device-Id`; the backend calls Azure OpenAI
and returns clean JSON. For signed-in users it also enforces the freemium scan
limit and persists the result; anonymous parses are rate-limited per device and
not stored.

- iOS side: [`ios/AIReceiptApp/Services/ReceiptExtractionAPIClient.swift`](../ios/AIReceiptApp/Services/ReceiptExtractionAPIClient.swift)
- Backend side: [`backend/app/api/routes/receipts.py`](../backend/app/api/routes/receipts.py) → [`services/extraction.py`](../backend/app/services/extraction.py) → [`services/azure_openai.py`](../backend/app/services/azure_openai.py)

---

## `POST /v1/extract`

**Auth is optional.** The iOS app is local-first (see
[`AUTH.md`](AUTH.md#ios--local-first-optional-sign-in)):

| Caller | Header | Behaviour |
|---|---|---|
| Signed in | `Authorization: Bearer <jwt>` | Parses, persists `Receipt` + `Expense`, uploads the image to Blob. `scans_remaining` is `null`. |
| Anonymous | `X-Device-Id: <uuid>` (required) | Parses and returns — **nothing is persisted server-side**. Counts against a per-device free allowance (`anon_scan_limit`, default 15); `scans_remaining` reports what's left. |

An anonymous call with no `X-Device-Id` is `400`. Once the allowance is spent the
endpoint returns `402` (the app shows a soft wall — history stays readable, the
shutter is disabled).

### Request (JSON, camelCase — from the iOS client)

| Field             | Type       | Notes |
|-------------------|------------|-------|
| `imageBase64`     | string     | JPEG bytes, base64 (no data-URI prefix). ~0.7 quality from the app. |
| `ocrLines`        | string[]   | On-device Vision OCR lines. Noisy/possibly empty — a hint, not ground truth. |
| `clientRequestID` | string     | UUID. Idempotency / dedupe / correlation in logs + blob name. |

```json
{
  "imageBase64": "/9j/4AAQSkZJRg...",
  "ocrLines": ["WHOLE FOODS MARKET", "BANANAS 1.79", "TOTAL 22.79"],
  "clientRequestID": "6C1B9E2A-1F3D-4B0A-9E7C-2A1F3D4B0A9E"
}
```

### Response `200` (JSON)

| Field        | Type              | Notes |
|--------------|-------------------|-------|
| `id`         | string \| null    | Signed-in only — id of the `Receipt` row the backend just created, so the client can correlate / `PATCH` / `DELETE` it. `null` for anonymous. |
| `merchant`   | string            | `""` if not legible. |
| `date`       | string \| null    | `YYYY-MM-DD`. `null` → app uses today. |
| `total`      | string            | Decimal string, `.` separator, no symbol/grouping. `"0"` if unreadable. |
| `tax`        | string            | Decimal string. `"0"` if none shown. |
| `category`   | string            | One of the slugs below. Unknown → `other`. |
| `items`      | array             | `{ name: string, price: string, quantity: int≥1 }`. |
| `confidence` | number \| null    | 0–1, optional. |
| `scans_remaining` | int \| null   | Anonymous only — free scans left for this device after this call. `null` when signed in. |

```json
{
  "merchant": "Whole Foods Market",
  "date": "2026-09-01",
  "total": "22.79",
  "tax": "1.34",
  "category": "groceries",
  "items": [
    { "name": "Bananas", "price": "1.79", "quantity": 1 },
    { "name": "Oat milk", "price": "4.29", "quantity": 1 }
  ],
  "confidence": 0.92
}
```

### Errors

| Status | Meaning |
|--------|---------|
| `400`  | Anonymous call missing the `X-Device-Id` header. |
| `401`  | Bearer token present but invalid/expired. |
| `402`  | Anonymous device has used all its free scans — sign in to continue. |
| `422`  | `imageBase64` not valid base64, or empty. |
| `429`  | Anonymous: too many calls from this client IP this hour (`anon_ip_hourly_limit`, default 60). Signed-in monthly limit is *planned*. |
| `502`  | Azure OpenAI unavailable or returned nothing usable. |

Body: `{ "detail": "Human-readable message" }` — the iOS client shows `detail`
verbatim, so keep it user-appropriate.

### Category vocabulary

Matches the iOS `ExpenseCategory` raw values and `backend/app/models/category.py`:

```
groceries  restaurants  transport  shopping  entertainment
health     utilities    travel     other
```

---

## `POST /v1/receipts/import`

`Authorization: Bearer <jwt>` **required**. Called once, right after an
anonymous iOS user signs in, to migrate their on-device receipts into the
account. See [`AUTH.md`](AUTH.md#sign-in--migration-flow).

### Request (JSON)

```json
{
  "receipts": [
    {
      "merchant": "Corner Store",
      "date": "2026-09-03",
      "total": "9.99",
      "tax": "0.80",
      "category": "groceries",
      "currency": "USD",
      "items": [{ "name": "Milk", "price": "3.50", "quantity": 1 }],
      "imageBase64": "/9j/4AAQ..."
    }
  ]
}
```

Every field except `merchant`/`total` has a fallback (`date`→null, `tax`→`"0"`,
`category`→`other`, `currency`→`USD`, `items`→`[]`). `imageBase64` is optional;
when present the backend uploads it to Blob (best-effort — a failed upload
doesn't fail the import).

### Response `201`

`ReceiptOut[]` — the created rows, same shape as `GET /v1/receipts` items. One
`Receipt` + one `Expense` are created per input item. After this the app refills
its SwiftData cache from `GET /v1/receipts` and treats the backend as the source
of truth.

---

## Receipt CRUD (bearer only)

Used by the signed-in iOS app to keep its local store in step with the account
(`AccountSync`). Web reads the list; it doesn't use these yet.

| Method & path | Body | Response | Notes |
|---|---|---|---|
| `GET /v1/receipts?limit=&month=` | — | `ReceiptOut[]` | Newest first. `month=YYYY-MM` filters by purchase date. iOS pulls the unfiltered list to reconcile; the dashboard uses `month`. |
| `GET /v1/receipts/{id}/image` | — | `image/jpeg` bytes | The stored receipt photo, so a device that pulled the row (bytes never sync between devices) can show it. `404` when there's no image. `Cache-Control: private, max-age=86400`. |
| `POST /v1/receipts` | `ReceiptCreate` (same shape as one import item) | `201 ReceiptOut` | Creates the `Receipt` + its `Expense`. |
| `PATCH /v1/receipts/{id}` | partial: `merchant, date, total, tax, category, items` — only keys sent change | `200 ReceiptOut` | Keeps the linked `Expense` (amount/merchant/category/date) in sync. `404` if not the caller's. |
| `DELETE /v1/receipts/{id}` | — | `204` | Removes the receipt and its expense. `404` if not the caller's. |

`ReceiptOut` (snake_case on the wire): `id, merchant, purchased_at, total, tax,
currency, category_slug, image_blob_url, extraction_confidence, line_items`.

**`GET /v1/expenses/summary?month=YYYY-MM`** (bearer) returns that month's
`total`, `by_category`, and the month-before total (`previous_month_total`),
plus `earliest_month` (YYYY-MM of the oldest expense) so a month-stepper knows
how far back to allow. `month` defaults to the current month; an unparseable
value falls back to it. Both the iOS and web dashboards use this to browse
past months.

---

## The Azure OpenAI call

One narrow extraction call — no agent loop. Send the image (the model reads
receipt layout well) plus the OCR text as a hint, and use **structured outputs**
so the reply always validates against the schema.

### Deployment / model

Uses a vision-capable Azure OpenAI **deployment** named by
`AZURE_OPENAI_DEPLOYMENT` (default `gpt-5-mini`, version `2025-08-07`, SKU
`GlobalStandard`) with `AZURE_OPENAI_API_VERSION` `2025-04-01-preview` or later.

> `gpt-4o` / `gpt-4o-mini` are **deprecated** on Azure OpenAI — the current small
> multimodal tier is the `gpt-5-mini` family.

**Cost vs. accuracy is a deployment choice**, not a code change: `gpt-5-nano` is
cheapest and often enough for clean receipts; `gpt-5-mini` is the balanced
default; `gpt-5` is most robust on faded/creased/handwritten ones. Test on real
receipts and set the deployment name accordingly.

Note: `gpt-5*` are reasoning models — they reject `temperature` ≠ 1 and use
`max_completion_tokens` (not `max_tokens`). The code below reflects that.

### Code (`backend/app/services/azure_openai.py`)

```python
from openai import AzureOpenAI
from app.schemas.extraction import ExtractedReceipt

client = AzureOpenAI(
    azure_endpoint=settings.azure_openai_endpoint,
    api_key=settings.azure_openai_api_key,
    api_version=settings.azure_openai_api_version,
)

completion = client.chat.completions.parse(
    model=settings.azure_openai_deployment,   # = the *deployment* name
    max_completion_tokens=4096,               # reasoning tokens + JSON payload
    messages=[
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": [
            {"type": "text", "text": f"Extract this receipt. OCR lines (may be wrong/empty):\n<ocr>\n{ocr}\n</ocr>"},
            {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"}},
        ]},
    ],
    response_format=ExtractedReceipt,   # Pydantic model → strict JSON schema
)
receipt = completion.choices[0].message.parsed   # -> ExtractedReceipt | None
```

`ExtractedReceipt` (money as decimal strings, `extra="forbid"`, category is a
`Literal` of the slugs) is the single source of truth for the schema —
`backend/app/schemas/extraction.py`.

### System prompt

> You extract structured data from receipt photos for an expense tracker.
> Transcribe only what is visible in the image; the OCR text is a noisy aid, not
> ground truth. Never invent a merchant, amount, or date — if a field is not
> legible use the empty/zero/null fallback described by the schema. Amounts are
> decimal strings using a period as the decimal separator, with no currency
> symbol and no thousands separators. Dates are YYYY-MM-DD. Choose the single
> best-fitting category from the allowed list.

### `curl` (raw REST equivalent)

```bash
IMAGE_B64=$(base64 -i receipt.jpg | tr -d '\n')
DEPLOYMENT=gpt-5-mini
API_VERSION=2025-04-01-preview

curl "$AZURE_OPENAI_ENDPOINT/openai/deployments/$DEPLOYMENT/chat/completions?api-version=$API_VERSION" \
  -H "content-type: application/json" \
  -H "api-key: $AZURE_OPENAI_API_KEY" \
  -d @- <<JSON
{
  "max_completion_tokens": 4096,
  "messages": [
    { "role": "system", "content": "…system prompt above…" },
    { "role": "user", "content": [
      { "type": "text", "text": "Extract this receipt. OCR lines:\n<ocr>\nWHOLE FOODS MARKET\nTOTAL 22.79\n</ocr>" },
      { "type": "image_url", "image_url": { "url": "data:image/jpeg;base64,$IMAGE_B64" } }
    ]}
  ],
  "response_format": {
    "type": "json_schema",
    "json_schema": {
      "name": "extracted_receipt",
      "strict": true,
      "schema": {
        "type": "object",
        "additionalProperties": false,
        "required": ["merchant", "purchased_at", "total", "tax", "category", "currency", "line_items", "confidence"],
        "properties": {
          "merchant":     { "type": "string" },
          "purchased_at": { "type": ["string", "null"] },
          "total":        { "type": "string" },
          "tax":          { "type": "string" },
          "currency":     { "type": "string" },
          "category":     { "type": "string", "enum": ["groceries","restaurants","transport","shopping","entertainment","health","utilities","travel","other"] },
          "confidence":   { "type": ["number", "null"] },
          "line_items": {
            "type": "array",
            "items": {
              "type": "object",
              "additionalProperties": false,
              "required": ["name", "price", "quantity"],
              "properties": {
                "name":     { "type": "string" },
                "price":    { "type": "string" },
                "quantity": { "type": "integer" }
              }
            }
          }
        }
      }
    }
  }
}
JSON
```

---

## Operational notes

- **Auth + free-scan limit** live on the backend, never the app.
- **`clientRequestID`** dedupes retries so a user isn't charged a scan twice, and
  names the blob (`<user_id>/<clientRequestID>.jpg`).
- **Image retention** is a deliberate choice — images are PII. Blob upload is
  best-effort; extraction still succeeds if it fails.
- **App Insights**: wrap the Azure OpenAI call in a span; record token usage from
  `completion.usage` for cost tracking.
- **Localization**: `total`/`tax` are always `.`-decimal machine strings on the
  wire; the iOS app formats them per the user's locale.
