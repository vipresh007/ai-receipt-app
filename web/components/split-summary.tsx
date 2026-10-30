"use client";

import { useState, useSyncExternalStore } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, Copy, History, Repeat, Share2, Trash2 } from "lucide-react";
import { apiDelete, apiGet, apiPost } from "@/lib/api";
import { money, shortDate } from "@/lib/format";
import type { Participant, Split, TimelineEntry } from "@/lib/types";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { LIVE } from "@/lib/live";

const noSubscribe = () => () => {};

/** Whether the browser has a native share sheet (phones). False while
 * server-rendering, so the first paint matches. */
export function useCanShare(): boolean {
  return useSyncExternalStore(noSubscribe, () => "share" in navigator, () => false);
}

/** Send someone their share: the native share sheet where there is one
 * (phones), otherwise copy the link. */
export function ShareLinkButton({ participant, split }: { participant: Participant; split: Split }) {
  const [copied, setCopied] = useState(false);
  const canShare = useCanShare();
  const text = `Your share of ${split.description}: ${money(participant.share, split.currency)}`;

  async function share() {
    if (canShare) {
      try {
        await navigator.share({ title: "Tally", text, url: participant.share_url });
        return;
      } catch {
        /* dismissed, or unsupported here: fall back to copying */
      }
    }
    await navigator.clipboard.writeText(`${text}\n${participant.share_url}`);
    setCopied(true);
    setTimeout(() => setCopied(false), 1800);
  }

  return (
    <Button type="button" variant="secondary" size="sm" onClick={share} aria-label={`Send ${participant.display_name} their link`}>
      {copied ? <Check size={14} /> : canShare ? <Share2 size={14} /> : <Copy size={14} />}
      {copied ? "Copied" : canShare ? "Send" : "Copy link"}
    </Button>
  );
}

/** Who owes what on a split, with each person's link and (one-off splits) a
 * paid tick. */
