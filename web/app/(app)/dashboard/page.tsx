"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { apiGet } from "@/lib/api";
import type { CategoryTotal, Insight, ReceiptOut, SpendingSummary, TrendPoint } from "@/lib/types";
import {
  type Granularity,
  anchorFromPeriodKey,
  bucketTrend,
  monthsInPeriod,
  periodKey,
  periodLabel,
  shiftPeriod,
} from "@/lib/period";
import { money } from "@/lib/format";
import { Card, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { MetricTile } from "@/components/metric-tile";
import { CategoryBreakdown } from "@/components/category-breakdown";
import { SpendingTrend } from "@/components/spending-trend";
import { InsightList } from "@/components/insight-list";
import { ReceiptRow } from "@/components/receipt-row";
import { cn } from "@/lib/utils";

const GRANULARITIES: { value: Granularity; label: string }[] = [
  { value: "month", label: "Month" },
  { value: "quarter", label: "Quarter" },
  { value: "year", label: "Year" },
];

const TREND_TAKE: Record<Granularity, number> = { month: 6, quarter: 6, year: 5 };
const CURRENT_WORD: Record<Granularity, string> = {
  month: "This month",
  quarter: "This quarter",
  year: "This year",
};
const PREVIOUS_WORD: Record<Granularity, string> = {
  month: "Previous month",
  quarter: "Previous quarter",
  year: "Previous year",
};

function thisMonth(): string {
  return new Date().toISOString().slice(0, 7); // YYYY-MM
}

function mergeCategoryTotals(summaries: SpendingSummary[]): CategoryTotal[] {
  const totals = new Map<string, number>();
  for (const s of summaries) {
    for (const c of s.by_category) {
      totals.set(c.category_slug, (totals.get(c.category_slug) ?? 0) + Number(c.amount));
    }
  }
  return [...totals.entries()]
    .map(([category_slug, amount]) => ({ category_slug, amount: String(amount) }))
    .sort((a, b) => Number(b.amount) - Number(a.amount));
}

export default function DashboardPage() {
  const [month, setMonth] = useState(thisMonth);
  const [granularity, setGranularity] = useState<Granularity>("month");

  // Allow deep-linking a month, e.g. from /months.
  useEffect(() => {
    const m = new URLSearchParams(window.location.search).get("month");
    if (m && /^\d{4}-\d{2}$/.test(m)) setMonth(m);
  }, []);

  const periodMonths = monthsInPeriod(month, granularity);
  const previousAnchor = shiftPeriod(month, granularity, -1);
  const previousPeriodMonths = monthsInPeriod(previousAnchor, granularity);
  const isCurrentPeriod = periodKey(month, granularity) === periodKey(thisMonth(), granularity);

  // Category totals for whatever period is selected — a single month is one
  // request, a quarter or year merges several. `expenses/summary` stays a
  // per-month endpoint; this composes it rather than needing a new one.
  const periodSummary = useQuery({
    queryKey: ["summary-period", periodMonths.join(",")],
    queryFn: () => Promise.all(periodMonths.map((m) => apiGet<SpendingSummary>(`v1/expenses/summary?month=${m}`))),
  });
  const previousSummary = useQuery({
    queryKey: ["summary-period", previousPeriodMonths.join(",")],
    queryFn: () =>
      Promise.all(previousPeriodMonths.map((m) => apiGet<SpendingSummary>(`v1/expenses/summary?month=${m}`))),
  });
  const earliestBound = useQuery({
    queryKey: ["summary", "earliest-bound"],
    queryFn: () => apiGet<SpendingSummary>(`v1/expenses/summary?month=${thisMonth()}`),
  });
  const insights = useQuery({
    queryKey: ["insights"],
    queryFn: () => apiGet<Insight[]>("v1/insights"),
    enabled: granularity === "month" && isCurrentPeriod,
  });
  const receipts = useQuery({
    queryKey: ["receipts", "month", month],
    queryFn: () => apiGet<ReceiptOut[]>(`v1/receipts?limit=8&month=${month}`),
    enabled: granularity === "month",
  });
  const trend = useQuery({
    queryKey: ["trend", "24"],
    queryFn: () => apiGet<TrendPoint[]>("v1/expenses/trend?months=24"),
  });

  const periodTotal = periodSummary.data ? periodSummary.data.reduce((s, x) => s + Number(x.total), 0) : undefined;
  const previousTotal = previousSummary.data
    ? previousSummary.data.reduce((s, x) => s + Number(x.total), 0)
    : undefined;
  const byCategory = periodSummary.data ? mergeCategoryTotals(periodSummary.data) : [];
  const delta = periodTotal !== undefined && previousTotal !== undefined ? periodTotal - previousTotal : 0;
  const showDelta = previousTotal !== undefined && previousTotal > 0;

  const earliestMonth = earliestBound.data?.earliest_month;
  const canGoBack = !earliestMonth || previousPeriodMonths.some((m) => m >= earliestMonth);
  const canGoForward = !isCurrentPeriod;

  const chartData = bucketTrend(trend.data ?? [], granularity, TREND_TAKE[granularity]);

  return (
    <div className="space-y-xl">
      <header className="flex items-center justify-between">
        <h1 className="text-title">Dashboard</h1>
        <div className="flex items-center gap-md text-callout">
          <Link href="/expenses/new" className="text-text-secondary hover:text-text">
            Add expense
          </Link>
          <Link href="/scan" className="text-accent hover:underline">
            Scan a receipt →
          </Link>
        </div>
      </header>

      <div className="space-y-md">
        <div className="flex justify-center">
          <div className="inline-flex rounded-md border border-border bg-surface p-hair">
            {GRANULARITIES.map((g) => (
              <button
                key={g.value}
                type="button"
                onClick={() => setGranularity(g.value)}
                className={cn(
                  "rounded-sm px-lg py-xs text-caption font-medium transition-colors",
                  granularity === g.value
                    ? "bg-accent text-accent-fg"
                    : "text-text-secondary hover:text-text",
                )}
              >
                {g.label}
              </button>
            ))}
          </div>
        </div>

        <div className="flex items-center justify-center gap-lg">
          <button
            type="button"
            onClick={() => setMonth((m) => shiftPeriod(m, granularity, -1))}
            disabled={!canGoBack}
            aria-label="Previous period"
            className="rounded-md p-xs text-text-secondary hover:bg-surface-2 disabled:opacity-30"
          >
            <ChevronLeft size={20} />
          </button>
          <span className="min-w-[12rem] text-center text-headline">{periodLabel(month, granularity)}</span>
          <button
            type="button"
            onClick={() => setMonth((m) => shiftPeriod(m, granularity, 1))}
            disabled={!canGoForward}
            aria-label="Next period"
            className="rounded-md p-xs text-text-secondary hover:bg-surface-2 disabled:opacity-30"
          >
            <ChevronRight size={20} />
          </button>
        </div>
      </div>

      <div className="grid gap-lg sm:grid-cols-2">
        <MetricTile
          label={isCurrentPeriod ? CURRENT_WORD[granularity] : periodLabel(month, granularity)}
          loading={periodSummary.isLoading}
          value={periodTotal !== undefined ? money(periodTotal) : "—"}
          delta={
            showDelta
              ? {
                  text: `${money(Math.abs(delta))} vs ${PREVIOUS_WORD[granularity].toLowerCase()}`,
                  dir: delta > 0 ? "up" : "down",
                }
              : undefined
          }
        />
        <MetricTile
          label={PREVIOUS_WORD[granularity]}
          loading={previousSummary.isLoading}
          value={previousTotal !== undefined ? money(previousTotal) : "—"}
          muted
        />
      </div>

      <Card>
        <div className="flex items-center justify-between">
          <CardTitle>
            Last {TREND_TAKE[granularity]} {granularity === "month" ? "months" : `${granularity}s`}
          </CardTitle>
          <Link href="/months" className="text-caption text-text-secondary hover:text-text">
            All months →
          </Link>
        </div>
        <div className="mt-md">
          {trend.isLoading ? (
            <Skeleton className="h-40 w-full" />
          ) : (
            <SpendingTrend
              data={chartData}
              activeKey={periodKey(month, granularity)}
              onSelect={(key) => setMonth(anchorFromPeriodKey(key, granularity))}
            />
          )}
        </div>
      </Card>

      <Card>
        <CardTitle>By category</CardTitle>
        <div className="mt-md">
          {periodSummary.isLoading ? <Skeleton className="h-48 w-full" /> : <CategoryBreakdown data={byCategory} />}
        </div>
      </Card>

      {granularity === "month" && isCurrentPeriod && (
        <Card>
          <CardTitle>Insights</CardTitle>
          <div className="mt-md">
            {insights.isLoading ? (
              <Skeleton className="h-16 w-full" />
            ) : (
              <InsightList items={insights.data ?? []} />
            )}
          </div>
        </Card>
      )}

      {granularity === "month" && (
        <Card>
          <div className="flex items-center justify-between">
            <CardTitle>{isCurrentPeriod ? "Recent" : "Receipts"}</CardTitle>
            <Link href="/receipts" className="text-caption text-text-secondary hover:text-text">
              All receipts
            </Link>
          </div>
          <div className="mt-sm divide-y divide-border">
            {receipts.isLoading &&
              Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="my-sm h-10 w-full" />)}
            {receipts.data?.map((r) => <ReceiptRow key={r.id} receipt={r} />)}
            {!receipts.isLoading && receipts.data?.length === 0 && (
              <p className="py-lg text-center text-callout text-text-secondary">
                No receipts in {periodLabel(month, granularity)}.
              </p>
            )}
          </div>
        </Card>
      )}
    </div>
  );
}
