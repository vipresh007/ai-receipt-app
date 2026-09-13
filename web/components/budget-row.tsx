import type { Budget } from "@/lib/types";
import { categoryColor, categoryMeta } from "@/lib/categories";
import { money } from "@/lib/format";
import { cn } from "@/lib/utils";

function statusColor(percent: number): "danger" | "warning" | "success" {
  if (percent >= 100) return "danger";
  if (percent >= 70) return "warning";
  return "success";
}

const BAR_COLOR = { danger: "bg-danger", warning: "bg-warning", success: "bg-success" };
const BADGE_COLOR = {
  danger: "bg-danger-muted text-danger",
  warning: "bg-warning-muted text-warning",
  success: "bg-success-muted text-success",
};

export function BudgetRow({ budget, onRemove }: { budget: Budget; onRemove?: () => void }) {
  const meta = categoryMeta(budget.category_slug);
  const Icon = meta.icon;
  const color = categoryColor(budget.category_slug);
  const status = statusColor(budget.percent_used);

  return (
    <div className="flex items-center gap-md py-lg first:pt-0 last:pb-0">
      <div
        className="grid h-9 w-9 shrink-0 place-items-center rounded-md"
        style={{ backgroundColor: `color-mix(in srgb, ${color} 16%, transparent)` }}
      >
        <Icon size={18} style={{ color }} />
      </div>
      <div className="min-w-0 flex-1 space-y-xs">
        <div className="flex items-center justify-between gap-md">
          <span className="text-callout font-medium text-text">{meta.label}</span>
          <span
            className={cn("shrink-0 rounded-full px-sm py-hair text-micro font-semibold tabular", BADGE_COLOR[status])}
          >
            {Math.round(budget.percent_used)}%
          </span>
        </div>
        <div className="h-2 overflow-hidden rounded-full bg-surface-2">
          <div
            className={cn("h-full rounded-full transition-[width]", BAR_COLOR[status])}
            style={{ width: `${Math.min(budget.percent_used, 100)}%` }}
          />
        </div>
        <p className="tabular text-caption text-text-secondary">
          {money(budget.spent)} of {money(budget.monthly_limit)}
        </p>
      </div>
      {onRemove && (
        <button
          onClick={onRemove}
          className="shrink-0 text-caption text-text-tertiary hover:text-danger"
          aria-label={`Remove ${meta.label} budget`}
        >
          Remove
        </button>
      )}
    </div>
  );
}
