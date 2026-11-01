import { ArrowDownRight, ArrowUpRight } from "lucide-react";
import { cn } from "@/lib/utils";

/** "↑ 12%" — red when a price went up, green when it came down. */
export function PriceChange({ change }: { change: number | null }) {
  if (change === null || change === 0) return null;
  const up = change > 0;
  const Icon = up ? ArrowUpRight : ArrowDownRight;
  return (
    <span className={cn("inline-flex items-center gap-[2px] text-caption font-medium", up ? "text-danger" : "text-success")}>
      <Icon size={13} />
      {Math.round(Math.abs(change) * 100)}%
    </span>
  );
}
