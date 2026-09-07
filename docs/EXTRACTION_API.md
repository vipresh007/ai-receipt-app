# Receipt Extraction API — contract

## Architecture

```
iOS app  ──POST /v1/extract──▶  FastAPI backend  ──▶  Azure OpenAI (vision + structured outputs)
             Bearer JWT              │  │
                                     │  └──▶ Azure Blob Storage (original image)
                                     └─────▶ PostgreSQL (Receipt + Expense)
```

The app never holds an Azure key. It calls the backend with a bearer token; the
backend calls Azure OpenAI and returns clean JSON. The backend also enforces the
freemium scan limit and persists the result.

- iOS side: [`ios/AIReceiptApp/Services/ReceiptExtractionAPIClient.swift`](../ios/AIReceiptApp/Services/ReceiptExtractionAPIClient.swift)
- Backend side: [`backend/app/api/routes/receipts.py`](../backend/app/api/routes/receipts.py) → [`services/extraction.py`](../backend/app/services/extraction.py) → [`services/azure_openai.py`](../backend/app/services/azure_openai.py)

---

## `POST /v1/extract`

`Authorization: Bearer <jwt>` required.

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
| `merchant`   | string            | `""` if not legible. |
| `date`       | string \| null    | `YYYY-MM-DD`. `null` → app uses today. |
| `total`      | string            | Decimal string, `.` separator, no symbol/grouping. `"0"` if unreadable. |
| `tax`        | string            | Decimal string. `"0"` if none shown. |
| `category`   | string            | One of the slugs below. Unknown → `other`. |
| `items`      | array             | `{ name: string, price: string, quantity: int≥1 }`. |
| `confidence` | number \| null    | 0–1, optional. |

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
| `401`  | Missing/invalid token. |
| `422`  | `imageBase64` not valid base64, or empty. |
| `429`  | Free-tier monthly scan limit reached *(planned)*. |
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

## The Azure OpenAI call

One narrow extraction call — no agent loop. Send the image (the model reads
receipt layout well) plus the OCR text as a hint, and use **structured outputs**
so the reply always validates against the schema.

### Deployment / model

Uses a vision-capable Azure OpenAI **deployment** named by
`AZURE_OPENAI_DEPLOYMENT` (default `gpt-4o`). Structured outputs need
`gpt-4o` (2024-08-06+) / `gpt-4o-mini` or newer and API version `2024-08-01-preview`
or later (`AZURE_OPENAI_API_VERSION`, default `2024-10-21`).

**Cost vs. accuracy is a deployment choice**, not a code change: `gpt-4o-mini` is
far cheaper per scan and is often enough for receipts; `gpt-4o` is more robust on
faded/creased/handwritten ones. Test on real receipts and set the deployment
name accordingly.

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
    temperature=0,
    max_tokens=1024,
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
DEPLOYMENT=gpt-4o
API_VERSION=2024-10-21

curl "$AZURE_OPENAI_ENDPOINT/openai/deployments/$DEPLOYMENT/chat/completions?api-version=$API_VERSION" \
  -H "content-type: application/json" \
  -H "api-key: $AZURE_OPENAI_API_KEY" \
  -d @- <<JSON
{
  "temperature": 0,
  "max_tokens": 1024,
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
