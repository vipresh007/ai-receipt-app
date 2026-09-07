# AI Receipt — Product Spec

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
