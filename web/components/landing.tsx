import {
  ArrowRight,
  Camera,
  CheckCircle2,
  FolderCheck,
  ScanLine,
  Sparkles,
  WalletCards,
} from "lucide-react";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";

const SIGNUP = "/auth/login?screen_hint=signup";
const LOGIN = "/auth/login";

export function SiteHeader() {
  return (
    <header className="sticky top-0 z-20 border-b border-border bg-bg">
      <div className="mx-auto flex h-14 max-w-content items-center justify-between px-lg">
        <span className="flex items-center gap-sm">
          <span className="grid h-7 w-7 place-items-center rounded-md bg-accent text-accent-fg">
            <ScanLine size={16} />
          </span>
          <span className="text-callout font-semibold">AI Receipt</span>
        </span>
        <nav className="flex items-center gap-xs">
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

export function Hero() {
  return (
    <section className="relative overflow-hidden px-lg">
      <div
        aria-hidden
        className="pointer-events-none absolute left-1/2 top-[-15%] h-[440px] w-[760px] -translate-x-1/2 rounded-pill bg-accent-muted blur-3xl"
      />
      <div className="relative mx-auto flex max-w-content flex-col items-center gap-xl py-5xl text-center md:py-[7rem]">
        <span className="inline-flex items-center gap-xs rounded-pill border border-border bg-surface px-md py-hair text-micro uppercase tracking-wide text-text-secondary">
          <Sparkles size={12} className="text-accent" /> AI expense tracking
        </span>

        <h1 className="max-w-3xl text-[2.5rem] font-bold leading-[1.05] tracking-tight sm:text-[3.25rem]">
          Snap a receipt.
          <br />
          It files itself.
        </h1>

        <p className="max-w-xl text-body text-text-secondary">
          Point your camera at any receipt. AI reads the merchant, total, tax and
          category and drops it straight into your spending — in about five
          seconds.
        </p>

        <div className="flex flex-col gap-sm sm:flex-row">
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

        <AppPreview />
      </div>
    </section>
  );
}

function AppPreview() {
  const rows = [
    { slug: "groceries", label: "Groceries", pct: 84, amt: "$412.90" },
    { slug: "restaurants", label: "Restaurants", pct: 62, amt: "$305.14" },
    { slug: "transport", label: "Transport", pct: 34, amt: "$168.40" },
    { slug: "shopping", label: "Shopping", pct: 20, amt: "$98.20" },
  ];
  return (
    <div className="mt-xl w-full max-w-2xl rounded-2xl border border-border bg-surface p-lg text-left shadow-e2">
      <p className="text-micro uppercase text-text-tertiary">This month</p>
      <p className="mt-xs text-display font-bold tabular">$1,284.50</p>
      <div className="mt-lg space-y-sm">
        {rows.map((r) => (
          <div key={r.slug} className="flex items-center gap-md">
            <span className="w-24 shrink-0 text-caption text-text-secondary">{r.label}</span>
            <span className="h-2 flex-1 overflow-hidden rounded-pill bg-surface-2">
              <span
                className="block h-full rounded-pill"
                style={{ width: `${r.pct}%`, background: `var(--cat-${r.slug})` }}
              />
            </span>
            <span className="w-16 shrink-0 text-right text-caption tabular text-text-secondary">
              {r.amt}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

export function HowItWorks() {
  const steps = [
    { icon: Camera, title: "Snap it", body: "Photo or upload — crumpled, faded, handwritten receipts are fine." },
    { icon: CheckCircle2, title: "Check it", body: "A quick confirm screen. Fix anything the AI misread." },
    { icon: FolderCheck, title: "It's filed", body: "Saved, categorized, and on your dashboard instantly." },
  ];
  return (
    <section id="how" className="scroll-mt-14 border-t border-border px-lg py-4xl">
      <div className="mx-auto max-w-content">
        <h2 className="text-center text-title">Three taps, not a spreadsheet</h2>
        <div className="mt-2xl grid gap-xl sm:grid-cols-3">
          {steps.map(({ icon: Icon, title, body }, i) => (
            <div key={title} className="flex flex-col items-center gap-sm text-center">
              <span className="grid h-11 w-11 place-items-center rounded-xl bg-accent-muted text-accent">
                <Icon size={20} />
              </span>
              <p className="text-micro uppercase text-text-tertiary">Step {i + 1}</p>
              <h3 className="text-headline">{title}</h3>
              <p className="max-w-xs text-callout text-text-secondary">{body}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

export function Features() {
  const feats = [
    {
      icon: ScanLine,
      title: "Reads any receipt",
      body: "Merchant, date, total, tax and line items — pulled from the photo, not typed.",
    },
    {
      icon: WalletCards,
      title: "Categorized automatically",
      body: "Every expense lands in the right bucket. Nine categories, tuned colors, always editable.",
    },
    {
      icon: Sparkles,
      title: "Spending that explains itself",
      body: "Monthly totals, category breakdowns and plain-English insights on where it's going.",
    },
  ];
  return (
    <section className="border-t border-border bg-surface-2 px-lg py-4xl">
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

export function BottomCTA() {
  return (
    <section className="px-lg py-4xl">
      <div className="mx-auto flex max-w-content flex-col items-center gap-md rounded-2xl border border-border bg-accent-muted px-lg py-2xl text-center">
        <h2 className="text-title">Stop typing in transactions</h2>
        <p className="max-w-md text-callout text-text-secondary">
          Free to start. Sign in with Google or email and scan your first receipt.
        </p>
        <a href={SIGNUP} className={cn(buttonVariants(), "px-xl")}>
          Get started free <ArrowRight size={16} />
        </a>
      </div>
    </section>
  );
}

export function SiteFooter() {
  return (
    <footer className="border-t border-border px-lg py-xl">
      <div className="mx-auto flex max-w-content flex-col items-center justify-between gap-sm text-caption text-text-tertiary sm:flex-row">
        <span>© {new Date().getFullYear()} AI Receipt</span>
        <span>FastAPI · Next.js · Azure OpenAI</span>
      </div>
    </footer>
  );
}
