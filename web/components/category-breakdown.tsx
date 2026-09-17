import type { CategoryTotal } from "@/lib/types";
import { categoryColor, categoryMeta } from "@/lib/categories";
import { money } from "@/lib/format";

export function CategoryBreakdown({ data }: { data: CategoryTotal[] }) {
  if (data.length === 0) {
    return <p className="text-callout text-text-secondary">No spending this month yet.</p>;
  }

  return (
    <div className="-mx-hair flex gap-md overflow-x-auto pb-xs">
      {data.map((d) => {
        const meta = categoryMeta(d.category_slug);
        const Icon = meta.icon;
        const color = categoryColor(d.category_slug);
        return (
          <div key={d.category_slug} className="flex w-16 shrink-0 flex-col items-center text-center">
            <div
              className="mb-xs grid h-12 w-12 place-items-center rounded-lg"
              style={{ background: `color-mix(in srgb, ${color} 16%, transparent)`, color }}
            >
              <Icon size={20} />
            </div>
            <p className="tabular text-caption font-semibold text-text">{money(Number(d.amount))}</p>
            <p className="w-full truncate text-[10px] text-text-tertiary">{meta.label}</p>
          </div>
        );
      })}
    </div>
  );
}
