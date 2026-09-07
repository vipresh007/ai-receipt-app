import { redirect } from "next/navigation";
import { getToken } from "@/lib/session";
import { AppNav } from "@/components/app-nav";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const token = await getToken();
  if (!token) redirect("/login");

  return (
    <div className="mx-auto flex min-h-dvh max-w-content flex-col gap-lg px-lg py-lg md:flex-row md:gap-2xl md:py-2xl">
      <AppNav />
      <main className="min-w-0 flex-1 pb-2xl">{children}</main>
    </div>
  );
}
