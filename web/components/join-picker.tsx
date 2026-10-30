"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { apiPost } from "@/lib/api";
import type { GroupDetail } from "@/lib/types";
import { Button } from "@/components/ui/button";
import { CardTitle } from "@/components/ui/card";
import { cn } from "@/lib/utils";

const NEW = "new";

/** Signed in on an invite: pick the placeholder that's you (so expenses
 * already added under your name become yours), or join as someone new. */
export function JoinPicker({
  token,
  open,
  preselect,
}: {
  token: string;
  open: { id: string; display_name: string }[];
  preselect?: string;
}) {
  const router = useRouter();
  const [choice, setChoice] = useState<string>(
    preselect ?? (open.length ? "" : NEW),
  );
  const [joining, setJoining] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function join() {
    setJoining(true);
    setError(null);
    try {
      const group = await apiPost<GroupDetail>(
        `v1/groups/join/${encodeURIComponent(token)}`,
        {
          member_id: choice === NEW ? null : choice,
        },
      );
      router.push(`/groups/${group.id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't join the group.");
      setJoining(false);
    }
  }

  const options = [
    ...open.map((m) => ({ id: m.id, label: m.display_name })),
    { id: NEW, label: "I'm not on the list" },
  ];

  return (
    <div className="space-y-lg">
      {open.length > 0 && <CardTitle>Which one is you?</CardTitle>}
      {open.length > 0 && (
        <div role="radiogroup" className="grid gap-sm">
          {options.map((o) => (
            <button
              key={o.id}
              type="button"
              role="radio"
              aria-checked={choice === o.id}
              onClick={() => setChoice(o.id)}
              className={cn(
                "flex h-11 items-center rounded-md border px-md text-left text-callout transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--c-focus-ring)]",
                choice === o.id
                  ? "border-accent bg-accent-muted font-semibold text-accent"
                  : "border-border bg-surface hover:bg-surface-2",
                o.id === NEW && choice !== o.id && "text-text-secondary",
              )}
            >
              {o.label}
            </button>
          ))}
        </div>
      )}
      {error && <p className="text-caption text-danger">{error}</p>}
      <Button className="w-full" disabled={!choice || joining} onClick={join}>
        {joining ? "Joining…" : "Join group"}
      </Button>
    </div>
  );
}
