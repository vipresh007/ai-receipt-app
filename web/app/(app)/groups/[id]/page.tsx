"use client";

import { useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Banknote,
  Bell,
  Check,
  ChevronDown,
  ChevronLeft,
  Copy,
  ReceiptText,
  Share2,
  Trash2,
  X,
} from "lucide-react";
import { apiDelete, apiGet, apiPatch, apiPost } from "@/lib/api";
import { money, shortDate } from "@/lib/format";
import type { GroupDetail, GroupMember, Split } from "@/lib/types";
import { Card, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { PageHeader } from "@/components/page-header";
import { BalanceTag } from "@/components/balance-tag";
import { SplitEditor } from "@/components/split-editor";
import { SplitSummary, useCanShare } from "@/components/split-summary";
import { AddExpense } from "@/components/add-expense";
import { PayTo } from "@/components/pay-to";
import { cn } from "@/lib/utils";
import { LIVE } from "@/lib/live";

interface PaymentDraft {
  from: string;
  to: string;
  amount: string;
}

export default function GroupPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const queryClient = useQueryClient();
  const {
    data: group,
    isLoading,
    error: loadError,
  } = useQuery({
    ...LIVE,
    queryKey: ["group", id],
    queryFn: () => apiGet<GroupDetail>(`v1/groups/${id}`),
  });

  const [editing, setEditing] = useState<Split | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  const [payment, setPayment] = useState<PaymentDraft | null>(null);
  const [newMember, setNewMember] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

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
          {loadError instanceof Error
            ? loadError.message
            : "It may have been deleted, or you're not in it."}
        </p>
        <Link href="/groups" className="text-callout text-accent">
          Back to Shared
        </Link>
      </Card>
    );
  }

  const g = group;
  const me = g.members.find((m) => m.is_me);
  const nameOf = (memberId: string) => {
    const m = g.members.find((x) => x.id === memberId);
    return m ? (m.is_me ? "you" : m.display_name) : "someone";
  };
  const cap = (text: string) => text.charAt(0).toUpperCase() + text.slice(1);

  /** Between you and one member, as the group settles up: positive = they owe you. */
  const withMe = (m: GroupMember) =>
    g.payments.reduce((sum, p) => {
      if (p.from_member_id === m.id && p.to_member_id === me?.id)
        return sum + Number(p.amount);
      if (p.from_member_id === me?.id && p.to_member_id === m.id)
        return sum - Number(p.amount);
      return sum;
    }, 0);
  const others = g.payments.filter(
    (p) => p.from_member_id !== me?.id && p.to_member_id !== me?.id,
  );

  async function refresh(next?: GroupDetail) {
    if (next) queryClient.setQueryData(["group", id], next);
    await queryClient.invalidateQueries();
  }

  async function run(action: () => Promise<GroupDetail | null | void>) {
    setError(null);
    setNotice(null);
    try {
      await refresh((await action()) ?? undefined);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong.");
    }
  }

  function recordPayment(e: React.FormEvent) {
    e.preventDefault();
    if (!payment) return;
    run(async () => {
      const next = await apiPost<GroupDetail>(`v1/groups/${id}/settlements`, {
        from_member_id: payment.from,
        to_member_id: payment.to,
        amount: payment.amount,
      });
      setPayment(null);
      setNotice(
        `Recorded: ${cap(nameOf(payment.from))} paid ${nameOf(payment.to)} ${money(payment.amount, g.currency)}.`,
      );
      return next;
    });
  }

  function addMember(e: React.FormEvent) {
    e.preventDefault();
    if (!newMember.trim()) return;
    run(async () => {
      const next = await apiPost<GroupDetail>(`v1/groups/${id}/members`, {
        name: newMember,
      });
      setNewMember("");
      return next;
    });
  }

  async function deleteGroup() {
    if (
      !window.confirm(
        `Delete ${g.name}? Its expenses and payments go too; split receipts count in full again.`,
      )
    )
      return;
    await apiDelete(`v1/groups/${id}`);
    await queryClient.invalidateQueries();
    router.push("/groups");
  }

  async function removeSplit(split: Split) {
    if (!window.confirm(`Remove ${split.description || "this expense"}?`))
      return;
    await run(async () => {
      await apiDelete(`v1/splits/${split.id}`);
      setOpen(null);
    });
  }

  return (
    <div className="space-y-2xl">
      <div className="space-y-md">
        <Link
          href="/groups"
          className="inline-flex items-center gap-xs text-caption text-text-secondary hover:text-text"
        >
          <ChevronLeft size={15} /> Shared
        </Link>
        <PageHeader
          eyebrow={`${g.members.length} ${g.members.length === 1 ? "person" : "people"} · ${g.currency}`}
          title={g.name}
          actions={
            <BalanceTag
              balance={g.my_balance}
              currency={g.currency}
              className="text-callout"
            />
          }
        />
      </div>

      {error && (
        <p
          role="alert"
          className="rounded-md bg-danger-muted px-md py-sm text-caption text-danger"
        >
          {error}
        </p>
      )}
      {notice && !error && (
        <p
          role="status"
          className="rounded-md bg-success-muted px-md py-sm text-caption text-success"
        >
          {notice}
        </p>
      )}

      <div className="grid gap-2xl lg:grid-cols-[minmax(0,1fr)_minmax(0,24rem)]">
        {/* ── People: who's in, where each stands with you, what to do ──
            First on phones; the side column on wide screens. */}
        <div className="space-y-2xl lg:order-2">
          <Card className="space-y-lg">
            <CardTitle>People</CardTitle>
            <ul className="divide-y divide-border">
              {me && (
                <li className="flex items-center gap-md pb-md">
                  <Avatar name={me.display_name} accent />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-callout font-medium">You</p>
                    <p className="text-caption text-text-tertiary">
                      {balanceLine(Number(me.balance), g.currency)}
                    </p>
                  </div>
                </li>
              )}
              {g.members
                .filter((m) => !m.is_me)
                .map((m) => {
                  const owed = withMe(m);
                  const elsewhere = Number(m.balance) - owed;
                  return (
                    <li key={m.id} className="space-y-sm py-md last:pb-0">
                      <div className="flex items-center gap-md">
                        <Avatar name={m.display_name} />
                        <div className="min-w-0 flex-1">
                          <p className="flex items-center gap-xs truncate text-callout font-medium">
                            {m.display_name}
                            {!m.has_account && (
                              <span className="rounded-pill bg-surface-2 px-sm text-[10.5px] font-normal text-text-tertiary">
                                not joined
                              </span>
                            )}
                          </p>
                          <p
                            className={cn(
                              "text-caption tabular",
                              owed > 0
                                ? "text-success"
                                : owed < 0
                                  ? "text-danger"
                                  : "text-text-tertiary",
                            )}
                          >
                            {owed > 0
                              ? `owes you ${money(owed, g.currency)}`
                              : owed < 0
                                ? `you owe ${money(-owed, g.currency)}`
                                : Math.abs(elsewhere) < 0.005
                                  ? "settled up"
                                  : elsewhere < 0
                                    ? `owes others ${money(-elsewhere, g.currency)}`
                                    : `is owed ${money(elsewhere, g.currency)} by others`}
                          </p>
                        </div>
                        {!m.has_account &&
                          owed === 0 &&
                          Math.abs(elsewhere) < 0.005 && (
                            <button
                              type="button"
                              aria-label={`Remove ${m.display_name}`}
                              className="grid h-7 w-7 place-items-center rounded-full text-text-tertiary hover:bg-surface-2 hover:text-danger"
                              onClick={() => {
                                if (
                                  window.confirm(
                                    `Remove ${m.display_name} from the group?`,
                                  )
                                )
                                  run(() =>
                                    apiDelete<GroupDetail>(
                                      `v1/groups/${id}/members/${m.id}`,
                                    ),
                                  );
                              }}
                            >
                              <X size={14} />
                            </button>
                          )}
                      </div>
                      {owed !== 0 && me && (
                        <div className="flex flex-wrap gap-sm pl-[48px]">
                          <Button
                            variant="secondary"
                            size="sm"
                            onClick={() =>
                              setPayment(
                                owed > 0
                                  ? {
                                      from: m.id,
                                      to: me.id,
                                      amount: owed.toFixed(2),
                                    }
                                  : {
                                      from: me.id,
                                      to: m.id,
                                      amount: (-owed).toFixed(2),
                                    },
                              )
                            }
                          >
                            <Check size={14} /> Record payment
                          </Button>
                          {owed > 0 && m.has_account && (
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() =>
                                run(async () => {
                                  const next = await apiPost<GroupDetail>(
                                    `v1/groups/${id}/members/${m.id}/remind`,
                                    {},
                                  );
                                  setNotice(
                                    `Reminder sent to ${m.display_name}.`,
                                  );
                                  return next;
                                })
                              }
                            >
                              <Bell size={14} /> Remind
                            </Button>
                          )}
                        </div>
                      )}
                      {owed < 0 && (
                        <div className="pl-[48px]">
                          <PayTo
                            payTo={m.pay_to}
                            amount={owed}
                            currency={g.currency}
                            name={m.display_name}
                          />
                        </div>
                      )}
                    </li>
                  );
                })}
            </ul>

            {others.length > 0 && (
              <div className="space-y-xs rounded-lg bg-surface-2 p-md">
                <p className="text-caption font-medium text-text-secondary">
                  Between others
                </p>
                {others.map((p) => (
                  <p
                    key={`${p.from_member_id}-${p.to_member_id}`}
                    className="flex justify-between gap-md text-caption"
                  >
                    <span>
                      {cap(nameOf(p.from_member_id))} owes{" "}
                      {nameOf(p.to_member_id)}
                    </span>
                    <span className="font-mono tabular">
                      {money(p.amount, g.currency)}
                    </span>
                  </p>
                ))}
              </div>
            )}

            {payment && (
              <form
                onSubmit={recordPayment}
                className="space-y-md rounded-lg bg-surface-2 p-lg"
              >
                <p className="text-callout font-medium">Record a payment</p>
                <div className="grid gap-md">
                  <div className="grid grid-cols-2 gap-md">
                    <div className="space-y-xs">
                      <Label htmlFor="pay-from">Who paid</Label>
                      <MemberSelect
                        id="pay-from"
                        group={g}
                        value={payment.from}
                        onChange={(from) => setPayment({ ...payment, from })}
                      />
                    </div>
                    <div className="space-y-xs">
                      <Label htmlFor="pay-to">To</Label>
                      <MemberSelect
                        id="pay-to"
                        group={g}
                        value={payment.to}
                        onChange={(to) => setPayment({ ...payment, to })}
                      />
                    </div>
                  </div>
                  <div className="space-y-xs">
                    <Label htmlFor="pay-amount">Amount</Label>
                    <Input
                      id="pay-amount"
                      inputMode="decimal"
                      value={payment.amount}
                      onChange={(e) =>
                        setPayment({ ...payment, amount: e.target.value })
                      }
                      placeholder="0.00"
                      className="tabular"
                    />
                  </div>
                </div>
                <p className="text-caption text-text-tertiary">
                  Tally only keeps track. Paying back one expense? Tick
                  &ldquo;Mark paid&rdquo; on it instead.
                </p>
                <div className="flex justify-end gap-sm">
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    onClick={() => setPayment(null)}
                  >
                    Cancel
                  </Button>
                  <Button
                    type="submit"
                    size="sm"
                    disabled={
                      payment.from === payment.to ||
                      !(Number(payment.amount) > 0)
                    }
                  >
                    Record payment
                  </Button>
                </div>
              </form>
            )}

            <form
              onSubmit={addMember}
              className="flex gap-sm border-t border-border pt-lg"
            >
              <Input
                value={newMember}
                onChange={(e) => setNewMember(e.target.value)}
                placeholder="Add someone"
                maxLength={120}
                aria-label="New person's name"
              />
              <Button
                type="submit"
                variant="secondary"
                disabled={!newMember.trim()}
              >
                Add
              </Button>
            </form>
            <InviteLink url={g.invite_url} groupName={g.name} />

            <div className="space-y-sm border-t border-border pt-lg">
              <label className="flex items-start gap-sm text-callout">
                <input
                  type="checkbox"
                  checked={g.simplify_debts}
                  onChange={(e) =>
                    run(() =>
                      apiPatch<GroupDetail>(`v1/groups/${id}`, {
                        simplify_debts: e.target.checked,
                      }),
                    )
                  }
                  className="mt-[3px] h-4 w-4 accent-[var(--c-accent)]"
                />
                <span>
                  Simplify debts
                  <span className="block text-caption text-text-tertiary">
                    {g.simplify_debts
                      ? "Fewest payments: if you owe Sam and Sam owes Kim, you pay Kim directly."
                      : "Everyone pays back whoever they owe, expense by expense."}
                  </span>
                </span>
              </label>
              {!payment && me && g.members.length > 1 && (
                <button
                  type="button"
                  className="text-caption text-accent"
                  onClick={() =>
                    setPayment({
                      from: g.members.find((m) => !m.is_me)!.id,
                      to: me.id,
                      amount: "",
                    })
                  }
                >
                  Record some other payment
                </button>
              )}
            </div>
          </Card>

          {g.is_owner && (
            <Button
              variant="ghost"
              size="sm"
              className="text-danger"
              onClick={deleteGroup}
            >
              <Trash2 size={15} /> Delete group
            </Button>
          )}
        </div>

        {/* ── Expenses (by month), then payments ── */}
        <div className="space-y-2xl lg:order-1">
          <Card className="space-y-lg">
            <div className="flex flex-wrap items-center justify-between gap-md">
              <CardTitle>Expenses</CardTitle>
              {!editing && (
                <AddExpense
                  target={{ kind: "group", id: g.id, name: g.name }}
                  currency={g.currency}
                  onDone={() => refresh()}
                />
              )}
            </div>

            {editing && (
              <div className="rounded-lg bg-surface-2 p-lg">
                <SplitEditor
                  fixedGroupId={g.id}
                  existing={editing}
                  currency={g.currency}
                  onDone={async () => {
                    setEditing(null);
                    await refresh();
                  }}
                  onCancel={() => setEditing(null)}
                />
              </div>
            )}

            {g.splits.length === 0 ? (
              <p className="text-callout text-text-secondary">
                Nothing yet. Add an expense, or split a receipt with this group
                from the receipt itself.
              </p>
            ) : (
              byMonth(g.splits).map(([month, splits]) => (
                <section key={month} className="space-y-xs">
                  <h3 className="font-mono text-[11px] uppercase tracking-[0.14em] text-text-tertiary">
                    {month}
                  </h3>
                  <ul className="divide-y divide-border">
                    {splits.map((split) => (
                      <ExpenseRow
                        key={split.id}
                        split={split}
                        open={open === split.id}
                        onToggle={() =>
                          setOpen(open === split.id ? null : split.id)
                        }
                        onChange={() => refresh()}
                        onEdit={
                          split.receipt_id && split.is_owner
                            ? () => router.push(`/receipts/${split.receipt_id}`)
                            : () => setEditing(split)
                        }
                        onRemove={() => removeSplit(split)}
                      />
                    ))}
                  </ul>
                </section>
              ))
            )}
          </Card>

          {g.settlements.length > 0 && (
            <Card className="space-y-md">
              <CardTitle>Payments</CardTitle>
              <ul className="divide-y divide-border">
                {g.settlements.map((s) => (
                  <li key={s.id} className="flex items-center gap-md py-sm">
                    <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-success-muted text-success">
                      <Banknote size={15} />
                    </span>
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-callout">
                        {cap(nameOf(s.from_member_id))} paid{" "}
                        {nameOf(s.to_member_id)}
                      </p>
                      <p className="text-caption text-text-tertiary">
                        {shortDate(s.date)}
                        {s.note && ` · ${s.note}`}
                      </p>
                    </div>
                    <span className="font-mono text-callout tabular">
                      {money(s.amount, g.currency)}
                    </span>
                    <button
                      type="button"
                      aria-label="Delete payment"
                      className="grid h-7 w-7 shrink-0 place-items-center rounded-full text-text-tertiary hover:bg-surface-2 hover:text-danger"
                      onClick={() => {
                        if (window.confirm("Delete this payment?"))
                          run(() =>
                            apiDelete<GroupDetail>(
                              `v1/groups/${id}/settlements/${s.id}`,
                            ),
                          );
                      }}
                    >
                      <X size={14} />
                    </button>
                  </li>
                ))}
              </ul>
            </Card>
          )}
        </div>
      </div>
    </div>
  );
}

