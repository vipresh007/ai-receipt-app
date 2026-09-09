"use client";

import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { apiGet } from "@/lib/api";
import type { ReceiptOut } from "@/lib/types";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { ReceiptRow } from "@/components/receipt-row";

export default function ReceiptsPage() {
  const { data, isLoading } = useQuery({
    queryKey: ["receipts", "all"],
    queryFn: () => apiGet<ReceiptOut[]>("v1/receipts?limit=100"),
  });

  return (
    <div className="space-y-xl">
      <header className="flex items-center justify-between">
        <h1 className="text-title">Receipts</h1>
        <Link href="/expenses/new" className="text-callout text-accent hover:underline">
          Add expense
        </Link>
      </header>
      <Card>
        <div className="divide-y divide-border">
          {isLoading &&
            Array.from({ length: 8 }).map((_, i) => (
              <Skeleton key={i} className="my-sm h-10 w-full" />
            ))}
          {data?.map((r) => <ReceiptRow key={r.id} receipt={r} />)}
          {!isLoading && data?.length === 0 && (
            <p className="py-2xl text-center text-callout text-text-secondary">
              Nothing here yet. Scan your first receipt.
            </p>
          )}
        </div>
      </Card>
    </div>
  );
}
