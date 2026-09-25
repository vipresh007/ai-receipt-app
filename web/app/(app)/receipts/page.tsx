"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Plus, RefreshCw, Search } from "lucide-react";
import { apiDelete, apiGet } from "@/lib/api";
import type { ReceiptOut, RecurringGroup } from "@/lib/types";
import { CATEGORY_ORDER, categoryMeta } from "@/lib/categories";
import { money, shortDate } from "@/lib/format";
import { Card, CardTitle } from "@/components/ui/card";
import { Button, buttonVariants } from "@/components/ui/button";
import { PageHeader } from "@/components/page-header";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { ReceiptRow, SelectableReceiptRow } from "@/components/receipt-row";

function monthKey(iso: string | null): string {
  return iso && iso.length >= 7 ? iso.slice(0, 7) : "0000-00";
}

function monthLabel(key: string): string {
  if (key === "0000-00") return "No date";
  const [y, m] = key.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, 1)).toLocaleDateString(undefined, {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
}

interface MonthGroup {
  key: string;
  items: ReceiptOut[];
  total: number;
}

/** Newest first; receipts with no date sort last. */
function byDateDesc(a: ReceiptOut, b: ReceiptOut): number {
  const ad = a.purchased_at ?? "";
  const bd = b.purchased_at ?? "";
  if (ad === bd) return 0;
  return ad > bd ? -1 : 1;
}

function groupByMonth(receipts: ReceiptOut[]): MonthGroup[] {
  const map = new Map<string, ReceiptOut[]>();
  for (const r of receipts) {
    const k = monthKey(r.purchased_at);
    const arr = map.get(k) ?? [];
    if (!map.has(k)) map.set(k, arr);
    arr.push(r);
  }
  return [...map.entries()]
    .sort((a, b) => (a[0] < b[0] ? 1 : -1)) // newest month first
    .map(([key, items]) => ({
      key,
      // Regression: this used to compare monthKey(a) vs monthKey(b), which is
      // identical for every item in the same group (that's how they got
      // grouped) — the comparator always returned -1, so items within a
      // month were never actually ordered by date.
      items: items.slice().sort(byDateDesc),
      total: items.reduce((s, r) => s + Number(r.total), 0),
    }));
}

/// Debounces a fast-changing value (typing) so we don't refetch on every keystroke.
function useDebounced<T>(value: T, delayMs = 300): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const id = setTimeout(() => setDebounced(value), delayMs);
    return () => clearTimeout(id);
  }, [value, delayMs]);
  return debounced;
}

