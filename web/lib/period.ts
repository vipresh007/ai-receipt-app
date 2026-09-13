import type { TrendPoint } from "./types";

export type Granularity = "month" | "quarter" | "year";

function ym(y: number, m: number): string {
  return `${y}-${String(m).padStart(2, "0")}`;
}

function parts(anchorMonth: string): [number, number] {
  const [y, m] = anchorMonth.split("-").map(Number);
  return [y, m];
}

/** Every YYYY-MM inside the period containing `anchorMonth`. */
export function monthsInPeriod(anchorMonth: string, granularity: Granularity): string[] {
  const [y, m] = parts(anchorMonth);
  if (granularity === "month") return [anchorMonth];
  if (granularity === "quarter") {
    const qStart = Math.floor((m - 1) / 3) * 3 + 1;
    return [0, 1, 2].map((i) => ym(y, qStart + i));
  }
  return Array.from({ length: 12 }, (_, i) => ym(y, i + 1));
}

/** Move the anchor one whole period forward/back (a month, a quarter, or a year). */
export function shiftPeriod(anchorMonth: string, granularity: Granularity, dir: 1 | -1): string {
  const step = granularity === "month" ? 1 : granularity === "quarter" ? 3 : 12;
  const [y, m] = parts(anchorMonth);
  const d = new Date(Date.UTC(y, m - 1 + step * dir, 1));
  return ym(d.getUTCFullYear(), d.getUTCMonth() + 1);
}

/** A stable key identifying the period, comparable across granularities
 * ("2026-09", "2026-Q3", "2026") — used to highlight the active chart bar
 * and to tell whether the viewed period is the current one. */
export function periodKey(anchorMonth: string, granularity: Granularity): string {
  const [y, m] = parts(anchorMonth);
  if (granularity === "year") return String(y);
  if (granularity === "quarter") return `${y}-Q${Math.floor((m - 1) / 3) + 1}`;
  return anchorMonth;
}

/** Human label for the period header, e.g. "September 2026" / "Q3 2026" / "2026". */
export function periodLabel(anchorMonth: string, granularity: Granularity): string {
  const [y, m] = parts(anchorMonth);
  if (granularity === "year") return String(y);
  if (granularity === "quarter") return `Q${Math.floor((m - 1) / 3) + 1} ${y}`;
  return new Date(Date.UTC(y, m - 1, 1)).toLocaleDateString(undefined, {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
}

/** Reverse of periodKey — an anchor month inside the period the key names. */
export function anchorFromPeriodKey(key: string, granularity: Granularity): string {
  if (granularity === "year") return ym(Number(key), 1);
  if (granularity === "quarter") {
    const [y, q] = key.split("-Q").map(Number);
    return ym(y, (q - 1) * 3 + 1);
  }
  return key;
}

interface Bucket {
  key: string;
  label: string;
  amount: number;
}

/** Groups monthly trend points into month/quarter/year buckets, chronological,
 * keeping only the trailing `take` buckets. */
export function bucketTrend(data: TrendPoint[], granularity: Granularity, take: number): Bucket[] {
  if (granularity === "month") {
    return data.slice(-take).map((d) => ({ key: d.month, label: shortMonth(d.month), amount: Number(d.total) }));
  }
  const totals = new Map<string, number>();
  for (const d of data) {
    const [y, m] = d.month.split("-").map(Number);
    const key = granularity === "quarter" ? `${y}-Q${Math.floor((m - 1) / 3) + 1}` : String(y);
    totals.set(key, (totals.get(key) ?? 0) + Number(d.total));
  }
  const keys = [...totals.keys()].sort().slice(-take);
  return keys.map((key) => ({
    key,
    label: granularity === "quarter" ? `Q${key.split("-Q")[1]} '${key.slice(2, 4)}` : key,
    amount: totals.get(key) ?? 0,
  }));
}

function shortMonth(yearMonth: string): string {
  const [y, m] = yearMonth.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, 1)).toLocaleDateString(undefined, { month: "short", timeZone: "UTC" });
}

/** Sum of the trend total for every month in `months`. */
export function sumMonths(data: TrendPoint[], months: string[]): number {
  const byMonth = new Map(data.map((d) => [d.month, Number(d.total)]));
  return months.reduce((sum, m) => sum + (byMonth.get(m) ?? 0), 0);
}
