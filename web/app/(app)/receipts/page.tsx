"use client";

import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { apiGet } from "@/lib/api";
import type { ReceiptOut } from "@/lib/types";
import { money } from "@/lib/format";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { ReceiptRow } from "@/components/receipt-row";

function monthKey(iso: string | null): string {
  return iso && iso.length >= 7 ? iso.slice(0, 7) : "0000-00";
}

function monthLabel(key: string): string {
  if (key === "0000-00") return "No date";
  const [y, m] = key.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, 1)).toLocaleDateString(undefined, {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
}

interface MonthGroup {
  key: string;
  items: ReceiptOut[];
  total: number;
}

function groupByMonth(receipts: ReceiptOut[]): MonthGroup[] {
  const map = new Map<string, ReceiptOut[]>();
  for (const r of receipts) {
    const k = monthKey(r.purchased_at);
    const arr = map.get(k) ?? [];
    if (!map.has(k)) map.set(k, arr);
    arr.push(r);
  }
  return [...map.entries()]
    .sort((a, b) => (a[0] < b[0] ? 1 : -1)) // newest month first
    .map(([key, items]) => ({
      key,
      items: items.slice().sort((a, b) => (monthKey(a.purchased_at) < monthKey(b.purchased_at) ? 1 : -1)),
      total: items.reduce((s, r) => s + Number(r.total), 0),
    }));
}

export default function ReceiptsPage() {
  const { data, isLoading } = useQuery({
    queryKey: ["receipts", "all"],
    queryFn: () => apiGet<ReceiptOut[]>("v1/receipts?limit=200"),
  });

  const groups = data ? groupByMonth(data) : [];

  return (
    <div className="space-y-xl">
      <header className="flex items-center justify-between">
        <h1 className="text-title">Receipts</h1>
        <Link href="/expenses/new" className="text-callout text-accent hover:underline">
          Add expense
        </Link>
      </header>

      {isLoading && (
        <Card>
          <div className="divide-y divide-border">
            {Array.from({ length: 8 }).map((_, i) => (
              <Skeleton key={i} className="my-sm h-10 w-full" />
            ))}
          </div>
        </Card>
      )}

      {!isLoading && data?.length === 0 && (
        <Card>
          <p className="py-2xl text-center text-callout text-text-secondary">
            Nothing here yet. Scan your first receipt.
          </p>
        </Card>
      )}

      {groups.map((g) => (
        <section key={g.key} className="space-y-sm">
          <div className="flex items-baseline justify-between px-hair">
            <h2 className="text-caption font-medium uppercase tracking-wide text-text-tertiary">
              {monthLabel(g.key)}
            </h2>
            <span className="tabular text-caption text-text-secondary">{money(g.total)}</span>
          </div>
          <Card>
            <div className="divide-y divide-border">
              {g.items.map((r) => (
                <ReceiptRow key={r.id} receipt={r} />
              ))}
            </div>
          </Card>
        </section>
      ))}
    </div>
  );
}
