"use client";

import { useState, useSyncExternalStore } from "react";
import { Check, Copy, Share2 } from "lucide-react";
import { apiPost } from "@/lib/api";
import { money } from "@/lib/format";
import type { Participant, Split } from "@/lib/types";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

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
  const [busy, setBusy] = useState<string | null>(null);
  const oneOff = !split.group_id;

  async function toggleSettled(p: Participant) {
    setBusy(p.id);
    try {
      onChange(await apiPost<Split>(`v1/splits/${split.id}/participants/${p.id}/settled`, { settled: !p.settled }));
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="space-y-lg">
      <ul className="divide-y divide-border">
        {split.participants.map((p) => (
          <li key={p.id} className="flex flex-wrap items-center gap-md py-sm">
            <div className="min-w-0 flex-1">
              <p className={cn("truncate text-callout", p.settled && "text-text-tertiary line-through")}>
                {p.is_me ? "You" : p.display_name}
                {p.is_payer && <span className="ml-sm text-caption text-text-tertiary">paid</span>}
              </p>
            </div>
            <span className="font-mono text-callout tabular">{money(p.share, split.currency)}</span>
            {!p.is_me && split.is_owner && (
              <div className="flex items-center gap-xs">
                {oneOff && (
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
                <ShareLinkButton participant={p} split={split} />
              </div>
            )}
          </li>
        ))}
      </ul>
      {split.is_owner && (onEdit || onRemove) && (
        <div className="flex justify-end gap-sm">
          {onRemove && (
            <Button type="button" variant="ghost" size="sm" onClick={onRemove}>
              Remove split
            </Button>
          )}
          {onEdit && (
            <Button type="button" variant="secondary" size="sm" onClick={onEdit}>
              Edit split
            </Button>
          )}
        </div>
      )}
    </div>
  );
}
