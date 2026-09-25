"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { LayoutDashboard, LogOut, ReceiptText, ScanLine, Target } from "lucide-react";
import { cn } from "@/lib/utils";
import { TallyMark } from "@/components/tally-mark";

const LINKS = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/scan", label: "Scan", icon: ScanLine },
  { href: "/receipts", label: "Receipts", icon: ReceiptText },
  { href: "/budgets", label: "Budgets", icon: Target },
];

export function AppNav({ displayName }: { displayName?: string }) {
  const pathname = usePathname();

  return (
    <nav className="flex shrink-0 items-stretch gap-xs md:w-52 md:flex-col">
      <Link href="/" className="mb-2xl hidden items-center gap-md px-md md:flex">
        <span className="grid h-10 w-10 place-items-center rounded-[11px] bg-hero text-gold ring-1 ring-white/5">
          <TallyMark size={22} />
        </span>
        <span className="font-display text-[24px] font-extrabold tracking-[-0.03em]">Tally</span>
      </Link>

      {LINKS.map(({ href, label, icon: Icon }) => {
        const active = pathname === href || pathname.startsWith(`${href}/`);
        return (
          <Link
            key={href}
            href={href}
            aria-current={active ? "page" : undefined}
            className={cn(
              "flex flex-1 items-center justify-center gap-md rounded-pill px-lg py-sm text-callout transition-colors md:flex-none md:justify-start",
              active
                ? "bg-accent-muted font-semibold text-accent"
                : "text-text-secondary hover:bg-surface-2 hover:text-text",
            )}
          >
            <Icon size={18} />
            <span className={cn(!active && "hidden md:inline")}>{label}</span>
          </Link>
        );
      })}

      <div className="mt-auto hidden flex-col gap-xs pt-lg md:flex">
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
  );
}
