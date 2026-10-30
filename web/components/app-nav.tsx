"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { LayoutDashboard, LogOut, ReceiptText, ScanLine, Target, UserRound, Users } from "lucide-react";
import { cn } from "@/lib/utils";
import { TallyMark } from "@/components/tally-mark";
import { AppDownloadBanner } from "@/components/app-download-banner";

const LINKS = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/scan", label: "Scan", icon: ScanLine },
  { href: "/receipts", label: "Receipts", icon: ReceiptText },
  { href: "/groups", label: "Shared", icon: Users },
  { href: "/budgets", label: "Budgets", icon: Target },
];

/** Phones get the iOS app's tabs: Budgets lives under Dashboard and Account
 * there too. */
const TABS = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/scan", label: "Scan", icon: ScanLine },
  { href: "/receipts", label: "Receipts", icon: ReceiptText },
  { href: "/groups", label: "Shared", icon: Users },
  { href: "/account", label: "Account", icon: UserRound },
];

function isActive(pathname: string, href: string): boolean {
  return (
    pathname === href ||
    pathname.startsWith(`${href}/`) ||
    (href === "/groups" && pathname.startsWith("/people/"))
  );
}

function Brand({ size = "md" }: { size?: "sm" | "md" }) {
  return (
    <Link href="/" className="flex items-center gap-md" aria-label="Tally home">
      <span
        className={cn(
          "grid place-items-center bg-hero text-gold ring-1 ring-white/5",
          size === "md" ? "h-10 w-10 rounded-[11px]" : "h-8 w-8 rounded-[9px]",
        )}
      >
        <TallyMark size={size === "md" ? 22 : 17} />
      </span>
      <span
        className={cn(
          "font-display font-extrabold tracking-[-0.03em]",
          size === "md" ? "text-[24px]" : "text-[20px]",
        )}
      >
        Tally
      </span>
    </Link>
  );
}

export function AppNav({ displayName }: { displayName?: string }) {
  const pathname = usePathname();
  const initial = (displayName ?? "").trim().charAt(0).toUpperCase() || "A";

  return (
    <>
      {/* ── Phones: top bar (logo back to the home page) ── */}
      <header className="-mx-lg -mt-lg mb-xs space-y-sm px-lg pt-[max(12px,env(safe-area-inset-top))] md:hidden">
        <div className="flex items-center justify-between">
          <Brand size="sm" />
          <Link
            href="/account"
            aria-label="Account"
            className="grid h-9 w-9 place-items-center rounded-full bg-hero font-display text-[15px] font-bold text-gold ring-1 ring-white/5"
          >
            {initial}
          </Link>
        </div>
        <AppDownloadBanner />
      </header>

      {/* ── Phones: floating tab bar, like the iOS app ── */}
      <nav
        aria-label="Main"
        className="fixed inset-x-md bottom-[max(12px,env(safe-area-inset-bottom))] z-40 flex items-stretch gap-xs rounded-[28px] bg-[color-mix(in_srgb,var(--c-surface)_86%,transparent)] p-[5px] shadow-e2 ring-1 ring-border backdrop-blur-xl md:hidden"
      >
        {TABS.map(({ href, label, icon: Icon }) => {
          const active = isActive(pathname, href);
          return (
            <Link
              key={href}
              href={href}
              aria-current={active ? "page" : undefined}
              className={cn(
                "flex min-w-0 flex-1 flex-col items-center gap-[2px] rounded-[22px] py-[7px] text-[10.5px] font-medium transition-colors",
                active ? "bg-accent-muted text-accent" : "text-text-secondary",
              )}
            >
              <Icon size={21} strokeWidth={active ? 2.3 : 1.9} />
              <span className="truncate">{label}</span>
            </Link>
          );
        })}
      </nav>

      {/* ── Tablets and up: sidebar ── */}
      <nav className="hidden w-52 shrink-0 flex-col gap-xs md:flex">
        <div className="mb-2xl px-md">
          <Brand />
        </div>

        {LINKS.map(({ href, label, icon: Icon }) => {
          const active = isActive(pathname, href);
          return (
            <Link
              key={href}
              href={href}
              aria-current={active ? "page" : undefined}
              className={cn(
                "flex items-center gap-md rounded-pill px-lg py-sm text-callout transition-colors",
                active
                  ? "bg-accent-muted font-semibold text-accent"
                  : "text-text-secondary hover:bg-surface-2 hover:text-text",
              )}
            >
              <Icon size={18} />
              <span>{label}</span>
            </Link>
          );
        })}

        <div className="mt-auto flex flex-col gap-xs pt-lg">
          {displayName && (
            <Link
              href="/account"
              aria-current={pathname === "/account" ? "page" : undefined}
              className={cn(
                "truncate rounded-md px-md py-sm text-caption transition-colors hover:bg-surface-2",
                pathname === "/account" ? "text-accent" : "text-text-tertiary hover:text-text",
              )}
              title={displayName}
            >
              {displayName}
            </Link>
          )}
          <a
            href="/auth/logout"
            className="flex items-center gap-sm rounded-md px-md py-sm text-callout text-text-secondary transition-colors hover:bg-surface-2 hover:text-text"
          >
            <LogOut size={18} />
            Sign out
          </a>
        </div>
      </nav>
    </>
  );
}
