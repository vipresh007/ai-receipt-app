import type { ReactNode } from "react";
import {
  ArrowRight,
  Camera,
  Check,
  CircleCheckBig,
  Database,
  FileText,
  Sparkles,
  TrendingUp,
  Zap,
} from "lucide-react";
import { buttonVariants } from "@/components/ui/button";
import { TallyMark } from "@/components/tally-mark";
import { Sparkline } from "@/components/hero-metric";
import { categoryColor, categoryMeta } from "@/lib/categories";
import { cn } from "@/lib/utils";

const SIGNUP = "/auth/login?screen_hint=signup";
const LOGIN = "/auth/login";

/* ─────────────────────────── header ─────────────────────────── */

export function SiteHeader({ isSignedIn = false }: { isSignedIn?: boolean }) {
  return (
    <header className="sticky top-0 z-30 border-b border-border/70 bg-bg/80 backdrop-blur-md">
      <div className="mx-auto flex h-20 max-w-[1440px] items-center justify-between px-3xl sm:px-4xl">
        <span className="flex items-center gap-sm">
          <Wordmark size="lg" />
        </span>
        <nav className="flex items-center gap-xs">
          <a
            href="#how"
            className="hidden rounded-md px-md py-sm text-callout text-text-secondary transition-colors hover:text-text sm:block"
          >
            How it works
          </a>
          {isSignedIn ? (
            <a href="/dashboard" className={buttonVariants({ size: "sm" })}>
              Go to Dashboard
            </a>
          ) : (
            <>
              <a
                href={LOGIN}
                className="rounded-md px-md py-sm text-callout text-text-secondary transition-colors hover:text-text"
              >
                Log in
              </a>
              <a href={SIGNUP} className={buttonVariants({ size: "sm" })}>
                Get started
              </a>
            </>
          )}
        </nav>
      </div>
    </header>
  );
}

function Wordmark({ size = "default" }: { size?: "default" | "lg" }) {
  const isLarge = size === "lg";
  return (
    <span className="flex items-center gap-sm">
      <span
        className={cn(
          "grid place-items-center rounded-lg bg-accent text-accent-fg shadow-e1",
          isLarge ? "h-12 w-12 rounded-xl" : "h-9 w-9",
        )}
      >
        <TallyMark size={isLarge ? 28 : 22} />
      </span>
      <span
        className={cn(
          "font-extrabold tracking-tight",
          isLarge ? "text-title" : "text-headline",
        )}
      >
        Tally
      </span>
    </span>
  );
}

/* ─────────────────────────── hero ─────────────────────────── */

