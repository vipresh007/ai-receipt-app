import type { ReactNode } from "react";
import {
  ArrowRight,
  Camera,
  Check,
  FileText,
  Layers,
  ScanLine,
  Sparkles,
  Table2,
} from "lucide-react";
import { buttonVariants } from "@/components/ui/button";
import { categoryColor } from "@/lib/categories";
import { cn } from "@/lib/utils";

const SIGNUP = "/auth/login?screen_hint=signup";
const LOGIN = "/auth/login";

/* ─────────────────────────── header ─────────────────────────── */

export function SiteHeader() {
  return (
    <header className="sticky top-0 z-30 border-b border-border/70 bg-bg/80 backdrop-blur-md">
      <div className="mx-auto flex h-14 max-w-content items-center justify-between px-lg">
        <span className="flex items-center gap-sm">
          <Wordmark />
        </span>
        <nav className="flex items-center gap-xs">
          <a
            href="#how"
            className="hidden rounded-md px-md py-sm text-callout text-text-secondary transition-colors hover:text-text sm:block"
          >
            How it works
          </a>
          <a
            href={LOGIN}
            className="rounded-md px-md py-sm text-callout text-text-secondary transition-colors hover:text-text"
          >
            Log in
          </a>
          <a href={SIGNUP} className={buttonVariants({ size: "sm" })}>
            Get started
          </a>
        </nav>
      </div>
    </header>
  );
}

function Wordmark() {
  return (
    <span className="flex items-center gap-sm">
      <span className="grid h-7 w-7 place-items-center rounded-md bg-accent text-accent-fg shadow-e1">
        <ScanLine size={16} />
      </span>
      <span className="text-callout font-semibold tracking-tight">AI Receipt</span>
    </span>
  );
}

/* ─────────────────────────── hero ─────────────────────────── */