export default function ReceiptsPage() {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");
  const [category, setCategory] = useState("");
  const debouncedSearch = useDebounced(search);
  const filtersActive = debouncedSearch !== "" || category !== "";

  const [editMode, setEditMode] = useState(false);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [deleting, setDeleting] = useState(false);

  const params = new URLSearchParams({ limit: "200" });
  if (debouncedSearch) params.set("q", debouncedSearch);
  if (category) params.set("category", category);

  const { data, isLoading } = useQuery({
    queryKey: ["receipts", "all", debouncedSearch, category],
    queryFn: () => apiGet<ReceiptOut[]>(`v1/receipts?${params.toString()}`),
  });

  const { data: recurring } = useQuery({
    queryKey: ["receipts", "recurring"],
    queryFn: () => apiGet<RecurringGroup[]>("v1/receipts/recurring"),
  });

  const groups = data ? groupByMonth(data) : [];
  const monthlyRecurringTotal = (recurring ?? []).reduce((s, g) => s + Number(g.average_amount), 0);

  function toggleSelected(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function exitEditMode() {
    setEditMode(false);
    setSelected(new Set());
  }

  async function deleteSelected() {
    if (selected.size === 0 || deleting) return;
    if (!window.confirm(`Delete ${selected.size} receipt${selected.size === 1 ? "" : "s"}? This can't be undone.`)) {
      return;
    }
    setDeleting(true);
    try {
      await Promise.all([...selected].map((id) => apiDelete(`v1/receipts/${id}`)));
      await queryClient.invalidateQueries({ queryKey: ["receipts"] });
      exitEditMode();
    } finally {
      setDeleting(false);
    }
  }

  return (
    <div className="space-y-2xl">
      <PageHeader
        eyebrow={data && !filtersActive ? `${data.length} receipt${data.length === 1 ? "" : "s"}` : "All receipts"}
        title="Receipts"
        actions={
          <>
            {!editMode && (
              <Link href="/expenses/new" className={buttonVariants({ variant: "secondary", size: "sm" })}>
                <Plus size={15} /> Add expense
              </Link>
            )}
            {(data?.length ?? 0) > 0 && (
              <Button
                variant={editMode ? "primary" : "ghost"}
                size="sm"
                onClick={() => (editMode ? exitEditMode() : setEditMode(true))}
              >
                {editMode ? "Done" : "Select"}
              </Button>
            )}
          </>
        }
      />

      {editMode && (
        <div className="sticky top-lg z-10 flex items-center justify-between gap-md rounded-xl bg-surface px-xl py-md shadow-e2 ring-1 ring-border">
          <span className="text-callout">
            <span className="font-mono tabular">{selected.size}</span>{" "}
            <span className="text-text-secondary">selected</span>
          </span>
          <Button variant="danger" size="sm" onClick={deleteSelected} disabled={selected.size === 0 || deleting}>
            {deleting ? "Deleting…" : "Delete"}
          </Button>
        </div>
      )}

      <div className="flex flex-col gap-md sm:flex-row">
        <div className="relative flex-1">
          <Search
            size={16}
            className="pointer-events-none absolute left-md top-1/2 -translate-y-1/2 text-text-tertiary"
          />
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search merchants or items"
            className="pl-4xl"
          />
        </div>
        <select
          value={category}
          onChange={(e) => setCategory(e.target.value)}
          className="h-11 rounded-md border border-border bg-surface px-md text-body text-text focus-visible:border-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--c-focus-ring)] sm:w-48"
        >
          <option value="">All categories</option>
          {CATEGORY_ORDER.map((slug) => (
            <option key={slug} value={slug}>
              {categoryMeta(slug).label}
            </option>
          ))}
        </select>
      </div>

      {!filtersActive && (recurring ?? []).length > 0 && (
        <Card>
          <div className="flex flex-wrap items-center justify-between gap-md">
            <div className="flex items-center gap-md">
              <span className="grid h-9 w-9 shrink-0 place-items-center rounded-md bg-accent-muted text-accent">
                <RefreshCw size={17} />
              </span>
              <div>
                <CardTitle>Recurring</CardTitle>
                <p className="mt-hair text-caption text-text-secondary">
                  {recurring!.length} likely subscription{recurring!.length === 1 ? "" : "s"}
                </p>
              </div>
            </div>
            <p className="text-right">
              <span className="font-display text-[26px] font-extrabold tracking-[-0.03em] tabular">
                {money(monthlyRecurringTotal)}
              </span>
              <span className="font-mono text-caption text-text-tertiary"> /mo</span>
            </p>
          </div>
          <ul className="mt-lg divide-y divide-border">
            {recurring!.map((g) => (
              <li key={g.merchant} className="flex items-center justify-between gap-md py-md">
                <div className="min-w-0">
                  <p className="truncate text-callout font-medium">{g.merchant}</p>
                  <p className="text-caption text-text-tertiary">
                    {g.occurrences} charges · last {shortDate(g.last_purchased_at)}
                  </p>
                </div>
                <span className="font-mono text-callout tabular">{money(g.average_amount)}</span>
              </li>
            ))}
          </ul>
        </Card>
      )}

      {isLoading && (
        <Card>
          <div className="divide-y divide-border">
            {Array.from({ length: 8 }).map((_, i) => (
              <Skeleton key={i} className="my-sm h-10 w-full" />
            ))}
          </div>
        </Card>
      )}

      {!isLoading && data?.length === 0 && (
        <Card>
          <p className="py-2xl text-center text-callout text-text-secondary">
            {filtersActive ? "No receipts match." : "Nothing here yet. Scan your first receipt."}
          </p>
        </Card>
      )}

      {groups.map((g) => (
        <section key={g.key} className="space-y-md">
          <div className="flex flex-wrap items-baseline justify-between gap-x-md px-hair">
            <h2 className="font-display text-[22px] font-bold tracking-[-0.02em]">{monthLabel(g.key)}</h2>
            <p className="font-mono text-caption text-text-tertiary tabular">
              {g.items.length} receipt{g.items.length === 1 ? "" : "s"} ·{" "}
              <span className="text-callout text-text">{money(g.total)}</span>
            </p>
          </div>
          <Card className="py-md">
            <div className="divide-y divide-border">
              {g.items.map((r) =>
                editMode ? (
                  <SelectableReceiptRow
                    key={r.id}
                    receipt={r}
                    selected={selected.has(r.id)}
                    onToggle={() => toggleSelected(r.id)}
                  />
                ) : (
                  <ReceiptRow key={r.id} receipt={r} />
                ),
              )}
            </div>
          </Card>
        </section>
      ))}
    </div>
  );
}
