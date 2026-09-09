"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { apiGet } from "@/lib/api";
import type { Insight, ReceiptOut, SpendingSummary, TrendPoint } from "@/lib/types";
import { money } from "@/lib/format";
import { Card, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { MetricTile } from "@/components/metric-tile";
import { CategoryBreakdown } from "@/components/category-breakdown";
import { SpendingTrend } from "@/components/spending-trend";
import { InsightList } from "@/components/insight-list";
import { ReceiptRow } from "@/components/receipt-row";

function thisMonth(): string {
  return new Date().toISOString().slice(0, 7); // YYYY-MM
}

function shiftMonth(ym: string, delta: number): string {
  const [y, m] = ym.split("-").map(Number);
  const d = new Date(Date.UTC(y, m - 1 + delta, 1));
  return d.toISOString().slice(0, 7);
}

function monthLabel(ym: string): string {
  const [y, m] = ym.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, 1)).toLocaleDateString(undefined, {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
}

export default function DashboardPage() {
  const [month, setMonth] = useState(thisMonth);
  const isCurrent = month === thisMonth();

  // Allow deep-linking a month, e.g. from /months.
  useEffect(() => {
    const m = new URLSearchParams(window.location.search).get("month");
    if (m && /^\d{4}-\d{2}$/.test(m)) setMonth(m);
  }, []);

  const summary = useQuery({
    queryKey: ["summary", month],
    queryFn: () => apiGet<SpendingSummary>(`v1/expenses/summary?month=${month}`),
  });
  const insights = useQuery({
    queryKey: ["insights"],
    queryFn: () => apiGet<Insight[]>("v1/insights"),
  });
  const receipts = useQuery({
    queryKey: ["receipts", "month", month],
    queryFn: () => apiGet<ReceiptOut[]>(`v1/receipts?limit=8&month=${month}`),
  });
  const trend = useQuery({
    queryKey: ["trend"],
    queryFn: () => apiGet<TrendPoint[]>("v1/expenses/trend?months=6"),
  });

  const s = summary.data;
  const delta = s ? Number(s.total) - Number(s.previous_month_total) : 0;
  const showDelta = s ? Number(s.previous_month_total) > 0 : false;
  const canBack = !s?.earliest_month || month > s.earliest_month;

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

      <div className="flex items-center justify-center gap-lg">
        <button
          type="button"
          onClick={() => setMonth((m) => shiftMonth(m, -1))}
          disabled={!canBack}
          aria-label="Previous month"
          className="rounded-md p-xs text-text-secondary hover:bg-surface-2 disabled:opacity-30"
        >
          <ChevronLeft size={20} />
        </button>
        <span className="min-w-[12rem] text-center text-headline">{monthLabel(month)}</span>
        <button
          type="button"
          onClick={() => setMonth((m) => shiftMonth(m, 1))}
          disabled={isCurrent}
          aria-label="Next month"
          className="rounded-md p-xs text-text-secondary hover:bg-surface-2 disabled:opacity-30"
        >
          <ChevronRight size={20} />
        </button>
      </div>

      <div className="grid gap-lg sm:grid-cols-2">
        <MetricTile
          label={isCurrent ? "This month" : monthLabel(month)}
          loading={summary.isLoading}
          value={s ? money(s.total) : "—"}
          delta={
            showDelta
              ? {
                  text: `${money(Math.abs(delta))} vs previous month`,
                  dir: delta > 0 ? "up" : "down",
                }
              : undefined
          }
        />
        <MetricTile
          label="Previous month"
          loading={summary.isLoading}
          value={s ? money(s.previous_month_total) : "—"}
          muted
        />
      </div>

      <Card>
        <div className="flex items-center justify-between">
          <CardTitle>Last 6 months</CardTitle>
          <Link
            href="/months"
            className="text-caption text-text-secondary hover:text-text"
          >
            All months →
          </Link>
        </div>
        <div className="mt-md">
          {trend.isLoading ? (
            <Skeleton className="h-40 w-full" />
          ) : (
            <SpendingTrend data={trend.data ?? []} activeMonth={month} />
          )}
        </div>
      </Card>

      <Card>
        <CardTitle>By category</CardTitle>
        <div className="mt-md">
          {summary.isLoading ? (
            <Skeleton className="h-48 w-full" />
          ) : (
            <CategoryBreakdown data={s?.by_category ?? []} />
          )}
        </div>
      </Card>

      {isCurrent && (
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

      <Card>
        <div className="flex items-center justify-between">
          <CardTitle>{isCurrent ? "Recent" : "Receipts"}</CardTitle>
          <Link href="/receipts" className="text-caption text-text-secondary hover:text-text">
            All receipts
          </Link>
        </div>
        <div className="mt-sm divide-y divide-border">
          {receipts.isLoading &&
            Array.from({ length: 4 }).map((_, i) => (
              <Skeleton key={i} className="my-sm h-10 w-full" />
            ))}
          {receipts.data?.map((r) => <ReceiptRow key={r.id} receipt={r} />)}
          {!receipts.isLoading && receipts.data?.length === 0 && (
            <p className="py-lg text-center text-callout text-text-secondary">
              No receipts in {monthLabel(month)}.
            </p>
          )}
        </div>
      </Card>
    </div>
  );
}
