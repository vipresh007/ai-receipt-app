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

/** Notification emails and how people pay you back. */
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

/** Your data as spreadsheets. */
export function ExportCard() {
  const [busy, setBusy] = useState<string | null>(null);

  async function download(name: "receipts" | "shared") {
    setBusy(name);
    try {
      const res = await fetch(`/api/proxy/v1/export/${name}.csv`, { cache: "no-store" });
      if (!res.ok) throw new Error();
      const url = URL.createObjectURL(await res.blob());
      const a = document.createElement("a");
      a.href = url;
      a.download = `tally-${name}-${new Date().toLocaleDateString("en-CA")}.csv`;
      a.click();
      URL.revokeObjectURL(url);
    } finally {
      setBusy(null);
    }
  }

  return (
    <Card className="space-y-md">
      <CardTitle>Export</CardTitle>
      <p className="text-caption text-text-secondary">CSV files that open in Numbers, Excel or Google Sheets.</p>
      <div className="flex flex-wrap gap-sm">
        <Button variant="secondary" size="sm" onClick={() => download("receipts")} disabled={!!busy}>
          <Download size={14} /> {busy === "receipts" ? "Preparing…" : "Receipts"}
        </Button>
        <Button variant="secondary" size="sm" onClick={() => download("shared")} disabled={!!busy}>
          <Download size={14} /> {busy === "shared" ? "Preparing…" : "Shared expenses"}
        </Button>
      </div>
    </Card>
  );
}