export function Hero() {
  return (
    <section className="relative overflow-hidden">
      {/* soft dual glow — product teal + the landing-only gold accent */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-24 right-[-10%] h-[420px] w-[420px] rounded-pill bg-accent-muted blur-[110px]"
      />
      <div
        aria-hidden
        className="pointer-events-none absolute left-[-8%] top-[18%] h-[320px] w-[320px] rounded-pill blur-[110px]"
        style={{ background: "var(--c-landing-accent-muted)" }}
      />

      <div className="relative mx-auto grid max-w-content gap-3xl px-lg pb-4xl pt-3xl lg:grid-cols-[1.05fr_1fr] lg:items-center lg:gap-2xl lg:pt-4xl">
        <div>
          <span className="inline-flex items-center gap-xs rounded-pill border border-border bg-surface/80 px-md py-hair text-micro uppercase tracking-wide text-text-secondary backdrop-blur">
            <Sparkles size={12} style={{ color: "var(--c-landing-accent)" }} />
            Expense tracking, minus the tracking
          </span>

          <h1 className="mt-lg text-[2.75rem] font-extrabold leading-[1.05] tracking-tight sm:text-[3.4rem] lg:text-[3.75rem]">
            Snap a receipt.
            <br />
            <span style={{ color: "var(--c-landing-accent)" }}>It tallies itself.</span>
          </h1>

          <p className="mt-lg max-w-md text-body text-text-secondary sm:text-[1.0625rem]">
            Point your camera at any receipt — crumpled, faded, handwritten. AI
            pulls the merchant, total, tax and category and drops it into your
            spending in about five seconds.
          </p>

          <div className="mt-xl flex flex-col gap-sm sm:flex-row">
            <a
              href={SIGNUP}
              className={cn(buttonVariants(), "h-12 px-xl text-body")}
            >
              Get started free <ArrowRight size={16} />
            </a>
            <a
              href="#how"
              className={cn(
                buttonVariants({ variant: "secondary" }),
                "h-12 px-xl text-body",
              )}
            >
              See how it works
            </a>
          </div>

          <ul className="mt-xl flex flex-wrap items-center gap-x-lg gap-y-xs text-caption text-text-tertiary">
            {["~5-second scans", "Reads faded & handwritten", "Auto-categorized"].map(
              (t) => (
                <li key={t} className="flex items-center gap-xs">
                  <Check size={13} className="text-accent" />
                  {t}
                </li>
              ),
            )}
          </ul>
        </div>

        <HeroVisual />
      </div>
    </section>
  );
}

function HeroVisual() {
  return (
    <div className="relative mx-auto w-full max-w-md pt-lg lg:max-w-none lg:pt-0">
      {/* main dashboard mock, angled */}
      <div className="relative rotate-[1.5deg] transition-transform duration-500 hover:rotate-0">
        <BrowserFrame>
          <DashboardMock />
        </BrowserFrame>
      </div>

      {/* receipt card, layered in front */}
      <div className="absolute -bottom-lg -left-sm w-36 -rotate-6 drop-shadow-xl sm:-left-xl sm:w-44">
        <ReceiptCard compact />
      </div>

      {/* floating "saved" chip */}
      <div className="absolute -right-xs -top-sm rotate-3 rounded-xl border border-border bg-surface px-md py-sm shadow-e2 sm:-right-lg sm:top-6">
        <div className="flex items-center gap-xs text-caption font-medium">
          <span className="grid h-5 w-5 place-items-center rounded-pill bg-success-muted text-success">
            <Check size={12} />
          </span>
          Saved in 4s
        </div>
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
    { slug: "groceries", amt: "$412" },
    { slug: "restaurants", amt: "$268" },
    { slug: "transport", amt: "$143" },
    { slug: "shopping", amt: "$311" },
  ];
  return (
    <div className="space-y-md">
      <div className="flex items-center justify-between gap-md rounded-xl bg-hero p-md">
        <div>
          <p className="text-[10px] font-bold uppercase tracking-wide text-gold">This month</p>
          <p className="mt-hair text-2xl font-extrabold tabular text-hero-text">$1,284.50</p>
          <p className="mt-xs inline-flex items-center rounded-pill bg-hero-chip px-sm py-hair text-[10px] font-semibold text-hero-text">
            ↓ $92 vs last month
          </p>
        </div>
        <span className="shrink-0 text-gold">
          <Sparkline points={[1420, 1550, 1376, 1284]} width={96} height={44} />
        </span>
      </div>

      <div className="flex gap-sm">
        {cats.map((c) => {
          const Icon = categoryMeta(c.slug).icon;
          const color = categoryColor(c.slug);
          return (
            <div key={c.slug} className="flex flex-1 flex-col items-center gap-hair">
              <span
                className="grid h-8 w-8 place-items-center rounded-md"
                style={{ background: `color-mix(in srgb, ${color} 16%, transparent)`, color }}
              >
                <Icon size={14} />
              </span>
              <span className="text-[10px] font-semibold tabular">{c.amt}</span>
            </div>
          );
        })}
      </div>

      <div className="rounded-xl bg-bg p-sm text-[11px] text-text-secondary">
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
        <h2 className="max-w-lg text-title font-extrabold tracking-tight">
          It reads the whole receipt.
        </h2>
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
      body: "Snap it or pick from your library. Bad lighting and coffee stains are fine.",
      visual: <StepCameraViz />,
    },
    {
      icon: Check,
      title: "Glance & confirm",
      body: "One screen shows what the AI read. Tap to fix anything — usually nothing.",
      visual: <StepConfirmViz />,
    },
    {
      icon: CircleCheckBig,
      title: "It's filed",
      body: "Categorized, dated, and on your dashboard before your phone's back in your pocket.",
      visual: <StepFiledViz />,
    },
  ];
  return (
    <section
      id="how"
      className="scroll-mt-16 border-t border-border bg-surface-2 px-lg py-4xl"
    >
      <div className="mx-auto max-w-content">
        <p className="text-micro uppercase tracking-wide text-text-tertiary">
          How it works
        </p>
        <h2 className="mt-sm max-w-lg text-title font-extrabold tracking-tight">
          From shoebox to dashboard in three taps
        </h2>

        <div className="relative mt-2xl">
          {/* connecting line (desktop) */}
          <div
            aria-hidden
            className="absolute left-[16.66%] right-[16.66%] top-6 hidden h-px bg-border-strong sm:block"
          />
          <ol className="grid gap-xl sm:grid-cols-3">
            {steps.map(({ icon: Icon, title, body, visual }, i) => (
              <li key={title} className="flex flex-col items-center text-center">
                <span className="relative z-10 grid h-12 w-12 place-items-center rounded-pill bg-gradient-to-br from-accent to-[color:var(--cat-transport)] text-white shadow-e1">
                  <Icon size={20} />
                </span>
                <span className="mt-sm text-micro uppercase tracking-wide text-text-tertiary">
                  Step {i + 1}
                </span>
                <div className="mt-md w-full max-w-[240px] rounded-xl border border-border bg-surface p-md">
                  {visual}
                </div>
                <h3 className="mt-md text-headline">{title}</h3>
                <p className="mt-xs max-w-xs text-callout text-text-secondary">
                  {body}
                </p>
              </li>
            ))}
          </ol>
        </div>
      </div>
    </section>
  );
}

