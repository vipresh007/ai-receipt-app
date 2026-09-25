"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { apiDelete, apiGet } from "@/lib/api";
import type { Me } from "@/lib/types";
import { Button } from "@/components/ui/button";
import { Card, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { PageHeader } from "@/components/page-header";

export default function AccountPage() {
  const { data, isLoading } = useQuery({
    queryKey: ["me"],
    queryFn: () => apiGet<Me>("v1/auth/me"),
  });

  const [confirm, setConfirm] = useState("");
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleDelete() {
    if (confirm !== "DELETE" || deleting) return;
    setDeleting(true);
    setError(null);
    try {
      await apiDelete("v1/auth/me");
      // clears the session cookie and lands back on the marketing page
      window.location.href = "/auth/logout";
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't delete the account.");
      setDeleting(false);
    }
  }

  return (
    <div className="mx-auto max-w-lg space-y-xl">
      <PageHeader eyebrow="Settings" title="Account" />

      <Card className="space-y-sm">
        {isLoading ? (
          <Skeleton className="h-16 w-full" />
        ) : (
          <dl className="grid grid-cols-[auto_1fr] gap-x-lg gap-y-xs text-callout">
            <dt className="text-text-tertiary">Name</dt>
            <dd>{data?.display_name || "—"}</dd>
            <dt className="text-text-tertiary">Email</dt>
            <dd>{data?.email}</dd>
            <dt className="text-text-tertiary">Plan</dt>
            <dd className="capitalize">{data?.plan}</dd>
          </dl>
        )}
        <a
          href="/auth/logout"
          className="inline-block pt-sm text-caption text-text-secondary hover:text-text"
        >
          Sign out
        </a>
      </Card>

      <Card className="space-y-md border-danger/40">
        <CardTitle className="text-danger">Delete account</CardTitle>
        <p className="text-caption text-text-secondary">
          Permanently removes your account and every receipt on it, on all devices. This
          can&apos;t be undone. Type <span className="font-mono text-text">DELETE</span> to confirm.
        </p>
        <Input
          value={confirm}
          onChange={(e) => setConfirm(e.target.value)}
          placeholder="DELETE"
          aria-label="Type DELETE to confirm"
        />
        {error && <p className="text-caption text-danger">{error}</p>}
        <Button
          variant="danger"
          disabled={confirm !== "DELETE" || deleting}
          onClick={handleDelete}
        >
          {deleting ? "Deleting…" : "Delete my account"}
        </Button>
      </Card>

      <nav className="flex gap-lg px-hair text-caption text-text-tertiary">
        <a href="/privacy" className="hover:text-text">
          Privacy Policy
        </a>
        <a href="/terms" className="hover:text-text">
          Terms
        </a>
      </nav>
    </div>
  );
}
