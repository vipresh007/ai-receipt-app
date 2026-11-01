# Tally — Product Spec

## One-liner

Take a picture of a receipt → AI reads it → the expense is automatically saved
and categorized.

## MVP flow

1. User opens the iOS app.
2. User scans or uploads a receipt.
3. The AI extracts:
   - Store name
   - Date
   - Total amount
   - Tax
   - Category
   - Optionally, individual line items
4. User gets a quick confirmation screen to fix anything read incorrectly.
5. User saves it.

## Expense dashboard

- Monthly spending
- Spending by category
- Recent receipts
- Basic trends

### AI insights section

Generates useful observations such as:

- "You spent 18% more on restaurants this month."
- "Your grocery spending has increased for three months."

## Business model (future)

Freemium:

- **Free** — limited number of receipt scans per month.
- **Paid** — unlimited scanning, advanced insights, exports, shared expenses,
  and eventually bank syncing.

## MVP goal

Make expense tracking easier than manually entering a transaction.

If scanning a receipt takes 5–10 seconds and the user immediately sees it
organized in their spending history, the core value of the app already exists.

## Prices (item price tracking)

Items bought on two or more receipts are tracked by name across stores
(lowercased, punctuation dropped, "1.2kg" kept — `services/prices.py`, iOS
`PriceTracker`, web `lib/prices.ts`; keep the three in sync). Unit price =
line price ÷ quantity. Receipts → Prices lists them with the latest price and
the change against the last different price; each line on a receipt shows
"was $3.99 at Loblaws, Jun 12" when it cost something else last time; the
dashboard adds "Oat milk 1L is $4.49 now, up 12% from $3.99 in June" for the
biggest 5%+ rise among items bought in the last 45 days. Server:
`GET /v1/receipts/prices`. iOS computes it on device from SwiftData.
