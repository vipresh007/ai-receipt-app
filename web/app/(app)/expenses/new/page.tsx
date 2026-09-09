"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { apiPost } from "@/lib/api";
import { CATEGORY_ORDER, categoryMeta } from "@/lib/categories";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

export default function NewExpensePage() {
  const router = useRouter();
  const queryClient = useQueryClient();

  const [merchant, setMerchant] = useState("");
  const [amount, setAmount] = useState("");
  const [date, setDate] = useState(today());
  const [category, setCategory] = useState("other");
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const valid = merchant.trim() !== "" && Number(amount) > 0;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!valid || saving) return;
    setSaving(true);
    setError(null);
    try {
      await apiPost("v1/receipts", {
        merchant: merchant.trim(),
        date,
        total: amount,
        tax: "0",
        category,
        items: [],
        ...(note.trim() ? { note: note.trim() } : {}),
      });
      await queryClient.invalidateQueries();
      router.push("/receipts");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't save the expense.");
      setSaving(false);
    }
  }

  return (
    <div className="mx-auto max-w-lg space-y-xl">
      <h1 className="text-title">Add expense</h1>
      <p className="text-callout text-text-secondary">
        For spending without a receipt — cash, a bill, a reimbursement.
      </p>

      <Card>
        <form onSubmit={submit} className="space-y-lg">
          <div className="space-y-xs">
            <Label htmlFor="merchant">Merchant</Label>
            <Input
              id="merchant"
              value={merchant}
              onChange={(e) => setMerchant(e.target.value)}
              placeholder="Where the money went"
              autoFocus
            />
          </div>

          <div className="grid grid-cols-2 gap-md">
            <div className="space-y-xs">
              <Label htmlFor="amount">Amount</Label>
              <Input
                id="amount"
                type="number"
                inputMode="decimal"
                step="0.01"
                min="0"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="0.00"
              />
            </div>
            <div className="space-y-xs">
              <Label htmlFor="date">Date</Label>
              <Input
                id="date"
                type="date"
                value={date}
                max={today()}
                onChange={(e) => setDate(e.target.value)}
              />
            </div>
          </div>

          <div className="space-y-xs">
            <Label htmlFor="category">Category</Label>
            <select
              id="category"
              value={category}
              onChange={(e) => setCategory(e.target.value)}
              className="h-11 w-full rounded-md border border-border bg-surface px-md text-body text-text focus-visible:border-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--c-focus-ring)]"
            >
              {CATEGORY_ORDER.map((slug) => (
                <option key={slug} value={slug}>
                  {categoryMeta(slug).label}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-xs">
            <Label htmlFor="note">Note (optional)</Label>
            <Input id="note" value={note} onChange={(e) => setNote(e.target.value)} />
          </div>

          {error && <p className="text-caption text-danger">{error}</p>}

          <div className="flex gap-md">
            <Button type="submit" disabled={!valid || saving}>
              {saving ? "Saving…" : "Save expense"}
            </Button>
            <Button type="button" variant="secondary" onClick={() => router.back()}>
              Cancel
            </Button>
          </div>
        </form>
      </Card>
    </div>
  );
}
