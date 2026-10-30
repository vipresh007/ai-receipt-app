"use client";

import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { Bell } from "lucide-react";
import { apiGet } from "@/lib/api";
import { LIVE } from "@/lib/live";
import { cn } from "@/lib/utils";

/** Unread activity, checked every minute while the app is open. */
export function useUnreadActivity(): number {
  const { data } = useQuery({
    queryKey: ["activity-unread"],
    queryFn: () => apiGet<{ unread: number }>("v1/activity/unread"),
    ...LIVE,
  });
  return data?.unread ?? 0;
}

export function UnreadBadge({ count, className }: { count: number; className?: string }) {
  if (!count) return null;
  return (
    <span
      className={cn(
        "grid h-[18px] min-w-[18px] place-items-center rounded-full bg-accent px-[5px] text-[10.5px] font-bold text-accent-fg tabular",
        className,
      )}
    >
      {count > 9 ? "9+" : count}
    </span>
  );
}

export function ActivityBell() {
  const count = useUnreadActivity();
  return (
    <Link
      href="/activity"
      aria-label={count ? `Activity, ${count} new` : "Activity"}
      className="relative grid h-9 w-9 place-items-center rounded-full text-text-secondary hover:bg-surface-2 hover:text-text"
    >
      <Bell size={19} />
      <UnreadBadge count={count} className="absolute -right-[2px] -top-[2px]" />
    </Link>
  );
}
