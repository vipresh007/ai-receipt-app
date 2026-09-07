"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { ScanLine } from "lucide-react";
import { Button } from "./ui/button";
import { Input } from "./ui/input";
import { Label } from "./ui/label";

export function AuthForm({ mode }: { mode: "login" | "register" }) {
  const router = useRouter();
  const params = useSearchParams();
  const [displayName, setDisplayName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/auth/${mode}`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(
          mode === "register"
            ? { email, password, display_name: displayName }
            : { email, password },
        ),
      });
      if (!res.ok) {
        const body = (await res.json().catch(() => ({}))) as { detail?: string };
        setError(body.detail ?? "Something went wrong.");
        return;
      }
      router.replace(params.get("next") || "/dashboard");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={onSubmit} className="w-full max-w-sm space-y-lg">
      <div className="space-y-sm text-center">
        <div className="mx-auto grid h-11 w-11 place-items-center rounded-md bg-accent text-accent-fg">
          <ScanLine size={22} />
        </div>
        <h1 className="text-title">
          {mode === "login" ? "Welcome back" : "Create your account"}
        </h1>
        <p className="text-callout text-text-secondary">
          {mode === "login"
            ? "Sign in to your receipts."
            : "Start filing receipts in seconds."}
        </p>
      </div>

      {mode === "register" && (
        <div className="space-y-xs">
          <Label htmlFor="name">Name</Label>
          <Input
            id="name"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            placeholder="Alex Doe"
            autoComplete="name"
          />
        </div>
      )}

      <div className="space-y-xs">
        <Label htmlFor="email">Email</Label>
        <Input
          id="email"
          type="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="you@example.com"
          autoComplete="email"
        />
      </div>

      <div className="space-y-xs">
        <Label htmlFor="password">Password</Label>
        <Input
          id="password"
          type="password"
          required
          minLength={8}
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="At least 8 characters"
          autoComplete={mode === "login" ? "current-password" : "new-password"}
        />
      </div>

      {error && <p className="text-caption text-danger">{error}</p>}

      <Button type="submit" disabled={busy} className="w-full">
        {busy ? "Please wait…" : mode === "login" ? "Sign in" : "Create account"}
      </Button>

      <p className="text-center text-caption text-text-secondary">
        {mode === "login" ? (
          <>
            No account?{" "}
            <Link href="/register" className="text-accent hover:underline">
              Sign up
            </Link>
          </>
        ) : (
          <>
            Have an account?{" "}
            <Link href="/login" className="text-accent hover:underline">
              Sign in
            </Link>
          </>
        )}
      </p>
    </form>
  );
}