function StepCameraViz() {
  return (
    <div className="relative grid h-24 place-items-center rounded-lg bg-bg">
      <div className="absolute inset-3 rounded-md border border-dashed border-border-strong" />
      <div className="h-12 w-9 rotate-[-4deg] rounded-sm border border-border bg-surface shadow-e1" />
      <span className="absolute right-3 top-3 grid h-6 w-6 place-items-center rounded-pill bg-accent text-accent-fg">
        <Camera size={13} />
      </span>
    </div>
  );
}

function StepConfirmViz() {
  return (
    <div className="flex h-24 flex-col justify-center gap-sm rounded-lg bg-bg px-md">
      {[70, 45].map((w) => (
        <span key={w} className="flex items-center gap-sm">
          <span className="h-2 rounded-pill bg-surface-2" style={{ width: `${w}%` }} />
          <Check size={12} className="text-success" />
        </span>
      ))}
      <span className="flex items-center gap-sm">
        <span className="h-2 w-1/3 rounded-pill bg-accent-muted" />
        <span className="text-[10px] text-accent">Save</span>
      </span>
    </div>
  );
}

function StepFiledViz() {
  return (
    <div className="flex h-24 flex-col justify-center gap-xs rounded-lg bg-bg px-md">
      {["groceries", "restaurants", "transport"].map((slug, i) => (
        <span key={slug} className="flex items-center gap-sm">
          <span
            className="h-2.5 w-2.5 rounded-pill"
            style={{ background: categoryColor(slug) }}
          />
          <span
            className="h-1.5 rounded-pill bg-surface-2"
            style={{ width: `${64 - i * 14}%` }}
          />
          {i === 0 && <Check size={12} className="ml-auto text-success" />}
        </span>
      ))}
    </div>
  );
}

/* ─────────────────────────── features ─────────────────────────── */

