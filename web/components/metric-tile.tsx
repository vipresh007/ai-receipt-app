import { ArrowDownRight, ArrowUpRight } from "lucide-react";
import { Card } from "./ui/card";
import { Skeleton } from "./ui/skeleton";
import { cn } from "@/lib/utils";

export function MetricTile({
  label,
  value,
  delta,
  loading,
  muted,
}: {
  label: string;
  value: string;
  delta?: { text: string; dir: "up" | "down" };
  loading?: boolean;
  muted?: boolean;
}) {
  return (
    <Card className={cn(muted && "bg-surface-2")}>
      <p className="text-micro uppercase text-text-tertiary">{label}</p>
      {loading ? (
        <Skeleton className="mt-sm h-9 w-32" />
      ) : (
        <p className="mt-xs text-display tabular">{value}</p>
      )}
      {delta && !loading && (
        <p
          className={cn(
            "mt-xs flex items-center gap-hair text-caption",
            delta.dir === "up" ? "text-danger" : "text-success",
          )}
        >
          {delta.dir === "up" ? <ArrowUpRight size={14} /> : <ArrowDownRight size={14} />}
          {delta.text}
        </p>
      )}
    </Card>
  );
}
