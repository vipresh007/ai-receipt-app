"use client";

import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { Download } from "lucide-react";
import { apiPatch } from "@/lib/api";
import type { Me } from "@/lib/types";
import { Card, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

const CURRENCIES = ["CAD", "USD", "EUR", "GBP", "INR", "AUD", "NZD", "JPY", "MXN", "CHF", "SEK", "NOK", "DKK", "SGD", "HKD", "AED", "ZAR", "PHP", "BRL"];

/** Notification emails, how people pay you back, and your home currency. */
export function SharingSettings({ me }: { me: Me }) {
  const queryClient = useQueryClient();
  const [interac, setInterac] = useState(me.interac);
  const [saving, setSaving] = useState(false);
  const [note, setNote] = useState<{ ok: boolean; text: string } | null>(null);

  async function save(patch: Partial<Me>) {
    setSaving(true);
    setNote(null);
    try {
      const next = await apiPatch<Me>("v1/auth/me", patch);
      queryClient.setQueryData(["me"], next);
      setInterac(next.interac);
      setNote({ ok: true, text: "Saved." });
    } catch (err) {
      setNote({ ok: false, text: err instanceof Error ? err.message : "Couldn't save." });
    } finally {
      setSaving(false);
    }
  }

  return (
    <Card className="space-y-lg">
      <CardTitle>Sharing</CardTitle>
      <label className="flex items-start gap-sm text-callout">
        <input
          type="checkbox"
          checked={me.email_notifications}
          onChange={(e) => save({ email_notifications: e.target.checked })}
          className="mt-[3px] h-4 w-4 accent-[var(--c-accent)]"
        />
        <span>
          Email me when someone adds an expense with me, records a payment or sends a reminder
          <span className="block text-caption text-text-tertiary">Everything also shows under Activity.</span>
        </span>
      </label>
      <div className="space-y-xs border-t border-border pt-lg">
        <Label htmlFor="home-currency">Currency</Label>
        <select
          id="home-currency"
          value={me.currency_is_set ? me.currency ?? "" : ""}
          onChange={(e) => save({ currency: e.target.value } as Partial<Me>)}
          className="h-11 w-full rounded-md border border-border bg-surface px-md text-callout"
        >
          <option value="">Automatic{me.currency && !me.currency_is_set ? ` (${me.currency}, from your receipts)` : ""}</option>
          {CURRENCIES.map((code) => (
            <option key={code} value={code}>
              {code}
            </option>
          ))}
        </select>
        <p className="text-caption text-text-tertiary">Totals and new expenses use it.</p>
      </div>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          save({ interac });
        }}
        className="space-y-md border-t border-border pt-lg"
      >
        <div>
          <p className="text-callout font-medium">Get paid back</p>
          <p className="text-caption text-text-secondary">
            Your Interac e-Transfer email or phone, shown to people who owe you.
          </p>
        </div>
        <div className="space-y-xs">
          <Label htmlFor="interac">Interac e-Transfer email or phone</Label>
          <Input id="interac" value={interac} onChange={(e) => setInterac(e.target.value)} placeholder="you@example.com" maxLength={120} />
        </div>
        <div className="flex items-center justify-end gap-md">
          {note && <span className={note.ok ? "text-caption text-success" : "text-caption text-danger"}>{note.text}</span>}
          <Button type="submit" size="sm" disabled={saving}>
            Save
          </Button>
        </div>
      </form>
    </Card>
  );
}

type Range = "this-month" | "last-month" | "this-year" | "last-year" | "all" | "custom";

const RANGES: { value: Range; label: string }[] = [
  { value: "this-month", label: "This month" },
  { value: "last-month", label: "Last month" },
  { value: "this-year", label: "This year" },
  { value: "last-year", label: "Last year" },
  { value: "all", label: "All time" },
  { value: "custom", label: "Custom dates" },
];

const iso = (d: Date) => d.toLocaleDateString("en-CA"); // YYYY-MM-DD, local

/** [from, to] for a preset (both inclusive), or null = everything. */
function rangeDates(range: Range, from: string, to: string): [string, string] | null {
  const now = new Date();
  const y = now.getFullYear();
  const m = now.getMonth();
  switch (range) {
    case "this-month":
      return [iso(new Date(y, m, 1)), iso(new Date(y, m + 1, 0))];
    case "last-month":
      return [iso(new Date(y, m - 1, 1)), iso(new Date(y, m, 0))];
    case "this-year":
      return [`${y}-01-01`, `${y}-12-31`];
    case "last-year":
      return [`${y - 1}-01-01`, `${y - 1}-12-31`];
    case "custom":
      return [from, to];
    default:
      return null;
  }
}

/** Your data as spreadsheets, for any stretch of time. */
export function ExportCard() {
  const [busy, setBusy] = useState<string | null>(null);
  const [range, setRange] = useState<Range>("this-year");
  const [from, setFrom] = useState(() => iso(new Date(new Date().getFullYear(), 0, 1)));
  const [to, setTo] = useState(() => iso(new Date()));
  const [error, setError] = useState<string | null>(null);

  async function download(name: "receipts" | "shared") {
    setBusy(name);
    setError(null);
    try {
      const dates = rangeDates(range, from, to);
      const query = dates ? `?from=${dates[0]}&to=${dates[1]}` : "";
      const res = await fetch(`/api/proxy/v1/export/${name}.csv${query}`, { cache: "no-store" });
      if (!res.ok) {
        const body = (await res.json().catch(() => null)) as { detail?: string } | null;
        throw new Error(body?.detail ?? "Couldn't export.");
      }
      const url = URL.createObjectURL(await res.blob());
      const a = document.createElement("a");
      a.href = url;
      a.download = `tally-${name}-${dates ? `${dates[0]}-to-${dates[1]}` : "all"}.csv`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't export.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <Card className="space-y-md">
      <CardTitle>Export</CardTitle>
      <p className="text-caption text-text-secondary">CSV files that open in Numbers, Excel or Google Sheets.</p>
      <div className="space-y-xs">
        <Label htmlFor="export-range">Dates</Label>
        <select
          id="export-range"
          value={range}
          onChange={(e) => setRange(e.target.value as Range)}
          className="h-11 w-full rounded-md border border-border bg-surface px-md text-callout"
        >
          {RANGES.map((r) => (
            <option key={r.value} value={r.value}>
              {r.label}
            </option>
          ))}
        </select>
      </div>
      {range === "custom" && (
        <div className="grid grid-cols-2 gap-sm">
          <div className="space-y-xs">
            <Label htmlFor="export-from">From</Label>
            <Input id="export-from" type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} />
          </div>
          <div className="space-y-xs">
            <Label htmlFor="export-to">To</Label>
            <Input id="export-to" type="date" value={to} min={from} onChange={(e) => setTo(e.target.value)} />
          </div>
        </div>
      )}
      <div className="flex flex-wrap gap-sm">
        <Button variant="secondary" size="sm" onClick={() => download("receipts")} disabled={!!busy}>
          <Download size={14} /> {busy === "receipts" ? "Preparing…" : "Receipts"}
        </Button>
        <Button variant="secondary" size="sm" onClick={() => download("shared")} disabled={!!busy}>
          <Download size={14} /> {busy === "shared" ? "Preparing…" : "Shared expenses"}
        </Button>
      </div>
      {error && <p className="text-caption text-danger">{error}</p>}
    </Card>
  );
}
