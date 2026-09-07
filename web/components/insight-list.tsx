import { ArrowDownRight, ArrowUpRight, Flame, Minus } from "lucide-react";
import type { Insight, InsightKind } from "@/lib/types";
import { cn } from "@/lib/utils";

const ICON: Record<InsightKind, typeof Minus> = {
  up: ArrowUpRight,
  down: ArrowDownRight,
  streak: Flame,
  neutral: Minus,
  summary: Minus,
};

const COLOR: Record<InsightKind, string> = {
  up: "text-danger",
  down: "text-success",
  streak: "text-warning",
  neutral: "text-text-tertiary",
  summary: "text-text-tertiary",
};

export function InsightList({ items }: { items: Insight[] }) {
  if (items.length === 0) {
    return (
      <p className="text-callout text-text-secondary">
        Keep scanning — insights appear once there&rsquo;s a month of history to compare.
      </p>
    );
  }

  return (
    <ul className="space-y-sm">
      {items.map((insight) => {
        const Icon = ICON[insight.kind] ?? Minus;
        return (
          <li key={insight.id} className="flex items-start gap-sm text-callout">
            <Icon size={16} className={cn("mt-hair shrink-0", COLOR[insight.kind] ?? "text-text-tertiary")} />
            <span>{insight.message}</span>
          </li>
        );
      })}
    </ul>
  );
}
