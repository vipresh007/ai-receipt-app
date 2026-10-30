"use client";

import { useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Bell,
  Check,
  ChevronLeft,
  Copy,
  Mail,
  Plus,
  ReceiptText,
  Share2,
  Trash2,
} from "lucide-react";
import { apiDelete, apiGet, apiPatch, apiPost } from "@/lib/api";
import { money, shortDate } from "@/lib/format";
import type { PersonDetail, Split } from "@/lib/types";
import { Card, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { PageHeader } from "@/components/page-header";
import { PersonBalanceTag, personBalanceText } from "@/components/balance-tag";
import { SplitEditor } from "@/components/split-editor";
import { SplitSummary, useCanShare } from "@/components/split-summary";
import { PayTo } from "@/components/pay-to";
import { LIVE } from "@/lib/live";

export default function PersonPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const queryClient = useQueryClient();
  const {
    data: person,
    isLoading,
    error: loadError,
  } = useQuery({
    ...LIVE,
    queryKey: ["person", id],
    queryFn: () => apiGet<PersonDetail>(`v1/people/${id}`),
  });

  const [adding, setAdding] = useState(false);
  const [editing, setEditing] = useState<Split | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  const [payment, setPayment] = useState<{
    youPaid: boolean;
    amount: string;
  } | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (isLoading) {
    return (
      <div className="space-y-lg">
        <Skeleton className="h-16 w-1/2" />
        <Skeleton className="h-40" />
      </div>
    );
  }
  if (!person) {
    return (
      <Card className="space-y-sm">
        <CardTitle>Person not found</CardTitle>
        <p className="text-callout text-text-secondary">
          {loadError instanceof Error
            ? loadError.message
            : "They may have been removed."}
        </p>
        <Link href="/groups" className="text-callout text-accent">
          Back to Shared
        </Link>
      </Card>
    );
  }

  const p = person;
  const balance = Number(p.balance);

  /** Balances, your spending and lists can all move. */
  async function refresh(next?: PersonDetail) {
    if (next) queryClient.setQueryData(["person", id], next);
    await queryClient.invalidateQueries();
  }

  async function run(action: () => Promise<PersonDetail | null | void>) {
    setError(null);
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
      const next = await apiPost<PersonDetail>(`v1/people/${id}/payments`, {
        you_paid: payment.youPaid,
        amount: payment.amount,
      });
      setPayment(null);
      return next;
    });
  }

  async function removeSplit(split: Split) {
    if (!window.confirm(`Remove ${split.description || "this expense"}?`))
      return;
    await run(async () => {
      await apiDelete(`v1/splits/${split.id}`);
      setOpen(null);
    });
  }

  async function removePerson() {
    if (
      !window.confirm(
        `Remove ${p.name}? Expenses keep their name; payments with them are deleted.`,
      )
    )
      return;
    await apiDelete(`v1/people/${id}`);
    await queryClient.invalidateQueries();
    router.push("/groups");
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
          eyebrow={p.has_account ? "On Tally" : (p.email ?? "Just a name")}
          title={p.name}
          actions={
            <PersonBalanceTag
              balance={p.balance}
              currency={p.currency}
              name={p.name}
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

      <div className="grid gap-2xl lg:grid-cols-[minmax(0,1fr)_minmax(0,22rem)]">
        <div className="space-y-2xl">
          {/* ── Settle up ─────────────────────────────── */}
          <Card className="space-y-lg">
            <div className="flex flex-wrap items-center justify-between gap-md">
              <div>
                <CardTitle>Settle up</CardTitle>
                <p className="mt-xs text-callout text-text-secondary">
                  {personBalanceText(p.balance, p.currency, p.name)}.
                </p>
                {p.group_balances.length > 0 && (
                  <p className="mt-xs text-caption text-text-tertiary tabular">
                    {[
                      `Outside groups ${signed(p.outside_groups, p.currency)}`,
                      ...p.group_balances.map(
                        (g) => `${g.name} ${signed(g.balance, p.currency)}`,
                      ),
                    ].join(" · ")}
                  </p>
                )}
              </div>
              <div className="flex flex-wrap gap-sm">
                {balance > 0 && (
                  <RemindButton person={p} onSent={(next) => refresh(next)} />
                )}
                {!payment && (
                  <Button
                    variant={balance === 0 ? "ghost" : "secondary"}
                    size="sm"
                    onClick={() =>
                      setPayment({
                        youPaid: balance < 0,
                        amount:
                          balance === 0 ? "" : Math.abs(balance).toFixed(2),
                      })
                    }
                  >
                    <Check size={14} /> Record a payment
                  </Button>
                )}
              </div>
            </div>
            {balance < 0 && (
              <PayTo
                payTo={p.pay_to}
                amount={balance}
                currency={p.currency}
                name={p.name}
              />
            )}
            {payment && (
              <form
                onSubmit={recordPayment}
                className="space-y-md rounded-lg bg-surface-2 p-lg"
              >
                <div className="grid gap-md sm:grid-cols-[1fr_8rem]">
                  <div className="space-y-xs">
                    <Label htmlFor="pay-dir">Who paid</Label>
                    <select
                      id="pay-dir"
                      value={payment.youPaid ? "me" : "them"}
                      onChange={(e) =>
                        setPayment({
                          ...payment,
                          youPaid: e.target.value === "me",
                        })
                      }
                      className="h-11 w-full rounded-md border border-border bg-surface px-md text-callout"
                    >
                      <option value="them">{p.name} paid me</option>
                      <option value="me">I paid {p.name}</option>
                    </select>
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
                  Tally only keeps track. Send the money however you normally
                  do.
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
                    disabled={!(Number(payment.amount) > 0)}
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
                  withPeople={[{ id: p.id, name: p.name }]}
                  existing={editing ?? undefined}
                  currency={editing?.currency ?? p.currency}
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
            {p.splits.length === 0 && !adding ? (
              <p className="text-callout text-text-secondary">
                Nothing shared yet. Add an expense, or split a receipt with{" "}
                {p.name} from the receipt.
              </p>
            ) : (
              <ul className="divide-y divide-border">
                {p.splits.map((s) => {
                  const payer = s.participants.find((x) => x.is_payer);
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
                            {s.receipt_id && (
                              <ReceiptText
                                size={14}
                                className="shrink-0 text-text-tertiary"
                              />
                            )}
                            {s.description || "Expense"}
                          </span>
                          <span className="block truncate text-caption text-text-tertiary">
                            {payer
                              ? `${payer.is_me ? "You" : payer.display_name} paid ${money(s.total, s.currency)}`
                              : money(s.total, s.currency)}
                          </span>
                        </span>
                        <span className="text-right">
                          <span className="block font-mono text-callout tabular">
                            {s.my_share != null
                              ? money(s.my_share, s.currency)
                              : "—"}
                          </span>
                          <span className="block text-[11px] text-text-tertiary">
                            your share
                          </span>
                        </span>
                      </button>
                      {isOpen && (
                        <div className="mt-sm rounded-lg bg-surface-2 p-lg">
                          <SplitSummary
                            split={s}
                            onChange={() => refresh()}
                            onEdit={
                              s.receipt_id && s.is_owner
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
          {p.payments.length > 0 && (
            <Card className="space-y-lg">
              <CardTitle>Payments</CardTitle>
              <ul className="divide-y divide-border">
                {p.payments.map((pay) => (
                  <li key={pay.id} className="flex items-center gap-md py-sm">
                    <span className="w-14 shrink-0 font-mono text-[11px] uppercase tracking-[0.08em] text-text-tertiary">
                      {shortDate(pay.date)}
                    </span>
                    <p className="min-w-0 flex-1 truncate text-callout">
                      {pay.you_paid
                        ? `You paid ${p.name}`
                        : `${p.name} paid you`}
                      {pay.note && (
                        <span className="text-text-tertiary">
                          {" "}
                          · {pay.note}
                        </span>
                      )}
                    </p>
                    <span className="font-mono text-callout tabular">
                      {money(pay.amount, p.currency)}
                    </span>
                    {pay.can_delete && (
                      <Button
                        variant="ghost"
                        size="icon"
                        aria-label="Delete payment"
                        onClick={() => {
                          if (window.confirm("Delete this payment?"))
                            run(() =>
                              apiDelete<PersonDetail>(
                                `v1/people/${id}/payments/${pay.id}`,
                              ),
                            );
                        }}
                      >
                        <Trash2 size={15} />
                      </Button>
                    )}
                  </li>
                ))}
              </ul>
            </Card>
          )}
        </div>

        {/* ── Invite & details ─────────────────────────────── */}
        <div className="space-y-2xl">
          <InviteCard person={p} onSaved={(next) => refresh(next)} />
          <DetailsCard
            person={p}
            onSaved={(next) => refresh(next)}
            onRemove={removePerson}
          />
        </div>
      </div>
    </div>
  );
}

function InviteCard({
  person,
  onSaved,
}: {
  person: PersonDetail;
  onSaved: (p: PersonDetail) => void;
}) {
  const canShare = useCanShare();
  const [email, setEmail] = useState(person.email ?? "");
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState(false);
  const [note, setNote] = useState<{ ok: boolean; text: string } | null>(null);

  if (person.has_account) {
    return (
      <Card className="space-y-sm">
        <CardTitle>On Tally</CardTitle>
        <p className="text-callout text-text-secondary">
          {person.name} accepted your invite and sees what you share, from their
          side.
        </p>
      </Card>
    );
  }

  async function sendEmail() {
    setBusy(true);
    setNote(null);
    try {
      let current = person;
      if ((email.trim() || null) !== person.email) {
        current = await apiPatch<PersonDetail>(`v1/people/${person.id}`, {
          email: email.trim(),
        });
        onSaved(current);
      }
      if (!current.can_email) {
        setNote({
          ok: false,
          text: "Email invites aren't available yet. Share the link instead.",
        });
        return;
      }
      onSaved(await apiPost<PersonDetail>(`v1/people/${person.id}/invite`, {}));
      setNote({ ok: true, text: `Invite sent to ${current.email}.` });
    } catch (err) {
      setNote({
        ok: false,
        text: err instanceof Error ? err.message : "Couldn't send it.",
      });
    } finally {
      setBusy(false);
    }
  }

  async function shareLink() {
    const text = `I'm keeping track of what we share on Tally. See it here:`;
    if (canShare) {
      try {
        await navigator.share({ title: "Tally", text, url: person.invite_url });
        return;
      } catch {
        /* dismissed: copy instead */
      }
    }
    await navigator.clipboard.writeText(person.invite_url);
    setCopied(true);
    setTimeout(() => setCopied(false), 1800);
  }

  return (
    <Card className="space-y-lg">
      <div className="space-y-xs">
        <CardTitle>Invite {person.name}</CardTitle>
        <p className="text-caption text-text-secondary">
          Once they sign in from the invite, they see every expense you share
          and the balance, from their side.
        </p>
      </div>
      <Button
        variant="secondary"
        size="sm"
        className="w-full"
        onClick={shareLink}
      >
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
      <div className="space-y-xs border-t border-border pt-lg">
        <Label htmlFor="invite-email">Or email it</Label>
        <div className="flex gap-sm">
          <Input
            id="invite-email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="sam@example.com"
            maxLength={320}
          />
          <Button
            variant="secondary"
            disabled={!email.trim() || busy}
            onClick={sendEmail}
            aria-label="Email the invite"
          >
            <Mail size={15} />
          </Button>
        </div>
        {person.invited_at && !note && (
          <p className="text-caption text-text-tertiary">
            Invite emailed {shortDate(person.invited_at.slice(0, 10))}.
          </p>
        )}
        {note && (
          <p
            className={
              note.ok ? "text-caption text-success" : "text-caption text-danger"
            }
          >
            {note.text}
          </p>
        )}
      </div>
    </Card>
  );
}

function DetailsCard({
  person,
  onSaved,
  onRemove,
}: {
  person: PersonDetail;
  onSaved: (p: PersonDetail) => void;
  onRemove: () => void;
}) {
  const [name, setName] = useState(person.name);
  const [saving, setSaving] = useState(false);

  async function rename(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim() || name.trim() === person.name) return;
    setSaving(true);
    try {
      onSaved(
        await apiPatch<PersonDetail>(`v1/people/${person.id}`, {
          name: name.trim(),
        }),
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <Card className="space-y-lg">
      <form onSubmit={rename} className="space-y-xs">
        <Label htmlFor="person-rename">Name</Label>
        <div className="flex gap-sm">
          <Input
            id="person-rename"
            value={name}
            onChange={(e) => setName(e.target.value)}
            maxLength={120}
          />
          <Button
            type="submit"
            variant="secondary"
            disabled={saving || !name.trim() || name.trim() === person.name}
          >
            Save
          </Button>
        </div>
      </form>
      <Button
        variant="ghost"
        size="sm"
        className="text-danger"
        onClick={onRemove}
      >
        <Trash2 size={15} /> Remove {person.name}
      </Button>
    </Card>
  );
}

function signed(value: string, currency: string): string {
  const n = Number(value);
  return `${n > 0 ? "+" : n < 0 ? "−" : ""}${money(Math.abs(n), currency)}`;
}

/** Nudge them: Tally sends it (in the app once they've joined, by email when
 * there's an address), or you text it yourself. */
function RemindButton({
  person,
  onSent,
}: {
  person: PersonDetail;
  onSent: (p: PersonDetail) => void;
}) {
  const canShare = useCanShare();
  const [note, setNote] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const text = `Hi ${person.name}, a friendly reminder: you owe me ${money(person.balance, person.currency)}. Details on Tally: ${person.invite_url}`;

  async function remind() {
    setBusy(true);
    setNote(null);
    try {
      if (person.has_account || (person.email && person.can_email)) {
        onSent(
          await apiPost<PersonDetail>(`v1/people/${person.id}/remind`, {}),
        );
        setNote("Reminder sent.");
      } else if (canShare) {
        await navigator.share({ text });
      } else {
        await navigator.clipboard.writeText(text);
        setNote("Reminder copied. Paste it into a message.");
      }
    } catch (err) {
      if (!(err instanceof DOMException))
        setNote(err instanceof Error ? err.message : "Couldn't send it.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <span className="inline-flex flex-col items-end gap-[2px]">
      <Button variant="secondary" size="sm" onClick={remind} disabled={busy}>
        <Bell size={14} /> Remind
      </Button>
      {note && <span className="text-[11px] text-text-tertiary">{note}</span>}
    </span>
  );
}
