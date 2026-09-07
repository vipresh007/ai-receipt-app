import type { ReceiptOut } from "@/lib/types";
import { categoryColor, categoryMeta } from "@/lib/categories";
import { money, shortDate } from "@/lib/format";

export function ReceiptRow({ receipt }: { receipt: ReceiptOut }) {
  const meta = categoryMeta(receipt.category_slug);
  const Icon = meta.icon;
  const color = categoryColor(receipt.category_slug);

  return (
    <div className="flex items-center gap-md py-sm">
      <div
        className="grid h-8 w-8 shrink-0 place-items-center rounded-md"
        style={{
          background: `color-mix(in srgb, ${color} 14%, transparent)`,
          color,
        }}
      >
        <Icon size={16} />
      </div>
      <div className="min-w-0 flex-1">
        <p className="truncate text-callout">{receipt.merchant || "Unknown merchant"}</p>
        <p className="text-caption text-text-secondary">
          {[shortDate(receipt.purchased_at), meta.label].filter(Boolean).join(" · ")}
        </p>
      </div>
      <p className="tabular text-callout font-medium">
        {money(receipt.total, receipt.currency)}
      </p>
    </div>
  );
}
