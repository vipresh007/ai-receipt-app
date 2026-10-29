import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { auth0 } from "@/lib/auth0";
import { backendUrl } from "@/lib/backend";
import type { PublicGroup } from "@/lib/types";
import { Card, CardTitle } from "@/components/ui/card";
import { PublicShell } from "@/components/public-shell";
import { JoinPicker } from "@/components/join-picker";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export const metadata: Metadata = { title: "Join a group", robots: { index: false, follow: false } };
export const dynamic = "force-dynamic";

async function load(token: string): Promise<PublicGroup | null> {
  const res = await fetch(backendUrl(`v1/public/groups/${encodeURIComponent(token)}`), { cache: "no-store" });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Couldn't load this invite (${res.status}).`);
  return res.json();
}

export default async function JoinPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const [group, session] = await Promise.all([load(token), auth0.getSession()]);
  if (!group) notFound();

  const open = group.members.filter((m) => !m.claimed);
  const returnTo = `/join/${encodeURIComponent(token)}`;

  return (
    <PublicShell>
      <section className="space-y-sm">
        <p className="font-mono text-[11px] font-medium uppercase tracking-[0.16em] text-text-tertiary">
          You&apos;re invited
        </p>
        <h1 className="font-display text-[30px] font-extrabold leading-[1.1] tracking-[-0.03em] [text-wrap:balance]">
          Join {group.name}
        </h1>
        <p className="text-callout text-text-secondary">
          See what the group has spent, what you owe, and add expenses yourself.
        </p>
      </section>

      <Card className="space-y-lg">
        {session ? (
          <JoinPicker token={token} open={open} />
        ) : (
          <>
            <CardTitle>In the group</CardTitle>
            <p className="text-callout">{group.members.map((m) => m.display_name).join(", ")}</p>
            <a
              href={`/auth/login?returnTo=${encodeURIComponent(returnTo)}`}
              className={cn(buttonVariants(), "w-full")}
            >
              Sign in to join
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
