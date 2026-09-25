import type { CSSProperties, ReactNode } from "react";
import Link from "next/link";
import { ArrowRight, Check } from "lucide-react";
import { TallyMark } from "@/components/tally-mark";
import { cn } from "@/lib/utils";

const SIGNUP = "/auth/login?screen_hint=signup";
const LOGIN = "/auth/login";

/** Dark-theme category hues from design/tokens.json — the landing page is
 *  always on the ink ground, so it uses these directly rather than the
 *  theme-switching CSS vars. */
const CAT = {
  groceries: "#46C088",
  restaurants: "#F2A25C",
  transport: "#5AA0E0",
  shopping: "#EC85B8",
  other: "#9A9A94",
} as const;

const vars = (v: Record<string, string | number>) => v as CSSProperties;

/* ─────────────────────────── header ─────────────────────────── */

export function SiteHeader({ isSignedIn = false }: { isSignedIn?: boolean }) {
  return (
    <header className="sticky top-0 z-30 border-b border-[color:var(--rule)] bg-[rgba(12,20,18,0.82)] backdrop-blur-md">
      <div className="mx-auto flex h-[72px] max-w-[1180px] items-center justify-between px-6">
        <Link href="/" aria-label="Tally home">
          <Wordmark />
        </Link>
        <nav className="flex items-center gap-2 sm:gap-6">
          <Link
            href="/#how"
            className="hidden text-[15px] text-[color:var(--cream-2)] transition-colors hover:text-[color:var(--cream)] sm:block"
          >
            How it works
          </Link>
          {isSignedIn ? (
            <a href="/dashboard" className="l-btn l-btn-sm">
              Go to dashboard
            </a>
          ) : (
            <>
              <a
                href={LOGIN}
                className="px-3 text-[15px] text-[color:var(--cream-2)] transition-colors hover:text-[color:var(--cream)]"
              >
                Log in
              </a>
              <a href={SIGNUP} className="l-btn l-btn-sm">
                Get started
              </a>
            </>
          )}
        </nav>
      </div>
    </header>
  );
}

function Wordmark() {
  return (
    <span className="flex items-center gap-3">
      <span className="grid h-10 w-10 place-items-center rounded-[11px] bg-[color:var(--ink-3)] text-[color:var(--gold)] ring-1 ring-[color:var(--rule)]">
        <TallyMark size={22} />
      </span>
      <span className="l-display text-[22px] font-extrabold">Tally</span>
    </span>
  );
}

/* ─────────────────────────── hero ─────────────────────────── */

export function Hero() {
  return (
    <section className="relative overflow-hidden">
      <div
        aria-hidden
        className="pointer-events-none absolute right-[-12%] top-[-30%] h-[720px] w-[720px] rounded-full"
        style={{ background: "radial-gradient(circle, rgba(53,199,154,0.13), transparent 62%)" }}
      />
      <div
        aria-hidden
        className="pointer-events-none absolute left-[-18%] top-[30%] h-[520px] w-[520px] rounded-full"
        style={{ background: "radial-gradient(circle, rgba(217,174,92,0.10), transparent 64%)" }}
      />

      <div className="relative mx-auto grid max-w-[1180px] items-center gap-16 px-6 pb-24 pt-14 lg:grid-cols-[1.08fr_1fr] lg:gap-10 lg:pb-32 lg:pt-20">
        <div>
          <p className="l-eyebrow l-rise">Expense tracking, minus the typing</p>
          <h1
            className="l-display l-rise mt-6 text-[clamp(3rem,7.2vw,5.9rem)] font-extrabold leading-[0.95]"
            style={vars({ "--d": "80ms" })}
          >
            Snap a receipt.
            <br />
            <span className="text-[color:var(--gold)]">It tallies itself.</span>
          </h1>
          <p
            className="l-rise mt-8 max-w-[34rem] text-[19px] leading-[1.6] text-[color:var(--cream-2)]"
            style={vars({ "--d": "160ms" })}
          >
            Point your camera at any receipt &mdash; crumpled, faded, handwritten.
            Tally reads the merchant, total, tax and every line item, files it
            under the right category, and adds it to your month in about five
            seconds.
          </p>
          <div
            className="l-rise mt-10 flex flex-col gap-3 sm:flex-row"
            style={vars({ "--d": "240ms" })}
          >
            <a href={SIGNUP} className="l-btn">
              Start free <ArrowRight size={17} />
            </a>
            <Link href="/#how" className="l-btn l-btn-ghost">
              See how it works
            </Link>
          </div>
          <p
            className="l-mono l-rise mt-8 text-[12.5px] tracking-wide text-[color:var(--cream-3)]"
            style={vars({ "--d": "320ms" })}
          >
            Free forever tier &middot; No card &middot; Web now, iPhone soon
          </p>
        </div>

        <HeroScan />
      </div>
    </section>
  );
}

