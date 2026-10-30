import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Check } from "lucide-react";
import { backendUrl } from "@/lib/backend";
import { money, shortDate } from "@/lib/format";
import type { PublicSplit } from "@/lib/types";
import { Card, CardTitle } from "@/components/ui/card";
import { PublicShell } from "@/components/public-shell";
import { PayTo } from "@/components/pay-to";
import { cn } from "@/lib/utils";

// Links are private to whoever was sent them: never indexed, never cached.
export const metadata: Metadata = {
  title: "Your share",
  robots: { index: false, follow: false },
};
export const dynamic = "force-dynamic";

async function load(token: string): Promise<PublicSplit | null> {
  const res = await fetch(
    backendUrl(`v1/public/splits/${encodeURIComponent(token)}`),
    { cache: "no-store" },
  );
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Couldn't load this split (${res.status}).`);
  return res.json();
}

export default async function SharePage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  const split = await load(token);
  if (!split) notFound();

  const you = split.participants.find((p) => p.is_you);
  const yourItems = you
    ? split.items.filter((_, i) => you.item_indexes.includes(i))
    : [];
  const payer = split.payer_name;

  return (
    <PublicShell>
      <section className="space-y-sm">
        <p className="font-mono text-[11px] font-medium uppercase tracking-[0.16em] text-text-tertiary">
          {split.group_name ?? "Split"} · {shortDate(split.date)}
        </p>
        <h1 className="font-display text-[30px] font-extrabold leading-[1.1] tracking-[-0.03em] [text-wrap:balance]">
          {split.description || "Shared expense"}
        </h1>
      </section>

      <Card className="space-y-md">
        <CardTitle>
          {you ? `${you.display_name}, your share` : "Your share"}
        </CardTitle>
        <p className="font-display text-[48px] font-extrabold leading-none tracking-[-0.04em] tabular">
          {money(split.your_share, split.currency)}
        </p>
        <p className="text-callout text-text-secondary">
          of {money(split.total, split.currency)}
          {payer && you && !you.is_payer && (
            <>, paid by {payer}. Pay them back however you usually do.</>
          )}
        </p>
        {payer && you && !you.is_payer && !you.settled && split.pay_to && (
          <PayTo
            payTo={split.pay_to}
            amount={split.your_share}
            currency={split.currency}
            name={payer}
          />
        )}
        {you?.settled && (
          <p className="inline-flex items-center gap-xs rounded-pill bg-success-muted px-md py-xs text-caption font-medium text-success">
            <Check size={14} /> Marked as paid
          </p>
        )}
      </Card>

      {yourItems.length > 0 && (
        <Card className="space-y-md">
          <CardTitle>What you had</CardTitle>
          <ul className="divide-y divide-border">
            {yourItems.map((item, i) => (
              <li
                key={i}
                className="flex items-center justify-between gap-md py-sm text-callout"
              >
                <span className="min-w-0 truncate">
                  {item.quantity && item.quantity > 1
                    ? `${item.quantity} × `
                    : ""}
                  {item.name}
                </span>
                <span className="font-mono tabular">
                  {money(item.price, split.currency)}
                </span>
              </li>
            ))}
          </ul>
          <p className="text-caption text-text-tertiary">
            Items shared with others are divided between you. Tax and tip follow
            what each person had.
          </p>
        </Card>
      )}

      <Card className="space-y-md">
        <CardTitle>Everyone</CardTitle>
        <ul className="divide-y divide-border">
          {split.participants.map((p, i) => (
            <li
              key={i}
              className={cn(
                "flex items-center gap-md py-sm text-callout",
                p.is_you && "font-semibold",
              )}
            >
              <span
                className={cn(
                  "min-w-0 flex-1 truncate",
                  p.settled && "text-text-tertiary line-through",
                )}
              >
                {p.display_name}
                {p.is_you && (
                  <span className="ml-sm text-caption font-normal text-accent">
                    you
                  </span>
                )}
                {p.is_payer && (
                  <span className="ml-sm text-caption font-normal text-text-tertiary">
                    paid
                  </span>
                )}
              </span>
              <span className="font-mono tabular">
                {money(p.share, split.currency)}
              </span>
            </li>
          ))}
        </ul>
      </Card>
    </PublicShell>
  );
}
