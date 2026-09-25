import Link from "next/link";
import { Check } from "lucide-react";
import type { ReceiptOut } from "@/lib/types";
import { categoryColor, categoryMeta } from "@/lib/categories";
import { money, shortDate } from "@/lib/format";
import { cn } from "@/lib/utils";

export function ReceiptRowContent({ receipt }: { receipt: ReceiptOut }) {
  const meta = categoryMeta(receipt.category_slug);
  const Icon = meta.icon;
  const color = categoryColor(receipt.category_slug);

  return (
    <>
      <div
        className="grid h-9 w-9 shrink-0 place-items-center rounded-md"
        style={{
          background: `color-mix(in srgb, ${color} 14%, transparent)`,
          color,
        }}
      >
        <Icon size={17} />
      </div>
      <div className="min-w-0 flex-1">
        <p className="truncate text-callout font-medium">{receipt.merchant || "Unknown merchant"}</p>
        <p className="text-caption text-text-tertiary">
          {[shortDate(receipt.purchased_at), meta.label].filter(Boolean).join(" · ")}
        </p>
      </div>
      <p className="font-mono text-callout tabular">
        {money(receipt.total, receipt.currency)}
      </p>
    </>
  );
}

export function ReceiptRow({ receipt }: { receipt: ReceiptOut }) {
  return (
    <Link
      href={`/receipts/${receipt.id}`}
      className="-mx-sm flex items-center gap-md rounded-md px-sm py-md transition-colors hover:bg-surface-2"
    >
      <ReceiptRowContent receipt={receipt} />
    </Link>
  );
}

/** Same row, but tapping toggles a selection checkbox instead of navigating —
 * for bulk-delete mode. */
export function SelectableReceiptRow({
  receipt,
  selected,
  onToggle,
}: {
  receipt: ReceiptOut;
  selected: boolean;
  onToggle: () => void;
}) {
  return (
    <button
      onClick={onToggle}
      className="flex w-full items-center gap-md py-sm text-left transition-colors hover:bg-surface-2"
    >
      <div
        className={cn(
          "grid h-5 w-5 shrink-0 place-items-center rounded-full border-2",
          selected ? "border-accent bg-accent" : "border-border",
        )}
      >
        {selected && <Check size={12} className="text-accent-fg" strokeWidth={3} />}
      </div>
      <ReceiptRowContent receipt={receipt} />
    </button>
  );
}
