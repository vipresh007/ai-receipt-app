import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { auth0 } from "@/lib/auth0";
import { AppNav } from "@/components/app-nav";
import { LiveUpdates } from "@/components/live-updates";

// Signed-in pages: never in search results (robots.ts disallows them too).
export const metadata: Metadata = { robots: { index: false, follow: false } };

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const session = await auth0.getSession();
  if (!session) redirect("/auth/login");

  const displayName =
    (session.user.name as string | undefined) ??
    (session.user.email as string | undefined) ??
    "Account";

  return (
    <div className="mx-auto flex min-h-dvh max-w-[1320px] flex-col gap-lg px-lg py-lg md:flex-row md:gap-3xl md:px-2xl md:py-3xl">
      <AppNav displayName={displayName} />
      <LiveUpdates />
      {/* Room for the phone tab bar at the bottom. */}
      <main className="min-w-0 flex-1 pb-[calc(96px+env(safe-area-inset-bottom))] md:pb-2xl">{children}</main>
    </div>
  );
}
