import { redirect } from "next/navigation";
import { auth0 } from "@/lib/auth0";
import {
  BottomCTA,
  Features,
  Hero,
  HowItWorks,
  SiteFooter,
  SiteHeader,
} from "@/components/landing";

export default async function Home() {
  const session = await auth0.getSession();
  if (session) redirect("/dashboard");

  return (
    <div className="min-h-dvh bg-bg text-text">
      <SiteHeader />
      <main>
        <Hero />
        <HowItWorks />
        <Features />
        <BottomCTA />
      </main>
      <SiteFooter />
    </div>
  );
}
