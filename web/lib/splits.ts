import { fromCents, toCents } from "@/lib/format";
import type { SplitMode } from "@/lib/types";

/** Browser mirror of backend `services/splits.py`, for a live preview while
 * editing. The server recomputes on save and its numbers are the ones kept. */
export interface ShareInput {
  itemIndexes: number[];
  amount: string;
  /** Shares mode: parts of the total; blank = 1. */
  weight?: string;
}

/** Round exact cent amounts so they sum to `totalCents`: floor each, then the
 * leftover cents go to the largest fractional parts (earliest first). */
function allocate(totalCents: number, exact: number[]): number[] {
  const floors = exact.map((x) => Math.floor(x + 1e-9));
  let leftover = totalCents - floors.reduce((a, b) => a + b, 0);
  const order = exact
    .map((x, i) => ({ i, frac: x - floors[i] }))
    .sort((a, b) => b.frac - a.frac || a.i - b.i);
  for (const { i } of order) {
    if (leftover <= 0) break;
    floors[i] += 1;
    leftover -= 1;
  }
  return floors;
}

/** Each person's share as a 2-decimal string, or an error message. */
export function previewShares(
  total: string,
  mode: SplitMode,
  inputs: ShareInput[],
  itemPrices: string[],
): { shares: string[] } | { error: string } {
  const n = inputs.length;
  if (n === 0) return { error: "Add at least one person." };
  const totalCents = toCents(total);

  if (mode === "custom") {
    const cents = inputs.map((p) => toCents(p.amount));
    const sum = cents.reduce((a, b) => a + b, 0);
    if (sum !== totalCents) {
      return { error: `The amounts add up to ${fromCents(sum)}, not ${fromCents(totalCents)}.` };
    }
    return { shares: cents.map(fromCents) };
  }

  if (mode === "shares") {
    const weights = inputs.map((p) => (p.weight?.trim() ? Number(p.weight) : 1));
    if (weights.some((w) => !Number.isFinite(w) || w < 0)) return { error: "Shares can't be negative." };
    const whole = weights.reduce((a, b) => a + b, 0);
    if (whole === 0) return { error: "Give at least one person a share." };
    return { shares: allocate(totalCents, weights.map((w) => (totalCents * w) / whole)).map(fromCents) };
  }

  if (mode === "even") {
    return { shares: allocate(totalCents, Array(n).fill(totalCents / n)).map(fromCents) };
  }

  const itemCents = itemPrices.map(toCents);
  const base = Array(n).fill(0);
  itemCents.forEach((cents, idx) => {
    const holders = inputs.map((p, i) => (p.itemIndexes.includes(idx) ? i : -1)).filter((i) => i >= 0);
    const who = holders.length ? holders : inputs.map((_, i) => i);
    for (const i of who) base[i] += cents / who.length;
  });
  const rest = totalCents - itemCents.reduce((a, b) => a + b, 0);
  const subtotal = base.reduce((a, b) => a + b, 0);
  const exact = subtotal ? base.map((b) => b + (rest * b) / subtotal) : base.map((b) => b + rest / n);
  return { shares: allocate(totalCents, exact).map(fromCents) };
}
