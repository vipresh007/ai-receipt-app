"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { ArrowRight, ChevronLeft, ChevronRight, Plus, ScanLine } from "lucide-react";
import { apiGet } from "@/lib/api";
import type { Budget, CategoryTotal, Me, ReceiptOut, SpendingSummary, TrendPoint } from "@/lib/types";
import { spendingInsights } from "@/lib/insights";
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
import { buttonVariants } from "@/components/ui/button";
import { Card, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { PeriodHero } from "@/components/period-hero";
import { CategoryBreakdown } from "@/components/category-breakdown";
import { InsightList } from "@/components/insight-list";
import { ReceiptRow } from "@/components/receipt-row";
import { BudgetRow } from "@/components/budget-row";
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
const AGAINST_WORD: Record<Granularity, string> = {
  month: "the month before",
  quarter: "the quarter before",
  year: "the year before",
};

function thisMonth(): string {
  return new Date().toISOString().slice(0, 7); // YYYY-MM
}

function greeting(): string {
  const hour = new Date().getHours();
  if (hour < 12) return "Good morning";
  if (hour < 17) return "Good afternoon";
  return "Good evening";
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

/** Days the period covers — up to today if it's the current one. */
function daysCovered(months: string[], isCurrent: boolean): number {
  const [y0, m0] = months[0].split("-").map(Number);
  const [y1, m1] = months[months.length - 1].split("-").map(Number);
  const start = new Date(y0, m0 - 1, 1);
  const end = isCurrent ? new Date() : new Date(y1, m1, 0);
  return Math.max(1, Math.floor((end.getTime() - start.getTime()) / 86_400_000) + 1);
}

export default function DashboardPage() {
  const [month, setMonth] = useState(thisMonth);
  const [granularity, setGranularity] = useState<Granularity>("month");
  const me = useQuery({ queryKey: ["me"], queryFn: () => apiGet<Me>("v1/auth/me") });
  const firstName = me.data?.display_name?.split(" ")[0];

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
  // Two months back, only for the "up three months in a row" insight.
  const twoBeforeMonth = shiftPeriod(previousAnchor, "month", -1);
  const twoBeforeSummary = useQuery({
    queryKey: ["summary-period", twoBeforeMonth],
    queryFn: () => Promise.all([apiGet<SpendingSummary>(`v1/expenses/summary?month=${twoBeforeMonth}`)]),
    enabled: granularity === "month",
  });
  const receipts = useQuery({
    queryKey: ["receipts", "month", month],
    queryFn: () => apiGet<ReceiptOut[]>(`v1/receipts?limit=8&month=${month}`),
    enabled: granularity === "month",
  });
  const budgets = useQuery({
    queryKey: ["budgets", month],
    queryFn: () => apiGet<Budget[]>(`v1/budgets?month=${month}`),
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
  const perDay = periodTotal !== undefined ? periodTotal / daysCovered(periodMonths, isCurrentPeriod) : undefined;

  const earliestMonth = earliestBound.data?.earliest_month;
  const canGoBack = !earliestMonth || previousPeriodMonths.some((m) => m >= earliestMonth);
  const canGoForward = !isCurrentPeriod;

  const chartData = bucketTrend(trend.data ?? [], granularity, TREND_TAKE[granularity]);

  const insights =
    periodSummary.data && previousSummary.data
      ? spendingInsights({
          current: byCategory,
          previous: mergeCategoryTotals(previousSummary.data),
          twoBefore:
            granularity === "month" && twoBeforeSummary.data
              ? mergeCategoryTotals(twoBeforeSummary.data)
              : undefined,
          against: AGAINST_WORD[granularity],
          when: isCurrentPeriod ? CURRENT_WORD[granularity].toLowerCase() : `in ${periodLabel(month, granularity)}`,
          unit: granularity,
        })
      : [];
  const showInsights = insights.length > 0;
  const hasBudgets = granularity === "month" && !budgets.isLoading && (budgets.data?.length ?? 0) > 0;
  const hasSide = showInsights || hasBudgets;

  // Budgets go under whichever of "Where it went" / Insights is shorter, so
  // the two columns end as close to level as possible. Measured live (the
  // cards' heights depend on the data), and only the two cards themselves are
  // compared — never including Budgets — so moving it can't flip the result.
  const categoriesRef = useRef<HTMLDivElement>(null);
  const insightsRef = useRef<HTMLDivElement>(null);
  const [budgetsLeft, setBudgetsLeft] = useState(false);
  useEffect(() => {
    const measure = () => {
      const left = categoriesRef.current?.offsetHeight ?? 0;
      const right = insightsRef.current?.offsetHeight ?? 0;
      setBudgetsLeft(left <= right);
    };
    measure();
    const ro = new ResizeObserver(measure);
    if (categoriesRef.current) ro.observe(categoriesRef.current);
    if (insightsRef.current) ro.observe(insightsRef.current);
    return () => ro.disconnect();
  }, [showInsights, hasBudgets]);

  const budgetsCard = hasBudgets ? (
    <Card>
      <div className="flex items-center justify-between">
        <CardTitle>Budgets</CardTitle>
        <Link href="/budgets" className="flex items-center gap-xs text-caption text-text-secondary hover:text-text">
          Manage <ArrowRight size={13} />
        </Link>
      </div>
      <div className="mt-lg divide-y divide-border">
        {budgets.data!.slice(0, 3).map((b) => (
          <BudgetRow key={b.category_slug} budget={b} />
        ))}
      </div>
    </Card>
  ) : null;

  return (
    <div className="space-y-2xl">
      <header className="flex flex-wrap items-end justify-between gap-lg">
        <div>
          <p className="font-mono text-[11px] font-medium uppercase tracking-[0.16em] text-text-tertiary">
            {firstName ? greeting() : "Overview"}
          </p>
          <h1 className="mt-xs font-display text-[40px] font-extrabold leading-none tracking-[-0.04em] md:text-[48px]">
            {firstName ?? "Dashboard"}
          </h1>
        </div>
        <div className="flex gap-sm">
          <Link href="/expenses/new" className={buttonVariants({ variant: "secondary" })}>
            <Plus size={16} /> Add expense
          </Link>
          <Link href="/scan" className={buttonVariants()}>
            <ScanLine size={16} /> Scan a receipt
          </Link>
        </div>
      </header>

      <div className="flex flex-wrap items-center justify-between gap-md">
        <div className="inline-flex rounded-pill bg-surface-2 p-hair ring-1 ring-border">
          {GRANULARITIES.map((g) => (
            <button
              key={g.value}
              type="button"
              onClick={() => setGranularity(g.value)}
              aria-pressed={granularity === g.value}
              className={cn(
                "rounded-pill px-lg py-xs text-caption font-semibold transition-colors",
                granularity === g.value ? "bg-surface text-text shadow-e1" : "text-text-secondary hover:text-text",
              )}
            >
              {g.label}
            </button>
          ))}
        </div>

        <div className="flex items-center gap-sm">
          <button
            type="button"
            onClick={() => setMonth((m) => shiftPeriod(m, granularity, -1))}
            disabled={!canGoBack}
            aria-label="Previous period"
            className="grid h-9 w-9 place-items-center rounded-pill text-text-secondary ring-1 ring-border transition-colors hover:bg-surface-2 hover:text-text disabled:opacity-30"
          >
            <ChevronLeft size={18} />
          </button>
          <span className="min-w-[10.5rem] text-center font-display text-[20px] font-bold tracking-[-0.02em]">
            {periodLabel(month, granularity)}
          </span>
          <button
            type="button"
            onClick={() => setMonth((m) => shiftPeriod(m, granularity, 1))}
            disabled={!canGoForward}
            aria-label="Next period"
            className="grid h-9 w-9 place-items-center rounded-pill text-text-secondary ring-1 ring-border transition-colors hover:bg-surface-2 hover:text-text disabled:opacity-30"
          >
            <ChevronRight size={18} />
          </button>
        </div>
      </div>

      <PeriodHero
        label={isCurrentPeriod ? `${CURRENT_WORD[granularity]} · ${periodLabel(month, granularity)}` : periodLabel(month, granularity)}
        total={periodTotal}
        loading={periodSummary.isLoading}
        delta={showDelta ? { amount: delta, against: AGAINST_WORD[granularity] } : undefined}
        figures={[
          {
            label: PREVIOUS_WORD[granularity],
            value: previousTotal !== undefined ? money(previousTotal) : "—",
          },
          {
            label: isCurrentPeriod ? "Per day so far" : "Per day",
            value: perDay !== undefined ? money(perDay) : "—",
          },
        ]}
        trend={chartData}
        trendLoading={trend.isLoading}
        activeKey={periodKey(month, granularity)}
        onSelect={(key) => setMonth(anchorFromPeriodKey(key, granularity))}
      />

      <div
        className={cn(
          "grid items-start gap-2xl",
          hasSide && "lg:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)]",
        )}
      >
        <div className="space-y-2xl">
          <div ref={categoriesRef}>
            <Card>
              <div className="flex items-center justify-between">
                <CardTitle>Where it went</CardTitle>
                <Link href="/months" className="flex items-center gap-xs text-caption text-text-secondary hover:text-text">
                  All months <ArrowRight size={13} />
                </Link>
              </div>
              <div className="mt-xl">
                {periodSummary.isLoading ? <Skeleton className="h-56 w-full" /> : <CategoryBreakdown data={byCategory} />}
              </div>
            </Card>
          </div>
          {hasBudgets && budgetsLeft && budgetsCard}
        </div>

        {hasSide && (
          <div className="space-y-2xl">
            {showInsights && (
              <div ref={insightsRef}>
                <Card>
                  <CardTitle>Insights</CardTitle>
                  <div className="mt-lg">
                    <InsightList items={insights} />
                  </div>
                </Card>
              </div>
            )}
            {hasBudgets && !budgetsLeft && budgetsCard}
          </div>
        )}
      </div>

      {granularity === "month" && (
        <Card>
          <div className="flex items-center justify-between">
            <CardTitle>{isCurrentPeriod ? "Recent receipts" : "Receipts"}</CardTitle>
            <Link href="/receipts" className="flex items-center gap-xs text-caption text-text-secondary hover:text-text">
              All receipts <ArrowRight size={13} />
            </Link>
          </div>
          <div className="mt-md grid gap-x-3xl md:grid-cols-2">
            {receipts.isLoading &&
              Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="my-sm h-11 w-full" />)}
            {receipts.data?.map((r) => (
              <div key={r.id} className="border-b border-border last:border-b-0 md:[&:nth-last-child(2):nth-child(odd)]:border-b-0">
                <ReceiptRow receipt={r} />
              </div>
            ))}
          </div>
          {!receipts.isLoading && receipts.data?.length === 0 && (
            <div className="flex flex-col items-center gap-md py-2xl text-center">
              <p className="text-callout text-text-secondary">No receipts in {periodLabel(month, granularity)} yet.</p>
              <Link href="/scan" className={buttonVariants({ size: "sm" })}>
                <ScanLine size={15} /> Scan your first one
              </Link>
            </div>
          )}
        </Card>
      )}
    </div>
  );
}
