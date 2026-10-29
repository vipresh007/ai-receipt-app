"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Plus, X } from "lucide-react";
import { apiGet, apiPost, apiPut } from "@/lib/api";
import { money } from "@/lib/format";
import { previewShares } from "@/lib/splits";
import type {
  ExtractionItem,
  GroupDetail,
  GroupSummary,
  ParticipantIn,
  ReceiptOut,
  Split,
  SplitIn,
  SplitMode,
} from "@/lib/types";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";

const MODES: { value: SplitMode; label: string }[] = [
  { value: "even", label: "Evenly" },
  { value: "items", label: "By item" },
  { value: "custom", label: "Amounts" },
];

/** A person in the editor: you, a group member, or a typed name (one-off). */
interface Person {
  key: string;
  label: string;
  isMe: boolean;
  memberId?: string;
}

function today(): string {
  return new Date().toLocaleDateString("en-CA"); // YYYY-MM-DD, local
}

/**
 * Split a receipt (`receipt`) or a new expense inside a group (`fixedGroupId`
 * with no receipt). `existing` pre-fills an edit. Share math previews live;
 * the server's numbers come back in `onDone`.
 */
export function SplitEditor({
  receipt,
  fixedGroupId,
  existing,
  currency,
  onDone,
  onCancel,
}: {
  receipt?: ReceiptOut;
  fixedGroupId?: string;
  existing?: Split;
  currency: string;
  onDone: (split: Split) => void;
  onCancel: () => void;
}) {
  const { data: groups } = useQuery({
    queryKey: ["groups"],
    queryFn: () => apiGet<GroupSummary[]>("v1/groups"),
    enabled: !fixedGroupId,
  });
  const [groupId, setGroupId] = useState<string>(fixedGroupId ?? existing?.group_id ?? "");
  const { data: group } = useQuery({
    queryKey: ["group", groupId],
    queryFn: () => apiGet<GroupDetail>(`v1/groups/${groupId}`),
    enabled: !!groupId,
  });

  // Manual expense (no receipt).
  const [description, setDescription] = useState(existing?.description ?? "");
  const [total, setTotal] = useState(existing && !receipt ? existing.total : "");
  const [date, setDate] = useState(existing?.date ?? today());

  const items: ExtractionItem[] = receipt?.line_items ?? existing?.items ?? [];
  const splitTotal = receipt ? receipt.total : total || "0";

  // One-off people (beyond you), keyed p0, p1, …
  const [names, setNames] = useState<string[]>(() =>
    existing && !existing.group_id
      ? existing.participants.filter((p) => !p.is_me).map((p) => p.display_name)
      : [""],
  );
  const [includeMe, setIncludeMe] = useState(existing ? existing.participants.some((p) => p.is_me) : true);
  // Group members taking part (default: everyone), and who paid.
  const [excluded, setExcluded] = useState<Set<string>>(new Set());
  const [payerId, setPayerId] = useState<string>("");

  const [mode, setMode] = useState<SplitMode>(existing?.mode ?? "even");
  const [assigned, setAssigned] = useState<Record<string, number[]>>({});
  const [amounts, setAmounts] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const people: Person[] = useMemo(() => {
    if (groupId && group) {
      return group.members
        .filter((m) => !excluded.has(m.id))
        .map((m) => ({ key: m.id, label: m.is_me ? `${m.display_name} (you)` : m.display_name, isMe: m.is_me, memberId: m.id }));
    }
    const list: Person[] = includeMe ? [{ key: "me", label: "You", isMe: true }] : [];
    names.forEach((name, i) => list.push({ key: `p${i}`, label: name.trim() || `Person ${i + 1}`, isMe: false }));
    return list;
  }, [groupId, group, excluded, includeMe, names]);

  // Seed item assignments/amounts from an existing split, once people exist.
  const [seeded, setSeeded] = useState(false);
  if (existing && !seeded && people.length && (!existing.group_id || group)) {
    const nextAssigned: Record<string, number[]> = {};
    const nextAmounts: Record<string, string> = {};
    for (const p of existing.participants) {
      const person = people.find((x) => (p.member_id ? x.memberId === p.member_id : p.is_me ? x.isMe : x.label === p.display_name));
      if (!person) continue;
      nextAssigned[person.key] = p.item_indexes;
      if (p.amount) nextAmounts[person.key] = p.amount;
      if (p.is_payer && p.member_id) setPayerId(p.member_id);
    }
    if (existing.group_id && group) {
      const onSplit = new Set(existing.participants.map((p) => p.member_id));
      setExcluded(new Set(group.members.filter((m) => !onSplit.has(m.id)).map((m) => m.id)));
    }
    setAssigned(nextAssigned);
    setAmounts(nextAmounts);
    setSeeded(true);
  }

  const effectivePayer = groupId ? payerId || group?.members.find((m) => m.is_me)?.id || "" : "";

  const preview = previewShares(
    splitTotal,
    mode,
    people.map((p) => ({ itemIndexes: assigned[p.key] ?? [], amount: amounts[p.key] ?? "" })),
    items.map((i) => i.price),
  );

  function toggleItem(personKey: string, idx: number) {
    setAssigned((prev) => {
      const current = prev[personKey] ?? [];
      return { ...prev, [personKey]: current.includes(idx) ? current.filter((i) => i !== idx) : [...current, idx] };
    });
  }

  async function save() {
    setError(null);
    if (!receipt && (!description.trim() || !total)) {
      setError("Add a description and an amount.");
      return;
    }
    if ("error" in preview) {
      setError(preview.error);
      return;
    }
    const participants: ParticipantIn[] = people.map((p) => ({
      is_me: p.isMe,
      member_id: p.memberId ?? null,
      name: p.memberId ? undefined : p.isMe ? undefined : p.label,
      is_payer: groupId ? p.memberId === effectivePayer : p.isMe,
      item_indexes: mode === "items" ? assigned[p.key] ?? [] : [],
      amount: mode === "custom" ? amounts[p.key] ?? "0" : null,
    }));
    const body: SplitIn = {
      receipt_id: receipt?.id ?? null,
      group_id: groupId || null,
      mode,
      participants,
      ...(receipt ? {} : { description: description.trim(), total, currency, date, items: [] }),
    };
    setSaving(true);
    try {
      const split = existing
        ? await apiPut<Split>(`v1/splits/${existing.id}`, body)
        : await apiPost<Split>("v1/splits", body);
      onDone(split);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't save the split.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="space-y-xl">
      {!receipt && (
        <div className="grid gap-md sm:grid-cols-[1fr_9rem_10rem]">
          <div className="space-y-xs">
            <Label htmlFor="split-desc">What for</Label>
            <Input id="split-desc" placeholder="Cabin, groceries, taxi…" value={description} onChange={(e) => setDescription(e.target.value)} />
          </div>
          <div className="space-y-xs">
            <Label htmlFor="split-total">Amount</Label>
            <Input id="split-total" type="number" inputMode="decimal" step="0.01" min="0" value={total} onChange={(e) => setTotal(e.target.value)} />
          </div>
          <div className="space-y-xs">
            <Label htmlFor="split-date">Date</Label>
            <Input id="split-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} />
          </div>
        </div>
      )}

      {!fixedGroupId && (
        <div className="space-y-xs">
          <Label htmlFor="split-with">Split with</Label>
          <select
            id="split-with"
            value={groupId}
            onChange={(e) => {
              setGroupId(e.target.value);
              setExcluded(new Set());
              setPayerId("");
            }}
            className="h-11 w-full rounded-md border border-border bg-surface px-md text-callout"
          >
            <option value="">People (just this once)</option>
            {(groups ?? []).map((g) => (
              <option key={g.id} value={g.id}>
                Group: {g.name}
              </option>
            ))}
          </select>
        </div>
      )}

      {groupId ? (
        group && (
          <div className="space-y-md">
            <div className="space-y-xs">
              <p className="text-caption text-text-secondary">Who&apos;s in</p>
              <div className="flex flex-wrap gap-sm">
                {group.members.map((m) => {
                  const on = !excluded.has(m.id);
                  return (
                    <button
                      key={m.id}
                      type="button"
                      onClick={() =>
                        setExcluded((prev) => {
                          const next = new Set(prev);
                          if (on) next.add(m.id);
                          else next.delete(m.id);
                          return next;
                        })
                      }
                      aria-pressed={on}
                      className={cn(
                        "rounded-pill px-md py-xs text-caption font-medium ring-1 transition-colors",
                        on ? "bg-accent-muted text-accent ring-accent/40" : "bg-surface-2 text-text-secondary ring-transparent",
                      )}
                    >
                      {m.is_me ? `${m.display_name} (you)` : m.display_name}
                    </button>
                  );
                })}
              </div>
            </div>
            <div className="space-y-xs">
              <Label htmlFor="split-payer">Paid by</Label>
              <select
                id="split-payer"
                value={effectivePayer}
                onChange={(e) => setPayerId(e.target.value)}
                className="h-11 w-full rounded-md border border-border bg-surface px-md text-callout"
              >
                {people.map((p) => (
                  <option key={p.key} value={p.memberId}>
                    {p.label}
                  </option>
                ))}
              </select>
            </div>
          </div>
        )
      ) : (
        <div className="space-y-sm">
          <label className="flex items-center gap-sm text-callout">
            <input type="checkbox" checked={includeMe} onChange={(e) => setIncludeMe(e.target.checked)} className="h-4 w-4 accent-[var(--c-accent)]" />
            Include me (I paid; my share counts as my spending)
          </label>
          {names.map((name, i) => (
            <div key={i} className="flex items-center gap-sm">
              <Input
                aria-label={`Person ${i + 1} name`}
                placeholder={`Person ${i + 1}`}
                value={name}
                onChange={(e) => setNames((prev) => prev.map((n, j) => (j === i ? e.target.value : n)))}
              />
              {names.length > 1 && (
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  aria-label={`Remove ${name || `person ${i + 1}`}`}
                  onClick={() => setNames((prev) => prev.filter((_, j) => j !== i))}
                >
                  <X size={16} />
                </Button>
              )}
            </div>
          ))}
          <Button type="button" variant="secondary" size="sm" onClick={() => setNames((prev) => [...prev, ""])}>
            <Plus size={15} /> Add person
          </Button>
        </div>
      )}

      <div className="space-y-sm">
        <p className="text-caption text-text-secondary">How</p>
        <div role="radiogroup" aria-label="How to split" className="inline-flex rounded-pill bg-surface-2 p-[3px]">
          {MODES.filter((m) => m.value !== "items" || items.length > 0).map((m) => (
            <button
              key={m.value}
              type="button"
              role="radio"
              aria-checked={mode === m.value}
              onClick={() => setMode(m.value)}
              className={cn(
                "rounded-pill px-lg py-xs text-caption font-medium transition-colors",
                mode === m.value ? "bg-surface text-text shadow-e1" : "text-text-secondary hover:text-text",
              )}
            >
              {m.label}
            </button>
          ))}
        </div>
      </div>

      {mode === "items" && (
        <div className="space-y-sm">
          <p className="text-caption text-text-tertiary">
            Tap who had each item. Items nobody picks are shared by everyone; tax and tip follow each person&apos;s items.
          </p>
          <ul className="divide-y divide-border rounded-lg ring-1 ring-border">
            {items.map((item, idx) => (
              <li key={idx} className="space-y-xs px-md py-sm">
                <div className="flex justify-between gap-md text-callout">
                  <span className="min-w-0 truncate">{item.name}</span>
                  <span className="tabular text-text-secondary">{money(item.price, currency)}</span>
                </div>
                <div className="flex flex-wrap gap-xs">
                  {people.map((p) => {
                    const on = (assigned[p.key] ?? []).includes(idx);
                    return (
                      <button
                        key={p.key}
                        type="button"
                        aria-pressed={on}
                        onClick={() => toggleItem(p.key, idx)}
                        className={cn(
                          "rounded-pill px-sm py-[2px] text-[12px] ring-1 transition-colors",
                          on ? "bg-accent-muted text-accent ring-accent/40" : "text-text-tertiary ring-border hover:text-text",
                        )}
                      >
                        {p.isMe ? "You" : p.label}
                      </button>
                    );
                  })}
                </div>
              </li>
            ))}
          </ul>
        </div>
      )}

      <div className="space-y-sm">
        <p className="text-caption text-text-secondary">Shares</p>
        <ul className="divide-y divide-border rounded-lg bg-surface-2/60">
          {people.map((p, i) => (
            <li key={p.key} className="flex items-center justify-between gap-md px-md py-sm text-callout">
              <span className="min-w-0 truncate">{p.label}</span>
              {mode === "custom" ? (
                <Input
                  aria-label={`${p.label} amount`}
                  type="number"
                  inputMode="decimal"
                  step="0.01"
                  min="0"
                  className="h-9 w-28 text-right"
                  value={amounts[p.key] ?? ""}
                  onChange={(e) => setAmounts((prev) => ({ ...prev, [p.key]: e.target.value }))}
                />
              ) : (
                <span className="font-mono tabular">{"shares" in preview ? money(preview.shares[i], currency) : "—"}</span>
              )}
            </li>
          ))}
        </ul>
        <p className="text-right text-caption text-text-tertiary tabular">Total {money(splitTotal, currency)}</p>
      </div>

      {error && <p className="text-caption text-danger">{error}</p>}
      {!error && "error" in preview && people.length > 0 && <p className="text-caption text-warning">{preview.error}</p>}

      <div className="flex justify-end gap-sm">
        <Button type="button" variant="secondary" onClick={onCancel} disabled={saving}>
          Cancel
        </Button>
        <Button type="button" onClick={save} disabled={saving || people.length === 0}>
          {saving ? "Saving…" : existing ? "Save split" : "Split it"}
        </Button>
      </div>
    </div>
  );
}
