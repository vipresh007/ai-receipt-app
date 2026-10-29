"use client";

import { useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { ArrowRight, Check, ChevronLeft, Copy, Plus, ReceiptText, Share2, Trash2, X } from "lucide-react";
import { apiDelete, apiGet, apiPost } from "@/lib/api";
import { money, shortDate } from "@/lib/format";
import type { GroupDetail, Split } from "@/lib/types";
import { Card, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { PageHeader } from "@/components/page-header";
import { BalanceTag } from "@/components/balance-tag";
import { SplitEditor } from "@/components/split-editor";
import { SplitSummary, useCanShare } from "@/components/split-summary";
import { cn } from "@/lib/utils";

interface PaymentDraft {
  from: string;
  to: string;
  amount: string;
}

export default function GroupPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { data: group, isLoading, error: loadError } = useQuery({
    queryKey: ["group", id],
    queryFn: () => apiGet<GroupDetail>(`v1/groups/${id}`),
  });

  const [adding, setAdding] = useState(false);
  const [editing, setEditing] = useState<Split | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  const [payment, setPayment] = useState<PaymentDraft | null>(null);
  const [newMember, setNewMember] = useState("");
  const [error, setError] = useState<string | null>(null);

  if (isLoading) {
    return (
      <div className="space-y-lg">
        <Skeleton className="h-16 w-1/2" />
        <Skeleton className="h-40" />
        <Skeleton className="h-64" />
      </div>
    );
  }
  if (!group) {
    return (
      <Card className="space-y-sm">
        <CardTitle>Group not found</CardTitle>
        <p className="text-callout text-text-secondary">
          {loadError instanceof Error ? loadError.message : "It may have been deleted, or you're not in it."}
        </p>
        <Link href="/groups" className="text-callout text-accent">
          Back to groups
        </Link>
      </Card>
    );
  }

  const g = group;
  const nameOf = (memberId: string) => {
    const m = g.members.find((x) => x.id === memberId);
    return m ? (m.is_me ? "You" : m.display_name) : "Someone";
  };

  /** Every change can move balances, your spending and other lists. */
  async function refresh(next?: GroupDetail) {
    if (next) queryClient.setQueryData(["group", id], next);
    await queryClient.invalidateQueries();
  }

  async function run(action: () => Promise<GroupDetail | null | void>) {
    setError(null);
    try {
      const next = await action();
      await refresh(next ?? undefined);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong.");
    }
  }

  function recordPayment(e: React.FormEvent) {
    e.preventDefault();
    if (!payment) return;
    const { from, to, amount } = payment;
    run(async () => {
      const next = await apiPost<GroupDetail>(`v1/groups/${id}/settlements`, {
        from_member_id: from,
        to_member_id: to,
        amount,
      });
      setPayment(null);
      return next;
    });
  }

  function addMember(e: React.FormEvent) {
    e.preventDefault();
    if (!newMember.trim()) return;
    run(async () => {
      const next = await apiPost<GroupDetail>(`v1/groups/${id}/members`, { name: newMember });
      setNewMember("");
      return next;
    });
  }

  async function deleteGroup() {
    if (!window.confirm(`Delete ${g.name}? Its expenses and payments go too; split receipts count in full again.`)) return;
    await apiDelete(`v1/groups/${id}`);
    await queryClient.invalidateQueries();
    router.push("/groups");
  }

  async function removeSplit(split: Split) {
    if (!window.confirm(`Remove ${split.description || "this expense"}?`)) return;
    await run(async () => {
      await apiDelete(`v1/splits/${split.id}`);
      setOpen(null);
    });
  }

  const payers = (s: Split) => s.participants.find((p) => p.is_payer);

  return (
    <div className="space-y-2xl">
      <div className="space-y-md">
        <Link href="/groups" className="inline-flex items-center gap-xs text-caption text-text-secondary hover:text-text">
          <ChevronLeft size={15} /> Groups
        </Link>
        <PageHeader
          eyebrow={`${g.members.length} ${g.members.length === 1 ? "person" : "people"} · ${g.currency}`}
          title={g.name}
          actions={<BalanceTag balance={g.my_balance} currency={g.currency} className="text-callout" />}
        />
      </div>

      {error && (
        <p role="alert" className="rounded-md bg-danger-muted px-md py-sm text-caption text-danger">
          {error}
        </p>
      )}

      <div className="grid gap-2xl lg:grid-cols-[minmax(0,1fr)_minmax(0,22rem)]">
        <div className="space-y-2xl">
          {/* ── Settle up ─────────────────────────────── */}
          <Card className="space-y-lg">
            <div className="flex items-center justify-between gap-md">
              <CardTitle>Settle up</CardTitle>
              {!payment && g.members.length > 1 && (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setPayment({ from: g.members[0].id, to: g.members[1].id, amount: "" })}
                >
                  Record a payment
                </Button>
              )}
            </div>
            {g.payments.length === 0 ? (
              <p className="text-callout text-text-secondary">Everyone&apos;s square.</p>
            ) : (
              <ul className="divide-y divide-border">
                {g.payments.map((p) => (
                  <li key={`${p.from_member_id}-${p.to_member_id}`} className="flex flex-wrap items-center gap-md py-sm">
                    <p className="flex min-w-0 flex-1 items-center gap-sm text-callout">
                      <span className="truncate font-medium">{nameOf(p.from_member_id)}</span>
                      <ArrowRight size={14} className="shrink-0 text-text-tertiary" />
                      <span className="truncate font-medium">{nameOf(p.to_member_id)}</span>
                    </p>
                    <span className="font-mono text-callout tabular">{money(p.amount, g.currency)}</span>
                    <Button
                      variant="secondary"
                      size="sm"
                      onClick={() => setPayment({ from: p.from_member_id, to: p.to_member_id, amount: p.amount })}
                    >
                      <Check size={14} /> Paid
                    </Button>
                  </li>
                ))}
              </ul>
            )}

            {payment && (
              <form onSubmit={recordPayment} className="space-y-md rounded-lg bg-surface-2 p-lg">
                <div className="grid gap-md sm:grid-cols-[1fr_1fr_8rem]">
                  <div className="space-y-xs">
                    <Label htmlFor="pay-from">Who paid</Label>
                    <MemberSelect id="pay-from" group={g} value={payment.from} onChange={(from) => setPayment({ ...payment, from })} />
                  </div>
                  <div className="space-y-xs">
                    <Label htmlFor="pay-to">To</Label>
                    <MemberSelect id="pay-to" group={g} value={payment.to} onChange={(to) => setPayment({ ...payment, to })} />
                  </div>
                  <div className="space-y-xs">
                    <Label htmlFor="pay-amount">Amount</Label>
                    <Input
                      id="pay-amount"
                      inputMode="decimal"
                      value={payment.amount}
                      onChange={(e) => setPayment({ ...payment, amount: e.target.value })}
                      placeholder="0.00"
                      className="tabular"
                    />
                  </div>
                </div>
                <p className="text-caption text-text-tertiary">
                  Tally only keeps track. Send the money however you normally do.
                </p>
                <div className="flex justify-end gap-sm">
                  <Button type="button" variant="ghost" size="sm" onClick={() => setPayment(null)}>
                    Cancel
                  </Button>
                  <Button
                    type="submit"
                    size="sm"
                    disabled={payment.from === payment.to || !(Number(payment.amount) > 0)}
                  >
                    Record payment
                  </Button>
                </div>
              </form>
            )}
          </Card>

          {/* ── Expenses ─────────────────────────────── */}
          <Card className="space-y-lg">
            <div className="flex items-center justify-between gap-md">
              <CardTitle>Expenses</CardTitle>
              {!adding && !editing && (
                <Button size="sm" onClick={() => setAdding(true)}>
                  <Plus size={15} /> Add expense
                </Button>
              )}
            </div>

            {(adding || editing) && (
              <div className="rounded-lg bg-surface-2 p-lg">
                <SplitEditor
                  fixedGroupId={g.id}
                  existing={editing ?? undefined}
                  currency={g.currency}
                  onDone={async () => {
                    setAdding(false);
                    setEditing(null);
                    await refresh();
                  }}
                  onCancel={() => {
                    setAdding(false);
                    setEditing(null);
                  }}
                />
              </div>
            )}

            {g.splits.length === 0 && !adding ? (
              <p className="text-callout text-text-secondary">
                Nothing yet. Add an expense here, or split a receipt with this group from the receipt itself.
              </p>
            ) : (
              <ul className="divide-y divide-border">
                {g.splits.map((s) => {
                  const payer = payers(s);
                  const isOpen = open === s.id;
                  return (
                    <li key={s.id} className="py-sm">
                      <button
                        type="button"
                        onClick={() => setOpen(isOpen ? null : s.id)}
                        aria-expanded={isOpen}
                        className="flex w-full items-center gap-md rounded-md py-xs text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--c-focus-ring)]"
                      >
                        <span className="w-14 shrink-0 font-mono text-[11px] uppercase tracking-[0.08em] text-text-tertiary">
                          {shortDate(s.date)}
                        </span>
                        <span className="min-w-0 flex-1">
                          <span className="flex items-center gap-xs truncate text-callout font-medium">
                            {s.receipt_id && <ReceiptText size={14} className="shrink-0 text-text-tertiary" />}
                            {s.description || "Expense"}
                          </span>
                          <span className="block truncate text-caption text-text-tertiary">
                            {payer ? `${payer.is_me ? "You" : payer.display_name} paid ${money(s.total, s.currency)}` : money(s.total, s.currency)}
                          </span>
                        </span>
                        <span className="text-right">
                          <span className="block font-mono text-callout tabular">
                            {s.my_share != null ? money(s.my_share, s.currency) : "—"}
                          </span>
                          <span className="block text-[11px] text-text-tertiary">your share</span>
                        </span>
                      </button>
                      {isOpen && (
                        <div className="mt-sm rounded-lg bg-surface-2 p-lg">
                          <SplitSummary
                            split={s}
                            onChange={() => refresh()}
                            onEdit={
                              s.receipt_id
                                ? () => router.push(`/receipts/${s.receipt_id}`)
                                : () => {
                                    setEditing(s);
                                    setAdding(false);
                                  }
                            }
                            onRemove={() => removeSplit(s)}
                          />
                        </div>
                      )}
                    </li>
                  );
                })}
              </ul>
            )}
          </Card>

          {/* ── Payments ─────────────────────────────── */}
          {g.settlements.length > 0 && (
            <Card className="space-y-lg">
              <CardTitle>Payments</CardTitle>
              <ul className="divide-y divide-border">
                {g.settlements.map((st) => (
                  <li key={st.id} className="flex items-center gap-md py-sm">
                    <span className="w-14 shrink-0 font-mono text-[11px] uppercase tracking-[0.08em] text-text-tertiary">
                      {shortDate(st.date)}
                    </span>
                    <p className="min-w-0 flex-1 truncate text-callout">
                      {nameOf(st.from_member_id)} paid {nameOf(st.to_member_id)}
                      {st.note && <span className="text-text-tertiary"> · {st.note}</span>}
                    </p>
                    <span className="font-mono text-callout tabular">{money(st.amount, g.currency)}</span>
                    <Button
                      variant="ghost"
                      size="icon"
                      aria-label="Delete payment"
                      onClick={() => {
                        if (window.confirm("Delete this payment?"))
                          run(() => apiDelete<GroupDetail>(`v1/groups/${id}/settlements/${st.id}`));
                      }}
                    >
                      <Trash2 size={15} />
                    </Button>
                  </li>
                ))}
              </ul>
            </Card>
          )}
        </div>

        {/* ── People ─────────────────────────────── */}
        <div className="space-y-2xl">
          <Card className="space-y-lg">
            <CardTitle>People</CardTitle>
            <ul className="space-y-sm">
              {g.members.map((m) => (
                <li key={m.id} className="flex items-center gap-sm">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-callout font-medium">{m.is_me ? `${m.display_name} (you)` : m.display_name}</p>
                    {!m.has_account && <p className="text-[11px] text-text-tertiary">Hasn&apos;t joined yet</p>}
                  </div>
                  <span
                    className={cn(
                      "font-mono text-caption tabular",
                      Number(m.balance) > 0 && "text-success",
                      Number(m.balance) < 0 && "text-danger",
                      Number(m.balance) === 0 && "text-text-tertiary",
                    )}
                  >
                    {Number(m.balance) > 0 && "+"}
                    {money(m.balance, g.currency)}
                  </span>
                  {!m.has_account && (
                    <Button
                      variant="ghost"
                      size="icon"
                      aria-label={`Remove ${m.display_name}`}
                      onClick={() => run(() => apiDelete<GroupDetail>(`v1/groups/${id}/members/${m.id}`))}
                    >
                      <X size={15} />
                    </Button>
                  )}
                </li>
              ))}
            </ul>
            <form onSubmit={addMember} className="flex gap-sm">
              <Input
                value={newMember}
                onChange={(e) => setNewMember(e.target.value)}
                placeholder="Add a name"
                maxLength={120}
                aria-label="New person's name"
              />
              <Button type="submit" variant="secondary" disabled={!newMember.trim()}>
                Add
              </Button>
            </form>
            <InviteLink url={g.invite_url} groupName={g.name} />
          </Card>

          {g.is_owner && (
            <Button variant="ghost" size="sm" className="text-danger" onClick={deleteGroup}>
              <Trash2 size={15} /> Delete group
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}

function MemberSelect({
  id,
  group,
  value,
  onChange,
}: {
  id: string;
  group: GroupDetail;
  value: string;
  onChange: (id: string) => void;
}) {
  return (
    <select
      id={id}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="h-11 w-full rounded-md border border-border bg-surface px-md text-body text-text focus-visible:border-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--c-focus-ring)]"
    >
      {group.members.map((m) => (
        <option key={m.id} value={m.id}>
          {m.is_me ? "You" : m.display_name}
        </option>
      ))}
    </select>
  );
}

function InviteLink({ url, groupName }: { url: string; groupName: string }) {
  const canShare = useCanShare();
  const [copied, setCopied] = useState(false);

  async function share() {
    const text = `Join ${groupName} on Tally to see what we've spent and who owes whom.`;
    if (canShare) {
      try {
        await navigator.share({ title: groupName, text, url });
        return;
      } catch {
        /* dismissed: fall back to copying */
      }
    }
    await navigator.clipboard.writeText(url);
    setCopied(true);
    setTimeout(() => setCopied(false), 1800);
  }

  return (
    <div className="space-y-sm border-t border-border pt-lg">
      <p className="text-caption text-text-secondary">
        Send the invite link. Each person signs in and picks their name, so they see the group too.
      </p>
      <Button variant="secondary" size="sm" className="w-full" onClick={share}>
        {copied ? <Check size={14} /> : canShare ? <Share2 size={14} /> : <Copy size={14} />}
        {copied ? "Invite link copied" : canShare ? "Send invite link" : "Copy invite link"}
      </Button>
    </div>
  );
}