export function SplitSummary({
  split,
  onChange,
  onEdit,
  onRemove,
}: {
  split: Split;
  onChange: (split: Split) => void;
  onEdit?: () => void;
  onRemove?: () => void;
}) {
  const queryClient = useQueryClient();
  const [busy, setBusy] = useState<string | null>(null);
  const payers = split.participants.filter((p) => p.is_payer);
  const payerLabel =
    payers.length === 1 ? (payers[0].is_me ? "you" : payers[0].display_name) : "the payers";

  async function toggleSettled(p: Participant) {
    setBusy(p.id);
    try {
      onChange(await apiPost<Split>(`v1/splits/${split.id}/participants/${p.id}/settled`, { settled: !p.settled }));
      // The history line, balances and lists that show it change too.
      await queryClient.invalidateQueries();
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="space-y-lg">
      <ul className="divide-y divide-border">
        {split.participants.map((p) => {
          const owes = !p.is_payer && Number(p.share) > 0;
          return (
            <li key={p.id} className="flex flex-wrap items-center gap-x-md gap-y-xs py-sm">
              <div className="min-w-0 flex-1">
                <p className="truncate text-callout">{p.is_me ? "You" : p.display_name}</p>
                <p className="text-caption text-text-tertiary">
                  {p.is_payer
                    ? `paid ${money(p.paid ?? split.total, split.currency)}`
                    : p.settled
                      ? "paid back"
                      : `owes ${payerLabel}`}
                </p>
              </div>
              <span className={cn("font-mono text-callout tabular", p.settled && "text-text-tertiary line-through")}>
                {money(p.share, split.currency)}
              </span>
              {(owes && split.can_edit) || (!p.is_me && split.is_owner) ? (
                <div className="flex items-center gap-xs">
                  {owes && split.can_edit && (
                    <Button
                      type="button"
                      variant={p.settled ? "secondary" : "ghost"}
                      size="sm"
                      disabled={busy === p.id}
                      aria-pressed={p.settled}
                      onClick={() => toggleSettled(p)}
                    >
                      <Check size={14} /> {p.settled ? "Paid" : "Mark paid"}
                    </Button>
                  )}
                  {!p.is_me && split.is_owner && !p.settled && <ShareLinkButton participant={p} split={split} />}
                </div>
              ) : null}
            </li>
          );
        })}
      </ul>
      {split.repeat && (
        <p className="flex items-center gap-xs text-caption text-text-tertiary">
          <Repeat size={13} /> Repeats {split.repeat === "weekly" ? "every week" : "every month"}
          {split.next_at && <> · next {shortDate(split.next_at)}</>}
        </p>
      )}
      {((split.can_edit && onEdit) || (split.is_owner && onRemove)) && (
        <div className="flex justify-end gap-sm">
          {split.is_owner && onRemove && (
            <Button type="button" variant="ghost" size="sm" onClick={onRemove}>
              Remove split
            </Button>
          )}
          {split.can_edit && onEdit && (
            <Button type="button" variant="secondary" size="sm" onClick={onEdit}>
              Edit split
            </Button>
          )}
        </div>
      )}
      <SplitTimeline splitId={split.id} />
    </div>
  );
}

/** The expense's history (added, every change, who made it) and comments.
 * Everyone who can see the expense sees all of it. */
export function SplitTimeline({ splitId }: { splitId: string }) {
  const queryClient = useQueryClient();
  const { data: entries } = useQuery({
    ...LIVE,
    queryKey: ["timeline", splitId],
    queryFn: () => apiGet<TimelineEntry[]>(`v1/splits/${splitId}/timeline`),
  });
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function post(e: React.FormEvent) {
    e.preventDefault();
    if (!draft.trim() || sending) return;
    setSending(true);
    setError(null);
    try {
      queryClient.setQueryData(
        ["timeline", splitId],
        await apiPost<TimelineEntry[]>(`v1/splits/${splitId}/comments`, { body: draft.trim() }),
      );
      setDraft("");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't post it.");
    } finally {
      setSending(false);
    }
  }

  async function remove(id: string) {
    queryClient.setQueryData(["timeline", splitId], await apiDelete<TimelineEntry[]>(`v1/splits/${splitId}/comments/${id}`));
  }

  return (
    <div className="space-y-sm border-t border-border pt-md">
      <p className="text-caption font-medium text-text-secondary">History &amp; comments</p>
      <ol className="space-y-sm">
        {(entries ?? []).map((entry) =>
          entry.kind === "comment" ? (
            <li key={entry.id} className="group rounded-lg bg-surface px-md py-sm ring-1 ring-border">
              <div className="flex items-baseline justify-between gap-md">
                <span className="text-caption font-semibold">{entry.author_name}</span>
                <span className="flex items-center gap-sm text-[11px] text-text-tertiary">
                  {when(entry.at)}
                  {entry.can_delete && (
                    <button type="button" onClick={() => remove(entry.id)} className="hover:text-danger" aria-label="Delete comment">
                      <Trash2 size={12} />
                    </button>
                  )}
                </span>
              </div>
              <p className="mt-[2px] whitespace-pre-wrap break-words text-callout">{entry.text}</p>
            </li>
          ) : (
            <li key={entry.id} className="flex gap-sm text-caption text-text-secondary">
              <History size={13} className="mt-[3px] shrink-0 text-text-tertiary" />
              <span className="min-w-0 flex-1">
                <span className="font-medium text-text">{entry.author_name}</span> {entry.text}
                <span className="ml-sm text-[11px] text-text-tertiary">{when(entry.at)}</span>
              </span>
            </li>
          ),
        )}
      </ol>
      <form onSubmit={post} className="flex gap-sm">
        <Input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="Add a comment"
          maxLength={1000}
          aria-label="Add a comment"
          className="h-9"
        />
        <Button type="submit" size="sm" variant="secondary" disabled={!draft.trim() || sending}>
          Post
        </Button>
      </form>
      {error && <p className="text-caption text-danger">{error}</p>}
    </div>
  );
}

function when(iso: string): string {
  const d = new Date(iso);
  const sameDay = d.toDateString() === new Date().toDateString();
  return sameDay
    ? d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" })
    : d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}
