"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { ArrowDownRight, ArrowUpRight, ChevronRight } from "lucide-react";
import { apiGet } from "@/lib/api";
import type { TrendPoint } from "@/lib/types";
import { bucketTrend } from "@/lib/period";
import { money } from "@/lib/format";
import { cn } from "@/lib/utils";
import { Card, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { SpendingTrend } from "@/components/spending-trend";
import { PageHeader } from "@/components/page-header";

function monthName(ym: string): string {
  const [y, m] = ym.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, 1)).toLocaleDateString(undefined, {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
}

export default function MonthsPage() {
  const router = useRouter();
  const { data, isLoading } = useQuery({
    queryKey: ["trend", "all"],
    queryFn: () => apiGet<TrendPoint[]>("v1/expenses/trend?months=24"),
  });

  // Newest first; drop leading empty months but keep any with spend.
  const rows = (data ?? [])
    .slice()
    .reverse()
    .filter((p, i) => Number(p.total) > 0 || i === 0);

  const chartData = bucketTrend(data ?? [], "month", 12);

  return (
    <div className="space-y-xl">
      <PageHeader
        eyebrow="History"
        title="Months"
        actions={
          <Link href="/dashboard" className="text-callout text-text-secondary hover:text-text">
            Back to dashboard
          </Link>
        }
      />

      <Card>
        <CardTitle>Last 12 months</CardTitle>
        <div className="mt-md">
          {isLoading ? (
            <Skeleton className="h-40 w-full" />
          ) : (
            <SpendingTrend
              data={chartData}
              activeKey=""
              onSelect={(key) => router.push(`/dashboard?month=${key}`)}
            />
          )}
        </div>
      </Card>

      <Card>
        <div className="divide-y divide-border">
          {isLoading &&
            Array.from({ length: 6 }).map((_, i) => (
              <Skeleton key={i} className="my-sm h-12 w-full" />
            ))}

          {!isLoading &&
            rows.map((p, i) => {
              const prev = rows[i + 1];
              const change = prev ? Number(p.total) - Number(prev.total) : 0;
              const pct =
                prev && Number(prev.total) > 0
                  ? Math.round((Math.abs(change) / Number(prev.total)) * 100)
                  : null;
              const up = change > 0;
              return (
                <Link
                  key={p.month}
                  href={`/dashboard?month=${p.month}`}
                  className="flex items-center gap-md py-md hover:opacity-80"
                >
                  <div className="flex-1">
                    <p className="text-callout font-medium text-text">{monthName(p.month)}</p>
                    {pct !== null && change !== 0 && (
                      <p
                        className={cn(
                          "mt-hair flex items-center gap-hair text-caption",
                          up ? "text-danger" : "text-success",
                        )}
                      >
                        {up ? <ArrowUpRight size={13} /> : <ArrowDownRight size={13} />}
                        {money(Math.abs(change))} · {pct}% {up ? "more" : "less"}
                      </p>
                    )}
                  </div>
                  <span className="tabular text-callout font-semibold text-text">
                    {money(p.total)}
                  </span>
                  <ChevronRight size={16} className="text-text-tertiary" />
                </Link>
              );
            })}

          {!isLoading && rows.every((p) => Number(p.total) === 0) && (
            <p className="py-2xl text-center text-callout text-text-secondary">
              No spending recorded yet.
            </p>
          )}
        </div>
      </Card>
    </div>
  );
}