function Avatar({ name, accent }: { name: string; accent?: boolean }) {
  return (
    <span
      className={cn(
        "grid h-9 w-9 shrink-0 place-items-center rounded-full text-callout font-semibold",
        accent ? "bg-accent-muted text-accent" : "bg-surface-2",
      )}
    >
      {name.charAt(0).toUpperCase()}
    </span>
  );
}

function balanceLine(balance: number, currency: string): string {
  if (balance > 0.004)
    return `you're owed ${money(balance, currency)} in total`;
  if (balance < -0.004) return `you owe ${money(-balance, currency)} in total`;
  return "you're settled up";
}

/** Expenses grouped by month, newest first: [["October 2026", [...]], ...]. */
function byMonth(splits: Split[]): [string, Split[]][] {
  const groups = new Map<string, Split[]>();
  for (const split of [...splits].sort((a, b) => (a.date < b.date ? 1 : -1))) {
    const label = new Date(`${split.date}T00:00:00`).toLocaleDateString(
      undefined,
      { month: "long", year: "numeric" },
    );
    groups.set(label, [...(groups.get(label) ?? []), split]);
  }
  return [...groups.entries()];
}

function ExpenseRow({
  split,
  open,
  onToggle,
  onChange,
  onEdit,
  onRemove,
}: {
  split: Split;
  open: boolean;
  onToggle: () => void;
  onChange: () => void;
  onEdit: () => void;
  onRemove: () => void;
}) {
  const payers = split.participants.filter((p) => p.is_payer);
  const paidBy =
    payers.length === 1
      ? `${payers[0].is_me ? "You" : payers[0].display_name} paid`
      : `${payers.length} people paid`;
  const unpaid = split.participants.filter(
    (p) => !p.is_payer && !p.settled && Number(p.share) > 0,
  ).length;
  return (
    <li className="py-sm">
      <button
        type="button"
        onClick={onToggle}
        aria-expanded={open}
        className="flex w-full items-center gap-md rounded-md py-xs text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--c-focus-ring)]"
      >
        <span className="w-14 shrink-0 font-mono text-[11px] uppercase tracking-[0.08em] text-text-tertiary">
          {shortDate(split.date)}
        </span>
        <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-surface-2 text-text-secondary">
          <ReceiptText size={15} />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block truncate text-callout font-medium">
            {split.description || "Expense"}
          </span>
          <span className="block truncate text-caption text-text-tertiary">
            {paidBy} {money(split.total, split.currency)}
            {unpaid === 0 && " · all paid back"}
          </span>
        </span>
        <span className="text-right">
          <span className="block font-mono text-callout tabular">
            {split.my_share != null
              ? money(split.my_share, split.currency)
              : "—"}
          </span>
          <span className="block text-[11px] text-text-tertiary">
            your share
          </span>
        </span>
        <ChevronDown
          size={16}
          className={cn(
            "shrink-0 text-text-tertiary transition-transform",
            open && "rotate-180",
          )}
        />
      </button>
      {open && (
        <div className="mt-sm rounded-lg bg-surface-2 p-lg">
          <SplitSummary
            split={split}
            onChange={onChange}
            onEdit={onEdit}
            onRemove={onRemove}
          />
        </div>
      )}
    </li>
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
        Send the invite link. Each person signs in and picks their name, so they
        see the group too.
      </p>
      <Button variant="secondary" size="sm" className="w-full" onClick={share}>
        {copied ? (
          <Check size={14} />
        ) : canShare ? (
          <Share2 size={14} />
        ) : (
          <Copy size={14} />
        )}
        {copied
          ? "Invite link copied"
          : canShare
            ? "Send invite link"
            : "Copy invite link"}
      </Button>
    </div>
  );
}