function HeroScan() {
  const chips: { k: string; v: ReactNode; x: string }[] = [
    { k: "Merchant", v: "Bluebird Cafe", x: "lg:ml-6" },
    { k: "Date", v: "Sep 5, 2026", x: "lg:ml-14" },
    {
      k: "Category",
      v: (
        <span className="inline-flex items-center gap-2">
          <i className="h-2 w-2 rounded-full" style={{ background: CAT.restaurants }} />
          Restaurants
        </span>
      ),
      x: "lg:ml-10",
    },
    { k: "Total", v: "$8.43", x: "lg:ml-3" },
  ];

  return (
    <div className="relative flex flex-col items-center gap-10 lg:flex-row lg:justify-center lg:gap-0">
      <div className="relative w-[272px] shrink-0 -rotate-[2.5deg] sm:w-[300px]">
        <Receipt />
      </div>

      <div className="z-10 grid w-full max-w-[300px] grid-cols-2 gap-3 lg:-ml-3 lg:flex lg:w-auto lg:max-w-none lg:flex-col lg:gap-3.5">
        {chips.map((c, i) => (
          <div
            key={c.k}
            className={cn(
              "l-rise rounded-2xl bg-[rgba(24,39,35,0.95)] px-4 py-3 shadow-[0_18px_40px_rgba(0,0,0,0.45)] ring-1 ring-[color:var(--rule-2)] backdrop-blur",
              c.x,
            )}
            style={vars({ "--d": `${700 + i * 160}ms` })}
          >
            <p className="l-mono text-[10.5px] uppercase tracking-[0.12em] text-[color:var(--cream-3)]">
              {c.k}
            </p>
            <p className="mt-0.5 text-[15px] font-medium tabular-nums">{c.v}</p>
          </div>
        ))}
        <div
          className={cn(
            "l-rise col-span-2 inline-flex items-center gap-2 self-start rounded-full bg-[color:var(--teal-soft)] px-3.5 py-2 text-[13px] font-medium text-[color:var(--teal)] lg:ml-8",
          )}
          style={vars({ "--d": "1380ms" })}
        >
          <Check size={14} strokeWidth={2.5} /> Saved to September &middot; 4.6s
        </div>
      </div>
    </div>
  );
}

function Receipt({ size = "lg" }: { size?: "lg" | "md" }) {
  const lg = size === "lg";
  return (
    <div
      className={cn(
        "l-receipt overflow-visible",
        lg ? "px-7 py-8 text-[13px] leading-[1.6]" : "px-6 py-7 text-[12px] leading-[1.6]",
      )}
    >
      <div className="text-center">
        <p className="l-display text-[21px] font-extrabold tracking-[-0.01em]">BLUEBIRD CAFE</p>
        <p className="text-[color:var(--graphite-2)]">123 Main St</p>
        <p className="text-[color:var(--graphite-2)]">09/05/2026 &nbsp;08:14</p>
      </div>
      <div className="my-4 border-t border-dashed border-[rgba(30,35,33,0.35)]" />
      <Line k="Oat latte" v="4.50" />
      <Line k="Almond croissant" v="3.25" />
      <div className="my-4 border-t border-dashed border-[rgba(30,35,33,0.35)]" />
      <Line k="Subtotal" v="7.75" muted />
      <Line k="Tax" v="0.68" muted />
      <div className="mt-1.5 flex justify-between text-[15px] font-medium">
        <span>TOTAL</span>
        <span>8.43</span>
      </div>
      <p className="mt-6 text-center text-[11px] tracking-[0.2em] text-[color:var(--graphite-2)]">
        THANK YOU
      </p>
      <div
        aria-hidden
        className="mx-auto mt-3 h-9 w-[78%] opacity-80"
        style={{
          background:
            "repeating-linear-gradient(90deg,#1e2321 0 2px,transparent 2px 4px,#1e2321 4px 5px,transparent 5px 8px,#1e2321 8px 11px,transparent 11px 12px,#1e2321 12px 13px,transparent 13px 16px)",
        }}
      />
      {lg && <div aria-hidden className="l-scan" style={vars({ "--scan-travel": "400px" })} />}
    </div>
  );
}