export function Features() {
  const feats = [
    {
      icon: Zap,
      accent: "restaurants",
      title: "Nothing to type",
      body: "No forms, no “select a category”. Point the camera and you're done.",
      viz: <FeatNoType />,
    },
    {
      icon: TrendingUp,
      accent: "transport",
      title: "Spending that explains itself",
      body: "Monthly totals, category breakdowns and plain-English nudges when something creeps up.",
      viz: <FeatTrend />,
    },
    {
      icon: Database,
      accent: "groceries",
      title: "Your data, structured",
      body: "Every receipt becomes clean, queryable data — chart it, export it, or just glance at it.",
      viz: <FeatData />,
    },
  ];
  return (
    <section className="border-t border-border px-lg py-4xl">
      <div className="mx-auto max-w-content">
        <h2 className="max-w-lg text-title font-extrabold tracking-tight">
          More than a pile of photos
        </h2>
        <div className="mt-2xl grid gap-lg sm:grid-cols-3">
          {feats.map(({ icon: Icon, accent, title, body, viz }) => (
            <div
              key={title}
              className="group flex flex-col rounded-2xl border border-border bg-surface p-lg transition-colors hover:border-border-strong"
            >
              <span
                className="grid h-11 w-11 place-items-center rounded-xl text-white shadow-e1"
                style={{
                  backgroundImage: `linear-gradient(135deg, var(--c-accent), ${categoryColor(accent)})`,
                }}
              >
                <Icon size={19} />
              </span>
              <h3 className="mt-md text-headline">{title}</h3>
              <p className="mt-xs flex-1 text-callout text-text-secondary">{body}</p>
              <div className="mt-lg rounded-lg border border-border bg-bg p-md">
                {viz}
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function FeatNoType() {
  return (
    <div className="flex items-center justify-between">
      <span className="relative inline-block">
        <span className="block space-y-1.5 opacity-40">
          {[64, 40, 52].map((w) => (
            <span key={w} className="block h-2 rounded-pill bg-surface-2" style={{ width: w }} />
          ))}
        </span>
        <span
          aria-hidden
          className="absolute left-[-4px] top-1/2 h-px w-[72px] -rotate-12 bg-danger"
        />
      </span>
      <span className="grid h-9 w-9 place-items-center rounded-pill bg-accent text-accent-fg">
        <Camera size={16} />
      </span>
    </div>
  );
}

function FeatTrend() {
  const bars = [30, 44, 38, 56, 50, 72];
  return (
    <div className="flex h-12 items-end gap-1.5">
      {bars.map((h, i) => (
        <span
          key={i}
          className="flex-1 rounded-t-sm"
          style={{
            height: `${h}%`,
            background:
              i === bars.length - 1
                ? "var(--c-accent)"
                : "var(--c-surface-2)",
          }}
        />
      ))}
    </div>
  );
}

function FeatData() {
  return (
    <div className="space-y-1.5 font-mono text-[10px] text-text-secondary">
      <div className="flex justify-between">
        <span>merchant</span>
        <span className="text-text">Bluebird Cafe</span>
      </div>
      <div className="flex justify-between">
        <span>total</span>
        <span className="text-text">8.43</span>
      </div>
      <div className="flex justify-between">
        <span>category</span>
        <span style={{ color: categoryColor("restaurants") }}>restaurants</span>
      </div>
    </div>
  );
}

/* ─────────────────────────── closing CTA ─────────────────────────── */

export function BottomCTA() {
  return (
    <section className="px-lg py-4xl">
      <div className="relative mx-auto max-w-content overflow-hidden rounded-2xl bg-hero px-lg py-3xl text-center shadow-e2 sm:px-2xl">
        {/* glyph watermark */}
        <TallyMark
          size={280}
          className="pointer-events-none absolute -right-12 -top-16 text-white/[0.06]"
        />
        <div className="relative mx-auto flex max-w-lg flex-col items-center gap-md">
          <SparklesIconInline />
          <h2 className="text-[1.9rem] font-extrabold leading-tight tracking-tight text-hero-text sm:text-title">
            Your <span className="text-gold">last</span> manual expense entry
          </h2>
          <p className="text-callout text-hero-text opacity-80">
            Sign in with Google or email and scan your first receipt in the next
            minute. Free forever tier, no card.
          </p>
          <a
            href={SIGNUP}
            className={cn(
              buttonVariants({ variant: "secondary" }),
              "border-transparent bg-hero-text px-xl text-hero-cta hover:bg-hero-cta-hover",
            )}
          >
            Get started free <ArrowRight size={16} />
          </a>
        </div>
      </div>
    </section>
  );
}

function SparklesIconInline() {
  return (
    <span className="grid h-11 w-11 place-items-center rounded-xl bg-hero-chip text-hero-text">
      <Sparkles size={20} />
    </span>
  );
}

/* ─────────────────────────── footer ─────────────────────────── */

const FOOTER_LINKS: { heading: string; links: { label: string; href: string }[] }[] = [
  {
    heading: "Product",
    links: [
      { label: "How it works", href: "#how" },
      { label: "Get started", href: SIGNUP },
      { label: "Log in", href: LOGIN },
    ],
  },
  {
    heading: "Legal",
    links: [
      { label: "Privacy policy", href: "/privacy" },
      { label: "Terms of service", href: "/terms" },
      { label: "Contact", href: "mailto:contact@dataeaver.ca" },
    ],
  },
];

export function SiteFooter() {
  return (
    <footer className="border-t border-border px-lg pb-xl pt-3xl">
      <div className="mx-auto max-w-content">
        <div className="grid gap-2xl sm:grid-cols-[1.4fr_1fr_1fr]">
          <div>
            <Wordmark />
            <p className="mt-md max-w-[26ch] text-caption text-text-secondary">
              Snap a receipt. It tallies itself. Free expense tracking for iOS
              and the web.
            </p>
          </div>
          {FOOTER_LINKS.map((col) => (
            <div key={col.heading}>
              <p className="text-micro uppercase tracking-wide text-text-tertiary">
                {col.heading}
              </p>
              <ul className="mt-md space-y-sm">
                {col.links.map((l) => (
                  <li key={l.label}>
                    <a
                      href={l.href}
                      className="text-callout text-text-secondary hover:text-text"
                    >
                      {l.label}
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="mt-2xl border-t border-border pt-lg text-caption text-text-tertiary">
          <span>© {new Date().getFullYear()} DATA EAVER INC. All rights reserved.</span>
        </div>
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
