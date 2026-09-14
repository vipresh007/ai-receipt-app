"use client";

import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { apiDelete, apiGet, apiPut } from "@/lib/api";
import type { Budget } from "@/lib/types";
import { CATEGORY_ORDER, categoryMeta } from "@/lib/categories";
import { money } from "@/lib/format";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { MetricTile } from "@/components/metric-tile";
import { BudgetRow } from "@/components/budget-row";

type FormMode = { type: "add" } | { type: "edit"; budget: Budget } | null;

export default function BudgetsPage() {
  const queryClient = useQueryClient();
  const { data: budgets, isLoading } = useQuery({
    queryKey: ["budgets"],
    queryFn: () => apiGet<Budget[]>("v1/budgets"),
  });

  const [formMode, setFormMode] = useState<FormMode>(null);
  const [category, setCategory] = useState("");
  const [limit, setLimit] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const usedSlugs = new Set((budgets ?? []).map((b) => b.category_slug));
  const availableCategories = CATEGORY_ORDER.filter((slug) => !usedSlugs.has(slug));

  const totalBudgeted = (budgets ?? []).reduce((s, b) => s + Number(b.monthly_limit), 0);
  const totalSpent = (budgets ?? []).reduce((s, b) => s + Number(b.spent), 0);
  const overBudgetCount = (budgets ?? []).filter((b) => b.percent_used >= 100).length;

  async function refresh() {
    await queryClient.invalidateQueries({ queryKey: ["budgets"] });
  }

  function openAdd() {
    setFormMode({ type: "add" });
    setCategory("");
    setLimit("");
    setError(null);
  }

  function openEdit(budget: Budget) {
    setFormMode({ type: "edit", budget });
    setCategory(budget.category_slug);
    setLimit(budget.monthly_limit);
    setError(null);
  }

  function closeForm() {
    setFormMode(null);
  }

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (!category || Number(limit) <= 0 || saving) return;
    setSaving(true);
    setError(null);
    try {
      await apiPut(`v1/budgets/${category}`, { monthly_limit: limit });
      closeForm();
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
          <Button size="sm" onClick={() => (formMode ? closeForm() : openAdd())}>
            {formMode ? "Cancel" : "Add budget"}
          </Button>
        )}
      </header>

      {!isLoading && (budgets ?? []).length > 0 && (
        <div className="grid gap-lg sm:grid-cols-2">
          <MetricTile label="Budgeted this month" value={money(totalBudgeted)} />
          <MetricTile
            label="Spent so far"
            value={money(totalSpent)}
            muted
            delta={
              overBudgetCount > 0
                ? {
                    text: `${overBudgetCount} categor${overBudgetCount === 1 ? "y" : "ies"} over budget`,
                    dir: "up",
                  }
                : undefined
            }
          />
        </div>
      )}

      {formMode && (
        <Card>
          <form onSubmit={save} className="space-y-lg">
            <div className="space-y-xs">
              <Label htmlFor="category">Category</Label>
              {formMode.type === "edit" ? (
                <p className="flex h-11 items-center text-callout text-text">
                  {categoryMeta(formMode.budget.category_slug).label}
                </p>
              ) : (
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
              )}
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
                autoFocus={formMode.type === "edit"}
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
            {(budgets ?? []).map((b) => (
              <BudgetRow
                key={b.category_slug}
                budget={b}
                onSelect={() => openEdit(b)}
                onRemove={() => remove(b.category_slug)}
              />
            ))}
          </div>
        </Card>
      )}
    </div>
  );
}
