"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { Camera, PencilLine, Plus, ReceiptText } from "lucide-react";
import { apiGet } from "@/lib/api";
import { money, shortDate } from "@/lib/format";
import type { ReceiptOut, Split } from "@/lib/types";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { SplitEditor } from "@/components/split-editor";
import { cn } from "@/lib/utils";

/** Who a new expense is with: a saved person, or a group. */
export type SplitWith = { kind: "person"; id: string; name: string } | { kind: "group"; id: string; name: string };

/** "?with=…" for the scan page, so a fresh scan comes back here to be split. */
export function withParam(target: SplitWith): string {
  return encodeURIComponent(`${target.kind}:${target.id}:${target.name}`);
}

export function parseWith(value: string | null): SplitWith | null {
  if (!value) return null;
  const [kind, id, ...rest] = decodeURIComponent(value).split(":");
  if ((kind !== "person" && kind !== "group") || !id) return null;
  return { kind, id, name: rest.join(":") || "them" };
}

/** Add an expense with someone (or a group): from one of your receipts, a
 * new scan, or typed in. */
export function AddExpense({
  target,
  currency,
  onDone,
}: {
  target: SplitWith;
  currency: string;
  onDone: (split: Split) => void;
}) {
  const [step, setStep] = useState<"menu" | "pick" | "type" | { receipt: ReceiptOut } | null>(null);

  const editorFor = (receipt?: ReceiptOut) => (
    <div className="rounded-lg bg-surface-2 p-lg">
      <SplitEditor
        receipt={receipt}
        fixedGroupId={target.kind === "group" ? target.id : undefined}
        withPeople={target.kind === "person" ? [{ id: target.id, name: target.name }] : undefined}
        currency={receipt?.currency ?? currency}
        onDone={(split) => {
          setStep(null);
          onDone(split);
        }}
        onCancel={() => setStep(null)}
      />
    </div>
  );

  if (step === null) {
    return (
      <Button size="sm" onClick={() => setStep("menu")}>
        <Plus size={15} /> Add expense
      </Button>
    );
  }
  if (step === "menu") {
    const choice = "flex flex-1 flex-col items-start gap-xs rounded-lg bg-surface-2 p-md text-left ring-1 ring-border hover:bg-surface-sunken";
    return (
      <div className="w-full space-y-sm">
        <div className="grid gap-sm sm:grid-cols-3">
          <button type="button" className={choice} onClick={() => setStep("pick")}>
            <ReceiptText size={18} className="text-accent" />
            <span className="text-callout font-medium">From a receipt</span>
            <span className="text-caption text-text-tertiary">One you&apos;ve already scanned</span>
          </button>
          <Link href={`/scan?with=${withParam(target)}`} className={choice}>
            <Camera size={18} className="text-accent" />
            <span className="text-callout font-medium">Scan a receipt</span>
            <span className="text-caption text-text-tertiary">Then split it with {target.name}</span>
          </Link>
          <button type="button" className={choice} onClick={() => setStep("type")}>
            <PencilLine size={18} className="text-accent" />
            <span className="text-callout font-medium">Type it in</span>
            <span className="text-caption text-text-tertiary">No receipt needed</span>
          </button>
        </div>
        <div className="flex justify-end">
          <Button variant="ghost" size="sm" onClick={() => setStep(null)}>
            Cancel
          </Button>
        </div>
      </div>
    );
  }
  if (step === "pick") {
    return <ReceiptPicker onPick={(receipt) => setStep({ receipt })} onCancel={() => setStep("menu")} />;
  }
  if (step === "type") return editorFor();
  return editorFor(step.receipt);
}

/** Your recent receipts that aren't split yet, searchable by store. */
function ReceiptPicker({ onPick, onCancel }: { onPick: (receipt: ReceiptOut) => void; onCancel: () => void }) {
  const [query, setQuery] = useState("");
  const { data, isLoading } = useQuery({
    queryKey: ["receipts", "pick", query],
    queryFn: () =>
      apiGet<ReceiptOut[]>(`v1/receipts?limit=30${query.trim() ? `&q=${encodeURIComponent(query.trim())}` : ""}`),
  });
  const receipts = (data ?? []).filter((r) => !r.split_id);
  return (
    <div className="w-full space-y-sm rounded-lg bg-surface-2 p-lg">
      <Input
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder="Search your receipts"
        aria-label="Search your receipts"
        autoFocus
      />
      <ul className="max-h-80 divide-y divide-border overflow-y-auto rounded-md bg-surface ring-1 ring-border">
        {isLoading && <li className="px-md py-sm text-caption text-text-tertiary">Loading…</li>}
        {!isLoading && receipts.length === 0 && (
          <li className="px-md py-sm text-caption text-text-tertiary">
            {query.trim() ? "No receipts match." : "No receipts to split yet. Scan one instead."}
          </li>
        )}
        {receipts.map((r) => (
          <li key={r.id}>
            <button
              type="button"
              onClick={() => onPick(r)}
              className={cn("flex w-full items-center gap-md px-md py-sm text-left hover:bg-surface-2")}
            >
              <span className="w-14 shrink-0 font-mono text-[11px] uppercase tracking-[0.08em] text-text-tertiary">
                {shortDate(r.purchased_at)}
              </span>
              <span className="min-w-0 flex-1 truncate text-callout">{r.merchant || "Receipt"}</span>
              <span className="font-mono text-callout tabular">{money(r.total, r.currency)}</span>
            </button>
          </li>
        ))}
      </ul>
      <div className="flex justify-end">
        <Button variant="ghost" size="sm" onClick={onCancel}>
          Back
        </Button>
      </div>
    </div>
  );
}
