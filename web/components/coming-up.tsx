"use client";

import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { ChevronRight, ShieldCheck, Undo2 } from "lucide-react";
import { apiGet } from "@/lib/api";
import type { ReceiptOut } from "@/lib/types";
import { shortDate } from "@/lib/format";
import { Card, CardTitle } from "@/components/ui/card";

function when(iso: string): string {
  const today = new Date().toISOString().slice(0, 10);
  const tomorrow = new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
  return iso === today ? "today" : iso === tomorrow ? "tomorrow" : shortDate(iso);
}

/** Return windows closing soon and warranties ending soon; hidden when there are none. */
export function ComingUp() {
  const { data } = useQuery({
    queryKey: ["receipts", "coming-up"],
    queryFn: () => apiGet<ReceiptOut[]>("v1/receipts/coming-up"),
  });
  if (!data?.length) return null;
  const today = new Date().toISOString().slice(0, 10);

  return (
    <Card>
      <CardTitle>Coming up</CardTitle>
      <ul className="mt-md divide-y divide-border">
        {data.slice(0, 5).map((r) => {
          const isReturn = !!r.return_by && r.return_by >= today;
          const date = (isReturn ? r.return_by : r.warranty_until)!;
          return (
            <li key={r.id}>
              <Link href={`/receipts/${r.id}`} className="flex items-center gap-md py-md hover:opacity-80">
                <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-accent-muted text-accent">
                  {isReturn ? <Undo2 size={14} /> : <ShieldCheck size={14} />}
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-callout">{r.merchant || "Receipt"}</span>
                  <span className="block text-caption text-text-secondary">
                    {isReturn ? `Return by ${when(date)}` : `Warranty ends ${when(date)}`}
                  </span>
                </span>
                <ChevronRight size={16} className="text-text-tertiary" />
              </Link>
            </li>
          );
        })}
      </ul>
    </Card>
  );
}
