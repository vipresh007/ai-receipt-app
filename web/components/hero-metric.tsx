import { ArrowDownRight, ArrowUpRight } from "lucide-react";
import { Skeleton } from "./ui/skeleton";
import { cn } from "@/lib/utils";

/** A tiny inline trend line — no chart library, just a handful of points
 * normalized into an SVG polyline. Purely decorative context for a big
 * number; the real, labeled chart lives in `SpendingTrend` below it (or,
 * on the landing page, isn't shown at all — this is the whole story there).
 * Sized via `width`/`height` so the same component works at hero scale and
 * shrunk down for the landing page's mock. */
export function Sparkline({ points, width = 120, height = 40 }: { points: number[]; width?: number; height?: number }) {
  if (points.length < 2) return null;

  const pad = Math.min(4, width / 10, height / 5);
  const min = Math.min(...points);
  const max = Math.max(...points);
  const range = max - min || 1;

  const coords = points.map((v, i) => {
    const x = pad + (i * (width - pad * 2)) / (points.length - 1);
    const y = height - pad - ((v - min) / range) * (height - pad * 2);
    return [x, y] as const;
  });

  const path = coords.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(" L");
  const [lastX, lastY] = coords[coords.length - 1];

  return (
    <svg viewBox={`0 0 ${width} ${height}`} style={{ width, height }} className="block" aria-hidden="true">
      <path d={`M${path}`} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
      <circle cx={lastX} cy={lastY} r={Math.min(3, width / 20)} fill="currentColor" />
    </svg>
  );
}

/**
 * The one gradient "moment" per screen — the current period's total. See
 * docs/DESIGN.md "The Ledger direction". Only ever one of these on a page;
 * a secondary number (e.g. previous period) uses `MetricTile` instead.
 */
export function HeroMetric({
  label,
  value,
  delta,
  sparkline,
  loading,
}: {
  label: string;
  value: string;
  delta?: { text: string; dir: "up" | "down" };
  sparkline?: number[];
  loading?: boolean;
}) {
  return (
    <div className="rounded-xl bg-hero p-lg shadow-e2">
      <p className="text-micro uppercase text-gold">{label}</p>
      {loading ? (
        <Skeleton className="mt-sm h-10 w-40 bg-white/10" />
      ) : (
        <p className="mt-xs text-[38px] font-extrabold leading-none tracking-tight text-hero-text tabular">
          {value}
        </p>
      )}
      {!loading && (delta || sparkline) && (
        <div className="mt-md flex items-center justify-between gap-md">
          {delta ? (
            <span
              className={cn(
                "inline-flex items-center gap-hair rounded-pill bg-hero-chip px-sm py-hair text-caption font-semibold text-hero-text tabular",
              )}
            >
              {delta.dir === "up" ? <ArrowUpRight size={12} /> : <ArrowDownRight size={12} />}
              {delta.text}
            </span>
          ) : (
            <span />
          )}
          {sparkline && <span className="text-gold"><Sparkline points={sparkline} /></span>}
        </div>
      )}
    </div>
  );
}
