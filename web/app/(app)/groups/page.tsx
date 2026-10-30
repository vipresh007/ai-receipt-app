"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { ChevronRight, Plus, X } from "lucide-react";
import { apiGet, apiPost } from "@/lib/api";
import type { GroupDetail, GroupSummary } from "@/lib/types";
import { Card, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { PageHeader } from "@/components/page-header";
import { BalanceTag } from "@/components/balance-tag";
import { PeopleSection } from "@/components/people-section";
import { LIVE } from "@/lib/live";

export default function GroupsPage() {
  const router = useRouter();
  const { data: groups, isLoading } = useQuery({
    ...LIVE,
    queryKey: ["groups"],
    queryFn: () => apiGet<GroupSummary[]>("v1/groups"),
  });

  const [creating, setCreating] = useState(false);
  const [name, setName] = useState("");
  const [members, setMembers] = useState<string[]>([""]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function create(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim() || saving) return;
    setSaving(true);
    setError(null);
    try {
      const group = await apiPost<GroupDetail>("v1/groups", {
        name,
        members: members.filter((m) => m.trim()),
      });
      router.push(`/groups/${group.id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't create the group.");
      setSaving(false);
    }
  }

  return (
    <div className="space-y-2xl">
      <PageHeader
        eyebrow="Split with others"
        title="Shared"
        description="Split with anyone by name, no group needed, and Tally keeps a running tab with each person. Groups are for trips, housemates, a standing dinner."
      />

      <PeopleSection />

      <div className="flex items-center justify-between gap-md">
        <h2 className="font-display text-[22px] font-extrabold tracking-[-0.02em]">Groups</h2>
        <Button size="sm" variant={creating ? "secondary" : "primary"} onClick={() => setCreating(!creating)}>
          {creating ? "Cancel" : "New group"}
        </Button>
      </div>

      {creating && (
        <Card>
          <form onSubmit={create} className="space-y-lg">
            <div className="space-y-xs">
              <Label htmlFor="group-name">Name</Label>
              <Input
                id="group-name"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Ski trip"
                maxLength={120}
                autoFocus
              />
            </div>
            <div className="space-y-xs">
              <Label>Who else is in it</Label>
              <p className="text-caption text-text-tertiary">
                Just names for now. Each person can claim theirs later from the invite link.
              </p>
              <div className="space-y-sm">
                {members.map((m, i) => (
                  <div key={i} className="flex gap-sm">
                    <Input
                      value={m}
                      onChange={(e) => setMembers(members.map((x, j) => (j === i ? e.target.value : x)))}
                      placeholder="Name"
                      maxLength={120}
                      aria-label={`Person ${i + 1}`}
                    />
                    {members.length > 1 && (
                      <Button
                        type="button"
                        variant="ghost"
                        size="icon"
                        aria-label="Remove"
                        onClick={() => setMembers(members.filter((_, j) => j !== i))}
                      >
                        <X size={16} />
                      </Button>
                    )}
                  </div>
                ))}
              </div>
              <Button type="button" variant="ghost" size="sm" onClick={() => setMembers([...members, ""])}>
                <Plus size={15} /> Add someone
              </Button>
            </div>
            {error && <p className="text-caption text-danger">{error}</p>}
            <div className="flex justify-end">
              <Button type="submit" disabled={!name.trim() || saving}>
                {saving ? "Creating…" : "Create group"}
              </Button>
            </div>
          </form>
        </Card>
      )}

      {isLoading ? (
        <div className="space-y-md">
          <Skeleton className="h-20" />
          <Skeleton className="h-20" />
        </div>
      ) : (groups ?? []).length === 0 ? (
        !creating && (
          <Card className="space-y-sm">
            <CardTitle>No groups yet</CardTitle>
            <p className="text-callout text-text-secondary">
              Make one when the same few people share lots of costs, like a trip or a flat.
            </p>
          </Card>
        )
      ) : (
        <ul className="space-y-md">
          {groups!.map((g) => (
            <li key={g.id}>
              <Link href={`/groups/${g.id}`} className="block rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--c-focus-ring)]">
                <Card className="flex items-center gap-lg transition-colors hover:bg-surface-2">
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-display text-[20px] font-bold tracking-[-0.02em]">{g.name}</p>
                    <p className="text-caption text-text-tertiary">
                      {g.member_count} {g.member_count === 1 ? "person" : "people"}
                    </p>
                  </div>
                  <BalanceTag balance={g.my_balance} currency={g.currency} />
                  <ChevronRight size={18} className="text-text-tertiary" />
                </Card>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
