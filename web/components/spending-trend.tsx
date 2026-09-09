"use client";

import { Bar, BarChart, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import type { TrendPoint } from "@/lib/types";
import { money } from "@/lib/format";

function shortMonth(ym: string): string {
  const [y, m] = ym.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, 1)).toLocaleDateString(undefined, {
    month: "short",
    timeZone: "UTC",
  });
}

function compact(n: number): string {
  return n >= 1000 ? `${Math.round(n / 100) / 10}k` : String(Math.round(n));
}

/** Month-to-month total spend. The `activeMonth` bar (YYYY-MM) is drawn solid. */
export function SpendingTrend({ data, activeMonth }: { data: TrendPoint[]; activeMonth: string }) {
  if (data.every((d) => Number(d.total) === 0)) {
    return <p className="text-callout text-text-secondary">Not enough history yet.</p>;
  }

  const rows = data.map((d) => ({ month: d.month, label: shortMonth(d.month), amount: Number(d.total) }));

  return (
    <ResponsiveContainer width="100%" height={170}>
      <BarChart data={rows} margin={{ left: 0, right: 8, top: 4, bottom: 4 }}>
        <XAxis
          dataKey="label"
          tickLine={false}
          axisLine={false}
          tick={{ fill: "var(--c-text-secondary)", fontSize: 12 }}
        />
        <YAxis
          width={36}
          tickLine={false}
          axisLine={false}
          tick={{ fill: "var(--c-text-tertiary)", fontSize: 11 }}
          tickFormatter={compact}
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
        <Bar dataKey="amount" radius={[6, 6, 0, 0]} barSize={30} fill="var(--c-accent)">
          {rows.map((r) => (
            <Cell key={r.month} fillOpacity={r.month === activeMonth ? 1 : 0.28} />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}
