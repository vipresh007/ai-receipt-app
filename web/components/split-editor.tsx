"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiGet, apiPatch, apiPost, apiPut } from "@/lib/api";
import { money, toCents } from "@/lib/format";
import { previewShares } from "@/lib/splits";
import { PeoplePicker, WhoHadIt } from "@/components/people-picker";
import type {
  ExtractionItem,
  GroupDetail,
  GroupSummary,
  ParticipantIn,
  PersonSummary,
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
  { value: "shares", label: "Shares" },
  { value: "percent", label: "%" },
  { value: "custom", label: "Amounts" },
];

/** A person in the editor: you, a group member, a saved person, or a new
 * name (saved as a person when the split is). */
interface Person {
  key: string;
  label: string;
  isMe: boolean;
  memberId?: string;
  personId?: string;
  /** Editing someone else's expense: the existing person on it. */
  participantId?: string;
}

const SEVERAL = "__several";

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
  withPeople,
  existing,
  currency,
  onDone,
  onCancel,
}: {
  receipt?: ReceiptOut;
  fixedGroupId?: string;
  /** Saved people to start with (adding an expense from a person's page). */
  withPeople?: { id: string; name: string }[];
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
  const [groupId, setGroupId] = useState<string>(
    fixedGroupId ?? existing?.group_id ?? "",
  );
  const { data: group } = useQuery({
    queryKey: ["group", groupId],
    queryFn: () => apiGet<GroupDetail>(`v1/groups/${groupId}`),
    enabled: !!groupId,
  });

  // Manual expense (no receipt).
  const [description, setDescription] = useState(existing?.description ?? "");
  const [total, setTotal] = useState(
    existing && !receipt ? existing.total : "",
  );
  const [date, setDate] = useState(existing?.date ?? today());

  const items: ExtractionItem[] = receipt?.line_items ?? existing?.items ?? [];
  const splitTotal = receipt ? receipt.total : total || "0";

  // One-off: saved people picked (in order), plus new names (keyed p0, p1, …).
  const { data: savedPeople } = useQuery({
    queryKey: ["people"],
    queryFn: () => apiGet<PersonSummary[]>("v1/people"),
  });
  const oneOffExisting =
    existing && !existing.group_id ? existing.participants : [];
  const [picked, setPicked] = useState<{ id: string; name: string }[]>(() =>
    existing
      ? oneOffExisting
          .filter((p) => !p.is_me && p.person_id)
          .map((p) => ({ id: p.person_id!, name: p.display_name }))
      : (withPeople ?? []),
  );
  const [names, setNames] = useState<string[]>(() => {
    const unsaved = oneOffExisting
      .filter((p) => !p.is_me && !p.person_id)
      .map((p) => p.display_name);
    return unsaved;
  });
  const [includeMe, setIncludeMe] = useState(
    existing ? existing.participants.some((p) => p.is_me) : true,
  );
  const [oneOffPayer, setOneOffPayer] = useState<string>(() => {
    const payer = oneOffExisting.find((p) => p.is_payer);
    return payer && !payer.is_me && payer.person_id
      ? `person:${payer.person_id}`
      : "me";
  });
  // Group members taking part (default: everyone), and who paid.
  const [excluded, setExcluded] = useState<Set<string>>(new Set());
  const [payerId, setPayerId] = useState<string>("");
  const [memberFilter, setMemberFilter] = useState("");

  // Someone else's expense: change the amounts, not who's on it.
  const adjustOnly = !!existing && !existing.is_owner;
  const [severalPayers, setSeveralPayers] = useState(
    () => (existing?.participants.filter((p) => p.is_payer).length ?? 0) > 1,
  );
  const [paidAmounts, setPaidAmounts] = useState<Record<string, string>>({});
  const [repeat, setRepeat] = useState<"" | "weekly" | "monthly">(
    existing?.repeat ?? "",
  );
  const [adjustPayer, setAdjustPayer] = useState<string>(
    () => existing?.participants.find((p) => p.is_payer)?.id ?? "",
  );

  const [mode, setMode] = useState<SplitMode>(existing?.mode ?? "even");
  const [assigned, setAssigned] = useState<Record<string, number[]>>({});
  const [amounts, setAmounts] = useState<Record<string, string>>({});
  const [weights, setWeights] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const people: Person[] = useMemo(() => {
    if (adjustOnly && existing) {
      return existing.participants.map((p) => ({
        key: `part:${p.id}`,
        label: p.is_me ? "You" : p.display_name,
        isMe: p.is_me,
        participantId: p.id,
      }));
    }
    if (groupId && group) {
      return group.members
        .filter((m) => !excluded.has(m.id))
        .map((m) => ({
          key: m.id,
          label: m.is_me ? `${m.display_name} (you)` : m.display_name,
          isMe: m.is_me,
          memberId: m.id,
        }));
    }
    const list: Person[] = includeMe
      ? [{ key: "me", label: "You", isMe: true }]
      : [];
    picked.forEach((p) =>
      list.push({
        key: `person:${p.id}`,
        label: p.name,
        isMe: false,
        personId: p.id,
      }),
    );
    names.forEach((name, i) => {
      if (name.trim())
        list.push({ key: `p${i}`, label: name.trim(), isMe: false });
    });
    return list;
  }, [
    adjustOnly,
    existing,
    groupId,
    group,
    excluded,
    includeMe,
    picked,
    names,
  ]);

  function togglePicked(person: PersonSummary) {
    setPicked((prev) =>
      prev.some((p) => p.id === person.id)
        ? prev.filter((p) => p.id !== person.id)
        : [...prev, { id: person.id, name: person.name }],
    );
  }

  // Seed item assignments/amounts from an existing split, once people exist.
  const [seeded, setSeeded] = useState(false);
  if (
    existing &&
    !seeded &&
    people.length &&
    (adjustOnly || !existing.group_id || group)
  ) {
    const nextAssigned: Record<string, number[]> = {};
    const nextAmounts: Record<string, string> = {};
    const nextWeights: Record<string, string> = {};
    const nextPaid: Record<string, string> = {};
    for (const p of existing.participants) {
      const person = people.find((x) =>
        adjustOnly
          ? x.participantId === p.id
          : p.member_id
            ? x.memberId === p.member_id
            : p.is_me
              ? x.isMe
              : p.person_id
                ? x.personId === p.person_id
                : x.label === p.display_name,
      );
      if (!person) continue;
      nextAssigned[person.key] = p.item_indexes;
      if (p.amount) nextAmounts[person.key] = p.amount;
      if (p.weight) nextWeights[person.key] = p.weight;
      if (p.paid) nextPaid[person.key] = p.paid;
      if (p.is_payer && p.member_id) setPayerId(p.member_id);
    }
    if (existing.group_id && group) {
      const onSplit = new Set(existing.participants.map((p) => p.member_id));
      setExcluded(
        new Set(
          group.members.filter((m) => !onSplit.has(m.id)).map((m) => m.id),
        ),
      );
    }
    setAssigned(nextAssigned);
    setAmounts(nextAmounts);
    setWeights(nextWeights);
    setPaidAmounts(nextPaid);
    setSeeded(true);
  }

  const effectivePayer = groupId
    ? payerId || group?.members.find((m) => m.is_me)?.id || ""
    : "";
  // One-off: you by default; falls back to the first person if you're not in it.
  const oneOffPayerKey = people.some((p) => p.key === oneOffPayer)
    ? oneOffPayer
    : people[0]?.key;
  const adjustPayerKey = `part:${adjustPayer}`;
  const payerSelectValue = severalPayers
    ? SEVERAL
    : adjustOnly
      ? adjustPayerKey
      : groupId
        ? (people.find((p) => p.memberId === effectivePayer)?.key ?? "")
        : oneOffPayerKey;
  function choosePayer(key: string) {
    if (key === SEVERAL) {
      setSeveralPayers(true);
      return;
    }
    setSeveralPayers(false);
    const person = people.find((p) => p.key === key);
    if (adjustOnly) setAdjustPayer(person?.participantId ?? "");
    else if (groupId) setPayerId(person?.memberId ?? "");
    else setOneOffPayer(key);
  }
  const paidSum = people.reduce(
    (sum, p) => sum + toCents(paidAmounts[p.key] ?? ""),
    0,
  );

  const preview = previewShares(
    splitTotal,
    mode,
    people.map((p) => ({
      itemIndexes: assigned[p.key] ?? [],
      amount: amounts[p.key] ?? "",
      weight: weights[p.key] ?? "",
    })),
    items.map((i) => i.price),
  );

  function toggleItem(personKey: string, idx: number) {
    setAssigned((prev) => {
      const current = prev[personKey] ?? [];
      return {
        ...prev,
        [personKey]: current.includes(idx)
          ? current.filter((i) => i !== idx)
          : [...current, idx],
      };
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
    if (severalPayers && paidSum !== toCents(splitTotal)) {
      setError(
        `What everyone paid must add up to ${money(splitTotal, currency)}.`,
      );
      return;
    }
    const weightFor = (key: string) =>
      mode === "shares" || mode === "percent"
        ? weights[key]?.trim() || null
        : null;
    const paidFor = (key: string) =>
      severalPayers ? paidAmounts[key]?.trim() || "0" : null;
    if (adjustOnly && existing) {
      setSaving(true);
      try {
        onDone(
          await apiPatch<Split>(`v1/splits/${existing.id}`, {
            ...(existing.receipt_id
              ? {}
              : { description: description.trim(), total, date }),
            mode,
            participants: people.map((p) => ({
              id: p.participantId,
              is_payer: !severalPayers && p.participantId === adjustPayer,
              paid: paidFor(p.key),
              item_indexes: mode === "items" ? (assigned[p.key] ?? []) : [],
              amount: mode === "custom" ? (amounts[p.key] ?? "0") : null,
              weight: weightFor(p.key),
            })),
          }),
        );
      } catch (err) {
        setError(
          err instanceof Error ? err.message : "Couldn't save the changes.",
        );
      } finally {
        setSaving(false);
      }
      return;
    }
    const participants: ParticipantIn[] = people.map((p) => ({
      is_me: p.isMe,
      member_id: p.memberId ?? null,
      person_id: p.personId ?? null,
      name: p.memberId || p.personId || p.isMe ? undefined : p.label,
      is_payer:
        !severalPayers &&
        (groupId ? p.memberId === effectivePayer : p.key === oneOffPayerKey),
      paid: paidFor(p.key),
      item_indexes: mode === "items" ? (assigned[p.key] ?? []) : [],
      amount: mode === "custom" ? (amounts[p.key] ?? "0") : null,
      weight: weightFor(p.key),
    }));
    const body: SplitIn = {
      receipt_id: receipt?.id ?? null,
      group_id: groupId || null,
      mode,
      participants,
      ...(receipt
        ? {}
        : {
            description: description.trim(),
            total,
            currency,
            date,
            items: [],
            repeat,
          }),
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
      {!receipt && !(adjustOnly && existing?.receipt_id) && (
        <div className="grid gap-md sm:grid-cols-[1fr_9rem_10rem]">
          <div className="space-y-xs">
            <Label htmlFor="split-desc">What for</Label>
            <Input
              id="split-desc"
              placeholder="Cabin, groceries, taxi…"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </div>
          <div className="space-y-xs">
            <Label htmlFor="split-total">Amount</Label>
            <Input
              id="split-total"
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0"
              value={total}
              onChange={(e) => setTotal(e.target.value)}
            />
          </div>
          <div className="space-y-xs">
            <Label htmlFor="split-date">Date</Label>
            <Input
              id="split-date"
              type="date"
              value={date}
              onChange={(e) => setDate(e.target.value)}
            />
          </div>
        </div>
      )}

      {!receipt && !adjustOnly && (
        <div className="space-y-xs">
          <Label htmlFor="split-repeat">Repeats</Label>
          <select
            id="split-repeat"
            value={repeat}
            onChange={(e) =>
              setRepeat(e.target.value as "" | "weekly" | "monthly")
            }
            className="h-11 w-full rounded-md border border-border bg-surface px-md text-callout sm:w-56"
          >
            <option value="">Doesn&apos;t repeat</option>
            <option value="weekly">Every week</option>
            <option value="monthly">Every month</option>
          </select>
        </div>
      )}

      {adjustOnly && (
        <p className="rounded-md bg-surface-2 px-md py-sm text-caption text-text-secondary">
          You can change the amounts, who paid and how it&apos;s divided.
          Who&apos;s on it is up to whoever added it. Everyone on it sees what
          you changed.
        </p>
      )}

      {/* Only a choice once there's a group to choose (or this split is in one). */}
      {!adjustOnly &&
        !fixedGroupId &&
        ((groups ?? []).length > 0 || groupId) && (
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
              <option value="">People</option>
              {(groups ?? []).map((g) => (
                <option key={g.id} value={g.id}>
                  Group: {g.name}
                </option>
              ))}
            </select>
          </div>
        )}

      {adjustOnly ? null : groupId ? (
        group && (
          <div className="space-y-md">
            <div className="space-y-xs">
              <div className="flex flex-wrap items-center justify-between gap-sm">
                <p className="text-caption text-text-secondary">
                  Who&apos;s in{" "}
                  <span className="text-text-tertiary">
                    ({group.members.length - excluded.size} of{" "}
                    {group.members.length})
                  </span>
                </p>
                {group.members.length > 8 && (
                  <span className="flex gap-sm text-caption">
                    <button
                      type="button"
                      className="text-accent"
                      onClick={() => setExcluded(new Set())}
                    >
                      Everyone
                    </button>
                    <button
                      type="button"
                      className="text-accent"
                      onClick={() =>
                        setExcluded(
                          new Set(
                            group.members
                              .filter((m) => !m.is_me)
                              .map((m) => m.id),
                          ),
                        )
                      }
                    >
                      Just me
                    </button>
                  </span>
                )}
              </div>
              {group.members.length > 8 && (
                <Input
                  value={memberFilter}
                  onChange={(e) => setMemberFilter(e.target.value)}
                  placeholder="Find someone"
                  aria-label="Find someone in the group"
                  className="h-9"
                />
              )}
              <div className="flex max-h-48 flex-wrap gap-sm overflow-y-auto">
                {group.members
                  .filter(
                    (m) =>
                      !memberFilter.trim() ||
                      m.display_name
                        .toLowerCase()
                        .includes(memberFilter.trim().toLowerCase()),
                  )
                  .map((m) => {
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
                          on
                            ? "bg-accent-muted text-accent ring-accent/40"
                            : "bg-surface-2 text-text-secondary ring-transparent",
                        )}
                      >
                        {m.is_me ? `${m.display_name} (you)` : m.display_name}
                      </button>
                    );
                  })}
              </div>
            </div>
          </div>
        )
      ) : (
        <div className="space-y-md">
          <label className="flex items-center gap-sm text-callout">
            <input
              type="checkbox"
              checked={includeMe}
              onChange={(e) => setIncludeMe(e.target.checked)}
              className="h-4 w-4 accent-[var(--c-accent)]"
            />
            Include me (my share counts as my spending)
          </label>
          <PeoplePicker
            saved={savedPeople ?? []}
            picked={picked}
            names={names.filter((n) => n.trim())}
            onPick={togglePicked}
            onUnpick={(personId) =>
              setPicked((prev) => prev.filter((p) => p.id !== personId))
            }
            onAddName={(name) =>
              setNames((prev) => [...prev.filter((n) => n.trim()), name])
            }
            onRemoveName={(index) =>
              setNames((prev) =>
                prev.filter((n) => n.trim()).filter((_, k) => k !== index),
              )
            }
          />
        </div>
      )}

      {people.length > 1 && (
        <div className="space-y-sm">
          <div className="space-y-xs">
            <Label htmlFor="split-payer">Paid by</Label>
            <select
              id="split-payer"
              value={payerSelectValue}
              onChange={(e) => choosePayer(e.target.value)}
              className="h-11 w-full rounded-md border border-border bg-surface px-md text-callout"
            >
              {people.map((p) => (
                <option key={p.key} value={p.key}>
                  {p.label}
                </option>
              ))}
              <option value={SEVERAL}>Several people…</option>
            </select>
          </div>
          {severalPayers && (
            <ul className="divide-y divide-border rounded-lg bg-surface-2">
              {people.map((p) => (
                <li
                  key={p.key}
                  className="flex items-center gap-md px-md py-sm text-callout"
                >
                  <span className="min-w-0 flex-1 truncate">
                    {p.label} paid
                  </span>
                  <Input
                    aria-label={`${p.label} paid`}
                    type="number"
                    inputMode="decimal"
                    step="0.01"
                    min="0"
                    placeholder="0.00"
                    className="h-9 w-28 text-right"
                    value={paidAmounts[p.key] ?? ""}
                    onChange={(e) =>
                      setPaidAmounts((prev) => ({
                        ...prev,
                        [p.key]: e.target.value,
                      }))
                    }
                  />
                </li>
              ))}
              <li
                className={cn(
                  "px-md py-sm text-right text-caption tabular",
                  paidSum === toCents(splitTotal)
                    ? "text-text-tertiary"
                    : "text-warning",
                )}
              >
                Paid {money(paidSum / 100, currency)} of{" "}
                {money(splitTotal, currency)}
              </li>
            </ul>
          )}
        </div>
      )}

      <div className="space-y-sm">
        <p className="text-caption text-text-secondary">How</p>
        <div
          role="radiogroup"
          aria-label="How to split"
          className="inline-flex max-w-full overflow-x-auto rounded-pill bg-surface-2 p-[3px]"
        >
          {MODES.filter((m) => m.value !== "items" || items.length > 0).map(
            (m) => (
              <button
                key={m.value}
                type="button"
                role="radio"
                aria-checked={mode === m.value}
                onClick={() => setMode(m.value)}
                className={cn(
                  "rounded-pill px-lg py-xs text-caption font-medium transition-colors",
                  mode === m.value
                    ? "bg-surface text-text shadow-e1"
                    : "text-text-secondary hover:text-text",
                )}
              >
                {m.label}
              </button>
            ),
          )}
        </div>
      </div>

      {mode === "items" && (
        <div className="space-y-sm">
          <p className="text-caption text-text-tertiary">
            Tap who had each item. Items nobody picks are shared by everyone;
            tax and tip follow each person&apos;s items.
          </p>
          <ul className="divide-y divide-border rounded-lg ring-1 ring-border">
            {items.map((item, idx) => (
              <li key={idx} className="space-y-xs px-md py-sm">
                <div className="flex justify-between gap-md text-callout">
                  <span className="min-w-0 truncate">{item.name}</span>
                  <span className="tabular text-text-secondary">
                    {money(item.price, currency)}
                  </span>
                </div>
                {people.length > 6 ? (
                  <WhoHadIt
                    people={people.map((p) => ({
                      key: p.key,
                      label: p.isMe ? "You" : p.label,
                    }))}
                    chosen={people
                      .filter((p) => (assigned[p.key] ?? []).includes(idx))
                      .map((p) => p.key)}
                    onToggle={(key) => toggleItem(key, idx)}
                  />
                ) : (
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
                            on
                              ? "bg-accent-muted text-accent ring-accent/40"
                              : "text-text-tertiary ring-border hover:text-text",
                          )}
                        >
                          {p.isMe ? "You" : p.label}
                        </button>
                      );
                    })}
                  </div>
                )}
              </li>
            ))}
          </ul>
        </div>
      )}

      <div className="space-y-sm">
        <p className="text-caption text-text-secondary">
          {mode === "shares"
            ? "Parts each person pays (2 and 3 split the total into fifths)"
            : mode === "percent"
              ? "Percent each person pays (adds up to 100)"
              : mode === "custom"
                ? "Exact amount for each person"
                : "Each person pays"}
        </p>
        <ul className="divide-y divide-border rounded-lg bg-surface-2">
          {people.map((p, i) => {
            const share =
              "shares" in preview ? money(preview.shares[i], currency) : "—";
            const weighted = mode === "shares" || mode === "percent";
            const typed = weighted || mode === "custom";
            return (
              <li
                key={p.key}
                className="flex items-center gap-md px-md py-sm text-callout"
              >
                <span className="min-w-0 flex-1 truncate">{p.label}</span>
                {typed && (
                  <Input
                    aria-label={
                      mode === "shares"
                        ? `${p.label} shares`
                        : mode === "percent"
                          ? `${p.label} percent`
                          : `${p.label} amount`
                    }
                    type="number"
                    inputMode="decimal"
                    step={weighted ? "any" : "0.01"}
                    min="0"
                    placeholder={
                      mode === "shares"
                        ? "1"
                        : mode === "percent"
                          ? "0"
                          : "0.00"
                    }
                    className="h-9 w-20 text-right"
                    value={(weighted ? weights : amounts)[p.key] ?? ""}
                    onChange={(e) =>
                      (weighted ? setWeights : setAmounts)((prev) => ({
                        ...prev,
                        [p.key]: e.target.value,
                      }))
                    }
                  />
                )}
                {weighted ? (
                  <span className="w-24 text-right font-mono text-caption text-text-secondary tabular">
                    = {share}
                  </span>
                ) : (
                  mode !== "custom" && (
                    <span className="font-mono tabular">{share}</span>
                  )
                )}
              </li>
            );
          })}
        </ul>
        <p className="text-right text-caption text-text-tertiary tabular">
          Total {money(splitTotal, currency)}
        </p>
      </div>

      {error && <p className="text-caption text-danger">{error}</p>}
      {!error && "error" in preview && people.length > 0 && (
        <p className="text-caption text-warning">{preview.error}</p>
      )}

      <div className="flex justify-end gap-sm">
        <Button
          type="button"
          variant="secondary"
          onClick={onCancel}
          disabled={saving}
        >
          Cancel
        </Button>
        <Button
          type="button"
          onClick={save}
          disabled={saving || people.length === 0}
        >
          {saving ? "Saving…" : existing ? "Save split" : "Split it"}
        </Button>
      </div>
    </div>
  );
}
