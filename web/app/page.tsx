import { redirect } from "next/navigation";
import { ScanLine } from "lucide-react";
import { auth0 } from "@/lib/auth0";
import { buttonVariants } from "@/components/ui/button";

export default async function Home() {
  const session = await auth0.getSession();
  if (session) redirect("/dashboard");

  return (
    <main className="grid min-h-dvh place-items-center p-lg">
      <div className="w-full max-w-sm space-y-xl text-center">
        <div className="mx-auto grid h-14 w-14 place-items-center rounded-2xl bg-accent text-accent-fg">
          <ScanLine size={28} />
        </div>
        <div className="space-y-sm">
          <h1 className="text-title">AI Receipt</h1>
          <p className="text-callout text-text-secondary">Snap a receipt. It files itself.</p>
        </div>
        <a href="/auth/login" className={buttonVariants({ className: "w-full" })}>
          Continue
        </a>
        <p className="text-caption text-text-tertiary">
          Sign in with Google, Apple, or email.
        </p>
      </div>
    </main>
  );
}
