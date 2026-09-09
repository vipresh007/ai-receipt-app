"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { LayoutDashboard, LogOut, ReceiptText, ScanLine } from "lucide-react";
import { cn } from "@/lib/utils";
import { TallyMark } from "@/components/tally-mark";

const LINKS = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/scan", label: "Scan", icon: ScanLine },
  { href: "/receipts", label: "Receipts", icon: ReceiptText },
];

export function AppNav({ displayName }: { displayName?: string }) {
  const pathname = usePathname();

  return (
    <nav className="flex shrink-0 items-stretch gap-xs md:w-52 md:flex-col">
      <div className="mb-xl hidden items-center gap-sm px-md md:flex">
        <div className="grid h-10 w-10 place-items-center rounded-lg bg-accent text-accent-fg">
          <TallyMark size={24} />
        </div>
        <span className="text-title tracking-tight">Tally</span>
      </div>

      {LINKS.map(({ href, label, icon: Icon }) => {
        const active = pathname === href || pathname.startsWith(`${href}/`);
        return (
          <Link
            key={href}
            href={href}
            aria-current={active ? "page" : undefined}
            className={cn(
              "flex flex-1 items-center justify-center gap-sm rounded-md px-md py-sm text-callout transition-colors md:flex-none md:justify-start",
              active
                ? "bg-accent-muted font-medium text-accent"
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
          <p className="truncate px-md text-caption text-text-tertiary" title={displayName}>
            {displayName}
          </p>
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
