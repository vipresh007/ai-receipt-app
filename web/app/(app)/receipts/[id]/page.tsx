"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { ChevronLeft } from "lucide-react";
import { apiDelete, apiGet, apiPatch } from "@/lib/api";
import type { ReceiptOut } from "@/lib/types";
import { CATEGORY_ORDER, categoryMeta } from "@/lib/categories";
import { money } from "@/lib/format";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";

export default function ReceiptDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const queryClient = useQueryClient();

  const { data: receipt, isLoading } = useQuery({
    queryKey: ["receipt", id],
    queryFn: () => apiGet<ReceiptOut>(`v1/receipts/${id}`),
  });

  const [merchant, setMerchant] = useState("");
  const [date, setDate] = useState("");
  const [category, setCategory] = useState("other");
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Seed the editable fields once the receipt loads.
  useEffect(() => {
    if (!receipt) return;
    setMerchant(receipt.merchant);
    setDate(receipt.purchased_at ?? "");
    setCategory(receipt.category_slug);
  }, [receipt]);

  const dirty =
    !!receipt &&
    (merchant !== receipt.merchant || date !== (receipt.purchased_at ?? "") || category !== receipt.category_slug);

  async function save() {
    if (!receipt || saving) return;
    setSaving(true);
    setError(null);
    try {
      await apiPatch(`v1/receipts/${id}`, { merchant, date, category });
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

        <dl className="grid grid-cols-2 gap-md text-callout">
          <div>
            <dt className="text-caption text-text-tertiary">Total</dt>
            <dd className="tabular font-medium text-text">{money(receipt.total, receipt.currency)}</dd>
          </div>
          <div>
            <dt className="text-caption text-text-tertiary">Tax</dt>
            <dd className="tabular font-medium text-text">{money(receipt.tax, receipt.currency)}</dd>
          </div>
        </dl>

        {receipt.line_items.length > 0 && (
          <div className="space-y-xs">
            <p className="text-caption text-text-tertiary">Items</p>
            <ul className="divide-y divide-border">
              {receipt.line_items.map((item, i) => (
                <li key={i} className="flex items-center justify-between py-xs text-callout">
                  <span className="text-text">{item.name}</span>
                  <span className="tabular text-text-secondary">{money(item.price, receipt.currency)}</span>
                </li>
              ))}
            </ul>
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
    </div>
  );
}
