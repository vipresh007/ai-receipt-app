import type { Metadata } from "next";
import Link from "next/link";
import { backendUrl } from "@/lib/backend";
import { Card, CardTitle } from "@/components/ui/card";
import { PublicShell } from "@/components/public-shell";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export const metadata: Metadata = {
  title: "Unsubscribe",
  robots: { index: false, follow: false },
};
export const dynamic = "force-dynamic";

type Info = { email: string; scope: string; what: string; has_account: boolean };

async function load(e: string, s: string, t: string): Promise<Info | null> {
  const q = new URLSearchParams({ e, s, t });
  const res = await fetch(backendUrl(`v1/public/unsubscribe?${q}`), { cache: "no-store" });
  return res.ok ? res.json() : null;
}

/** The footer link in every Tally email. Opening it changes nothing (mail
 * scanners open links); the button does. */
export default async function UnsubscribePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const { e = "", s = "", t = "", done } = await searchParams;
  const info = e && s && t ? await load(e, s, t) : null;

  return (
    <PublicShell>
      <Card className="space-y-lg">
        {!info ? (
          <>
            <CardTitle>This link isn&apos;t valid</CardTitle>
            <p className="text-callout text-text-secondary">
              It may have been cut short when it was copied. Use the Unsubscribe link at the bottom of
              any Tally email, or choose which emails you get in Tally under Account.
            </p>
          </>
        ) : done ? (
          <>
            <CardTitle>You&apos;re unsubscribed</CardTitle>
            <p className="text-callout text-text-secondary">
              {done === "all"
                ? `${info.email} won't get any more emails from Tally.`
                : `${info.email} won't get ${info.what} any more.`}
              {info.has_account && " You can turn emails back on in Tally under Account."}
            </p>
            {info.has_account && (
              <Link href="/account" className={cn(buttonVariants({ variant: "secondary", size: "sm" }), "w-fit")}>
                Choose which emails you get
              </Link>
            )}
          </>
        ) : (
          <>
            <CardTitle>Unsubscribe {info.email}?</CardTitle>
            <p className="text-callout text-text-secondary">
              {info.scope === "all"
                ? "You won't get any more emails from Tally, including invites."
                : `You won't get ${info.what} any more. Other emails and everything in the app stay as they are.`}
            </p>
            <form action="/unsubscribe/confirm" method="post" className="flex flex-wrap gap-sm">
              <input type="hidden" name="e" value={e} />
              <input type="hidden" name="s" value={s} />
              <input type="hidden" name="t" value={t} />
              <button type="submit" name="everything" value="" className={buttonVariants({ size: "sm" })}>
                Unsubscribe
              </button>
              {info.scope !== "all" && (
                <button
                  type="submit"
                  name="everything"
                  value="1"
                  className={buttonVariants({ variant: "secondary", size: "sm" })}
                >
                  Stop all Tally emails
                </button>
              )}
            </form>
          </>
        )}
      </Card>
    </PublicShell>
  );
}
