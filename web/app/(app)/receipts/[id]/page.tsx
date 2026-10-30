"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { ChevronLeft, Users } from "lucide-react";
import { apiDelete, apiGet, apiPatch } from "@/lib/api";
import type { ExtractionItem, ReceiptOut, Split } from "@/lib/types";
import { CATEGORY_ORDER, categoryMeta } from "@/lib/categories";
import { Card, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { PageHeader } from "@/components/page-header";
import { fromCents, money, shortDate, toCents } from "@/lib/format";
import { SplitEditor } from "@/components/split-editor";
import { parseWith, type SplitWith } from "@/components/add-expense";
import { SplitSummary } from "@/components/split-summary";
import { LIVE } from "@/lib/live";

export default function ReceiptDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const queryClient = useQueryClient();

  const { data: receipt, isLoading } = useQuery({
    queryKey: ["receipt", id],
    queryFn: () => apiGet<ReceiptOut>(`v1/receipts/${id}`),
  });

  const { data: split } = useQuery({
    ...LIVE,
    queryKey: ["split", receipt?.split_id],
    queryFn: () => apiGet<Split>(`v1/splits/${receipt!.split_id}`),
    enabled: !!receipt?.split_id,
  });
  const [splitting, setSplitting] = useState(false);
  // From a fresh scan ("Split with Akash"): open the editor with them picked.
  const [splitWith, setSplitWith] = useState<SplitWith | null>(null);
  useEffect(() => {
    const target = parseWith(new URLSearchParams(window.location.search).get("split"));
    if (target) {
      setSplitWith(target);
      setSplitting(true);
    }
  }, []);

  async function afterSplitChange() {
    setSplitting(false);
    // The receipt's share changes the dashboard, budgets and lists too.
    await queryClient.invalidateQueries();
  }

  async function removeSplit() {
    if (!split || !window.confirm("Remove this split? The receipt will count in full again.")) return;
    await apiDelete(`v1/splits/${split.id}`);
    await afterSplitChange();
  }

  const [merchant, setMerchant] = useState("");
  const [date, setDate] = useState("");
  const [category, setCategory] = useState("other");
  const [total, setTotal] = useState("");
  const [tax, setTax] = useState("");
  const [items, setItems] = useState<ExtractionItem[]>([]);
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Seed the editable fields once the receipt loads.
  useEffect(() => {
    if (!receipt) return;
    setMerchant(receipt.merchant);
    setDate(receipt.purchased_at ?? "");
    setCategory(receipt.category_slug);
    setTotal(receipt.total);
    setTax(receipt.tax);
    setItems(receipt.line_items);
  }, [receipt]);

  function updateItem(index: number, patch: Partial<ExtractionItem>) {
    // A price change moves the total by the same amount, so tax and anything
    // not itemized stay in it (items rarely add up to the total on their own).
    if (patch.price !== undefined) {
      const delta = toCents(patch.price) - toCents(items[index].price);
      if (delta !== 0) setTotal((t) => fromCents(Math.max(0, toCents(t) + delta)));
    }
    setItems((prev) => prev.map((item, i) => (i === index ? { ...item, ...patch } : item)));
  }

  const dirty =
    !!receipt &&
    (merchant !== receipt.merchant ||
      date !== (receipt.purchased_at ?? "") ||
      category !== receipt.category_slug ||
      total !== receipt.total ||
      tax !== receipt.tax ||
      JSON.stringify(items) !== JSON.stringify(receipt.line_items));

  async function save() {
    if (!receipt || saving) return;
    setSaving(true);
    setError(null);
    try {
      await apiPatch(`v1/receipts/${id}`, { merchant, date, category, total, tax, items });
      await queryClient.invalidateQueries({ queryKey: ["receipt", id] });
      await queryClient.invalidateQueries({ queryKey: ["receipts"] });
      router.push("/receipts");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't save the receipt.");
    } finally {
      setSaving(false);
    }
  }

  async function remove() {
    if (deleting) return;
    if (!window.confirm("Delete this receipt? This can't be undone.")) return;
    setDeleting(true);
    try {
      await apiDelete(`v1/receipts/${id}`);
      await queryClient.invalidateQueries({ queryKey: ["receipts"] });
      router.push("/receipts");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't delete the receipt.");
      setDeleting(false);
    }
  }

  if (isLoading) {
    return (
      <div className="mx-auto max-w-lg space-y-lg">
        <Skeleton className="h-8 w-40" />
        <Card>
          <Skeleton className="h-64 w-full" />
        </Card>
      </div>
    );
  }

  if (!receipt) {
    return (
      <div className="mx-auto max-w-lg space-y-lg">
        <p className="text-callout text-text-secondary">Receipt not found.</p>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-lg space-y-xl">
      <button
        onClick={() => router.push("/receipts")}
        className="flex items-center gap-xs text-caption text-text-secondary hover:text-text"
      >
        <ChevronLeft size={16} />
        Receipts
      </button>

      <PageHeader
        eyebrow={[shortDate(receipt.purchased_at), categoryMeta(receipt.category_slug).label].filter(Boolean).join(" · ")}
        title={receipt.merchant || "Receipt"}
        actions={
          <div className="text-right">
            <span className="font-display text-[28px] font-extrabold tracking-[-0.03em] tabular">
              {money(receipt.total, receipt.currency)}
            </span>
            {receipt.my_share != null && (
              <p className="text-caption text-text-secondary tabular">
                Your share {money(receipt.my_share, receipt.currency)}
              </p>
            )}
          </div>
        }
      />

      {receipt.image_blob_url && (
        <Card className="overflow-hidden p-0">
          {/* eslint-disable-next-line @next/next/no-img-element -- proxied, non-optimizable API bytes */}
          <img
            src={`/api/proxy/v1/receipts/${id}/image`}
            alt=""
            className="max-h-80 w-full object-contain bg-surface-2"
          />
        </Card>
      )}

      <Card className="space-y-lg">
        <div className="space-y-xs">
          <Label htmlFor="merchant">Merchant</Label>
          <Input id="merchant" value={merchant} onChange={(e) => setMerchant(e.target.value)} />
        </div>

        <div className="grid grid-cols-2 gap-md">
          <div className="space-y-xs">
            <Label htmlFor="date">Date</Label>
            <Input id="date" type="date" value={date} onChange={(e) => setDate(e.target.value)} />
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
        </div>

        <div className="grid grid-cols-2 gap-md">
          <div className="space-y-xs">
            <Label htmlFor="total">Total</Label>
            <Input
              id="total"
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0"
              value={total}
              onChange={(e) => setTotal(e.target.value)}
            />
          </div>
          <div className="space-y-xs">
            <Label htmlFor="tax">Tax</Label>
            <Input
              id="tax"
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0"
              value={tax}
              onChange={(e) => setTax(e.target.value)}
            />
          </div>
        </div>

        {items.length > 0 && (
          <div className="space-y-xs">
            <p className="text-caption text-text-tertiary">Items</p>
            <div className="space-y-sm">
              {items.map((item, i) => (
                <div key={i} className="flex items-center gap-sm">
                  <Input
                    value={item.name}
                    onChange={(e) => updateItem(i, { name: e.target.value })}
                    aria-label={`Item ${i + 1} name`}
                    className="flex-1"
                  />
                  <Input
                    type="number"
                    inputMode="decimal"
                    step="0.01"
                    min="0"
                    value={item.price}
                    onChange={(e) => updateItem(i, { price: e.target.value })}
                    aria-label={`Item ${i + 1} price`}
                    className="w-24"
                  />
                </div>
              ))}
            </div>
          </div>
        )}

        {error && <p className="text-caption text-danger">{error}</p>}

        <div className="flex items-center justify-between gap-md">
          <Button variant="danger" size="sm" onClick={remove} disabled={deleting}>
            {deleting ? "Deleting…" : "Delete"}
          </Button>
          <Button onClick={save} disabled={!dirty || saving}>
            {saving ? "Saving…" : "Save changes"}
          </Button>
        </div>
      </Card>

      <Card className="space-y-lg">
        <div className="flex items-center justify-between gap-md">
          <CardTitle>Split</CardTitle>
          {!split && !splitting && (
            <Button variant="secondary" size="sm" onClick={() => setSplitting(true)}>
              <Users size={15} /> Split this receipt
            </Button>
          )}
        </div>
        {splitting ? (
          <SplitEditor
            receipt={receipt}
            fixedGroupId={!split && splitWith?.kind === "group" ? splitWith.id : undefined}
            withPeople={!split && splitWith?.kind === "person" ? [{ id: splitWith.id, name: splitWith.name }] : undefined}
            existing={split}
            currency={receipt.currency}
            onDone={afterSplitChange}
            onCancel={() => setSplitting(false)}
          />
        ) : split ? (
          <SplitSummary
            split={split}
            onChange={(next) => queryClient.setQueryData(["split", receipt.split_id], next)}
            onEdit={() => setSplitting(true)}
            onRemove={removeSplit}
          />
        ) : (
          <p className="text-callout text-text-secondary">
            Shared this with someone? Split it by item or evenly and send each person a link
            with what they owe. Only your share counts toward your spending.
          </p>
        )}
      </Card>
    </div>
  );
}
