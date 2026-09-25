"use client";

import { ArrowDownRight, ArrowUpRight } from "lucide-react";
import { SpendingTrend } from "@/components/spending-trend";
import { money } from "@/lib/format";

interface Bucket {
  key: string;
  label: string;
  amount: number;
}

interface Figure {
  label: string;
  value: string;
}

/**
 * The one loud moment on the dashboard: the period's total, how it compares,
 * and the trend it sits in — on an always-ink panel with a gold glow (see
 * `--hero-gradient` in design/tokens.css). Clicking a point on the chart
 * navigates to that period.
 */
export function PeriodHero({
  label,
  total,
  loading,
  delta,
  figures,
  trend,
  trendLoading,
  activeKey,
  onSelect,
}: {
  label: string;
  total?: number;
  loading?: boolean;
  /** Positive = spent more than the comparison period. */
  delta?: { amount: number; against: string };
  figures: Figure[];
  trend: Bucket[];
  trendLoading?: boolean;
  activeKey: string;
  onSelect: (key: string) => void;
}) {
  const formatted = total !== undefined ? money(total) : "—";
  const dot = formatted.lastIndexOf(".");
  const whole = dot > 0 ? formatted.slice(0, dot) : formatted;
  const cents = dot > 0 ? formatted.slice(dot) : "";
  const up = (delta?.amount ?? 0) > 0;

  return (
    <section className="relative overflow-hidden rounded-2xl bg-hero text-hero-text shadow-e2 ring-1 ring-white/5">
      <div className="grid gap-2xl p-2xl md:p-3xl lg:grid-cols-[minmax(0,0.85fr)_minmax(0,1.5fr)] lg:items-end lg:gap-3xl">
        <div>
          <p className="font-mono text-[11px] font-medium uppercase tracking-[0.16em] text-gold">{label}</p>
          {loading ? (
            <div className="mt-md h-14 w-56 animate-pulse rounded-lg bg-white/10" />
          ) : (
            <p className="mt-sm font-display text-[52px] font-extrabold leading-none tracking-[-0.045em] tabular md:text-[64px]">
              {whole}
              <span className="text-[rgba(241,236,225,0.4)]">{cents}</span>
            </p>
          )}

          {!loading && delta && delta.amount !== 0 && (
            <span
              className="mt-lg inline-flex items-center gap-xs rounded-pill bg-hero-chip px-md py-xs text-caption font-medium tabular"
              style={{ color: up ? "#F2A25C" : "#35C79A" }}
            >
              {up ? <ArrowUpRight size={14} /> : <ArrowDownRight size={14} />}
              {money(Math.abs(delta.amount))} {up ? "more" : "less"} than {delta.against}
            </span>
          )}

          <dl className="mt-2xl grid grid-cols-2 gap-lg border-t border-white/10 pt-lg">
            {figures.map((f) => (
              <div key={f.label}>
                <dt className="font-mono text-[10.5px] uppercase tracking-[0.14em] text-[rgba(241,236,225,0.5)]">{f.label}</dt>
                <dd className="mt-xs font-mono text-callout tabular">{loading ? "—" : f.value}</dd>
              </div>
            ))}
          </dl>
        </div>

        <div className="min-w-0">
          {trendLoading ? (
            <div className="h-[210px] w-full animate-pulse rounded-lg bg-white/5" />
          ) : (
            <SpendingTrend data={trend} activeKey={activeKey} onSelect={onSelect} tone="hero" height={210} />
          )}
        </div>
      </div>
    </section>
  );
}
