import Link from "next/link";
import { TallyMark } from "@/components/tally-mark";
import { AppStoreBadge } from "@/components/landing";

/** Frame for the pages people open from a link someone sent them (a share,
 * an invite): no account needed to read them. */
export function PublicShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-dvh flex-col bg-bg">
      <header className="mx-auto flex w-full max-w-[560px] items-center px-lg pt-xl">
        <Link href="/" className="flex items-center gap-md">
          <span className="grid h-9 w-9 place-items-center rounded-[10px] bg-hero text-gold ring-1 ring-white/5">
            <TallyMark size={19} />
          </span>
          <span className="font-display text-[21px] font-extrabold tracking-[-0.03em]">Tally</span>
        </Link>
      </header>
      <main className="mx-auto w-full max-w-[560px] flex-1 space-y-xl px-lg py-2xl">{children}</main>
      <footer className="mx-auto flex w-full max-w-[560px] flex-wrap items-center justify-between gap-lg border-t border-border px-lg py-xl">
        <p className="max-w-[18rem] text-caption text-text-secondary">
          Tally reads your receipts and shows where your money goes. Free on iPhone and the web.
        </p>
        <AppStoreBadge />
      </footer>
    </div>
  );
}
