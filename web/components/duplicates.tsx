"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Copy } from "lucide-react";
import { apiGet, apiPost } from "@/lib/api";
import type { Extraction, ReceiptOut } from "@/lib/types";
import { money, shortDate } from "@/lib/format";
import { Button } from "@/components/ui/button";
import { Card, CardTitle } from "@/components/ui/card";

/** On the scan result: "Already in Tally". Keep the original (it takes this
 * scan's photo or items if it had none) or keep both. */
export function DuplicateNote({ result }: { result: Extraction }) {
  const router = useRouter();
  const queryClient = useQueryClient();
  const [hidden, setHidden] = useState(false);
  const [busy, setBusy] = useState(false);
  const dup = result.duplicate_of;
  if (!dup || !result.id || hidden) return null;

  async function keepOriginal() {
    setBusy(true);
    try {
      await apiPost(`v1/receipts/${result.id}/merge`, { into: dup!.id });
      await queryClient.invalidateQueries({ queryKey: ["receipts"] });
      router.push(`/receipts/${dup!.id}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-md rounded-md bg-surface-2 p-md">
      <p className="flex items-center gap-sm text-callout font-semibold">
        <Copy size={16} className="text-warning" /> Already in Tally
      </p>
      <p className="text-caption text-text-secondary">
        {dup.merchant || "A receipt"} · {dup.date ? shortDate(dup.date) : "no date"} · {money(dup.total)}
        {dup.created_at ? `, added ${shortDate(dup.created_at.slice(0, 10))}` : ""}
      </p>
      <div className="flex flex-wrap gap-sm">
        <Button size="sm" onClick={keepOriginal} disabled={busy}>
          Keep the original
        </Button>
        <Button size="sm" variant="secondary" onClick={() => setHidden(true)} disabled={busy}>
          Keep both
        </Button>
      </div>
    </div>
  );
}

/** Receipts that look like the same one added twice, for a one-time cleanup. */
export function DuplicatesCard() {
  const queryClient = useQueryClient();
  const { data } = useQuery({
    queryKey: ["receipts", "duplicates"],
    queryFn: () => apiGet<ReceiptOut[][]>("v1/receipts/duplicates"),
  });
  if (!data || data.length === 0) return null;

  async function removeCopy(copy: ReceiptOut, keep: ReceiptOut) {
    await apiPost(`v1/receipts/${copy.id}/merge`, { into: keep.id });
    await queryClient.invalidateQueries({ queryKey: ["receipts"] });
  }

  return (
    <Card>
      <div className="flex items-center gap-md">
        <span className="grid h-9 w-9 shrink-0 place-items-center rounded-md bg-surface-2 text-warning">
          <Copy size={17} />
        </span>
        <div>
          <CardTitle>Possible duplicates</CardTitle>
          <p className="mt-hair text-caption text-text-secondary">
            Same store, day and total. Remove a copy and the other keeps its photo and items.
          </p>
        </div>
      </div>
      <ul className="mt-lg divide-y divide-border">
        {data.map((group) => (
          <li key={group[0].id} className="space-y-xs py-md">
            <p className="text-callout font-medium">
              {group[0].merchant || "A receipt"} · {group[0].purchased_at ? shortDate(group[0].purchased_at) : ""} ·{" "}
              {money(group[0].total)}
            </p>
            {group.map((r, i) => (
              <div key={r.id} className="flex items-center justify-between gap-md text-caption">
                <Link href={`/receipts/${r.id}`} className="text-text-secondary hover:text-text">
                  {i === 0 ? "Original" : "Copy"}
                  {r.created_at ? `, added ${shortDate(r.created_at.slice(0, 10))}` : ""}
                  {r.image_blob_url ? " · photo" : ""}
                  {r.line_items.length ? ` · ${r.line_items.length} items` : ""}
                </Link>
                {i > 0 && (
                  <Button size="sm" variant="secondary" onClick={() => removeCopy(r, group[0])}>
                    Remove copy
                  </Button>
                )}
              </div>
            ))}
          </li>
        ))}
      </ul>
    </Card>
  );
}
