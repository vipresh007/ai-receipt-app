import type { CategoryTotal, InsightKind } from "@/lib/types";
import { categoryMeta } from "@/lib/categories";

export interface SpendingInsight {
  id: string;
  kind: InsightKind;
  message: string;
}

/** Change against the previous period worth mentioning (matches iOS's
 * `SpendingSummary.makeInsights` and the backend's rule-based generator). */
const THRESHOLD = 0.15;

function toMap(rows: CategoryTotal[]): Map<string, number> {
  const m = new Map<string, number>();
  for (const r of rows) m.set(r.category_slug, (m.get(r.category_slug) ?? 0) + Number(r.amount));
  return m;
}

/**
 * Plain-English notes about a period, computed from category totals the
 * dashboard already has — so they work for any month, quarter or year, not
 * just the current one. Mirrors the iOS app's on-device insights, plus two
 * that don't need history (biggest category, first-period note).
 *
 * @param against  e.g. "the month before"
 * @param when     e.g. "this month" / "in August 2026"
 * @param twoBefore  category totals two periods back; enables the
 *                   "up three periods in a row" note when given.
 */
export function spendingInsights({
  current,
  previous,
  twoBefore,
  against,
  when,
  unit,
}: {
  current: CategoryTotal[];
  previous: CategoryTotal[];
  twoBefore?: CategoryTotal[];
  against: string;
  when: string;
  unit: string;
}): SpendingInsight[] {
  const cur = toMap(current);
  const prev = toMap(previous);
  const total = [...cur.values()].reduce((s, v) => s + v, 0);
  if (total <= 0) return [];

  const label = (slug: string) => categoryMeta(slug).label.toLowerCase();
  const out: SpendingInsight[] = [];
  const ranked = [...cur.entries()].sort((a, b) => b[1] - a[1]);

  for (const [slug, amount] of ranked) {
    const prior = prev.get(slug);
    if (!prior || prior <= 0) continue;
    const change = (amount - prior) / prior;
    if (Math.abs(change) < THRESHOLD) continue;
    const pct = Math.round(Math.abs(change) * 100);
    out.push({
      id: `change-${slug}`,
      kind: change > 0 ? "up" : "down",
      message: `You spent ${pct}% ${change > 0 ? "more" : "less"} on ${label(slug)} than ${against}.`,
    });
    if (out.length >= 3) break;
  }

  if (twoBefore) {
    const older = toMap(twoBefore);
    const rising = ranked.find(([slug, amount]) => {
      const p1 = prev.get(slug) ?? 0;
      const p2 = older.get(slug) ?? 0;
      return p2 > 0 && p1 > p2 && amount > p1;
    });
    if (rising) {
      out.push({
        id: `streak-${rising[0]}`,
        kind: "streak",
        message: `Your ${label(rising[0])} spending has gone up three ${unit}s in a row.`,
      });
    }
  }

  const [topSlug, topAmount] = ranked[0];
  const share = Math.round((topAmount / total) * 100);
  out.push({
    id: `top-${topSlug}`,
    kind: "summary",
    message:
      ranked.length === 1
        ? `Everything ${when} went to ${label(topSlug)}.`
        : `${categoryMeta(topSlug).label} is your biggest category ${when} — ${share}% of what you spent.`,
  });

  const previousTotal = [...prev.values()].reduce((s, v) => s + v, 0);
  if (previousTotal <= 0) {
    out.push({
      id: "no-history",
      kind: "neutral",
      message: `Nothing recorded ${against.replace(/^the /, "for the ")} yet, so ${unit}-over-${unit} comparisons will start once there is.`,
    });
  }

  return out;
}
