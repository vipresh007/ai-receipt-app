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
import { buttonVariants } from "@/components/ui/button";

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
  const itemsTotal = split.items.reduce((sum, item) => sum + Number(item.price), 0);
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

      {split.items.length > 0 && (
        <Card className="space-y-md">
          <CardTitle>The receipt</CardTitle>
          <ul className="divide-y divide-border">
            {split.items.map((item, i) => {
              const had = split.participants.filter((p) => p.item_indexes.includes(i));
              const yours = !!you && you.item_indexes.includes(i);
              return (
                <li key={i} className="space-y-xs py-sm">
                  <div
                    className={cn(
                      "flex items-center justify-between gap-md text-callout",
                      yours && "font-semibold",
                    )}
                  >
                    <span className="min-w-0 truncate">
                      {item.quantity && item.quantity > 1 ? `${item.quantity} × ` : ""}
                      {item.name}
                    </span>
                    <span className="font-mono tabular">{money(item.price, split.currency)}</span>
                  </div>
                  {had.length > 0 && (
                    <div className="flex flex-wrap gap-xs">
                      {had.map((p, k) => (
                        <span
                          key={k}
                          className={cn(
                            "rounded-pill px-sm py-[1px] text-[12px]",
                            p.is_you ? "bg-accent-muted font-medium text-accent" : "bg-surface-2 text-text-secondary",
                          )}
                        >
                          {p.is_you ? "You" : p.display_name}
                        </span>
                      ))}
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
          <dl className="space-y-xs border-t border-border pt-md text-callout">
            <div className="flex justify-between text-text-secondary">
              <dt>Items</dt>
              <dd className="font-mono tabular">{money(itemsTotal, split.currency)}</dd>
            </div>
            {split.tax != null && Number(split.tax) > 0 && (
              <div className="flex justify-between text-text-secondary">
                <dt>Tax</dt>
                <dd className="font-mono tabular">{money(split.tax, split.currency)}</dd>
              </div>
            )}
            {Math.abs(Number(split.total) - itemsTotal - Number(split.tax ?? 0)) >= 0.005 && (
              <div className="flex justify-between text-text-secondary">
                <dt>Tip, fees and discounts</dt>
                <dd className="font-mono tabular">
                  {money(Number(split.total) - itemsTotal - Number(split.tax ?? 0), split.currency)}
                </dd>
              </div>
            )}
            <div className="flex justify-between font-semibold">
              <dt>Total</dt>
              <dd className="font-mono tabular">{money(split.total, split.currency)}</dd>
            </div>
          </dl>
          {split.mode === "items" && (
            <p className="text-caption text-text-tertiary">
              Items nobody picked are shared by everyone. Tax and tip follow what each person had.
            </p>
          )}
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
      {split.invite_url && split.owner_name && (
        <Card className="space-y-md">
          <CardTitle>
            {split.group_name ? `Everything in ${split.group_name}` : `Everything you share with ${split.owner_name}`}
          </CardTitle>
          <p className="text-callout text-text-secondary">
            Every expense, the running balance between you, and a way to record paying back. Free; sign in once.
          </p>
          <a href={split.invite_url} className={cn(buttonVariants({ variant: "secondary" }), "w-full")}>
            {split.group_name ? `See everything in ${split.group_name}` : `See everything you share with ${split.owner_name}`}
          </a>
        </Card>
      )}
    </PublicShell>
  );
}
