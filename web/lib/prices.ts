import type { TrackedItem } from "@/lib/types";

/** How item names match across receipts and stores — the same rule as the
 * backend's `services/prices.py` and iOS `PriceTracker.key`. */
export function priceKey(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^\p{L}\p{N}.%]+/gu, " ")
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .join(" ");
}

/** The last time you bought this item before `receiptDate`, at a different price. */
export function earlierPrice(
  tracked: TrackedItem[] | undefined,
  item: { name: string; price: string; quantity?: number },
  receiptDate: string | null,
): TrackedItem["purchases"][number] | null {
  if (!tracked || !receiptDate) return null;
  const found = tracked.find((t) => t.key === priceKey(item.name));
  const price = Number(item.price);
  if (!found || !(price > 0)) return null;
  const unit = (price / Math.max(item.quantity ?? 1, 1)).toFixed(2);
  const before = found.purchases.filter((p) => p.date < receiptDate && p.unit_price !== unit);
  return before.length ? before[before.length - 1] : null;
}

/** The item whose price rose most (5%+) among those bought in the last 45 days. */
export function biggestRise(tracked: TrackedItem[] | undefined, today = new Date()): TrackedItem | null {
  if (!tracked) return null;
  const since = new Date(today);
  since.setDate(since.getDate() - 45);
  const cutoff = since.toISOString().slice(0, 10);
  let best: TrackedItem | null = null;
  for (const t of tracked) {
    const last = t.purchases[t.purchases.length - 1];
    if (!last || last.date < cutoff || (t.change ?? 0) < 0.05) continue;
    if (!best || (t.change ?? 0) > (best.change ?? 0)) best = t;
  }
  return best;
}
