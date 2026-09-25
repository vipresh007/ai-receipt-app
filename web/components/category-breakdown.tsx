import type { CategoryTotal } from "@/lib/types";
import { categoryColor, categoryMeta } from "@/lib/categories";
import { money } from "@/lib/format";

/** Where the period's money went: one proportional bar across the top (the
 * whole period at a glance), then a ranked ledger of categories with each
 * one's share and total. */
export function CategoryBreakdown({ data }: { data: CategoryTotal[] }) {
  const rows = data.filter((d) => Number(d.amount) > 0);
  if (rows.length === 0) {
    return <p className="text-callout text-text-secondary">No spending in this period yet.</p>;
  }

  const total = rows.reduce((s, d) => s + Number(d.amount), 0);
  const share = (d: CategoryTotal) => (Number(d.amount) / total) * 100;

  return (
    <div>
      <div
        className="flex h-3 w-full gap-[3px] overflow-hidden rounded-pill"
        role="img"
        aria-label={rows
          .map((d) => `${categoryMeta(d.category_slug).label} ${Math.round(share(d))}%`)
          .join(", ")}
      >
        {rows.map((d) => (
          <span
            key={d.category_slug}
            className="h-full first:rounded-l-pill last:rounded-r-pill"
            style={{ width: `${share(d)}%`, background: categoryColor(d.category_slug) }}
          />
        ))}
      </div>

      <ul className="mt-xl divide-y divide-border">
        {rows.map((d) => {
          const meta = categoryMeta(d.category_slug);
          const Icon = meta.icon;
          const color = categoryColor(d.category_slug);
          const pct = share(d);
          return (
            <li key={d.category_slug} className="flex items-center gap-md py-md first:pt-0 last:pb-0">
              <span
                className="grid h-9 w-9 shrink-0 place-items-center rounded-md"
                style={{ background: `color-mix(in srgb, ${color} 15%, transparent)`, color }}
              >
                <Icon size={17} />
              </span>
              <div className="min-w-0 flex-1">
                <div className="flex items-baseline justify-between gap-md">
                  <span className="truncate text-callout font-medium">{meta.label}</span>
                  <span className="font-mono text-callout tabular">{money(Number(d.amount))}</span>
                </div>
                <div className="mt-xs flex items-center gap-sm">
                  <span className="h-1 flex-1 overflow-hidden rounded-pill bg-surface-2">
                    <span className="block h-full rounded-pill" style={{ width: `${pct}%`, background: color }} />
                  </span>
                  <span className="w-10 text-right font-mono text-[11px] tabular text-text-tertiary">
                    {pct < 1 ? "<1" : Math.round(pct)}%
                  </span>
                </div>
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
