# Receipt Extraction API — contract

## Architecture

```
iOS app  ──POST /v1/extract──▶  your backend  ──▶  Claude (Anthropic API)
                                     │
                              holds ANTHROPIC_API_KEY
```

The app never holds an LLM API key. It calls **your** backend; the backend calls
Claude and returns clean JSON. The backend is also where you enforce the
freemium scan limit, rate-limit abuse, and (optionally) store receipt images.

The iOS side of this contract is implemented in
[`ReceiptExtractionAPIClient.swift`](../AIReceiptApp/Services/ReceiptExtractionAPIClient.swift).

---

## `POST /v1/extract`

### Request (JSON)

| Field             | Type       | Notes |
|-------------------|------------|-------|
| `imageBase64`     | string     | JPEG bytes, base64. ~0.7 quality from the app. |
| `ocrLines`        | string[]   | On-device Vision OCR lines. May be noisy or empty — context only. |
| `clientRequestID` | string     | UUID. Use for idempotency / dedupe / logging. |

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
| `tax`        | string \| null    | Decimal string. `null`/absent → `0`. |
| `category`   | string \| null    | One of the enum below. Unknown/absent → `other`. |
| `items`      | array \| null     | `{ name: string, price: string, quantity?: int≥1 }`. |
| `confidence` | number \| null    | 0–1, optional. The app may use it later to flag low-confidence scans. |

```json
{
  "merchant": "Whole Foods Market",
  "date": "2026-09-01",
  "total": "22.79",
  "tax": "1.34",
  "category": "groceries",
  "items": [
    { "name": "Bananas", "price": "1.79", "quantity": 1 },
    { "name": "Oat milk", "price": "4.29" }
  ],
  "confidence": 0.92
}
```

### Error (non-2xx, JSON)

```json
{ "error": "Human-readable message shown to the user." }
```

The app surfaces `error` verbatim in an alert, so keep it user-appropriate
(no stack traces, no key material).

### Category vocabulary

Must match `ExpenseCategory` raw values exactly:

```
groceries  restaurants  transport  shopping  entertainment
health     utilities    travel     other
```

---

## The Claude call (reference)

Receipt reading is a **single, narrow extraction call** — no agent loop. Send
the image (Claude reads receipt layout well) plus the OCR text as a hint, and
force a single tool call so the reply is always schema-valid JSON.

### Model choice is yours

