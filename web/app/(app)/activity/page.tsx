"use client";

import { useEffect } from "react";
import Link from "next/link";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Bell, MessageSquare, PencilLine, Plus, Repeat, Settings2, Trash2, UserPlus, Wallet } from "lucide-react";
import { apiGet, apiPost } from "@/lib/api";
import type { ActivityFeed, ActivityItem } from "@/lib/types";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { PageHeader } from "@/components/page-header";
import { cn } from "@/lib/utils";
import { LIVE } from "@/lib/live";

const ICONS: Record<string, typeof Bell> = {
  expense_added: Plus,
  expense_edited: PencilLine,
  expense_deleted: Trash2,
  comment: MessageSquare,
  payment: Wallet,
  reminder: Bell,
  joined: UserPlus,
  repeated: Repeat,
  group_changed: Settings2,
};

function href(item: ActivityItem): string {
  if (item.person_id) return `/people/${item.person_id}`;
  if (item.group_id) return `/groups/${item.group_id}`;
  return "/groups";
}

function when(iso: string): string {
  const d = new Date(iso);
  const mins = Math.round((Date.now() - d.getTime()) / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  if (mins < 60 * 24) return `${Math.round(mins / 60)}h ago`;
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

export default function ActivityPage() {
  const queryClient = useQueryClient();
  const { data, isLoading } = useQuery({
    ...LIVE,
    queryKey: ["activity"],
    queryFn: () => apiGet<ActivityFeed>("v1/activity"),
  });

  // Opening the feed reads it (after this paint, so new ones still stand out).
  const unread = data?.unread ?? 0;
  useEffect(() => {
    if (!unread) return;
    apiPost("v1/activity/read", {}).then(() =>
      queryClient.setQueryData(["activity-unread"], { unread: 0 }),
    );
  }, [unread, queryClient]);

  return (
    <div className="space-y-2xl">
      <PageHeader
        eyebrow="Shared expenses"
        title="Activity"
        description="What the people you share with have added, changed, paid and said."
      />
      {isLoading ? (
        <Skeleton className="h-40" />
      ) : !data?.items.length ? (
        <Card>
          <p className="text-callout text-text-secondary">
            Nothing yet. When someone adds an expense with you, records a payment or comments,
            it shows up here.
          </p>
        </Card>
      ) : (
        <Card className="overflow-hidden !p-0">
          <ul className="divide-y divide-border">
            {data.items.map((item) => {
              const Icon = ICONS[item.kind] ?? Bell;
              return (
                <li key={item.id}>
                  <Link
                    href={href(item)}
                    className="flex gap-md px-2xl py-lg transition-colors hover:bg-surface-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--c-focus-ring)]"
                  >
                    <span
                      className={cn(
                        "mt-[2px] grid h-8 w-8 shrink-0 place-items-center rounded-full",
                        item.read ? "bg-surface-2 text-text-tertiary" : "bg-accent-muted text-accent",
                      )}
                    >
                      <Icon size={15} />
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="block text-callout">
                        <span className="font-semibold">{item.actor_name}</span> {item.text}
                      </span>
                      <span className="text-caption text-text-tertiary">{when(item.at)}</span>
                    </span>
                    {!item.read && <span className="mt-sm h-2 w-2 shrink-0 rounded-full bg-accent" aria-label="New" />}
                  </Link>
                </li>
              );
            })}
          </ul>
        </Card>
      )}
    </div>
  );
}
