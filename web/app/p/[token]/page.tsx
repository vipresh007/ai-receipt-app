import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { auth0 } from "@/lib/auth0";
import { backendUrl } from "@/lib/backend";
import { money } from "@/lib/format";
import type { PublicPerson } from "@/lib/types";
import { Card } from "@/components/ui/card";
import { PublicShell } from "@/components/public-shell";
import { AcceptInvite } from "@/components/accept-invite";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";

// Invite links are private to whoever was sent them.
export const metadata: Metadata = { title: "You're invited", robots: { index: false, follow: false } };
export const dynamic = "force-dynamic";

async function load(token: string): Promise<PublicPerson | null> {
  const res = await fetch(backendUrl(`v1/public/people/${encodeURIComponent(token)}`), { cache: "no-store" });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Couldn't load this invite (${res.status}).`);
  return res.json();
}

export default async function PersonInvitePage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const [invite, session] = await Promise.all([load(token), auth0.getSession()]);
  if (!invite) notFound();

  const balance = Number(invite.balance);
  const standing =
    balance > 0
      ? `${invite.from_name} owes you ${money(balance, invite.currency)}`
      : balance < 0
        ? `You owe ${invite.from_name} ${money(-balance, invite.currency)}`
        : "You're all square";
  const returnTo = `/p/${encodeURIComponent(token)}`;

  return (
    <PublicShell>
      <section className="space-y-sm">
        <p className="font-mono text-[11px] font-medium uppercase tracking-[0.16em] text-text-tertiary">
          Hi {invite.name}
        </p>
        <h1 className="font-display text-[30px] font-extrabold leading-[1.1] tracking-[-0.03em] [text-wrap:balance]">
          {invite.from_name} is sharing expenses with you
        </h1>
        <p className="text-callout text-text-secondary">
          {invite.expense_count === 0
            ? "Nothing added yet."
            : `${invite.expense_count} ${invite.expense_count === 1 ? "expense" : "expenses"} so far.`}
        </p>
      </section>

      <Card className="space-y-lg">
        <p className="font-display text-[28px] font-extrabold leading-tight tracking-[-0.03em] tabular">{standing}</p>
        {invite.claimed ? (
          <p className="text-callout text-text-secondary">
            This invite has been accepted.{" "}
            {session && (
              <Link href="/groups" className="text-accent">
                Open Shared
              </Link>
            )}
          </p>
        ) : session ? (
          <AcceptInvite token={token} />
        ) : (
          <>
            <a href={`/auth/login?returnTo=${encodeURIComponent(returnTo)}`} className={cn(buttonVariants(), "w-full")}>
              Sign in to see every expense
            </a>
            <p className="text-caption text-text-tertiary">
              Free. Sign in with Google or email, the same account as the Tally iPhone app.
            </p>
          </>
        )}
      </Card>
    </PublicShell>
  );
}
