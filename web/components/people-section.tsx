"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { ChevronRight } from "lucide-react";
import { apiGet, apiPost } from "@/lib/api";
import type { PersonDetail, PersonSummary } from "@/lib/types";
import { Card, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { PersonBalanceTag } from "@/components/balance-tag";
import { LIVE } from "@/lib/live";

/** People you split with outside groups, each with a running balance. */
export function PeopleSection() {
  const router = useRouter();
  const { data: people, isLoading } = useQuery({
    ...LIVE,
    queryKey: ["people"],
    queryFn: () => apiGet<PersonSummary[]>("v1/people"),
  });

  const [adding, setAdding] = useState(false);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [invite, setInvite] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function add(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim() || saving) return;
    setSaving(true);
    setError(null);
    try {
      const person = await apiPost<PersonDetail>("v1/people", { name, email: email.trim() || null });
      if (email.trim() && invite && person.can_email) {
        // Best effort: their page says if it didn't go, and has the link.
        await apiPost(`v1/people/${person.id}/invite`, {}).catch(() => undefined);
      }
      router.push(`/people/${person.id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't add them.");
      setSaving(false);
    }
  }

  const owedToYou = (people ?? []).filter((p) => Number(p.balance) > 0).length;

  return (
    <section className="space-y-lg">
      <div className="flex items-center justify-between gap-md">
        <div>
          <h2 className="font-display text-[22px] font-extrabold tracking-[-0.02em]">People</h2>
          {owedToYou > 0 && (
            <p className="text-caption text-text-tertiary">
              {owedToYou} {owedToYou === 1 ? "person owes" : "people owe"} you
            </p>
          )}
        </div>
        <Button size="sm" variant={adding ? "secondary" : "primary"} onClick={() => setAdding(!adding)}>
          {adding ? "Cancel" : "Add person"}
        </Button>
      </div>

      {adding && (
        <Card>
          <form onSubmit={add} className="space-y-lg">
            <div className="grid gap-md sm:grid-cols-2">
              <div className="space-y-xs">
                <Label htmlFor="person-name">Name</Label>
                <Input
                  id="person-name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="Sam"
                  maxLength={120}
                  autoFocus
                />
              </div>
              <div className="space-y-xs">
                <Label htmlFor="person-email">Email (optional)</Label>
                <Input
                  id="person-email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="You can add it later"
                  maxLength={320}
                />
              </div>
            </div>
            {email.trim() && (
              <label className="flex items-center gap-sm text-callout">
                <input
                  type="checkbox"
                  checked={invite}
                  onChange={(e) => setInvite(e.target.checked)}
                  className="h-4 w-4 accent-[var(--c-accent)]"
                />
                Email them an invite to see what you share
              </label>
            )}
            {error && <p className="text-caption text-danger">{error}</p>}
            <div className="flex justify-end">
              <Button type="submit" disabled={!name.trim() || saving}>
                {saving ? "Adding…" : "Add person"}
              </Button>
            </div>
          </form>
        </Card>
      )}

      {isLoading ? (
        <Skeleton className="h-20" />
      ) : (people ?? []).length === 0 ? (
        !adding && (
          <Card className="space-y-sm">
            <CardTitle>No one yet</CardTitle>
            <p className="text-callout text-text-secondary">
              Split a receipt with anyone by typing their name, or add someone here. You can add
              their email any time to invite them.
            </p>
          </Card>
        )
      ) : (
        <Card className="overflow-hidden !p-0">
          <ul className="divide-y divide-border">
            {people!.map((p) => (
              <li key={p.id}>
                <Link
                  href={`/people/${p.id}`}
                  className="flex items-center gap-md px-2xl py-lg transition-colors hover:bg-surface-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--c-focus-ring)]"
                >
                  <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-accent-muted text-callout font-semibold text-accent">
                    {p.name.slice(0, 1).toUpperCase()}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-callout font-medium">{p.name}</span>
                    <span className="block truncate text-caption text-text-tertiary">
                      {p.has_account ? "On Tally" : p.email ? (p.invited_at ? "Invited" : p.email) : "Just a name"}
                    </span>
                  </span>
                  <PersonBalanceTag balance={p.balance} currency={p.currency} name={p.name} />
                  <ChevronRight size={18} className="text-text-tertiary" />
                </Link>
              </li>
            ))}
          </ul>
        </Card>
      )}
    </section>
  );
}
