"use client";

import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { apiGet } from "@/lib/api";
import type { Insight, ReceiptOut, SpendingSummary } from "@/lib/types";
import { money } from "@/lib/format";
import { Card, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { MetricTile } from "@/components/metric-tile";
import { CategoryBreakdown } from "@/components/category-breakdown";
import { InsightList } from "@/components/insight-list";
import { ReceiptRow } from "@/components/receipt-row";

export default function DashboardPage() {
  const summary = useQuery({
    queryKey: ["summary"],
    queryFn: () => apiGet<SpendingSummary>("v1/expenses/summary"),
  });
  const insights = useQuery({
    queryKey: ["insights"],
    queryFn: () => apiGet<Insight[]>("v1/insights"),
  });
  const receipts = useQuery({
    queryKey: ["receipts", "recent"],
    queryFn: () => apiGet<ReceiptOut[]>("v1/receipts?limit=6"),
  });

  const s = summary.data;
  const delta = s ? Number(s.total) - Number(s.previous_month_total) : 0;
  const showDelta = s ? Number(s.previous_month_total) > 0 : false;

  return (
    <div className="space-y-xl">
      <header className="flex items-center justify-between">
        <h1 className="text-title">Dashboard</h1>
        <Link href="/scan" className="text-callout text-accent hover:underline">
          Scan a receipt →
        </Link>
      </header>

      <div className="grid gap-lg sm:grid-cols-2">
        <MetricTile
          label="This month"
          loading={summary.isLoading}
          value={s ? money(s.total) : "—"}
          delta={
            showDelta
              ? {
                  text: `${money(Math.abs(delta))} vs last month`,
                  dir: delta > 0 ? "up" : "down",
                }
              : undefined
          }
        />
        <MetricTile
          label="Last month"
          loading={summary.isLoading}
          value={s ? money(s.previous_month_total) : "—"}
          muted
        />
      </div>

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

      <Card>
        <div className="flex items-center justify-between">
          <CardTitle>Recent</CardTitle>
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
              No receipts yet.
            </p>
          )}
        </div>
      </Card>
    </div>
  );
}
