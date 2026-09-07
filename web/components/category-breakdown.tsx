"use client";

import { Bar, BarChart, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import type { CategoryTotal } from "@/lib/types";
import { categoryColor, categoryMeta } from "@/lib/categories";
import { money } from "@/lib/format";

export function CategoryBreakdown({ data }: { data: CategoryTotal[] }) {
  if (data.length === 0) {
    return <p className="text-callout text-text-secondary">No spending this month yet.</p>;
  }

  const rows = data.map((d) => ({
    slug: d.category_slug,
    label: categoryMeta(d.category_slug).label,
    amount: Number(d.amount),
  }));

  return (
    <ResponsiveContainer width="100%" height={Math.max(140, rows.length * 40)}>
      <BarChart data={rows} layout="vertical" margin={{ left: 8, right: 16, top: 4, bottom: 4 }}>
        <XAxis type="number" hide />
        <YAxis
          type="category"
          dataKey="label"
          width={100}
          tickLine={false}
          axisLine={false}
          tick={{ fill: "var(--c-text-secondary)", fontSize: 12 }}
        />
        <Tooltip
          cursor={{ fill: "var(--c-surface-2)" }}
          contentStyle={{
            background: "var(--c-surface)",
            border: "1px solid var(--c-border)",
            borderRadius: 12,
            fontSize: 12,
            color: "var(--c-text)",
          }}
          formatter={(v: number) => [money(v), "Spent"]}
        />
        <Bar dataKey="amount" radius={[0, 6, 6, 0]} barSize={18}>
          {rows.map((r) => (
            <Cell key={r.slug} fill={categoryColor(r.slug)} />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}
