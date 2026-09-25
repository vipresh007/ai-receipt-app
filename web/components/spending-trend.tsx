"use client";

import {
  Area,
  Bar,
  CartesianGrid,
  Cell,
  ComposedChart,
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

/** "default" follows the app theme; "hero" is tuned for the always-ink hero
 * panel (gold line, cream labels), independent of light/dark. */
type Tone = "default" | "hero";

const TONE: Record<
  Tone,
  {
    line: string;
    grid: string;
    tick: string;
    tickActive: string;
    calloutBg: string;
    calloutText: string;
    dotStroke: string;
    tooltipBg: string;
    tooltipBorder: string;
    tooltipText: string;
    cursor: string;
  }
> = {
  default: {
    line: "var(--c-accent)",
    grid: "var(--c-border)",
    tick: "var(--c-text-tertiary)",
    tickActive: "var(--c-text)",
    calloutBg: "var(--c-text)",
    calloutText: "var(--c-surface)",
    dotStroke: "var(--c-surface)",
    tooltipBg: "var(--c-surface)",
    tooltipBorder: "var(--c-border)",
    tooltipText: "var(--c-text)",
    cursor: "var(--c-border-strong)",
  },
  hero: {
    line: "#D9AE5C",
    grid: "rgba(241,236,225,0.08)",
    tick: "rgba(241,236,225,0.45)",
    tickActive: "#F1ECE1",
    calloutBg: "#F1ECE1",
    calloutText: "#0C1412",
    dotStroke: "#0C1412",
    tooltipBg: "#182723",
    tooltipBorder: "rgba(241,236,225,0.16)",
    tooltipText: "#F1ECE1",
    cursor: "rgba(241,236,225,0.18)",
  },
};

/** A trend chart over pre-bucketed periods (months, quarters, or years — see
 * `lib/period.ts`). The `activeKey` bucket gets a value callout; clicking any
 * bucket calls `onSelect` with that bucket's key, so the chart doubles as
 * navigation — the actual click target is a full-height invisible bar per
 * bucket, since the area/line's own hit area is too thin to tap reliably. */
export function SpendingTrend({
  data,
  activeKey,
  onSelect,
  tone = "default",
  height = 190,
}: {
  data: Bucket[];
  activeKey: string;
  onSelect?: (key: string) => void;
  tone?: Tone;
  height?: number;
}) {
  const t = TONE[tone];
  const fillId = `trendFill-${tone}`;

  if (data.every((d) => d.amount === 0)) {
    return (
      <p className="text-callout" style={{ color: t.tick }}>
        Not enough history yet.
      </p>
    );
  }

  const maxAmount = Math.max(...data.map((d) => d.amount), 1);
  const chartData = data.map((d) => ({ ...d, hit: maxAmount * 1.3 }));
  const mono = "var(--font-mono), ui-monospace, monospace";

  return (
    <ResponsiveContainer width="100%" height={height}>
      <ComposedChart data={chartData} margin={{ left: 0, right: 12, top: 34, bottom: 0 }}>
        <defs>
          <linearGradient id={fillId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={t.line} stopOpacity={0.34} />
            <stop offset="100%" stopColor={t.line} stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid vertical={false} stroke={t.grid} strokeDasharray="3 5" />
        <XAxis
          dataKey="label"
          tickLine={false}
          axisLine={false}
          tickMargin={10}
          tick={(props: { x: number; y: number; payload: { value: string; index: number } }) => {
            const bucket = chartData[props.payload.index];
            const active = bucket?.key === activeKey;
            return (
              <text
                x={props.x}
                y={props.y + 4}
                textAnchor="middle"
                fontSize={11}
                fontFamily={mono}
                fill={active ? t.tickActive : t.tick}
                fontWeight={active ? 600 : 400}
              >
                {props.payload.value}
              </text>
            );
          }}
        />
        <YAxis
          width={38}
          tickLine={false}
          axisLine={false}
          tick={{ fill: t.tick, fontSize: 11, fontFamily: mono }}
          tickFormatter={compact}
        />
        <Tooltip
          cursor={{ stroke: t.cursor, strokeWidth: 1 }}
          content={({ active, payload }) =>
            active && payload?.length ? (
              <div
                style={{
                  background: t.tooltipBg,
                  border: `1px solid ${t.tooltipBorder}`,
                  borderRadius: 12,
                  padding: "6px 10px",
                  fontSize: 12,
                  fontFamily: mono,
                  color: t.tooltipText,
                }}
              >
                {money((payload[0].payload as Bucket).amount)}
              </div>
            ) : null
          }
        />
        <Area
          type="monotone"
          dataKey="amount"
          stroke={t.line}
          strokeWidth={2.5}
          fill={`url(#${fillId})`}
          isAnimationActive={false}
          dot={(props: { cx?: number; cy?: number; payload?: Bucket }) => (
            <g key={props.payload?.key}>{activeDot(props.cx, props.cy, props.payload, activeKey, t)}</g>
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

/** The active bucket's dot + value callout; every other bucket draws nothing.
 * Returns plain elements rather than a named component — recharts clones what
 * `dot` returns, and cloning a named component trips React 19's
 * key-in-spread warning. The key lives on the wrapping <g> at the call site. */
function activeDot(
  cx: number | undefined,
  cy: number | undefined,
  payload: Bucket | undefined,
  activeKey: string,
  t: (typeof TONE)[Tone],
) {
  if (cx === undefined || cy === undefined || !payload || payload.key !== activeKey) return null;
  const label = compact(payload.amount);
  const width = 22 + label.length * 7.5;
  return (
    <>
      <rect x={cx - width / 2} y={cy - 34} width={width} height={22} rx={11} fill={t.calloutBg} />
      <text
        x={cx}
        y={cy - 19}
        textAnchor="middle"
        fontSize={11}
        fontWeight={600}
        fontFamily="var(--font-mono), ui-monospace, monospace"
        fill={t.calloutText}
      >
        {label}
      </text>
      <circle cx={cx} cy={cy} r={5} fill={t.line} stroke={t.dotStroke} strokeWidth={2.5} />
    </>
  );
}
