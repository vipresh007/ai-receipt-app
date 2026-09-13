"use client";

import {
  Bar,
  BarChart,
  Cell,
  LabelList,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { money } from "@/lib/format";

function compact(n: number): string {
  return n >= 1000 ? `${Math.round(n / 100) / 10}k` : String(Math.round(n));
}

interface Bucket {
  key: string;
  label: string;
  amount: number;
}

/** A bar chart over pre-bucketed periods (months, quarters, or years — see
 * `lib/period.ts`). The `activeKey` bar is drawn solid; clicking a bar calls
 * `onSelect` with that bucket's key, so the chart doubles as navigation. */
export function SpendingTrend({
  data,
  activeKey,
  onSelect,
}: {
  data: Bucket[];
  activeKey: string;
  onSelect?: (key: string) => void;
}) {
  if (data.every((d) => d.amount === 0)) {
    return <p className="text-callout text-text-secondary">Not enough history yet.</p>;
  }

  return (
    <ResponsiveContainer width="100%" height={170}>
      <BarChart data={data} margin={{ left: 0, right: 8, top: 4, bottom: 4 }}>
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
          <LabelList
            dataKey="amount"
            position="top"
            formatter={(v: number) => (v > 0 ? compact(v) : "")}
            style={{ fill: "var(--c-text-secondary)", fontSize: 10 }}
          />
          {data.map((r) => (
            // onClick lives on each Cell (closing over its own row) rather than
            // on <Bar>, whose onClick payload shape isn't worth depending on.
            <Cell
              key={r.key}
              fillOpacity={r.key === activeKey ? 1 : 0.28}
              onClick={onSelect ? () => onSelect(r.key) : undefined}
              cursor={onSelect ? "pointer" : undefined}
            />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}
