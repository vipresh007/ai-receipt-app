import { ArrowDownRight, ArrowUpRight } from "lucide-react";
import { Skeleton } from "./ui/skeleton";
import { cn } from "@/lib/utils";

/** A tiny inline trend line — no chart library, just a handful of points
 * normalized into an SVG polyline. Purely decorative context for a big
 * number; the real, labeled chart lives in `SpendingTrend` below it (or,
 * on the landing page, isn't shown at all — this is the whole story there).
 *
 * `width`/`height` are the logical coordinate box the path is plotted in —
 * with `stretch`, the rendered element ignores that width and fills its
 * flex/grid container instead (only `height` stays fixed), which is what
 * the real dashboard hero card wants: on a wide desktop card, a fixed
 * 120px chart pinned to the far edge (the old default) reads as a stray
 * afterthought a hundred pixels from the number it's describing. Without
 * `stretch` (the landing page's small fixed-size mock), it renders at
 * literally `width`×`height`. */
export function Sparkline({
  points,
  width = 120,
  height = 40,
  stretch = false,
}: {
  points: number[];
  width?: number;
  height?: number;
  stretch?: boolean;
}) {
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

  // The endpoint dot is a plain HTML circle positioned by percentage, not an
  // SVG <circle> — `preserveAspectRatio="none"` scales x and y independently
  // to stretch the path across a wide card, which turns an SVG circle into
  // a flattened ellipse. A CSS circle placed by percentage is immune to that.
  return (
    <span className={cn("relative block", stretch ? "w-full" : undefined)} style={stretch ? { height } : { width, height }}>
      <svg
        viewBox={`0 0 ${width} ${height}`}
        preserveAspectRatio={stretch ? "none" : undefined}
        className="block h-full w-full"
        aria-hidden="true"
      >
        <path d={`M${path}`} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
      </svg>
      <span
        aria-hidden="true"
        className="absolute rounded-full bg-current"
        style={{
          width: 6,
          height: 6,
          left: `${(lastX / width) * 100}%`,
          top: `${(lastY / height) * 100}%`,
          transform: "translate(-50%, -50%)",
        }}
      />
    </span>
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
      <div className="flex items-center gap-lg">
        <div className="min-w-0 flex-1">
          <p className="text-micro uppercase text-gold">{label}</p>
          {loading ? (
            <Skeleton className="mt-sm h-10 w-40 bg-white/10" />
          ) : (
            <p className="mt-xs text-[38px] font-extrabold leading-none tracking-tight text-hero-text tabular">
              {value}
            </p>
          )}
          {!loading && delta && (
            <span
              className={cn(
                "mt-md inline-flex shrink-0 items-center gap-hair rounded-pill bg-hero-chip px-sm py-hair text-caption font-semibold text-hero-text tabular",
              )}
            >
              {delta.dir === "up" ? <ArrowUpRight size={12} /> : <ArrowDownRight size={12} />}
              {delta.text}
            </span>
          )}
        </div>
        {!loading && sparkline && (
          <span className="hidden min-w-0 flex-1 text-gold sm:block">
            <Sparkline points={sparkline} height={64} stretch />
          </span>
        )}
      </div>
    </div>
  );
}
