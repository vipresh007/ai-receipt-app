"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { ArrowLeft, ChevronDown } from "lucide-react";
import { PriceChange } from "@/components/price-change";
import { apiGet } from "@/lib/api";
import type { TrackedItem } from "@/lib/types";
import { money, shortDate } from "@/lib/format";
import { priceKey } from "@/lib/prices";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { PageHeader } from "@/components/page-header";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";

/** Everything bought more than once, what it costs now, and every time it was bought. */
export default function PricesPage() {
  const { data, isLoading } = useQuery({
    queryKey: ["receipts", "prices"],
    queryFn: () => apiGet<TrackedItem[]>("v1/receipts/prices"),
  });
  const [search, setSearch] = useState("");
  const [open, setOpen] = useState<string | null>(null);
  const query = priceKey(search);
  const shown = (data ?? []).filter((t) => !query || t.key.includes(query));

  return (
    <div className="mx-auto max-w-2xl space-y-xl">
      <Link href="/receipts" className="inline-flex items-center gap-xs text-caption text-text-secondary hover:text-text">
        <ArrowLeft size={14} /> Receipts
      </Link>
      <PageHeader
        eyebrow="Prices"
        title="What things cost you"
        description="Items you've bought on two or more receipts, matched by name across stores. Prices are per item."
      />
      <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Find an item" aria-label="Find an item" />
      <Card className="!p-0">
        {isLoading && (
          <div className="space-y-sm p-lg">
            {Array.from({ length: 5 }).map((_, i) => (
              <Skeleton key={i} className="h-10 w-full" />
            ))}
          </div>
        )}
        {!isLoading && shown.length === 0 && (
          <p className="px-2xl py-2xl text-center text-callout text-text-secondary">
            {data?.length ? "No item matches." : "Once you've bought something twice, its prices show up here."}
          </p>
        )}
        <ul className="divide-y divide-border">
          {shown.map((t) => {
            const last = t.purchases[t.purchases.length - 1];
            const expanded = open === t.key;
            const cheapest = t.purchases.reduce((a, b) => (Number(b.unit_price) < Number(a.unit_price) ? b : a));
            return (
              <li key={t.key}>
                <button
                  type="button"
                  onClick={() => setOpen(expanded ? null : t.key)}
                  className="flex w-full items-center gap-md px-lg py-md text-left hover:bg-surface-2"
                  aria-expanded={expanded}
                >
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-callout font-medium">{t.name}</span>
                    <span className="block truncate text-caption text-text-tertiary">
                      {t.purchases.length} times · last {last.merchant}, {shortDate(last.date)}
                    </span>
                  </span>
                  <span className="text-right">
                    <span className="block font-mono text-callout tabular">{money(t.latest_price)}</span>
                    <PriceChange change={t.change} />
                  </span>
                  <ChevronDown size={16} className={cn("shrink-0 text-text-tertiary transition-transform", expanded && "rotate-180")} />
                </button>
                {expanded && (
                  <div className="space-y-sm bg-surface-2 px-lg py-md">
                    {Number(cheapest.unit_price) < Number(t.latest_price) && (
                      <p className="text-caption text-success">
                        Cheapest: {money(cheapest.unit_price)} at {cheapest.merchant}, {shortDate(cheapest.date)}
                      </p>
                    )}
                    <ul className="space-y-xs">
                      {[...t.purchases].reverse().map((p, i) => (
                        <li key={i} className="flex items-center justify-between text-caption">
                          <Link href={`/receipts/${p.receipt_id}`} className="text-text-secondary hover:text-text">
                            {shortDate(p.date)} · {p.merchant}
                          </Link>
                          <span className="font-mono tabular">{money(p.unit_price)}</span>
                        </li>
                      ))}
                    </ul>
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      </Card>
    </div>
  );
}