The example uses `claude-opus-5` (Anthropic's default recommendation). This is a
high-volume, narrow task, so many teams run a cheaper model to control cost —
measure extraction accuracy on your own receipts first, then pick:

| Model             | Input $/1M | Output $/1M |
|-------------------|-----------:|------------:|
| `claude-haiku-4-5`  | $1  | $5  |
| `claude-sonnet-5`   | $2  | $10 |
| `claude-opus-5`     | $5  | $25 |

Per call the token count is small (one image + a short schema + a short JSON
reply), so even Opus is cents-scale — but it adds up across a free tier. Switch
by changing the `model` string; the contract above does not change.

### Request shape

- **Force the tool call:** `tool_choice: { "type": "tool", "name": "save_receipt" }`
  with `strict: true` on the tool → arguments always validate against the schema.
- **Keep effort low:** `output_config: { "effort": "low" }`. Extraction doesn't
  need deep reasoning; low effort is faster and cheaper. (Leave `thinking` at its
  default — adaptive — rather than disabling it.)
- **Small `max_tokens`** (~1024) — the reply is just the tool arguments.
- **Cache the stable prefix:** put `cache_control: { "type": "ephemeral" }` on the
  tool definition (or the system block). The tool schema + system prompt are
  identical on every request, so you pay full input price once per ~5 min window
  and a large discount after.

### `curl`

```bash
IMAGE_B64=$(base64 -i receipt.jpg | tr -d '\n')

curl https://api.anthropic.com/v1/messages \
  -H "content-type: application/json" \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d @- <<JSON
{
  "model": "claude-opus-5",
  "max_tokens": 1024,
  "output_config": { "effort": "low" },
  "tool_choice": { "type": "tool", "name": "save_receipt" },
  "tools": [{
    "name": "save_receipt",
    "description": "Record the data read from a receipt image.",
    "strict": true,
    "cache_control": { "type": "ephemeral" },
    "input_schema": {
      "type": "object",
      "additionalProperties": false,
      "required": ["merchant", "date", "total", "tax", "category", "items"],
      "properties": {
        "merchant": { "type": "string", "description": "Store name. \"\" if not legible." },
        "date":     { "type": ["string", "null"], "description": "Purchase date YYYY-MM-DD, or null." },
        "total":    { "type": "string", "description": "Grand total, decimal string e.g. \"24.99\". \"0\" if unreadable." },
        "tax":      { "type": "string", "description": "Tax amount, decimal string. \"0\" if none shown." },
        "category": {
          "type": "string",
          "enum": ["groceries","restaurants","transport","shopping","entertainment","health","utilities","travel","other"]
        },
        "items": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["name", "price"],
            "properties": {
              "name":     { "type": "string" },
              "price":    { "type": "string", "description": "Line price, decimal string." },
              "quantity": { "type": "integer", "minimum": 1 }
            }
          }
        }
      }
    }
  }],
  "system": "You extract structured data from receipt photos for an expense tracker. Transcribe only what is visible in the image; the OCR text is a noisy aid, not ground truth. Never invent a merchant, amount, or date — if a field is not legible use the empty/zero/null fallback described in the schema. Amounts are decimal strings using a period as the decimal separator, with no currency symbol and no thousands separators. Pick the single best-fitting category from the enum.",
  "messages": [{
    "role": "user",
    "content": [
      { "type": "image", "source": { "type": "base64", "media_type": "image/jpeg", "data": "$IMAGE_B64" } },
      { "type": "text", "text": "Extract this receipt. OCR lines (may be empty / wrong):\n<ocr>\nWHOLE FOODS MARKET\nBANANAS 1.79\nOAT MILK 4.29\nTOTAL 22.79\n</ocr>" }
    ]
  }]
}
JSON
```

### Reading the reply

The tool arguments are the response payload — map them straight to the
`/v1/extract` response body:

```bash
echo "$response" | jq -c '.content[] | select(.type == "tool_use") | .input'
```

Guard before trusting `content`: if `.stop_reason == "refusal"` (rare for this
task), return a friendly `error` instead. Check `.usage.cache_read_input_tokens`
to confirm prefix caching is working.

---

## Minimal backend (Cloudflare Workers sketch)

Fastest way to stand this up with the key server-side. Set
`ANTHROPIC_API_KEY` as a Worker secret; deploy; put the Worker host in
`Config/Secrets.xcconfig`.

```js
export default {
  async fetch(req, env) {
    if (req.method !== "POST" || !new URL(req.url).pathname.endsWith("/v1/extract")) {
      return json({ error: "Not found" }, 404);
    }
    const { imageBase64, ocrLines = [] } = await req.json();
    if (!imageBase64) return json({ error: "Missing image." }, 400);

    // TODO: authenticate the user + enforce the monthly free-scan limit here.

    const ai = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-opus-5",
        max_tokens: 1024,
        output_config: { effort: "low" },
        tool_choice: { type: "tool", name: "save_receipt" },
        tools: [SAVE_RECEIPT_TOOL],          // the object from the curl above
        system: SYSTEM_PROMPT,
        messages: [{
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type: "image/jpeg", data: imageBase64 } },
            { type: "text", text: `Extract this receipt. OCR lines:\n<ocr>\n${ocrLines.join("\n")}\n</ocr>` },
          ],
        }],
      }),
    });

    const data = await ai.json();
    if (data.stop_reason === "refusal") return json({ error: "Couldn't process that image." }, 422);

    const tool = data.content?.find((b) => b.type === "tool_use");
    if (!tool) return json({ error: "Extraction failed." }, 502);
    return json(tool.input); // already matches the /v1/extract response body
  },
};

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
```

---

## Operational notes

- **Free-scan limit** and **auth** belong on the backend, not the app — the app
  can be tampered with.
- **`clientRequestID`** lets you dedupe retries (network flake after a successful
  extraction) so the user isn't charged a scan twice.
- **Image retention:** decide deliberately. Storing images enables re-processing
  and dispute evidence but is PII. If you don't need them, don't keep them.
- **Timeouts:** the app waits 30s. Keep the model call well under that; return a
  clear `error` on your own upstream timeout.
- **Localization:** `total`/`tax` are always `.`-decimal machine strings on the
  wire; the app formats them in the user's locale for display.