export function Hero() {
  return (
    <section className="relative overflow-hidden">
      {/* soft glow */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-x-0 top-[-20%] mx-auto h-[520px] max-w-4xl rounded-pill bg-accent-muted blur-[120px]"
      />
      <div className="relative mx-auto flex max-w-content flex-col items-center px-lg pt-4xl text-center md:pt-[6rem]">
        <span className="inline-flex items-center gap-xs rounded-pill border border-border bg-surface/80 px-md py-hair text-micro uppercase tracking-wide text-text-secondary backdrop-blur">
          <Sparkles size={12} className="text-accent" />
          Expense tracking, minus the tracking
        </span>

        <h1 className="mt-lg max-w-3xl text-[2.6rem] font-bold leading-[1.03] tracking-tight sm:text-[3.5rem]">
          Snap a receipt.{" "}
          <span className="bg-gradient-to-r from-accent to-[color:var(--cat-transport)] bg-clip-text text-transparent">
            It files itself.
          </span>
        </h1>

        <p className="mt-lg max-w-xl text-body text-text-secondary sm:text-[1.0625rem]">
          Point your camera at any receipt — crumpled, faded, handwritten. AI
          pulls the merchant, total, tax and category and drops it into your
          spending in about five seconds.
        </p>

        <div className="mt-xl flex flex-col gap-sm sm:flex-row">
          <a href={SIGNUP} className={cn(buttonVariants(), "px-xl")}>
            Get started free <ArrowRight size={16} />
          </a>
          <a
            href="#how"
            className={cn(buttonVariants({ variant: "secondary" }), "px-xl")}
          >
            See how it works
          </a>
        </div>

        <ul className="mt-lg flex flex-wrap items-center justify-center gap-x-lg gap-y-xs text-caption text-text-tertiary">
          {["~5-second scans", "Reads faded & handwritten", "Auto-categorized"].map(
            (t) => (
              <li key={t} className="flex items-center gap-xs">
                <Check size={13} className="text-accent" />
                {t}
              </li>
            ),
          )}
        </ul>

        <HeroVisual />
      </div>
    </section>
  );
}

function HeroVisual() {
  return (
    <div className="relative mt-2xl w-full max-w-3xl pb-4xl">
      {/* receipt card, peeking from behind */}
      <div className="absolute -left-2 top-8 hidden w-52 -rotate-6 sm:block">
        <ReceiptCard compact />
      </div>
      {/* main dashboard mock */}
      <div className="relative sm:ml-16">
        <BrowserFrame>
          <DashboardMock />
        </BrowserFrame>
      </div>
    </div>
  );
}

/* ─────────────────────────── framed mock ─────────────────────────── */

function BrowserFrame({ children }: { children: ReactNode }) {
  return (
    <div className="overflow-hidden rounded-2xl border border-border bg-surface shadow-e2">
      <div className="flex items-center gap-sm border-b border-border px-md py-sm">
        <span className="flex gap-xs">
          {["#ef4444", "#eab308", "#22c55e"].map((c) => (
            <span
              key={c}
              className="h-2.5 w-2.5 rounded-pill opacity-70"
              style={{ background: c }}
            />
          ))}
        </span>
        <span className="mx-auto rounded-md bg-surface-2 px-md py-hair text-[10px] text-text-tertiary">
          app.aireceipt.com/dashboard
        </span>
      </div>
      <div className="p-lg text-left">{children}</div>
    </div>
  );
}

function DashboardMock() {
  const cats = [
    { slug: "groceries", label: "Groceries", pct: 88, amt: "$412.90" },
    { slug: "restaurants", label: "Restaurants", pct: 64, amt: "$305.14" },
    { slug: "transport", label: "Transport", pct: 36, amt: "$168.40" },
    { slug: "shopping", label: "Shopping", pct: 21, amt: "$98.20" },
    { slug: "utilities", label: "Utilities", pct: 14, amt: "$61.75" },
  ];
  return (
    <div className="space-y-lg">
      <div className="grid grid-cols-2 gap-md">
        <div className="rounded-xl border border-border bg-bg p-md">
          <p className="text-[10px] uppercase tracking-wide text-text-tertiary">
            This month
          </p>
          <p className="mt-hair text-2xl font-bold tabular">$1,284.50</p>
          <p className="mt-hair text-[11px] text-success">↓ $92 vs last month</p>
        </div>
        <div className="rounded-xl border border-border bg-bg p-md">
          <p className="text-[10px] uppercase tracking-wide text-text-tertiary">
            Receipts
          </p>
          <p className="mt-hair text-2xl font-bold tabular">37</p>
          <p className="mt-hair text-[11px] text-text-tertiary">this month</p>
        </div>
      </div>

      <div className="space-y-sm">
        {cats.map((c) => (
          <div key={c.slug} className="flex items-center gap-md">
            <span className="w-20 shrink-0 text-[11px] text-text-secondary">
              {c.label}
            </span>
            <span className="h-2 flex-1 overflow-hidden rounded-pill bg-surface-2">
              <span
                className="block h-full rounded-pill"
                style={{ width: `${c.pct}%`, background: categoryColor(c.slug) }}
              />
            </span>
            <span className="w-14 shrink-0 text-right text-[11px] tabular text-text-secondary">
              {c.amt}
            </span>
          </div>
        ))}
      </div>

      <div className="rounded-xl border border-border bg-bg p-sm text-[11px] text-text-secondary">
        <span className="text-accent">✦ Insight </span>
        Restaurants are up 18% for the third month running.
      </div>
    </div>
  );
}

/* ─────────────────────────── receipt → data ─────────────────────────── */

function ReceiptCard({ compact }: { compact?: boolean }) {
  return (
    <div
      className={cn(
        "rounded-lg border border-border bg-surface p-md font-mono shadow-e1",
        compact ? "text-[9px] leading-[1.5]" : "text-[11px] leading-relaxed",
      )}
    >
      <p className="text-center font-semibold tracking-wide">BLUEBIRD CAFE</p>
      <p className="text-center text-text-tertiary">123 Main St</p>
      <div className="my-sm border-t border-dashed border-border" />
      <div className="flex justify-between">
        <span>Latte</span>
        <span>4.50</span>
      </div>
      <div className="flex justify-between">
        <span>Croissant</span>
        <span>3.25</span>
      </div>
      <div className="my-sm border-t border-dashed border-border" />
      <div className="flex justify-between text-text-tertiary">
        <span>Subtotal</span>
        <span>7.75</span>
      </div>
      <div className="flex justify-between text-text-tertiary">
        <span>Tax</span>
        <span>0.68</span>
      </div>
      <div className="flex justify-between font-semibold">
        <span>TOTAL</span>
        <span>8.43</span>
      </div>
    </div>
  );
}

function ExtractedCard() {
  const fields = [
    ["Merchant", "Bluebird Cafe"],
    ["Date", "Sep 5, 2026"],
    ["Total", "$8.43"],
    ["Tax", "$0.68"],
  ];
  return (
    <div className="rounded-xl border border-border bg-surface p-lg shadow-e1">
      <span
        className="inline-flex items-center gap-xs rounded-pill px-sm py-hair text-[11px] font-medium"
        style={{
          background: `color-mix(in srgb, ${categoryColor("restaurants")} 15%, transparent)`,
          color: categoryColor("restaurants"),
        }}
      >
        <FileText size={11} /> Restaurants
      </span>
      <dl className="mt-md grid grid-cols-2 gap-md">
        {fields.map(([k, v]) => (
          <div key={k}>
            <dt className="text-[11px] text-text-tertiary">{k}</dt>
            <dd className="text-callout tabular">{v}</dd>
          </div>
        ))}
      </dl>
      <div className="mt-md flex items-center gap-xs text-caption text-success">
        <Check size={14} /> Saved to September
      </div>
    </div>
  );
}

export function ReadsReceipts() {
  return (
    <section className="border-t border-border px-lg py-4xl">
      <div className="mx-auto max-w-content">
        <h2 className="max-w-lg text-title">It reads the whole receipt.</h2>
        <p className="mt-sm max-w-lg text-callout text-text-secondary">
          Merchant, date, subtotal, tax and every line item — lifted from the
          photo, not retyped. You just glance and confirm.
        </p>
        <div className="mt-2xl grid items-center gap-lg sm:grid-cols-[1fr_auto_1fr]">
          <div className="mx-auto w-full max-w-[200px] -rotate-2">
            <ReceiptCard />
          </div>
          <div className="flex items-center justify-center gap-xs text-text-tertiary">
            <span className="hidden text-micro uppercase tracking-wide sm:block">
              AI
            </span>
            <ArrowRight className="rotate-90 sm:rotate-0" size={20} />
          </div>
          <div className="mx-auto w-full max-w-xs">
            <ExtractedCard />
          </div>
        </div>
      </div>
    </section>
  );
}

/* ─────────────────────────── how it works ─────────────────────────── */

export function HowItWorks() {
  const steps = [
    {
      icon: Camera,
      title: "Point & shoot",
      body: "Snap it or upload from your library. Bad lighting and coffee stains are fine.",
    },
    {
      icon: Check,
      title: "Glance & confirm",
      body: "One screen shows what the AI read. Tap to fix anything — usually nothing.",
    },
    {
      icon: Layers,
      title: "It's filed",
      body: "Categorized, dated, and on your dashboard before you've put your phone away.",
    },
  ];
  return (
    <section id="how" className="scroll-mt-16 border-t border-border bg-surface-2 px-lg py-4xl">
      <div className="mx-auto max-w-content">
        <h2 className="text-center text-title">Three taps, not a spreadsheet</h2>
        <div className="mt-2xl grid gap-lg sm:grid-cols-3">
          {steps.map(({ icon: Icon, title, body }, i) => (
            <div
              key={title}
              className="rounded-2xl border border-border bg-surface p-lg"
            >
              <div className="flex items-center justify-between">
                <span className="grid h-10 w-10 place-items-center rounded-lg bg-accent-muted text-accent">
                  <Icon size={18} />
                </span>
                <span className="text-display font-bold text-border-strong">
                  {i + 1}
                </span>
              </div>
              <h3 className="mt-md text-headline">{title}</h3>
              <p className="mt-xs text-callout text-text-secondary">{body}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

/* ─────────────────────────── features ─────────────────────────── */

export function Features() {
  const feats = [
    {
      icon: ScanLine,
      title: "Nothing to type",
      body: "No forms, no “select a category”. Point the camera and you're done.",
    },
    {
      icon: Sparkles,
      title: "Spending that explains itself",
      body: "Monthly totals, category breakdowns, and plain-English nudges when something creeps up.",
    },
    {
      icon: Table2,
      title: "Your data, structured",
      body: "Every receipt becomes clean, queryable data — chart it, export it, or just glance at it.",
    },
  ];
  return (
    <section className="border-t border-border px-lg py-4xl">
      <div className="mx-auto grid max-w-content gap-lg sm:grid-cols-3">
        {feats.map(({ icon: Icon, title, body }) => (
          <div key={title} className="rounded-2xl border border-border bg-surface p-lg">
            <span className="grid h-10 w-10 place-items-center rounded-lg bg-accent-muted text-accent">
              <Icon size={18} />
            </span>
            <h3 className="mt-md text-headline">{title}</h3>
            <p className="mt-xs text-callout text-text-secondary">{body}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

/* ─────────────────────────── closing CTA ─────────────────────────── */

export function BottomCTA() {
  return (
    <section className="px-lg py-4xl">
      <div className="relative mx-auto flex max-w-content flex-col items-center gap-md overflow-hidden rounded-2xl border border-border bg-surface px-lg py-2xl text-center">
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 bg-accent-muted opacity-60"
        />
        <div className="relative flex flex-col items-center gap-md">
          <h2 className="text-title">Retire the expense spreadsheet</h2>
          <p className="max-w-md text-callout text-text-secondary">
            Free to start. Sign in with Google or email and scan your first
            receipt in the next minute.
          </p>
          <a href={SIGNUP} className={cn(buttonVariants(), "px-xl")}>
            Get started free <ArrowRight size={16} />
          </a>
        </div>
      </div>
    </section>
  );
}

/* ─────────────────────────── footer ─────────────────────────── */

export function SiteFooter() {
  return (
    <footer className="border-t border-border px-lg py-xl">
      <div className="mx-auto flex max-w-content flex-col items-center justify-between gap-sm text-caption text-text-tertiary sm:flex-row">
        <Wordmark />
        <span>© {new Date().getFullYear()} AI Receipt · FastAPI · Next.js · Azure OpenAI</span>
      </div>
    </footer>
  );
}

/* ─────────────────────────── error banner ─────────────────────────── */

export function AuthErrorBanner({ message }: { message: string }) {
  return (
    <div className="border-b border-danger/40 bg-danger-muted px-lg py-sm text-center text-caption text-danger">
      Sign-in didn&rsquo;t complete: {message}
    </div>
  );
}
