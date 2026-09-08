import { redirect } from "next/navigation";
import { auth0 } from "@/lib/auth0";
import { AppNav } from "@/components/app-nav";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const session = await auth0.getSession();
  if (!session) redirect("/auth/login");

  const displayName =
    (session.user.name as string | undefined) ??
    (session.user.email as string | undefined) ??
    "Account";

  return (
    <div className="mx-auto flex min-h-dvh max-w-content flex-col gap-lg px-lg py-lg md:flex-row md:gap-2xl md:py-2xl">
      <AppNav displayName={displayName} />
      <main className="min-w-0 flex-1 pb-2xl">{children}</main>
    </div>
  );
}
