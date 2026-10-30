"use client";

import { useState } from "react";
import { Check, Copy, ExternalLink } from "lucide-react";
import type { PayDetails } from "@/lib/types";

/** How to pay someone back, when they've said (Account → Get paid back). */
export function PayTo({
  payTo,
  amount,
  currency,
  name,
}: {
  payTo: PayDetails | null;
  amount: string | number;
  currency: string;
  name: string;
}) {
  const [copied, setCopied] = useState(false);
  if (!payTo || (!payTo.paypal_me && !payTo.interac)) return null;
  const value = Math.abs(Number(amount)).toFixed(2);

  async function copy() {
    await navigator.clipboard.writeText(payTo!.interac!);
    setCopied(true);
    setTimeout(() => setCopied(false), 1800);
  }

  return (
    <div className="space-y-xs rounded-lg bg-surface-2 p-md">
      <p className="text-caption font-medium text-text-secondary">Pay {name} back</p>
      <div className="flex flex-wrap gap-sm">
        {payTo.paypal_me && (
          <a
            href={`https://paypal.me/${encodeURIComponent(payTo.paypal_me)}/${value}${currency}`}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-xs rounded-pill bg-surface px-md py-xs text-caption font-medium ring-1 ring-border hover:bg-surface-sunken"
          >
            PayPal <ExternalLink size={12} />
          </a>
        )}
        {payTo.interac && (
          <button
            type="button"
            onClick={copy}
            className="inline-flex items-center gap-xs rounded-pill bg-surface px-md py-xs text-caption font-medium ring-1 ring-border hover:bg-surface-sunken"
          >
            {copied ? <Check size={12} /> : <Copy size={12} />}
            {copied ? "Copied" : `Interac e-Transfer: ${payTo.interac}`}
          </button>
        )}
      </div>
    </div>
  );
}
