"use client";

import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { apiDelete, apiGet, apiPut } from "@/lib/api";
import type { Budget } from "@/lib/types";
import { CATEGORY_ORDER, categoryColor, categoryMeta } from "@/lib/categories";
import { money } from "@/lib/format";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";

function progressColor(percent: number): string {
  if (percent >= 100) return "bg-danger";
  if (percent >= 70) return "bg-warning";
  return "bg-success";
}

export default function BudgetsPage() {
  const queryClient = useQueryClient();
  const { data: budgets, isLoading } = useQuery({
    queryKey: ["budgets"],
    queryFn: () => apiGet<Budget[]>("v1/budgets"),
  });

  const [showAdd, setShowAdd] = useState(false);
  const [category, setCategory] = useState("");
  const [limit, setLimit] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const usedSlugs = new Set((budgets ?? []).map((b) => b.category_slug));
  const availableCategories = CATEGORY_ORDER.filter((slug) => !usedSlugs.has(slug));

  async function refresh() {
    await queryClient.invalidateQueries({ queryKey: ["budgets"] });
  }

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (!category || Number(limit) <= 0 || saving) return;
    setSaving(true);
    setError(null);
    try {
      await apiPut(`v1/budgets/${category}`, { monthly_limit: limit });
      setShowAdd(false);
      setCategory("");
      setLimit("");
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't save the budget.");
    } finally {
      setSaving(false);
    }
  }

  async function remove(slug: string) {
    await apiDelete(`v1/budgets/${slug}`);
    await refresh();
  }

  return (
    <div className="space-y-xl">
      <header className="flex items-center justify-between">
        <h1 className="text-title">Budgets</h1>
        {availableCategories.length > 0 && (
          <Button size="sm" onClick={() => setShowAdd((v) => !v)}>
            {showAdd ? "Cancel" : "Add budget"}
          </Button>
        )}
      </header>

      {showAdd && (
        <Card>
          <form onSubmit={save} className="space-y-lg">
            <div className="space-y-xs">
              <Label htmlFor="category">Category</Label>
              <select
                id="category"
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                className="h-11 w-full rounded-md border border-border bg-surface px-md text-body text-text focus-visible:border-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--c-focus-ring)]"
              >
                <option value="">Choose one</option>
                {availableCategories.map((slug) => (
                  <option key={slug} value={slug}>
                    {categoryMeta(slug).label}
                  </option>
                ))}
              </select>
            </div>
            <div className="space-y-xs">
              <Label htmlFor="limit">Monthly limit</Label>
              <Input
                id="limit"
                type="number"
                inputMode="decimal"
                step="0.01"
                min="0"
                value={limit}
                onChange={(e) => setLimit(e.target.value)}
                placeholder="0.00"
              />
            </div>
            {error && <p className="text-caption text-danger">{error}</p>}
            <Button type="submit" disabled={!category || Number(limit) <= 0 || saving}>
              {saving ? "Saving…" : "Save"}
            </Button>
          </form>
        </Card>
      )}

      {isLoading && (
        <Card>
          <div className="space-y-lg">
            {Array.from({ length: 3 }).map((_, i) => (
              <Skeleton key={i} className="h-14 w-full" />
            ))}
          </div>
        </Card>
      )}

      {!isLoading && (budgets ?? []).length === 0 && (
        <Card>
          <p className="py-2xl text-center text-callout text-text-secondary">
            No budgets yet. Set a monthly limit for a category to track it here.
          </p>
        </Card>
      )}

      {(budgets ?? []).length > 0 && (
        <Card>
          <div className="divide-y divide-border">
            {(budgets ?? []).map((b) => {
              const meta = categoryMeta(b.category_slug);
              const Icon = meta.icon;
              return (
                <div key={b.category_slug} className="flex items-center gap-md py-lg first:pt-0 last:pb-0">
                  <div
                    className="grid h-9 w-9 shrink-0 place-items-center rounded-md"
                    style={{ backgroundColor: `color-mix(in srgb, ${categoryColor(b.category_slug)} 16%, transparent)` }}
                  >
                    <Icon size={18} style={{ color: categoryColor(b.category_slug) }} />
                  </div>
                  <div className="min-w-0 flex-1 space-y-xs">
                    <div className="flex items-baseline justify-between gap-md">
                      <span className="text-callout font-medium text-text">{meta.label}</span>
                      <span className="tabular text-caption text-text-secondary">
                        {money(b.spent)} of {money(b.monthly_limit)}
                      </span>
                    </div>
                    <div className="h-2 overflow-hidden rounded-full bg-surface-2">
                      <div
                        className={`h-full rounded-full ${progressColor(b.percent_used)}`}
                        style={{ width: `${Math.min(b.percent_used, 100)}%` }}
                      />
                    </div>
                  </div>
                  <button
                    onClick={() => remove(b.category_slug)}
                    className="shrink-0 text-caption text-text-tertiary hover:text-danger"
                    aria-label={`Remove ${meta.label} budget`}
                  >
                    Remove
                  </button>
                </div>
              );
            })}
          </div>
        </Card>
      )}
    </div>
  );
}
