# Splits and groups

Split a receipt (or any expense) with other people, keep running balances in
groups, and send each person a link showing what they owe. Tally tracks who
owes whom; it never moves money.

## Concepts

| Thing | What it is |
|---|---|
| **Group** | A named set of people (a trip, housemates). Has an invite link. |
| **Member** | A person in a group: either a Tally account (`user_id`) or just a name (a *placeholder*) until that person joins through the invite link and claims it. |
| **Split** | One expense divided between participants. Optionally tied to a receipt and/or a group. One split per receipt. |
| **Participant** | A person on a split, with their computed share. In a group split each participant is a member; in a one-off split they're just names. |
| **Settlement** | "Alex paid Sam $40" inside a group. One-off splits are settled per participant instead (a *paid* tick). |

## Your share is your spending

A receipt keeps its full total; its linked expense row (the personal spending
ledger behind the dashboard, trends and budgets) becomes **your share** once
the receipt is split. Deleting the split restores the full total. Receipts
carry `my_share` / `split_id` so iOS, which totals receipts locally, does the
same.

Group expenses someone else paid (no receipt of yours) affect group balances
only, not your personal spending (v1).

## How shares are computed (server is authoritative)

Work in cents; round with the largest-remainder method so shares always add
up to the total exactly.

- **even** — total ÷ number of participants.
- **items** — each line item is split evenly among the participants assigned
  to it; unassigned items are split among everyone. The rest of the total
  (tax, tip, fees, discounts) is shared in proportion to each person's item
  subtotal (evenly if nobody has items).
- **custom** — explicit amounts per participant; they must add up to the total.

The payer (the receipt owner by default) is a participant like any other: in
a group, they're owed everyone else's shares.

## Balances (groups)

For each split: the payer is credited `total − payer's share`, every other
participant is debited their share. Settlements move credit from receiver to
payer. A member's net balance is the sum; *who owes whom* is the net balances
matched greedily (largest debtor pays largest creditor), so a group never
needs more than `members − 1` payments.

## Links

| Link | Opens | Needs an account? |
|---|---|---|
| `tally.dataeaver.ca/s/<token>` | One participant's view of a split: what they owe, the items, who paid. | No |
| `tally.dataeaver.ca/join/<token>` | A group invite; sign in, then claim your name or join as new. | To join, yes |

A share link is a **snapshot of the split** (merchant, date, items, names,
amounts). It never exposes the receipt image or anything else in the
account. Tokens are 128-bit random.

## API

All under `/v1`, signed-in unless marked public.

- `POST /splits`, `GET /splits?group_id=&receipt_id=`, `GET/PUT/DELETE /splits/{id}`
- `POST /splits/{id}/participants/{pid}/settled` — tick a one-off share paid
- `GET/POST /groups`, `GET/PATCH/DELETE /groups/{id}`
- `POST /groups/{id}/members`, `DELETE /groups/{id}/members/{mid}`
- `POST /groups/{id}/settlements`, `DELETE /groups/{id}/settlements/{sid}`
- `POST /groups/join/{invite_token}` — `{member_id?}` to claim a placeholder
- public: `GET /public/splits/{share_token}`, `GET /public/groups/{invite_token}`

Who may do what: group members see the group and its splits; the split's
creator edits or deletes it; any member records a settlement or adds a
member; only the group's creator deletes the group.

## Account deletion

Your memberships become placeholders under your name (so others' balances
survive), your splits are deleted, and groups you created stay with the
other members.

## Clients

| | Web | iOS |
|---|---|---|
| Split a receipt | Receipt page → **Split** card (`components/split-editor.tsx`, `split-summary.tsx`) | Receipt detail → **Split** section (`Features/Splits/SplitSummaryView.swift` → `SplitEditorView`) |
| Groups | `/groups`, `/groups/[id]` | **Groups** tab (`GroupsView`, `GroupDetailView`); Budgets moved under Dashboard / Account |
| Share / invite links | `/s/[token]`, `/join/[token]` (public, noindex) | System share sheet with the web links; invites are joined on the web |
| Live share preview | `lib/splits.ts` | `Services/SplitMath.swift` (`SplitMathTests` mirror the server's cases) |

Both previews are conveniences: the shares saved are always the server's.
