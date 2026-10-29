"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { apiPost } from "@/lib/api";
import type { PersonDetail } from "@/lib/types";
import { Button } from "@/components/ui/button";

/** Signed in on someone's invite: link it to this account and open the
 * person page for whoever sent it. */
export function AcceptInvite({ token }: { token: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function accept() {
    setBusy(true);
    setError(null);
    try {
      const inviter = await apiPost<PersonDetail>(`v1/people/claim/${encodeURIComponent(token)}`, {});
      router.push(`/people/${inviter.id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't accept the invite.");
      setBusy(false);
    }
  }

  return (
    <div className="space-y-sm">
      <Button className="w-full" disabled={busy} onClick={accept}>
        {busy ? "Opening…" : "See what we share"}
      </Button>
      {error && <p className="text-caption text-danger">{error}</p>}
    </div>
  );
}