function Line({ k, v, muted }: { k: string; v: string; muted?: boolean }) {
  return (
    <div className={cn("flex items-baseline gap-2", muted && "text-[color:var(--graphite-2)]")}>
      <span className="whitespace-nowrap">{k}</span>
      <span className="l-leader" />
      <span>{v}</span>
    </div>
  );
}

/* ─────────────────────────── figures strip ─────────────────────────── */

export function Figures() {
  const figs = [
    { n: "~5", u: "sec", label: "from photo to a filed expense" },
    { n: "0", u: "forms", label: "to fill in — nothing to type" },
    { n: "1", u: "place", label: "for every receipt you keep" },
  ];
  return (
    <section className="border-y border-[color:var(--rule)] bg-[color:var(--ink-2)]">
      <div className="mx-auto grid max-w-[1180px] px-6 sm:grid-cols-3">
        {figs.map((f, i) => (
          <div
            key={f.label}
            className={cn(
              "py-10 sm:py-12",
              i > 0 && "border-t border-[color:var(--rule)] sm:border-l sm:border-t-0 sm:pl-10",
            )}
          >
            <p className="l-display flex items-baseline gap-2 text-[56px] font-extrabold leading-none">
              {f.n}
              <span className="l-mono text-[14px] font-medium tracking-normal text-[color:var(--gold)]">
                {f.u}
              </span>
            </p>
            <p className="mt-3 text-[15px] text-[color:var(--cream-2)]">{f.label}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

/* ─────────────────────────── reads the whole receipt ─────────────────────────── */

export function ReadsReceipts() {
  const reads = ["Merchant & address", "Date & time", "Every line item", "Subtotal, tax & total", "Category"];
  return (
    <section className="px-6 py-28 lg:py-36">
      <div className="mx-auto grid max-w-[1180px] items-center gap-16 lg:grid-cols-[1fr_1.05fr] lg:gap-24">
        <div>
          <p className="l-eyebrow">What it reads</p>
          <h2 className="l-display mt-5 text-[clamp(2.4rem,4.6vw,3.6rem)] font-extrabold leading-[1.02]">
            The whole receipt, not just the total.
          </h2>
          <p className="mt-6 max-w-[32rem] text-[18px] leading-[1.65] text-[color:var(--cream-2)]">
            Everything on the paper becomes clean, searchable data &mdash; lifted
            from the photo, never retyped. You glance, confirm, and move on.
          </p>
          <ul className="mt-10 border-t border-[color:var(--rule)]">
            {reads.map((r) => (
              <li
                key={r}
                className="flex items-center justify-between border-b border-[color:var(--rule)] py-3.5 text-[16px]"
              >
                {r}
                <Check size={16} className="text-[color:var(--gold)]" />
              </li>
            ))}
          </ul>
        </div>

        <ExtractedRecord />
      </div>
    </section>
  );
}

function ExtractedRecord() {
  return (
    <div className="relative">
      <div
        aria-hidden
        className="absolute -inset-8 rounded-[40px]"
        style={{ background: "radial-gradient(ellipse at 30% 20%, rgba(217,174,92,0.10), transparent 65%)" }}
      />
      <div className="relative overflow-hidden rounded-[28px] bg-[color:var(--ink-3)] ring-1 ring-[color:var(--rule-2)] shadow-[0_40px_80px_rgba(0,0,0,0.45)]">
        <div className="flex items-center justify-between border-b border-[color:var(--rule)] px-7 py-5">
          <div>
            <p className="l-display text-[22px] font-bold tracking-[-0.02em]">Bluebird Cafe</p>
            <p className="l-mono text-[12px] text-[color:var(--cream-3)]">Fri, Sep 5, 2026 &middot; 08:14</p>
          </div>
          <span
            className="inline-flex items-center gap-2 rounded-full px-3 py-1.5 text-[13px] font-medium"
            style={{ background: "rgba(242,162,92,0.14)", color: CAT.restaurants }}
          >
            <i className="h-2 w-2 rounded-full" style={{ background: CAT.restaurants }} />
            Restaurants
          </span>
        </div>

        <div className="l-mono px-7 py-6 text-[14px] tabular-nums">
          <p className="mb-3 text-[11px] uppercase tracking-[0.14em] text-[color:var(--cream-3)]">
            Line items
          </p>
          {[
            ["Oat latte", "1", "4.50"],
            ["Almond croissant", "1", "3.25"],
          ].map(([name, qty, amt]) => (
            <div key={name} className="flex items-baseline gap-2 py-1.5">
              <span className="text-[color:var(--cream)]">{name}</span>
              <span className="text-[color:var(--cream-3)]">&times;{qty}</span>
              <span className="l-leader text-[color:var(--cream)]" />
              <span>{amt}</span>
            </div>
          ))}
          <div className="my-4 border-t border-[color:var(--rule)]" />
          {[
            ["Subtotal", "7.75"],
            ["Tax", "0.68"],
          ].map(([k, v]) => (
            <div key={k} className="flex items-baseline gap-2 py-1 text-[color:var(--cream-2)]">
              <span>{k}</span>
              <span className="l-leader" />
              <span>{v}</span>
            </div>
          ))}
          <div className="mt-3 flex items-baseline justify-between">
            <span className="text-[12px] uppercase tracking-[0.14em] text-[color:var(--cream-3)]">Total</span>
            <span className="l-display text-[34px] font-extrabold tracking-[-0.03em] text-[color:var(--gold)]">
              $8.43
            </span>
          </div>
        </div>

        <div className="flex items-center gap-2 border-t border-[color:var(--rule)] bg-[color:var(--ink-2)] px-7 py-4 text-[14px] text-[color:var(--teal)]">
          <Check size={15} strokeWidth={2.5} /> Filed to September &mdash; nothing typed
        </div>
      </div>
    </div>
  );
}

/* ─────────────────────────── how it works (paper band) ─────────────────────────── */

export function HowItWorks() {
  const steps = [
    {
      title: "Point & shoot",
      body: "Snap it, or pick a photo you already took. Bad lighting and coffee stains are fine.",
    },
    {
      title: "Glance & confirm",
      body: "One screen shows what Tally read. Tap anything to fix it — usually there's nothing to fix.",
    },
    {
      title: "It's filed",
      body: "Dated, categorized and counted in your month before your phone is back in your pocket.",
    },
  ];
  return (
    <section id="how" className="scroll-mt-20 bg-[color:var(--paper)] px-6 py-28 text-[color:var(--graphite)] lg:py-36">
      <div className="mx-auto max-w-[1180px]">
        <p className="l-mono text-[12px] uppercase tracking-[0.14em] text-[color:var(--graphite-2)]">
          How it works
        </p>
        <h2 className="l-display mt-5 max-w-[16ch] text-[clamp(2.4rem,4.6vw,3.6rem)] font-extrabold leading-[1.02]">
          From shoebox to spending, in three taps.
        </h2>

        <ol className="mt-16 grid gap-12 border-t border-[rgba(30,35,33,0.15)] pt-12 md:grid-cols-3 md:gap-10">
          {steps.map((s, i) => (
            <li key={s.title}>
              <StepStrokes count={i + 1} />
              <h3 className="l-display mt-7 text-[26px] font-bold tracking-[-0.02em]">{s.title}</h3>
              <p className="mt-3 max-w-[30ch] text-[16.5px] leading-[1.6] text-[color:var(--graphite-2)]">
                {s.body}
              </p>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}

/** Step N drawn as N hand-drawn tally strokes. */
function StepStrokes({ count }: { count: number }) {
  const xs = [8, 26, 44];
  return (
    <svg
      viewBox="0 0 56 48"
      className="l-draw h-12 w-14"
      role="img"
      aria-label={`Step ${count}`}
      fill="none"
      stroke="#1e2321"
      strokeWidth={5}
      strokeLinecap="round"
    >
      {xs.slice(0, count).map((x, i) => (
        <path
          key={x}
          pathLength={1}
          style={vars({ "--i": i })}
          d={`M${x} 6 C${x + 1.5} 18 ${x - 1} 30 ${x + 0.5} 42`}
        />
      ))}
    </svg>
  );
}

/* ─────────────────────────── spending preview ─────────────────────────── */

export function Features() {
  return (
    <section className="px-6 py-28 lg:py-36">
      <div className="mx-auto grid max-w-[1180px] items-center gap-16 lg:grid-cols-[1fr_1.2fr] lg:gap-20">
        <div>
          <p className="l-eyebrow">Your month, explained</p>
          <h2 className="l-display mt-5 text-[clamp(2.4rem,4.6vw,3.6rem)] font-extrabold leading-[1.02]">
            Spending that tells you something.
          </h2>
          <p className="mt-6 max-w-[32rem] text-[18px] leading-[1.65] text-[color:var(--cream-2)]">
            Monthly totals, category breakdowns, budgets and recurring charges
            &mdash; with plain-English notes when something starts to creep up.
          </p>
          <div className="mt-10 rounded-2xl bg-[color:var(--ink-2)] p-5 ring-1 ring-[color:var(--rule)]">
            <p className="l-mono text-[11px] uppercase tracking-[0.14em] text-[color:var(--gold)]">
              Insight
            </p>
            <p className="mt-2 text-[16px] leading-[1.55]">
              Restaurants are up 18% for the third month running &mdash; mostly
              weekday lunches.
            </p>
          </div>
        </div>

        <MonthPreview />
      </div>
    </section>
  );
}

function MonthPreview() {
  // Apr → Sep monthly totals. Chart is drawn to scale on a 1,200–1,600 axis.
  const months = ["Apr", "May", "Jun", "Jul", "Aug", "Sep"];
  const totals = [1420, 1550, 1376, 1490, 1376, 1284.5];
  const X0 = 44;
  const X1 = 588;
  const Y_TOP = 16;
  const Y_BOT = 166;
  const V_MIN = 1200;
  const V_MAX = 1600;
  const x = (i: number) => X0 + (i * (X1 - X0)) / (totals.length - 1);
  const y = (v: number) => Y_TOP + ((V_MAX - v) / (V_MAX - V_MIN)) * (Y_BOT - Y_TOP);
  const line = totals.map((v, i) => `${i ? "L" : "M"}${x(i).toFixed(1)} ${y(v).toFixed(1)}`).join(" ");
  const area = `${line} L${x(totals.length - 1)} ${Y_BOT} L${X0} ${Y_BOT} Z`;
  const grid = [1300, 1400, 1500];

  const cats = [
    { name: "Groceries", amt: 412, c: CAT.groceries },
    { name: "Shopping", amt: 311, c: CAT.shopping },
    { name: "Restaurants", amt: 268, c: CAT.restaurants },
    { name: "Other", amt: 150.5, c: CAT.other },
    { name: "Transport", amt: 143, c: CAT.transport },
  ];
  const max = Math.max(...cats.map((c) => c.amt));
  const fmt = (n: number) =>
    n.toLocaleString("en-US", { style: "currency", currency: "USD", minimumFractionDigits: n % 1 ? 2 : 0 });

  return (
    <div className="overflow-hidden rounded-[28px] bg-[color:var(--ink-3)] ring-1 ring-[color:var(--rule-2)] shadow-[0_40px_80px_rgba(0,0,0,0.45)]">
      <div className="flex flex-wrap items-end justify-between gap-4 px-7 pt-7">
        <div>
          <p className="l-mono text-[11px] uppercase tracking-[0.14em] text-[color:var(--cream-3)]">
            September spending
          </p>
          <p className="l-display mt-1 text-[48px] font-extrabold leading-none tracking-[-0.035em] tabular-nums">
            $1,284<span className="text-[color:var(--cream-3)]">.50</span>
          </p>
        </div>
        <span className="rounded-full bg-[color:var(--teal-soft)] px-3 py-1.5 text-[13px] font-medium text-[color:var(--teal)]">
          &darr; $92 vs August
        </span>
      </div>

      <svg viewBox="0 0 620 196" className="mt-4 block w-full" role="img" aria-label="Monthly spending, April to September: $1,420, $1,550, $1,376, $1,490, $1,376, $1,284.50">
        <defs>
          <linearGradient id="l-area" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0%" stopColor="#D9AE5C" stopOpacity="0.32" />
            <stop offset="100%" stopColor="#D9AE5C" stopOpacity="0" />
          </linearGradient>
        </defs>
        {grid.map((g) => (
          <g key={g}>
            <line x1={X0} x2={X1} y1={y(g)} y2={y(g)} stroke="rgba(241,236,225,0.08)" strokeDasharray="3 5" />
            <text x={X0 - 10} y={y(g) + 4} textAnchor="end" fontSize="11" fill="rgba(241,236,225,0.4)" fontFamily="var(--font-mono)">
              {`${(g / 1000).toFixed(1)}k`}
            </text>
          </g>
        ))}
        <path d={area} fill="url(#l-area)" />
        <path d={line} fill="none" stroke="#D9AE5C" strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round" />
        {totals.map((v, i) => (
          <circle key={i} cx={x(i)} cy={y(v)} r={i === totals.length - 1 ? 5.5 : 3} fill={i === totals.length - 1 ? "#D9AE5C" : "#182723"} stroke="#D9AE5C" strokeWidth="2" />
        ))}
        {months.map((m, i) => (
          <text key={m} x={x(i)} y={188} textAnchor="middle" fontSize="11" fill={i === months.length - 1 ? "#F1ECE1" : "rgba(241,236,225,0.4)"} fontFamily="var(--font-mono)">
            {m}
          </text>
        ))}
      </svg>

      <div className="mt-2 border-t border-[color:var(--rule)] px-7 py-6">
        <ul className="space-y-3.5">
          {cats.map((c) => (
            <li key={c.name} className="grid grid-cols-[110px_1fr_auto] items-center gap-4 text-[14px]">
              <span className="flex items-center gap-2 text-[color:var(--cream-2)]">
                <i className="h-2 w-2 rounded-full" style={{ background: c.c }} />
                {c.name}
              </span>
              <span className="h-1.5 rounded-full bg-[color:var(--rule)]">
                <span className="block h-full rounded-full" style={{ width: `${(c.amt / max) * 100}%`, background: c.c }} />
              </span>
              <span className="l-mono w-[76px] text-right tabular-nums">{fmt(c.amt)}</span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

/* ─────────────────────────── privacy ─────────────────────────── */

export function Privacy() {
  const facts = [
    ["No ads, no ad trackers", "Nothing in Tally exists to watch you or sell to you."],
    ["Your data isn't for sale", "We never sell personal data. Service providers only process it to run Tally."],
    ["No account needed on iPhone", "Scan and track on your phone first; sign in only when you want sync and the web app."],
    ["Delete it all, anytime", "Deleting your account removes every receipt and image with it."],
  ];
  return (
    <section className="border-t border-[color:var(--rule)] px-6 py-28 lg:py-32">
      <div className="mx-auto grid max-w-[1180px] gap-14 lg:grid-cols-[0.9fr_1.1fr] lg:gap-20">
        <div>
          <p className="l-eyebrow">Privacy</p>
          <h2 className="l-display mt-5 text-[clamp(2.4rem,4.6vw,3.6rem)] font-extrabold leading-[1.02]">
            Your receipts stay yours.
          </h2>
          <a
            href="/privacy"
            className="mt-6 inline-flex items-center gap-2 text-[15px] text-[color:var(--gold)] hover:text-[color:var(--gold-2)]"
          >
            Read the privacy policy <ArrowRight size={15} />
          </a>
        </div>
        <dl className="grid gap-px overflow-hidden rounded-[24px] bg-[color:var(--rule)] ring-1 ring-[color:var(--rule)] sm:grid-cols-2">
          {facts.map(([t, d]) => (
            <div key={t} className="bg-[color:var(--ink)] p-7">
              <dt className="l-display text-[20px] font-bold tracking-[-0.015em]">{t}</dt>
              <dd className="mt-2 text-[15px] leading-[1.6] text-[color:var(--cream-2)]">{d}</dd>
            </div>
          ))}
        </dl>
      </div>
    </section>
  );
}

/* ─────────────────────────── closing CTA ─────────────────────────── */

export function BottomCTA() {
  const strokes = [40, 88, 136, 184];
  return (
    <section className="px-6 pb-28">
      <div className="relative mx-auto max-w-[1180px] overflow-hidden rounded-[32px] bg-[color:var(--ink-2)] px-8 py-20 ring-1 ring-[color:var(--rule)] sm:px-16 lg:py-24">
        <svg
          aria-hidden
          viewBox="0 0 240 240"
          className="l-draw pointer-events-none absolute -right-6 top-1/2 hidden h-[300px] w-[300px] -translate-y-1/2 opacity-90 md:block"
          fill="none"
          strokeLinecap="round"
        >
          {strokes.map((x, i) => (
            <path key={x} pathLength={1} style={vars({ "--i": i })} stroke="#D9AE5C" strokeWidth="11" d={`M${x} 40 C${x + 3} 100 ${x - 2} 150 ${x + 1} 200`} />
          ))}
          <path pathLength={1} style={vars({ "--i": 4 })} stroke="#35C79A" strokeWidth="10" d="M20 176 C80 140 150 96 210 58" />
        </svg>

        <div className="relative max-w-[36rem]">
          <h2 className="l-display text-[clamp(2.6rem,5.4vw,4.4rem)] font-extrabold leading-[0.98]">
            Your <span className="text-[color:var(--gold)]">last</span> manual expense entry.
          </h2>
          <p className="mt-6 text-[18px] leading-[1.6] text-[color:var(--cream-2)]">
            Sign in with Google, Apple or email and scan your first receipt in
            the next minute. Free forever tier, no card.
          </p>
          <a href={SIGNUP} className="l-btn mt-9">
            Start free <ArrowRight size={17} />
          </a>
        </div>
      </div>
    </section>
  );
}

/* ─────────────────────────── footer ─────────────────────────── */

const FOOTER_LINKS: { heading: string; links: { label: string; href: string }[] }[] = [
  {
    heading: "Product",
    links: [
      { label: "How it works", href: "/#how" },
      { label: "Get started", href: SIGNUP },
      { label: "Log in", href: LOGIN },
    ],
  },
  {
    heading: "Company",
    links: [
      { label: "Data Eaver Inc.", href: "https://dataeaver.ca" },
      { label: "Privacy policy", href: "/privacy" },
      { label: "Terms of service", href: "/terms" },
      { label: "Contact", href: "mailto:contact@dataeaver.ca" },
    ],
  },
];

export function SiteFooter() {
  return (
    <footer className="border-t border-[color:var(--rule)] px-6 pb-10 pt-16">
      <div className="mx-auto max-w-[1180px]">
        <div className="grid gap-12 sm:grid-cols-[1.5fr_1fr_1fr]">
          <div>
            <Wordmark />
            <p className="mt-5 max-w-[28ch] text-[15px] leading-[1.6] text-[color:var(--cream-2)]">
              Snap a receipt. It tallies itself. Expense tracking for the web,
              with iPhone coming soon.
            </p>
          </div>
          {FOOTER_LINKS.map((col) => (
            <div key={col.heading}>
              <p className="l-mono text-[11px] uppercase tracking-[0.14em] text-[color:var(--cream-3)]">
                {col.heading}
              </p>
              <ul className="mt-5 space-y-3">
                {col.links.map((l) => (
                  <li key={l.label}>
                    <a
                      href={l.href}
                      className="text-[15px] text-[color:var(--cream-2)] transition-colors hover:text-[color:var(--cream)]"
                    >
                      {l.label}
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
        <div className="mt-14 border-t border-[color:var(--rule)] pt-6 text-[13px] text-[color:var(--cream-3)]">
          &copy; {new Date().getFullYear()} Data Eaver Inc. All rights reserved.
        </div>
      </div>
    </footer>
  );
}

/* ─────────────────────────── error banner ─────────────────────────── */

export function AuthErrorBanner({ message }: { message: string }) {
  return (
    <div className="border-b border-[#F26A5C]/40 bg-[#F26A5C]/15 px-6 py-3 text-center text-[14px] text-[#F26A5C]">
      Sign-in didn&rsquo;t complete: {message}
    </div>
  );
}
