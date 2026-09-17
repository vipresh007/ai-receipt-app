"use client";

import { Area, Bar, Cell, ComposedChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { money } from "@/lib/format";

function compact(n: number): string {
  return n >= 1000 ? `${Math.round(n / 100) / 10}k` : String(Math.round(n));
}

interface Bucket {
  key: string;
  label: string;
  amount: number;
}

function ChartTooltip({ active, payload }: { active?: boolean; payload?: { payload: Bucket }[] }) {
  if (!active || !payload?.length) return null;
  return (
    <div
      style={{
        background: "var(--c-surface)",
        border: "1px solid var(--c-border)",
        borderRadius: 12,
        padding: "6px 10px",
        fontSize: 12,
        color: "var(--c-text)",
      }}
    >
      {money(payload[0].payload.amount)}
    </div>
  );
}

/** The active bucket's dot + value callout; every other bucket draws nothing
 * (the invisible `hit` bars still make them clickable). Returns a plain `<g>`
 * rather than delegating to a named component — recharts clones whatever
 * `dot` returns to attach its own props, and cloning a named component
 * (through recharts 2.x's own internals) trips React 19's new
 * key-in-spread warning; a plain element sidesteps it. */
function trendDot(cx: number | undefined, cy: number | undefined, payload: Bucket | undefined, activeKey: string) {
  // The outer <g key=...> is set at the call site — never build the key into
  // a props object that then gets spread (see the comment above).
  if (cx === undefined || cy === undefined || !payload || payload.key !== activeKey) {
    return null;
  }
  const label = compact(payload.amount);
  const width = 20 + label.length * 7;
  return (
    <>
      <rect x={cx - width / 2} y={cy - 32} width={width} height={22} rx={8} fill="var(--c-text)" />
      <text x={cx} y={cy - 17} textAnchor="middle" fontSize={11} fontWeight={700} fill="var(--c-surface)">
        {label}
      </text>
      <circle cx={cx} cy={cy} r={4} fill="var(--c-accent)" stroke="var(--c-surface)" strokeWidth={2} />
    </>
  );
}

/** A bar chart over pre-bucketed periods (months, quarters, or years — see
 * `lib/period.ts`). The `activeKey` bucket gets a value callout; clicking any
 * bucket calls `onSelect` with that bucket's key, so the chart doubles as
 * navigation — the actual click target is a full-height invisible bar per
 * bucket, since the area/line's own hit area is too thin to tap reliably. */
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

  const maxAmount = Math.max(...data.map((d) => d.amount), 1);
  const chartData = data.map((d) => ({ ...d, hit: maxAmount * 1.3 }));

  return (
    <ResponsiveContainer width="100%" height={170}>
      <ComposedChart data={chartData} margin={{ left: 0, right: 8, top: 28, bottom: 4 }}>
        <defs>
          <linearGradient id="trendFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--c-accent)" stopOpacity={0.32} />
            <stop offset="100%" stopColor="var(--c-accent)" stopOpacity={0} />
          </linearGradient>
        </defs>
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
        <Tooltip cursor={{ stroke: "var(--c-border)", strokeWidth: 1 }} content={<ChartTooltip />} />
        <Area
          type="monotone"
          dataKey="amount"
          stroke="var(--c-accent)"
          strokeWidth={2.5}
          fill="url(#trendFill)"
          isAnimationActive={false}
          dot={(props: { cx?: number; cy?: number; payload?: Bucket }) => (
            <g key={props.payload?.key}>{trendDot(props.cx, props.cy, props.payload, activeKey)}</g>
          )}
        />
        <Bar dataKey="hit" fill="transparent" isAnimationActive={false}>
          {chartData.map((d) => (
            <Cell
              key={d.key}
              onClick={onSelect ? () => onSelect(d.key) : undefined}
              cursor={onSelect ? "pointer" : undefined}
            />
          ))}
        </Bar>
      </ComposedChart>
    </ResponsiveContainer>
  );
}
