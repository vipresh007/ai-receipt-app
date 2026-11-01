"use client";

import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { ShieldCheck, Undo2, X } from "lucide-react";
import { apiPatch } from "@/lib/api";
import type { ReceiptOut } from "@/lib/types";
import { shortDate } from "@/lib/format";
import { Card, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";

function addTo(iso: string | null, days = 0, years = 0): string {
  const d = iso ? new Date(`${iso}T12:00:00`) : new Date();
  d.setFullYear(d.getFullYear() + years);
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

function daysUntil(iso: string): number {
  const today = new Date();
  today.setHours(12, 0, 0, 0);
  return Math.round((new Date(`${iso}T12:00:00`).getTime() - today.getTime()) / 86_400_000);
}

/** The last day to return it and when the warranty ends; saved as you pick. */
export function ReturnWarranty({ receipt }: { receipt: ReceiptOut }) {
  const queryClient = useQueryClient();
  const [error, setError] = useState<string | null>(null);
  // Kept here (not in the receipt query) so saving a date doesn't reset
  // unsaved edits in the receipt form above.
  const [dates, setDates] = useState({
    return_by: receipt.return_by ?? null,
    warranty_until: receipt.warranty_until ?? null,
  });

  async function set(field: "return_by" | "warranty_until", value: string | null) {
    setError(null);
    const before = dates[field];
    setDates((d) => ({ ...d, [field]: value }));
    try {
      await apiPatch<ReceiptOut>(`v1/receipts/${receipt.id}`, { [field]: value });
      queryClient.invalidateQueries({ queryKey: ["receipts", "coming-up"] });
    } catch (err) {
      setDates((d) => ({ ...d, [field]: before }));
      setError(err instanceof Error ? err.message : "Couldn't save that.");
    }
  }

  const left = dates.return_by ? daysUntil(dates.return_by) : null;

  return (
    <Card className="space-y-lg">
      <CardTitle>Return &amp; warranty</CardTitle>
      <Row
        icon={<Undo2 size={16} />}
        label="Return by"
        value={dates.return_by}
        presets={[
          ["14 days", addTo(receipt.purchased_at, 14)],
          ["30 days", addTo(receipt.purchased_at, 30)],
          ["90 days", addTo(receipt.purchased_at, 90)],
        ]}
        onChange={(v) => set("return_by", v)}
      />
      {left !== null && (
        <p className={`text-caption ${left >= 0 && left <= 3 ? "text-danger" : "text-text-secondary"}`}>
          {left < 0
            ? "The return window has closed."
            : left === 0
              ? "Today is the last day to return it."
              : `${left} day${left === 1 ? "" : "s"} left. We'll email you 3 days before.`}
        </p>
      )}
      <Row
        icon={<ShieldCheck size={16} />}
        label="Warranty until"
        value={dates.warranty_until}
        presets={[
          ["1 year", addTo(receipt.purchased_at, 0, 1)],
          ["2 years", addTo(receipt.purchased_at, 0, 2)],
          ["3 years", addTo(receipt.purchased_at, 0, 3)],
        ]}
        onChange={(v) => set("warranty_until", v)}
      />
      {error && <p className="text-caption text-danger">{error}</p>}
    </Card>
  );
}

function Row({
  icon,
  label,
  value,
  presets,
  onChange,
}: {
  icon: React.ReactNode;
  label: string;
  value: string | null;
  presets: [string, string][];
  onChange: (value: string | null) => void;
}) {
  return (
    <div className="space-y-sm">
      <div className="flex items-center gap-sm">
        <span className="text-accent">{icon}</span>
        <span className="flex-1 text-callout">{label}</span>
        {value ? (
          <>
            <Input
              type="date"
              value={value}
              onChange={(e) => e.target.value && onChange(e.target.value)}
              aria-label={label}
              className="h-9 w-40"
            />
            <button type="button" onClick={() => onChange(null)} aria-label={`Remove ${label.toLowerCase()}`} className="text-text-tertiary hover:text-danger">
              <X size={16} />
            </button>
          </>
        ) : (
          <span className="text-caption text-text-tertiary">Not set</span>
        )}
      </div>
      {!value && (
        <div className="flex flex-wrap gap-xs pl-[24px]">
          {presets.map(([text, date]) => (
            <button
              key={text}
              type="button"
              onClick={() => onChange(date)}
              title={shortDate(date)}
              className="rounded-full px-sm py-[3px] text-caption text-text-secondary ring-1 ring-border hover:bg-surface-2"
            >
              {text}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
