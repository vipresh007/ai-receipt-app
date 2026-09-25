import { ArrowDownRight, ArrowUpRight, Flame, Info, Minus, PieChart } from "lucide-react";
import type { InsightKind } from "@/lib/types";
import type { SpendingInsight } from "@/lib/insights";
import { cn } from "@/lib/utils";

const ICON: Record<InsightKind, typeof Minus> = {
  up: ArrowUpRight,
  down: ArrowDownRight,
  streak: Flame,
  neutral: Info,
  summary: PieChart,
};

const TONE: Record<InsightKind, string> = {
  up: "bg-danger-muted text-danger",
  down: "bg-success-muted text-success",
  streak: "bg-warning-muted text-warning",
  neutral: "bg-surface-2 text-text-tertiary",
  summary: "bg-accent-muted text-accent",
};

export function InsightList({ items }: { items: SpendingInsight[] }) {
  if (items.length === 0) {
    return (
      <p className="text-callout text-text-secondary">
        Keep scanning — insights appear once there&rsquo;s a month of history to compare.
      </p>
    );
  }

  return (
    <ul className="divide-y divide-border">
      {items.map((insight) => {
        const Icon = ICON[insight.kind] ?? Minus;
        return (
          <li key={insight.id} className="flex items-start gap-md py-md first:pt-0 last:pb-0">
            <span
              className={cn(
                "mt-[1px] grid h-7 w-7 shrink-0 place-items-center rounded-pill",
                TONE[insight.kind] ?? TONE.neutral,
              )}
            >
              <Icon size={15} />
            </span>
            <span className="text-callout leading-[1.5]">{insight.message}</span>
          </li>
        );
      })}
    </ul>
  );
}
