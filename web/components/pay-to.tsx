"use client";

import { useState } from "react";
import { Check, Copy } from "lucide-react";
import { money } from "@/lib/format";
import type { PayDetails } from "@/lib/types";

/** How to pay someone back by Interac e-Transfer, when they've added it. */
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
  if (!payTo?.interac) return null;
  const value = money(Math.abs(Number(amount)), currency);

  async function copy() {
    await navigator.clipboard.writeText(payTo!.interac!);
    setCopied(true);
    setTimeout(() => setCopied(false), 1800);
  }

  return (
    <div className="space-y-xs rounded-lg bg-surface-2 p-md">
      <p className="text-caption font-medium text-text-secondary">
        Pay {name} back: send {value} by Interac e-Transfer
      </p>
      <div className="flex flex-wrap gap-sm">
        {payTo.interac && (
          <button
            type="button"
            onClick={copy}
            className="inline-flex items-center gap-xs rounded-pill bg-surface px-md py-xs text-caption font-medium ring-1 ring-border hover:bg-surface-sunken"
          >
            {copied ? <Check size={12} /> : <Copy size={12} />}
            {copied ? "Copied" : payTo.interac}
          </button>
        )}
      </div>
    </div>
  );
}
